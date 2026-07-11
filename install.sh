#!/bin/sh -eu
# Copyright (c) Tailscale Inc
# Copyright (c) 2024 The Brave Authors
# SPDX-License-Identifier: BSD-3-Clause
#
# This script installs Brave Browser, or Brave Origin using the OS's package manager
# Requires: coreutils, grep, sh and one of sudo/doas/run0/pkexec/sudo-rs
# Source: https://github.com/brave/install.sh

GLIBC_VER_MIN="2.26"
APT_VER_MIN="1.1"

FLAVOR="${FLAVOR:-browser}"
CHANNEL="${CHANNEL:-release}"

main() {
    ## Check if the browser can run on this system

    case "$(uname)" in
        Darwin) error "Please go to https://brave.com/download/ to download the Mac app";;
        *) glibc_supported;;
    esac

    case "$(uname -m)" in
        aarch64|x86_64) ;;
        *) error "Unsupported architecture $(uname -m). Only 64-bit x86 or ARM machines are supported.";;
    esac

    ## Validate the flavor and channel

    case "$FLAVOR" in
        browser) FLAVOR_LABEL="Brave Browser";;
        origin) FLAVOR_LABEL="Brave Origin";;
        *) error "Invalid flavor $FLAVOR. Only browser and origin are supported.";;
    esac

    case "$CHANNEL" in
        release) dashCHANNEL="";;
        beta|nightly) dashCHANNEL="-$CHANNEL";;
        *) error "Invalid channel $CHANNEL. Only release, beta and nightly are supported.";;
    esac

    ## Locate the necessary tools

    case "$(whoami)" in
        root) sudo="";;
        *) sudo="$(first_of sudo doas run0 pkexec sudo-rs)" || error "Please install sudo/doas/run0/pkexec/sudo-rs to proceed.";;
    esac

    case "$(first_of curl wget)" in
        wget) curl="wget -qO-";;
        *) curl="curl -fsS";;
    esac

    ## Install the browser

    echo "Installing $FLAVOR_LABEL ($CHANNEL)"

    if available apt-get && apt_supported; then
        export DEBIAN_FRONTEND=noninteractive
        if ! available curl && ! available wget; then
            show $sudo apt-get update || apt_error
            show $sudo apt-get install -y curl
        fi
        show $curl "https://brave-browser-apt-$CHANNEL.s3.brave.com/brave-browser$dashCHANNEL-archive-keyring.gpg"|\
            show $sudo install -DTm644 /dev/stdin "/usr/share/keyrings/brave-browser$dashCHANNEL-archive-keyring.gpg"
        show $curl "https://brave-browser-apt-$CHANNEL.s3.brave.com/brave-browser.sources"|\
            show $sudo install -DTm644 /dev/stdin "/etc/apt/sources.list.d/brave-browser-$CHANNEL.sources"
        show $sudo rm -f /etc/apt/sources.list.d/brave-browser-*.list
        show $sudo apt-get update || apt_error
        show $sudo apt-get install -y "brave-$FLAVOR$dashCHANNEL"

    elif available dnf; then
        if dnf --version|grep -q dnf5; then
            show $sudo dnf config-manager addrepo --overwrite --from-repofile="https://brave-browser-rpm-$CHANNEL.s3.brave.com/brave-browser$dashCHANNEL.repo"
        else
            show $sudo dnf install -y 'dnf-command(config-manager)'
            show $sudo dnf config-manager --add-repo "https://brave-browser-rpm-$CHANNEL.s3.brave.com/brave-browser$dashCHANNEL.repo"
        fi
        show $sudo dnf install -y "brave-$FLAVOR$dashCHANNEL"

    elif available eopkg; then
        [ "$FLAVOR" = browser ] || error "$FLAVOR_LABEL is not available for eopkg."
        show $sudo eopkg update-repo -y
        show $sudo eopkg install -y brave

    elif available pacman; then
        if pacman -Ss "brave-$FLAVOR$dashCHANNEL" >/dev/null 2>&1; then
            show $sudo pacman -Sy --needed --noconfirm "brave-$FLAVOR$dashCHANNEL"
        else
            aur_helper="$(first_of paru pikaur yay)" ||
                error "Could not find an AUR helper. Please install paru/pikaur/yay to proceed." "" \
                      "You can find more information about AUR helpers at https://wiki.archlinux.org/title/AUR_helpers"
            case "$FLAVOR" in
                browser) aur_pkg="brave$dashCHANNEL-bin";;
                *) aur_pkg="brave-$FLAVOR$dashCHANNEL-bin";;
            esac
            show "$aur_helper" -Sy --needed --noconfirm "$aur_pkg"
        fi

    elif available zypper; then
        show $sudo zypper --non-interactive addrepo --gpgcheck --repo "https://brave-browser-rpm-$CHANNEL.s3.brave.com/brave-browser$dashCHANNEL.repo"
        show $sudo zypper --non-interactive --gpg-auto-import-keys refresh
        show $sudo zypper --non-interactive install "brave-$FLAVOR$dashCHANNEL"

    elif available yum; then
        available yum-config-manager || show $sudo yum install yum-utils -y
        show $sudo yum-config-manager -y --add-repo "https://brave-browser-rpm-$CHANNEL.s3.brave.com/brave-browser$dashCHANNEL.repo"
        show $sudo yum install "brave-$FLAVOR$dashCHANNEL" -y

    elif available rpm-ostree; then
        available curl || available wget || error "Please install curl/wget to proceed."
        show $curl "https://brave-browser-rpm-$CHANNEL.s3.brave.com/brave-browser$dashCHANNEL.repo"|\
            show $sudo install -DTm644 /dev/stdin "/etc/yum.repos.d/brave-browser$dashCHANNEL.repo"
        show $sudo rpm-ostree install -y --idempotent "brave-$FLAVOR$dashCHANNEL"

    elif available xbps-install; then
        if ! available unzip; then
            show $sudo xbps-install -Sy unzip
        fi

        case "$CHANNEL" in
            release) CHAN="" ;;
            beta|nightly) CHAN="-$CHANNEL" ;;
        esac

        case "$FLAVOR" in
            browser) BASE="brave-browser$CHAN" ;;
            origin) BASE="brave-origin$CHAN" ;;
        esac

        INSTALL_DIR="/opt/$BASE"

        if [ "$CHANNEL" = "release" ]; then
            LATEST_TAG=$(show $curl "https://api.github.com/repos/brave/brave-browser/releases/latest" 2>/dev/null | grep '"tag_name"' | head -1 | cut -d'"' -f4)
        else
            LATEST_TAG=$(show $curl "https://api.github.com/repos/brave/brave-browser/releases?per_page=10" 2>/dev/null | grep '"tag_name"' | head -1 | cut -d'"' -f4)
        fi

        [ -n "$LATEST_TAG" ] || error "Could not determine the latest Brave release from GitHub."
        VERSION="${LATEST_TAG#v}"

        echo "Downloading $BASE-$VERSION-linux-amd64.zip from GitHub release $LATEST_TAG ..."

        TMPDIR="$(mktemp -d)"
        EXTRACT_DIR="$TMPDIR/extract"
        ZIP_URL="https://github.com/brave/brave-browser/releases/download/$LATEST_TAG/$BASE-$VERSION-linux-amd64.zip"

        show $curl -L "$ZIP_URL" -o "$TMPDIR/brave.zip" || error "Failed to download Brave from $ZIP_URL"

        if [ -d "$INSTALL_DIR" ]; then
            show $sudo rm -rf "$INSTALL_DIR"
        fi

        mkdir -p "$EXTRACT_DIR"
        show unzip -q "$TMPDIR/brave.zip" -d "$EXTRACT_DIR"

        show $sudo mkdir -p "$INSTALL_DIR"
        show $sudo cp -a "$EXTRACT_DIR"/. "$INSTALL_DIR/"
        show $sudo chown -R root:root "$INSTALL_DIR"

        case "$FLAVOR" in
            browser) LAUNCHER="brave" ;;
            origin) LAUNCHER="brave-origin" ;;
        esac
        [ -f "$INSTALL_DIR/$LAUNCHER" ] || LAUNCHER="brave"

        show $sudo ln -sf "$INSTALL_DIR/$LAUNCHER" "/usr/local/bin/brave"

        show $sudo mkdir -p /usr/share/applications
        show $sudo tee /usr/share/applications/brave-browser.desktop >/dev/null <<DESKTOP_EOF
