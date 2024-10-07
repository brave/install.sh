#!/bin/sh
# Copyright (c) Tailscale Inc
# Copyright (c) 2024 The Brave Authors
# SPDX-License-Identifier: BSD-3-Clause
#
# This script detects the current operating system, and installs
# Brave according to that OS's conventions.

set -eu

# All the code is wrapped in a main function that gets called at the
# bottom of the file, so that a truncated partial download doesn't end
# up executing half a script.
main() {
	# Step 1: detect the current linux distro, version, and packaging system.
	#
	# We rely on a combination of 'uname' and /etc/os-release to find
	# an OS name and version, and from there work out what
	# installation method we should be using.
	#
	# The end result of this step is that the following three
	# variables are populated, if detection was successful.
	OS=""
	VERSION=""
	PACKAGETYPE=""
	CHANNEL="${CHANNEL:-release}"
	ARCH="$(uname -m)"

	case "$ARCH" in
		aarch64|arm64|x86_64)
			;;
		*)
			echo "Unsupported architecture $ARCH. Only 64-bit x86 or ARM machines are supported."
			exit 1
			;;
	esac

	case "$CHANNEL" in
		release|beta|nightly)
			;;
		*)
			echo "Unsupported channel $CHANNEL. Only release, beta and nightly are supported."
			exit 1
			;;
	esac

	if [ -f /etc/os-release ]; then
		# /etc/os-release populates a number of shell variables. We care about the following:
		#  - ID: the short name of the OS (e.g. "debian")
		#  - VERSION_ID: the numeric release version for the OS, if any (e.g. "18.04")
		#  - VERSION_CODENAME: the codename of the OS release, if any (e.g. "buster")
		#  - UBUNTU_CODENAME: if it exists, use instead of VERSION_CODENAME
		. /etc/os-release # TODO: grep for the needed variables instead?
		case "$ID" in
			ubuntu|pop|neon|zorin|tuxedo)
				OS="ubuntu"
				if [ "${UBUNTU_CODENAME:-}" != "" ]; then
				    VERSION="$UBUNTU_CODENAME"
				else
				    VERSION="$VERSION_CODENAME"
				fi
				PACKAGETYPE="apt"
				;;
			debian)
				OS="$ID"
				VERSION="$VERSION_CODENAME"
				PACKAGETYPE="apt"
				;;
			linuxmint)
				if [ "${UBUNTU_CODENAME:-}" != "" ]; then
				    OS="ubuntu"
				    VERSION="$UBUNTU_CODENAME"
				elif [ "${DEBIAN_CODENAME:-}" != "" ]; then
				    OS="debian"
				    VERSION="$DEBIAN_CODENAME"
				else
				    OS="ubuntu"
				    VERSION="$VERSION_CODENAME"
				fi
				PACKAGETYPE="apt"
				;;
			elementary)
				OS="ubuntu"
				VERSION="$UBUNTU_CODENAME"
				PACKAGETYPE="apt"
				;;
			parrot|mendel)
				OS="debian"
				PACKAGETYPE="apt"
				;;
			galliumos)
				OS="ubuntu"
				PACKAGETYPE="apt"
				VERSION="bionic"
				;;
			pureos|kaisen)
				OS="debian"
				PACKAGETYPE="apt"
				VERSION="bullseye"
				;;
			raspbian)
				OS="$ID"
				VERSION="$VERSION_CODENAME"
				PACKAGETYPE="apt"
				;;
			kali)
				OS="debian"
				PACKAGETYPE="apt"
				YEAR="$(echo "$VERSION_ID" | cut -f1 -d.)"
				if [ "$YEAR" -lt 2021 ]; then
					# Kali VERSION_ID is "kali-rolling", which isn't distinguishing
					VERSION="buster"
				else
					VERSION="bullseye"
				fi
				;;
			Deepin)
				OS="debian"
				PACKAGETYPE="apt"
				if [ "$VERSION_ID" -lt 20 ]; then
					VERSION="buster"
				else
					VERSION="bullseye"
				fi
				;;
			centos)
				OS="$ID"
				VERSION="$VERSION_ID"
				PACKAGETYPE="dnf"
				if [ "$VERSION" = "7" ]; then
					PACKAGETYPE="yum"
				fi
				;;
			ol)
				OS="oracle"
				VERSION="$(echo "$VERSION_ID" | cut -f1 -d.)"
				PACKAGETYPE="dnf"
				if [ "$VERSION" = "7" ]; then
					PACKAGETYPE="yum"
				fi
				;;
			rhel)
				OS="$ID"
				VERSION="$(echo "$VERSION_ID" | cut -f1 -d.)"
				PACKAGETYPE="dnf"
				if [ "$VERSION" = "7" ]; then
					PACKAGETYPE="yum"
				fi
				;;
			fedora)
				OS="$ID"
				VERSION=""
				PACKAGETYPE="dnf"
				;;
			rocky|almalinux|nobara|openmandriva|sangoma|risios|cloudlinux|alinux|fedora-asahi-remix)
				OS="fedora"
				VERSION=""
				PACKAGETYPE="dnf"
				;;
			amzn)
				OS="amazon-linux"
				VERSION="$VERSION_ID"
				PACKAGETYPE="yum"
				;;
			xenenterprise)
				OS="centos"
				VERSION="$(echo "$VERSION_ID" | cut -f1 -d.)"
				PACKAGETYPE="yum"
				;;
			opensuse-leap|sles)
				OS="opensuse"
				VERSION="leap/$VERSION_ID"
				PACKAGETYPE="zypper"
				;;
			opensuse-tumbleweed)
				OS="opensuse"
				VERSION="tumbleweed"
				PACKAGETYPE="zypper"
				;;
			sle-micro-rancher)
				OS="opensuse"
				VERSION="leap/15.4"
				PACKAGETYPE="zypper"
				;;
			arch|archarm|endeavouros|blendos|garuda)
				OS="arch"
				VERSION="" # rolling release
				PACKAGETYPE="pacman"
				;;
			manjaro|manjaro-arm)
				OS="manjaro"
				VERSION="" # rolling release
				PACKAGETYPE="pacman"
				;;
			osmc)
				OS="debian"
				PACKAGETYPE="apt"
				VERSION="bullseye"
				;;
		esac
	fi

	# If we failed to detect something through os-release, consult
	# uname and try to infer things from that.
	if [ -z "$OS" ]; then
		if type uname >/dev/null 2>&1; then
			case "$(uname)" in
				Darwin)
					OS="macos"
					VERSION="$(sw_vers -productVersion | cut -f1-2 -d.)"
					PACKAGETYPE="appstore"
					;;
				Linux)
					OS="other-linux"
					VERSION=""
					PACKAGETYPE=""
					;;
			esac
		fi
	fi

	# Ideally we want to use curl, but on some installs we
	# only have wget. Detect and use what's available.
	CURL=
        # TODO: disable following redirects?
	if type curl >/dev/null; then
		CURL="curl -fsSL"
	elif type wget >/dev/null; then
		CURL="wget -q -O-"
	fi
	if [ -z "$CURL" ]; then
		echo "The installer needs either curl or wget to download files."
		echo "Please install either curl or wget to proceed."
		exit 1
	fi

	TEST_URL="https://pkgs.tailscale.com/" # TODO: Brave-hosted
	RC=0
	TEST_OUT=$($CURL "$TEST_URL" 2>&1) || RC=$?
	if [ $RC != 0 ]; then
		echo "The installer cannot reach $TEST_URL"
		echo "Please make sure that your machine has internet access."
		echo "Test output:"
		echo "$TEST_OUT"
		exit 1
	fi

	# Step 2: having detected an OS we support, is it one of the
	# versions we support?
	OS_UNSUPPORTED=
	case "$OS" in
		ubuntu|debian|raspbian|centos|oracle|rhel|amazon-linux|opensuse|photon)
			# Check with the package server whether a given version is supported.
			URL="https://pkgs.tailscale.com/stable/$OS/$VERSION/installer-supported" # TODO: use a Brave endpoint
			$CURL "$URL" 2> /dev/null | grep -q OK || OS_UNSUPPORTED=1 # TODO: check for status codes and error with different message if server is down
			;;
		fedora)
			# All versions supported, no version checking required.
			;;
		arch)
			# Rolling release, no version checking needed.
			;;
		manjaro)
			# Rolling release, no version checking needed.
			;;
		macos)
			# We delegate macOS installation to the app store, it will
			# perform version checks for us.
			;;
		other-linux)
			OS_UNSUPPORTED=1
			;;
		*)
			OS_UNSUPPORTED=1
			;;
	esac
	if [ "$OS_UNSUPPORTED" = "1" ]; then
		case "$OS" in
			other-linux)
				echo "Couldn't determine what kind of Linux is running."
				;;
			"")
				echo "Couldn't determine what operating system you're running."
				;;
			*)
				echo "$OS $VERSION isn't supported by this script yet."
				;;
		esac
		echo
		echo "If you'd like us to support your system better, please file an issue at "
		echo "https://github.com/brave/brave-browser/issues and tell us what OS you're running."
		echo
		echo "Please include the following information we gathered from your system:"
		echo
		echo "OS=$OS"
		echo "VERSION=$VERSION"
		echo "PACKAGETYPE=$PACKAGETYPE"
		if type uname >/dev/null 2>&1; then
			echo "UNAME=$(uname -a)"
		else
			echo "UNAME="
		fi
		echo
		if [ -f /etc/os-release ]; then
			cat /etc/os-release
		else
			echo "No /etc/os-release"
		fi
		exit 1
	fi

	# Step 3: work out if we can run privileged commands, and if so,
	# how.
	CAN_ROOT=
	SUDO=
	if [ "$(id -u)" = 0 ]; then
		CAN_ROOT=1
		SUDO=""
	elif type sudo >/dev/null; then
		CAN_ROOT=1
		SUDO="sudo"
	elif type doas >/dev/null; then
		CAN_ROOT=1
		SUDO="doas"
	fi
	if [ "$CAN_ROOT" != "1" ]; then
		echo "This installer needs to run commands as root."
		echo "We tried looking for 'sudo' and 'doas', but couldn't find them."
		echo "Either re-run this script as root, or set up sudo/doas."
		exit 1
	fi


	# Step 4: run the installation.
	OSVERSION="$OS"
	[ "$VERSION" != "" ] && OSVERSION="$OSVERSION $VERSION"
	echo "Installing Brave for $OSVERSION, using method $PACKAGETYPE"
	case "$PACKAGETYPE" in
		apt)
			export DEBIAN_FRONTEND=noninteractive

			set -x
			$SUDO mkdir -p --mode=0755 /usr/share/keyrings
			$CURL "https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg" | $SUDO tee /usr/share/keyrings/brave-browser-archive-keyring.gpg >/dev/null # TODO: handle other channels
			echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main"| $SUDO tee /etc/apt/sources.list.d/brave-browser-release.list # TODO: support other channels

			$SUDO apt-get update
			$SUDO apt-get install -y brave-browser
			set +x
		;;
		yum)
			set -x
			$SUDO yum install yum-utils -y
			$SUDO yum-config-manager -y --add-repo "https://pkgs.tailscale.com/$CHANNEL/$OS/$VERSION/tailscale.repo"
			$SUDO yum install tailscale -y
			$SUDO systemctl enable --now tailscaled
			set +x
		;;
		dnf)
			set -x
			# TODO: support other channels
			$SUDO dnf install -y 'dnf-command(config-manager)'
			$SUDO dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
			# TODO: https://pkgs.tailscale.com/stable/fedora/tailscale.repo covers the pgp key - should we?
			$SUDO rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
			$SUDO dnf install -y brave-browser
			set +x
		;;
		zypper)
			set -x
			$SUDO rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
			$SUDO zypper --non-interactive ar -g -r https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
			$SUDO zypper --non-interactive --gpg-auto-import-keys refresh
			$SUDO zypper --non-interactive install brave-browser
			set +x
			;;
		pacman)
			# TODO: support beta and nightly
			if command -v paru >/dev/null; then
				set -x
				paru -S brave-bin
				set +x
			elif command -v pikaur >/dev/null; then
				set -x
				pikaur -S brave-bin
				set +x
			elif command -v yay >/dev/null; then
				set -x
				yay -S brave-bin
				set +x
			else
				# TODO: should we prefix error messages with something like "Error: "? and also print them to stderr?
				echo "Could not find an AUR helper to install Brave (see: https://wiki.archlinux.org/title/AUR_helpers)"
				exit 1
			fi
			;;
		appstore)
			echo "Download Brave from https://brave.com/download/"
			exit 0
			;;
		*)
			echo "unexpected: unknown package type $PACKAGETYPE"
			exit 1
			;;
	esac

	echo "Installation complete! Start Brave by typing brave-browser." # TODO: support other distros than just Debian
	echo
}

main
