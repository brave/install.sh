#!/bin/sh
# Copyright (c) Tailscale Inc
# Copyright (c) 2024 The Brave Authors
# SPDX-License-Identifier: BSD-3-Clause
#
# This script installs the Brave browser using the OS's package manager
# Requires: coreutils, grep, sh, sudo/doas (except macOS)
# Source: https://github.com/brave/install.sh

# Browser requirements
GLIBC_VER_MIN="2.26"
MACOS_VER_MIN="11.0"

set -eu

# All the code is wrapped in a main function that gets called at the
# bottom of the file, so that a truncated partial download doesn't end
# up executing half a script.
main() {
    ## Check if the browser can run on this system

    os="$(uname)"
    arch="$(uname -m)"

    case "$os" in
        Darwin) macos_ver="$(sw_vers -productVersion 2>/dev/null || true)"
           supported macOS "$macos_ver" "$MACOS_VER_MIN";;
        *) glibc_ver="$(ldd --version 2>/dev/null|head -n1|grep -oE '[0-9]+\.[0-9]+$' || true)"
           supported glibc "$glibc_ver" "$GLIBC_VER_MIN";;
    esac

    case "$arch" in
        aarch64|arm64|x86_64) ;;
        *) error "Unsupported architecture $arch. Only 64-bit x86 or ARM machines are supported.";;
    esac

    ## Find and/or install the necessary tools

    if [ "$(id -u)" = 0 ] || [ "$os" = Darwin ] && id -Gn|grep -qw admin; then
        sudo=""
    elif available sudo; then
        sudo="sudo"
    elif available doas; then
        sudo="doas"
    elif available run0; then
        sudo="run0"
    else
        error "Please install sudo or doas to proceed."
    fi

    if available curl; then
        curl="curl -fsS"
    elif available wget; then
        curl="wget -qO-"
    elif available apt-get; then
        curl="curl -fsS"
        export DEBIAN_FRONTEND=noninteractive
        show $sudo apt-get update
        show $sudo apt-get install -y curl
    fi

    ## Install the browser

    if available apt-get; then
        export DEBIAN_FRONTEND=noninteractive
        show $sudo mkdir -p --mode=0755 /usr/share/keyrings
        show $curl "https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg"|\
            show $sudo tee /usr/share/keyrings/brave-browser-archive-keyring.gpg >/dev/null
        show $sudo chmod a+r /usr/share/keyrings/brave-browser-archive-keyring.gpg
        show echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main"|\
            show $sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
        show $sudo apt-get update
        show $sudo apt-get install -y brave-browser

    elif available dnf; then
        show $sudo dnf install -y 'dnf-command(config-manager)'
        if dnf --version|grep -q dnf5; then
            show $sudo dnf config-manager addrepo --overwrite --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        else
            show $sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        fi
        show $sudo dnf install -y brave-browser

    elif available eopkg; then
        show $sudo eopkg update-repo -y
        show $sudo eopkg install -y brave

    elif available yum; then
        available yum-config-manager || show $sudo yum install yum-utils -y
        show $sudo yum-config-manager -y --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        show $sudo yum install brave-browser -y

    elif available zypper; then
        show $sudo zypper --non-interactive addrepo --gpgcheck --repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        show $sudo zypper --non-interactive --gpg-auto-import-keys refresh
        show $sudo zypper --non-interactive install brave-browser

    elif available pacman; then
        pacman_opts="-Sy --needed --noconfirm"
        if pacman -Ss brave-browser >/dev/null 2>&1; then
            show $sudo pacman $pacman_opts brave-browser
        elif available paru; then
            show paru $pacman_opts brave-bin
        elif available pikaur; then
            show pikaur $pacman_opts brave-bin
        elif available yay; then
            show yay $pacman_opts brave-bin
        else
            error "Could not find an AUR helper. Please install paru, pikaur, or yay to proceed." "" \
                "You can find more information about AUR helpers at https://wiki.archlinux.org/title/AUR_helpers"
        fi

    elif [ "$os" = Darwin ]; then
        trap "$sudo hdiutil detach -force -quiet /Volumes/Brave\ Browser" EXIT
        show $sudo hdiutil attach -quiet https://laptop-updates.brave.com/latest/osx
        show $sudo rsync -a --del /Volumes/Brave\ Browser/Brave\ Browser.app /Applications/
        show $sudo hdiutil detach -force -quiet /Volumes/Brave\ Browser || true
        echo "Installation complete! Start Brave by typing: open -a Brave\ Browser"
        exit

    else
        error "Could not find a supported package manager. Only apt, dnf, eopkg, paru/pikaur/yay, yum and zypper are supported." "" \
            "If you'd like us to support your system better, please file an issue at" \
            "https://github.com/brave/install.sh/issues and include the following information:" "" \
            "$(uname -srvmo)" "" \
            "$(cat /etc/os-release || true)"
    fi

    printf "Installation complete! Start Brave by typing: "
    basename "$(command -v brave-browser || command -v brave)"
}

# Helpers
available() { command -v "${1:?}" >/dev/null; }
error() { exec >&2; printf "Error: "; printf "%s\n" "${@:?}"; exit 1; }
newer() { [ "$(printf "%s\n%s" "$1" "$2"|sort -V|head -n1)" = "${2:?}" ]; }
show() { (set -x; "${@:?}"); }
supported() { newer "$2" "${3:?}" || error "Unsupported ${1:?} version ${2:-<empty>}. Only $1 versions >=$3 are supported."; }

main
