test: shellcheck ut $(distros)

# Output per target, use bash in recipes, fail on errors, be quiet by default

MAKEFLAGS := -rRO
SHELL := $(shell command -v bash)
MAYBE_SUDO := $(shell id -nG|grep -qw 'docker\|root' && echo || echo sudo)
.SHELLFLAGS := -eEo pipefail -c
.ONESHELL:
$(V).SILENT:
.PHONY: clean shellcheck test ut $(distros) $(distros:%=%_clean)

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
	$(MAYBE_SUDO) docker run --rm -v "$$PWD/install.sh:/install.sh" alpine \
	    sh -$(if $(V),x,)ec 'source <(grep -x "\w\w*() {.*}" /install.sh) && $(test)'
	echo OK

# Analyze install.sh with shellcheck

shellcheck:
	printf "Testing script install.sh... "
	shellcheck -e SC2086 install.sh
	echo OK
