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
	# TODO: should we replace all tabs with spaces?

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
	APT_KEY_TYPE="" # Only for apt-based distros
	APT_SYSTEMCTL_START=false # Only needs to be true for Kali
	CHANNEL="${CHANNEL:-release}"

	case "$CHANNEL" in
		release|beta|nightly) # TODO: beta, nightly
			;;
		*)
			echo "unsupported channel $CHANNEL"
			exit 1
			;;
	esac

	if [ -f /etc/os-release ]; then
		# /etc/os-release populates a number of shell variables. We care about the following:
		#  - ID: the short name of the OS (e.g. "debian", "freebsd")
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
				# Third-party keyrings became the preferred method of
				# installation in Ubuntu 20.04.
				if expr "$VERSION_ID" : "2.*" >/dev/null; then
					APT_KEY_TYPE="keyring"
				else
					APT_KEY_TYPE="legacy" # TODO: is this still needed?
				fi
				;;
			debian)
				OS="$ID"
				VERSION="$VERSION_CODENAME"
				PACKAGETYPE="apt"
				# Third-party keyrings became the preferred method of
				# installation in Debian 11 (Bullseye).
				if [ -z "${VERSION_ID:-}" ]; then
					# rolling release. If you haven't kept current, that's on you.
					APT_KEY_TYPE="keyring"
				elif [ "$VERSION_ID" -lt 11 ]; then
					APT_KEY_TYPE="legacy"
				else
					APT_KEY_TYPE="keyring"
				fi
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
				if [ "$VERSION_ID" -lt 5 ]; then
					APT_KEY_TYPE="legacy"
				else
					APT_KEY_TYPE="keyring"
				fi
				;;
			elementary)
				OS="ubuntu"
				VERSION="$UBUNTU_CODENAME"
				PACKAGETYPE="apt"
				if [ "$VERSION_ID" -lt 6 ]; then
					APT_KEY_TYPE="legacy"
				else
					APT_KEY_TYPE="keyring"
				fi
				;;
			parrot|mendel)
				OS="debian"
				PACKAGETYPE="apt"
				if [ "$VERSION_ID" -lt 5 ]; then
					VERSION="buster"
					APT_KEY_TYPE="legacy"
				else
					VERSION="bullseye"
					APT_KEY_TYPE="keyring"
				fi
				;;
			galliumos)
				OS="ubuntu"
				PACKAGETYPE="apt"
				VERSION="bionic"
				APT_KEY_TYPE="legacy"
				;;
			pureos|kaisen)
				OS="debian"
				PACKAGETYPE="apt"
				VERSION="bullseye"
				APT_KEY_TYPE="keyring"
				;;
			raspbian)
				OS="$ID"
				VERSION="$VERSION_CODENAME"
				PACKAGETYPE="apt"
				# Third-party keyrings became the preferred method of
				# installation in Raspbian 11 (Bullseye).
				if [ "$VERSION_ID" -lt 11 ]; then
					APT_KEY_TYPE="legacy"
				else
					APT_KEY_TYPE="keyring"
				fi
				;;
			kali)
				OS="debian"
				PACKAGETYPE="apt"
				YEAR="$(echo "$VERSION_ID" | cut -f1 -d.)"
				APT_SYSTEMCTL_START=true
				# Third-party keyrings became the preferred method of
				# installation in Debian 11 (Bullseye), which Kali switched
				# to in roughly 2021.x releases
				if [ "$YEAR" -lt 2021 ]; then
					# Kali VERSION_ID is "kali-rolling", which isn't distinguishing
					VERSION="buster"
					APT_KEY_TYPE="legacy"
				else
					VERSION="bullseye"
					APT_KEY_TYPE="keyring"
				fi
				;;
			Deepin)  # https://github.com/tailscale/tailscale/issues/7862
				OS="debian"
				PACKAGETYPE="apt"
				if [ "$VERSION_ID" -lt 20 ]; then
					APT_KEY_TYPE="legacy"
					VERSION="buster"
				else
					APT_KEY_TYPE="keyring"
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
			alpine)
				OS="$ID"
				VERSION="$VERSION_ID"
				PACKAGETYPE="apk"
				;;
			postmarketos)
				OS="alpine"
				VERSION="$VERSION_ID"
				PACKAGETYPE="apk"
				;;
			nixos)
				echo "Please add Tailscale to your NixOS configuration directly:"
				echo
				echo "services.tailscale.enable = true;"
				exit 1
				;;
			void)
				OS="$ID"
				VERSION="" # rolling release
				PACKAGETYPE="xbps"
				;;
			gentoo)
				OS="$ID"
				VERSION="" # rolling release
				PACKAGETYPE="emerge"
				;;
			osmc)
				OS="debian"
				PACKAGETYPE="apt"
				VERSION="bullseye"
				APT_KEY_TYPE="keyring"
				;;
			photon)
				OS="photon"
				VERSION="$(echo "$VERSION_ID" | cut -f1 -d.)"
				PACKAGETYPE="tdnf"
				;;
		esac

                # TODO: Flatpak?
	fi

	# If we failed to detect something through os-release, consult
	# uname and try to infer things from that.
	if [ -z "$OS" ]; then
		if type uname >/dev/null 2>&1; then
			case "$(uname)" in
				FreeBSD)
					# FreeBSD before 12.2 doesn't have
					# /etc/os-release, so we wouldn't have found it in
					# the os-release probing above.
					OS="freebsd"
					VERSION="$(freebsd-version | cut -f1 -d.)"
					PACKAGETYPE=""
					;;
				OpenBSD)
					OS="openbsd"
					VERSION="$(uname -r)"
					PACKAGETYPE=""
					;;
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
			URL="https://pkgs.tailscale.com/$CHANNEL/$OS/$VERSION/installer-supported" # TODO: use a Brave endpoint
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
		alpine)
			# All versions supported, no version checking needed.
			# TODO: is that true? When was tailscale packaged?
			;;
		void)
			# Rolling release, no version checking needed.
			;;
		gentoo)
			# Rolling release, no version checking needed.
			;;
		freebsd)
			OS_UNSUPPORTED=1
			;;
		openbsd)
			OS_UNSUPPORTED=1
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
				echo "You could try the static binaries at:"
				echo "https://pkgs.tailscale.com/$CHANNEL/#static"
				;;
			"")
				echo "Couldn't determine what operating system you're running."
				;;
			*)
				echo "$OS $VERSION isn't supported by this script yet."
				;;
		esac
		echo
		echo "If you'd like us to support your system better, please email support@tailscale.com"
		echo "and tell us what OS you're running."
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
			if [ "$APT_KEY_TYPE" = "legacy" ] && ! type gpg >/dev/null; then
				$SUDO apt-get update
				$SUDO apt-get install -y gnupg
			fi

			set -x
			$SUDO mkdir -p --mode=0755 /usr/share/keyrings
			case "$APT_KEY_TYPE" in
				legacy) # TODO: remove?
					$CURL "https://pkgs.tailscale.com/$CHANNEL/$OS/$VERSION.asc" | $SUDO apt-key add -
					$CURL "https://pkgs.tailscale.com/$CHANNEL/$OS/$VERSION.list" | $SUDO tee /etc/apt/sources.list.d/tailscale.list
				;;
				keyring)
                                        $CURL "https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg" | $SUDO tee /usr/share/keyrings/brave-browser-archive-keyring.gpg >/dev/null # TODO: handle other channels
                                        echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main"| $SUDO tee /etc/apt/sources.list.d/brave-browser-release.list # TODO: support other channels
									;;
			esac
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
		tdnf)
			set -x
			curl -fsSL "https://pkgs.tailscale.com/$CHANNEL/$OS/$VERSION/tailscale.repo" > /etc/yum.repos.d/tailscale.repo
			$SUDO tdnf install -y tailscale
			$SUDO systemctl enable --now tailscaled
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
			# TODO: support more aur helpers
            # TODO: aur helpers will ask interactive questions - not sure if we consider that a problem
			if command -v paru >/dev/null; then
				set -x
				paru -S brave-bin
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
		apk)
			set -x
			if ! grep -Eq '^http.*/community$' /etc/apk/repositories; then
				if type setup-apkrepos >/dev/null; then
					$SUDO setup-apkrepos -c -1
				else
					echo "installing tailscale requires the community repo to be enabled in /etc/apk/repositories"
					exit 1
				fi
			fi
			$SUDO apk add tailscale
			$SUDO rc-update add tailscale
			$SUDO rc-service tailscale start
			set +x
			;;
		xbps)
			set -x
			$SUDO xbps-install tailscale -y
			set +x
			;;
		emerge)
			set -x
			$SUDO emerge --ask=n net-vpn/tailscale
			set +x
			;;
		appstore)
			set -x
			open "https://apps.apple.com/us/app/tailscale/id1475387142"
			set +x
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
