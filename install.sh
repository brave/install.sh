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
show() { (set -x; "$@"); }

# All the code is wrapped in a main function that gets called at the
# bottom of the file, so that a truncated partial download doesn't end
# up executing half a script.
main() {
    ## Check if the browser can run on this system

    arch="$(uname -m)"
    glibc_ver="$(ldd --version 2>/dev/null|head -n1|grep -oE '[0-9]+\.[0-9]+$' || true)"
    glibc_ver_min="2.26"

    if [ "$(printf "%s\n%s" "$glibc_ver" "$glibc_ver_min"|sort -V|head -n1)" != "$glibc_ver_min" ]; then
        error "Unsupported glibc version ${glibc_ver:-<empty>}. Only glibc versions >=$glibc_ver_min are supported."
    fi

    case "$arch" in
        aarch64|arm64|x86_64) ;;
        *) error "Unsupported architecture $arch. Only 64-bit x86 or ARM machines are supported.";;
    esac

    ## Find and/or install necessary tools

    if [ "$(id -u)" = 0 ]; then
        sudo=""
    elif is_command sudo; then
        sudo="sudo"
    elif is_command doas; then
        sudo="doas"
    else
        error "Please install sudo or doas (or run this script as root) to proceed."
    fi

    if is_command curl; then
        curl="curl -fsS"
    elif is_command wget; then
        curl="wget -qO-"
    elif is_command apt-get; then
        curl="curl -fsS"
        export DEBIAN_FRONTEND=noninteractive
        show $sudo apt-get update
        show $sudo apt-get install -y curl
    fi

    ## Install the browser

    if is_command apt-get; then
        export DEBIAN_FRONTEND=noninteractive
        show $sudo mkdir -p --mode=0755 /usr/share/keyrings
        show $curl "https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg"|\
            show $sudo tee /usr/share/keyrings/brave-browser-archive-keyring.gpg >/dev/null
        show echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main"|\
            show $sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
        show $sudo apt-get update
        show $sudo apt-get install -y brave-browser
    elif is_command dnf; then
        show $sudo dnf install -y 'dnf-command(config-manager)'
        show $sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        show $sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
        show $sudo dnf install -y brave-browser
    elif is_command yum; then
        if ! is_command yum-config-manager; then
            show $sudo yum install yum-utils -y
        fi
        show $sudo yum-config-manager -y --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        show $sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
        show $sudo yum install brave-browser -y
    elif is_command zypper; then
        show $sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
        show $sudo zypper --non-interactive ar -g -r https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        show $sudo zypper --non-interactive --gpg-auto-import-keys refresh
        show $sudo zypper --non-interactive install brave-browser
    elif is_command pacman; then
        pacman_opts="-Sy --needed --noconfirm"
        if pacman -Ss brave-browser >/dev/null 2>&1; then
            show $sudo pacman $pacman_opts brave-browser
        elif is_command paru; then
            show paru $pacman_opts brave-bin
        elif is_command pikaur; then
            show pikaur $pacman_opts brave-bin
        elif is_command yay; then
            show yay $pacman_opts brave-bin
        else
            error "Could not find an AUR helper. Please install paru, pikaur, or yay to proceed." "" \
                "You can find more information about AUR helpers at https://wiki.archlinux.org/title/AUR_helpers"
        fi
    elif [ "$(uname)" = Darwin ]; then
        if is_command brew; then
            NONINTERACTIVE=1 show brew install --cask brave-browser
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

    echo "Installation complete! Start Brave by typing $(command -v brave-browser || command -v brave)."
}

main