[Desktop Entry]
Version=1.0
Name=$FLAVOR_LABEL
GenericName=Web Browser
Comment=$FLAVOR_LABEL Web Browser
Exec=/usr/local/bin/brave %U
Terminal=false
Type=Application
Icon=brave-browser
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
DESKTOP_EOF

        if [ -f "$INSTALL_DIR/product_logo_128.png" ]; then
            show $sudo mkdir -p /usr/share/pixmaps
            show $sudo cp "$INSTALL_DIR/product_logo_128.png" /usr/share/pixmaps/brave-browser.png
            for _size in 16 24 32 48 64 128 256; do
                if [ -f "$INSTALL_DIR/product_logo_${_size}.png" ]; then
                    show $sudo mkdir -p "/usr/share/icons/hicolor/${_size}x${_size}/apps"
                    show $sudo cp "$INSTALL_DIR/product_logo_${_size}.png" "/usr/share/icons/hicolor/${_size}x${_size}/apps/brave-browser.png"
                fi
            done
        fi

        show $sudo ln -sf "$INSTALL_DIR/$LAUNCHER" "/usr/local/bin/brave-$FLAVOR$dashCHANNEL"

        rm -rf "$TMPDIR"

    else
        error "Could not find a supported package manager. Only apt/dnf/eopkg/pacman(+paru/pikaur/yay)/rpm-ostree/yum/zypper/xbps are supported." "" \
            "If you'd like us to support your system better, please file an issue at" \
            "https://github.com/brave/install.sh/labels/new-distro and include the following information:" "" \
            "$(uname -srvmo || true)" "" \
            "$(cat /etc/os-release || true)"
    fi

    case "$FLAVOR" in
        browser) binary="$(command -v "brave$dashCHANNEL" || command -v "brave-$FLAVOR$dashCHANNEL" || true)";;
        *) binary="$(command -v "brave-$FLAVOR$dashCHANNEL" || true)";;
    esac

    case "$binary" in
        "") echo "Installation complete!";;
        *) printf "Installation complete! Start %s by typing: %s\n" "$FLAVOR_LABEL" "$(basename "$binary")";;
    esac
}

# Helpers
available() { command -v "${1:?}" >/dev/null; }
first_of() { for c in "${@:?}"; do if available "$c"; then echo "$c"; return 0; fi; done; return 1; }
show() { (set -x; "${@:?}"); }
error() { exec >&2; printf "Error: "; printf "%s\n" "${@:?}"; exit 1; }
newer() { [ "$(printf "%s\n%s" "$1" "$2"|sort -V|head -n1)" = "${2:?}" ]; }
supported() { newer "$2" "${3:?}" || error "Unsupported ${1:?} version ${2:-<empty>}. Only $1 versions >=$3 are supported."; }
glibc_supported() { supported glibc "$(ldd --version 2>/dev/null|head -n1|grep -oE '[0-9]+\.[0-9]+$' || true)" "${GLIBC_VER_MIN:?}"; }
apt_error() { error 'The "apt-get update" command is not working on your system. The Brave installer cannot proceed. Please try again after fixing your system configuration.'; }
apt_supported() { supported apt "$(apt-get -v|head -n1|cut -d' ' -f2)" "${APT_VER_MIN:?}"; }

main
