#!/bin/sh
# Copyright (c) Tailscale Inc
# Copyright (c) 2024 The Brave Authors
# SPDX-License-Identifier: BSD-3-Clause
#
# This script installs the Brave browser using the OS's package manager

set -eu

# Helpers
error() { exec >&2; printf "Error: "; printf "%s\n" "${@:?}"; exit 1; }
is_command() { command -v "${1:?}" >/dev/null; }

# All the code is wrapped in a main function that gets called at the
# bottom of the file, so that a truncated partial download doesn't end
# up executing half a script.
main() {
    ARCH="$(uname -m)"
    GLIBC_VER="$(ldd --version 2>/dev/null|head -n1|grep -oE '[0-9]+\.[0-9]+$' || true)"
    GLIBC_VER_MIN="2.26"

    ## Check if the browser can run on this system

    if [ "$(printf "%s\n%s" "$GLIBC_VER" "$GLIBC_VER_MIN"|sort -V|head -n1)" != "$GLIBC_VER_MIN" ]; then
        error "Unsupported glibc version ${GLIBC_VER:-<empty>}. Only glibc versions >=$GLIBC_VER_MIN are supported."
    fi

    case "$ARCH" in
        aarch64|arm64|x86_64) ;;
        *) error "Unsupported architecture $ARCH. Only 64-bit x86 or ARM machines are supported.";;
    esac

    ## Locate necessary tools

    if is_command curl; then
        CURL="curl -fsS"
    elif is_command wget; then
        CURL="wget -qO-"
    elif is_command apt-get; then
        error "Please install curl or wget to proceed."
    fi

    if [ "$(id -u)" = 0 ]; then
        SUDO=""
    elif is_command sudo; then
        SUDO="sudo"
    elif is_command doas; then
        SUDO="doas"
    else
        error "Please install sudo or doas (or run this script as root) to proceed."
    fi

    ## Install the browser

    if is_command apt-get; then
        export DEBIAN_FRONTEND=noninteractive
        set -x
        $SUDO mkdir -p --mode=0755 /usr/share/keyrings
        $CURL "https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg"|\
            $SUDO tee /usr/share/keyrings/brave-browser-archive-keyring.gpg >/dev/null
        echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main"|\
            $SUDO tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
        $SUDO apt-get update
        $SUDO apt-get install -y brave-browser
        set +x
    elif is_command dnf; then
        set -x
        $SUDO dnf install -y 'dnf-command(config-manager)'
        $SUDO dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        $SUDO rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
        $SUDO dnf install -y brave-browser
        set +x
    elif is_command yum; then
        if ! is_command yum-config-manager; then
            set -x
            $SUDO yum install yum-utils -y
            set +x
        fi
        set -x
        $SUDO yum-config-manager -y --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        $SUDO rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
        $SUDO yum install brave-browser -y
        set +x
    elif is_command zypper; then
        set -x
        $SUDO rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
        $SUDO zypper --non-interactive ar -g -r https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        $SUDO zypper --non-interactive --gpg-auto-import-keys refresh
        $SUDO zypper --non-interactive install brave-browser
        set +x
    elif is_command pacman; then
        if pacman -Ss brave-browser >/dev/null 2>&1; then
            set -x
            $SUDO pacman -Sy --needed --noconfirm brave-browser
            set +x
        elif is_command paru; then
            AUR_HELPER="paru"
        elif is_command pikaur; then
            AUR_HELPER="pikaur"
        elif is_command yay; then
            AUR_HELPER="yay"
        else
            error "Could not find an AUR helper. Please install paru, pikaur, or yay to proceed." "" \
                "You can find more information about AUR helpers at https://wiki.archlinux.org/title/AUR_helpers"
        fi
        if [ "${AUR_HELPER:-}" ]; then
            set -x
            "$AUR_HELPER" -Sy --needed --noconfirm brave-bin
            set +x
        fi
    elif [ "$(uname)" = Darwin ]; then
        if is_command brew; then
            set -x
            NONINTERACTIVE=1 brew install --cask brave-browser
            set +x
        else
            error "Could not find brew. Please install brew to proceed." ""\
                "A Brave .dmg can also be downloaded from https://brave.com/download/"
        fi
    else
        error "Could not find a supported package manager. Only apt, dnf, paru/pikaur/yay, yum and zypper are supported." "" \
            "If you'd like us to support your system better, please file an issue at" \
            "https://github.com/brave/brave-browser/issues and include the following information:" "" \
            "$(uname -srvmo)" "" \
            "$(cat /etc/os-release)"
    fi

    echo "Installation complete! Start Brave by typing $([ "${AUR_HELPER:-}" ] && echo brave || echo brave-browser)."
}

main
