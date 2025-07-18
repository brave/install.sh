# Select the Browser channel

CHANNEL ?= release
$(if $(filter $(CHANNEL),release beta nightly),,$(error Unknown browser channel `$(CHANNEL)'))

# Distros to test install.sh on

unsupported := alpine voidlinux/voidlinux-musl ubuntu_16.04 debian_9 linuxmintd/mint18-amd64 fedora_26 opensuse/leap_42.3
supported := ubuntu_18.04 ubuntu_25.04 debian_11 linuxmintd/mint19-amd64 fedora_27 fedora_41 opensuse/leap_15 opensuse/tumbleweed rockylinux_9 $(if $(CHANNEL:release=),,manjarolinux/base)
distros := $(unsupported) $(supported)

test: shellcheck ut $(distros)

# Output per target, use bash in recipes, fail on errors, be quiet by default

MAKEFLAGS := -rRO
SHELL := $(shell command -v bash)
.SHELLFLAGS := -eEo pipefail -c
.ONESHELL:
$(V).SILENT:
.PHONY: clean shellcheck test ut $(distros) $(distros:%=%_clean)

# Test install.sh on different distributions via docker

$(distros): distro = $(subst _,:,$@)
$(distros) $(distros:%=%_clean): log = $(subst /,_,$(subst _,:,$(@:%_clean=%))).log

$(unsupported):
	printf "Testing $(CHANNEL) on unsupported distribution $(distro)... "
	if ! docker run --rm -e CHANNEL="$(CHANNEL)" -v "$$PWD/install.sh:/install.sh" "$(distro)" /install.sh >"$(log)" 2>&1 &&\
	   grep -q "Unsupported glibc version" "$(log)"; then
	    echo OK
	else
	    printf "Failed\n\n" && tail -v "$(log)" && false
	fi

opensuse/tumbleweed: setup = zypper --non-interactive install libglib-2_0-0
manjarolinux/base: setup = mv /etc/pacman.conf{.pacnew,} || true

$(supported):
	printf "Testing $(CHANNEL) on supported distribution $(distro)... "
	dashCHANNEL="$$([[ "$(CHANNEL)" == release ]] && echo || echo "-$(CHANNEL)")"
	if docker run --rm -e CHANNEL="$(CHANNEL)" -v "$$PWD/install.sh:/install.sh" "$(distro)" \
	   sh -c '$(or $(setup),true) && /install.sh && "brave-browser$$dashCHANNEL" --version || "brave$$dashCHANNEL" --version' >"$(log)" 2>&1; then
	    echo OK
	else
	    printf "Failed\n\n" && tail -v "$(log)" && false
	fi

clean: $(distros:%=%_clean)

$(distros:%=%_clean):
	rm -f "$(log)"

# Test helper functions from install.sh in an alpine container

uts := ut_available ut_first_of ut_show ut_newer ut_supported
.PHONY: $(uts)
ut: $(uts)

ut_available: test = available ls && ! available foo
ut_first_of: test = [ $$(first_of ls foo) = ls ] && [ $$(first_of foo bar ls) = ls ]
ut_show: test = show ls 2>&1 >/dev/null|grep -qFx "+ ls"
ut_newer: test = newer 1.12 1.9 && newer 0.1.1 0.0.2 && ! newer "" non-empty
ut_supported: test = supported foo 1.12 1.9

$(uts): ut_%:
	printf "Testing function $*()... "
	docker run --rm -v "$$PWD/install.sh:/install.sh" alpine \
	    sh -$(if $(V),x,)ec 'source <(grep -x "\w\w*() {.*}" /install.sh) && $(test)'
	echo OK

# Analyze install.sh with shellcheck

shellcheck:
	printf "Testing script install.sh... "
	shellcheck -e SC2086 install.sh
	echo OK
