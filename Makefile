unsupported := alpine voidlinux/voidlinux-musl ubuntu_16.04 debian_9 linuxmintd/mint18-amd64 fedora_26 opensuse/leap_42.3
supported := ubuntu_18.04 debian_10 linuxmintd/mint19-amd64 fedora_28 opensuse/leap_15 opensuse/tumbleweed rockylinux_9 manjarolinux/base # fedora_27 hangs
distros := $(unsupported) $(supported)

test: $(distros)

MAKEFLAGS := -rRO
SHELL := $(shell command -v bash)
.SHELLFLAGS := -eEo pipefail -c
.ONESHELL:
$(V).SILENT:
.PHONY: test $(distros)

$(distros): distro = $(subst _,:,$@)
$(distros): log = $(subst /,_,$(subst _,:,$@)).log

$(unsupported):
	echo -n "Testing $(distro) (unsupported)... "
	if ! docker run --rm -v "$$PWD/install.sh:/install.sh" "$(distro)" /install.sh >"$(log)" 2>&1; then
	    grep -q "Unsupported glibc version" "$(log)" && echo OK
	else
	    printf "Failed\n\n" && tail -v "$(log)" && false
	fi

opensuse/tumbleweed: setup = zypper --non-interactive install libglib-2_0-0

$(supported):
	echo -n "Testing $(distro) (supported)... "
	if docker run --rm -v "$$PWD/install.sh:/install.sh" "$(distro)" \
	   sh -c '$(or $(setup),true) && /install.sh && brave-browser --version || brave --version' >"$(log)" 2>&1; then
	    echo OK
	else
	    printf "Failed\n\n" && tail -v "$(log)" && false
	fi
