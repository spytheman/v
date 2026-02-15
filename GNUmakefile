CC ?= cc
CFLAGS ?=
LDFLAGS ?=
TMPDIR ?= /tmp
VROOT  ?= .
VC     ?= ./vc
VEXE   ?= ./v
VCREPO ?= https://github.com/vlang/vc
TCCREPO ?= https://github.com/vlang/tccbin
LEGACYREPO ?= https://github.com/macports/macports-legacy-support

VCFILE := v.c
TMPTCC := $(VROOT)/thirdparty/tcc
LEGACYLIBS := $(VROOT)/thirdparty/legacy
TMPLEGACY := $(LEGACYLIBS)/source
TCCOS := unknown
TCCARCH := unknown
GITCLEANPULL := git clean -xf && git pull --quiet
GITFASTCLONE := git clone --filter=blob:none --quiet

#### Platform detections and overrides:
_SYS := $(shell uname 2>/dev/null || echo Unknown)
_SYS := $(patsubst MSYS%,MSYS,$(_SYS))
_SYS := $(patsubst MINGW%,MinGW,$(_SYS))

ifneq ($(filter $(_SYS),MSYS MinGW),)
WIN32 := 1
EXE_EXT := .exe
endif

ifeq ($(_SYS),Linux)
LINUX := 1
TCCOS := linux
ifneq ($(shell ldd --version 2>&1 | grep -i musl),)
TCCOS := linuxmusl
endif
endif

ifeq ($(_SYS),Darwin)
MAC := 1
TCCOS := macos
ifeq ($(shell expr $(shell uname -r | cut -d. -f1) \<= 15), 1)
LEGACY := 1
endif
endif

ifeq ($(_SYS),FreeBSD)
TCCOS := freebsd
LDFLAGS += -lexecinfo
endif

ifeq ($(_SYS),NetBSD)
NETBSD := 1
TCCOS := netbsd
LDFLAGS += -lexecinfo
endif

ifeq ($(_SYS),OpenBSD)
TCCOS := openbsd
LDFLAGS += -lexecinfo
endif

ifdef ANDROID_ROOT
ANDROID := 1
undefine LINUX
TCCOS := android
endif
#####

ifdef WIN32
TCCOS := windows
VCFILE := v_win.c
endif

TCCARCH := $(shell uname -m 2>/dev/null || echo unknown)

ifeq ($(TCCARCH),x86_64)
	TCCARCH := amd64
else
ifneq ($(filter x86%,$(TCCARCH)),)
	TCCARCH := i386
else
ifeq ($(TCCARCH),arm64)
	TCCARCH := arm64
else
ifneq ($(filter arm%,$(TCCARCH)),)
	TCCARCH := arm
# otherwise, just use the arch name
endif
endif
endif
endif

.PHONY: all clean rebuild check fresh_vc fresh_tcc fresh_legacy check_for_working_tcc etags ctags agent-check agent-suggest agent-context agent-bootstrap-check agent-contract-check agent-summary-schema-check agent-doctor agent-ready agent-preflight agent-smoke agent-run agent-bugfix-min agent-doc-sync-check agent-artifact-clean-check agent-clean-local

ifdef prod
VFLAGS+=-prod
endif

all: latest_vc latest_tcc latest_legacy
ifdef WIN32
	$(CC) $(CFLAGS) -std=c99 -municode -w -o v1$(EXE_EXT) $(VC)/$(VCFILE) $(LDFLAGS) -lws2_32 || cmd/tools/cc_compilation_failed_windows.sh
	./v1$(EXE_EXT) -no-parallel -o v2$(EXE_EXT) $(VFLAGS) cmd/v
	./v2$(EXE_EXT) -o $(VEXE)$(EXE_EXT) $(VFLAGS) cmd/v
	$(RM) v1$(EXE_EXT)
	$(RM) v2$(EXE_EXT)
else
ifdef LEGACY
	$(MAKE) -C $(TMPLEGACY)
	$(MAKE) -C $(TMPLEGACY) PREFIX=$(realpath $(LEGACYLIBS)) CFLAGS=$(CFLAGS) LDFLAGS=$(LDFLAGS) install
	rm -rf $(TMPLEGACY)
	$(eval override LDFLAGS+=-L$(realpath $(LEGACYLIBS))/lib -lMacportsLegacySupport)
endif
	$(CC) $(CFLAGS) -std=c99 -w -o v1$(EXE_EXT) $(VC)/$(VCFILE) -lm -lpthread $(LDFLAGS) || cmd/tools/cc_compilation_failed_non_windows.sh
ifdef NETBSD
	paxctl +m v1$(EXE_EXT)
endif
	./v1$(EXE_EXT) -no-parallel -o v2$(EXE_EXT) $(VFLAGS) cmd/v
ifdef NETBSD
	paxctl +m v2$(EXE_EXT)
endif
	./v2$(EXE_EXT) -nocache -o $(VEXE)$(EXE_EXT) $(VFLAGS) cmd/v
ifdef NETBSD
	paxctl +m $(VEXE)$(EXE_EXT)
endif
	rm -rf v1$(EXE_EXT) v2$(EXE_EXT)
endif
	@$(VEXE)$(EXE_EXT) run cmd/tools/detect_tcc.v
	@echo "V has been successfully built"
	@$(VEXE)$(EXE_EXT) -version
	@$(VEXE)$(EXE_EXT) run .github/problem-matchers/register_all.vsh

clean:
	rm -rf $(TMPTCC)
	rm -rf $(LEGACYLIBS)
	rm -rf $(VC)

rebuild: clean all

ifndef local
latest_vc: $(VC)/.git/config
	cd $(VC) && $(GITCLEANPULL)
else
latest_vc:
	@echo "Using local vc"
endif

check_for_working_tcc:
	@$(TMPTCC)/tcc.exe --version > /dev/null 2> /dev/null || echo "The executable '$(TMPTCC)/tcc.exe' does not work."

fresh_vc:
	rm -rf $(VC)
	$(GITFASTCLONE) $(VCREPO) $(VC)

ifndef local
latest_tcc: $(TMPTCC)/.git/config
	cd $(TMPTCC) && $(GITCLEANPULL)
ifneq (,$(wildcard ./tcc.exe))
	@$(MAKE) --quiet check_for_working_tcc 2> /dev/null
endif

else
latest_tcc:
	@echo "Using local tcc"
	@$(MAKE) --quiet check_for_working_tcc 2> /dev/null
endif

fresh_tcc:
	rm -rf $(TMPTCC)
ifndef local
# Check whether a TCC branch exists for the user's system configuration.
ifneq (,$(findstring thirdparty-$(TCCOS)-$(TCCARCH), $(shell git ls-remote --heads $(TCCREPO) | sed 's/^[a-z0-9]*\trefs.heads.//')))
	$(GITFASTCLONE) --branch thirdparty-$(TCCOS)-$(TCCARCH) $(TCCREPO) $(TMPTCC)
	@$(MAKE) --quiet check_for_working_tcc 2> /dev/null
else
	@echo 'Pre-built TCC not available for thirdparty-$(TCCOS)-$(TCCARCH) at $(TCCREPO), will use the system compiler: $(CC)'
	$(GITFASTCLONE) --branch thirdparty-unknown-unknown $(TCCREPO) $(TMPTCC)
endif
else
	@echo "Using local tccbin"
	@$(MAKE) --quiet check_for_working_tcc 2> /dev/null
endif

ifndef local
latest_legacy: $(TMPLEGACY)/.git/config
ifdef LEGACY
	cd $(TMPLEGACY) && $(GITCLEANPULL)
endif
else
latest_legacy:
ifdef LEGACY
	@echo "Using local legacysupport"
endif
endif

fresh_legacy:
	rm -rf $(LEGACYLIBS)
	$(GITFASTCLONE) $(LEGACYREPO) $(TMPLEGACY)

$(TMPTCC)/.git/config:
	$(MAKE) fresh_tcc

$(VC)/.git/config:
	$(MAKE) fresh_vc

$(TMPLEGACY)/.git/config:
ifdef LEGACY
	$(MAKE) fresh_legacy
endif

asan:
	$(MAKE) all CFLAGS='-fsanitize=address,undefined'

selfcompile:
	$(VEXE)$(EXE_EXT) -cg -o v cmd/v

selfcompile-static:
	$(VEXE)$(EXE_EXT) -cg -cflags '--static' -o v-static cmd/v

### NB: Please keep this Makefile and make.bat simple.
install:
	@echo 'Please use `sudo ./v symlink` instead, or manually add the current directory to your PATH.'

check:
	$(VEXE)$(EXE_EXT) test-all

agent-check:
	$(VEXE)$(EXE_EXT) -silent test vlib/v/compiler_errors_test.v
	$(VEXE)$(EXE_EXT) -silent test vlib/v/
	$(VEXE)$(EXE_EXT) check-md AGENTS.md
	$(VEXE)$(EXE_EXT) check-md LLMS.md

agent-suggest:
	./cmd/tools/agents/suggest_tests.vsh $(ARGS) $(FILES)

agent-context:
	./cmd/tools/agents/agent_context.vsh $(ARGS) $(FILES)

agent-bootstrap-check:
	./cmd/tools/agents/bootstrap_check.vsh

agent-contract-check:
	./cmd/tools/agents/validate_agent_contract.vsh
	$(VEXE)$(EXE_EXT) cmd/tools/agents/suggest_tests_test.v
	$(VEXE)$(EXE_EXT) cmd/tools/agents/validate_agent_contract_test.v
	$(VEXE)$(EXE_EXT) cmd/tools/agents/validate_agent_run_summary_test.v
	$(VEXE)$(EXE_EXT) cmd/tools/agents/print_agent_run_summary_test.v
	$(VEXE)$(EXE_EXT) cmd/tools/agents/agent_context_test.v
	$(VEXE)$(EXE_EXT) cmd/tools/agents/doctor_test.v
	$(VEXE)$(EXE_EXT) -nocache cmd/tools/agents/sync_agent_docs_test.v
	./cmd/tools/agents/sync_agent_docs.vsh --check
	$(MAKE) agent-artifact-clean-check

agent-summary-schema-check:
	./cmd/tools/agents/validate_agent_run_summary.vsh $(AGENT_ARTIFACT)

agent-doctor:
	./cmd/tools/agents/doctor.vsh

agent-ready:
	./cmd/tools/agents/bootstrap_check.vsh --build-missing --rebuild-stale
	$(MAKE) agent-preflight VEXE=./vnew local=1

AGENT_PREFLIGHT_ARTIFACT_DEFAULT := $(shell mktemp /tmp/agent_preflight_smoke.XXXXXX.json)
AGENT_SMOKE_ARTIFACT_DEFAULT := $(shell mktemp /tmp/agent_smoke_summary.XXXXXX.json)
AGENT_SMOKE_SCRIPT_DEFAULT := $(shell mktemp /tmp/agent_smoke_commands.XXXXXX.sh)
AGENT_ARTIFACT_DEFAULT := $(shell mktemp /tmp/agent_run_summary.XXXXXX.json)
AGENT_RUN_SCRIPT_DEFAULT := $(shell mktemp /tmp/agent_run_commands.XXXXXX.sh)
AGENT_BUGFIX_ARTIFACT_DEFAULT := $(shell mktemp /tmp/agent_bugfix_min_summary.XXXXXX.json)
AGENT_BUGFIX_SCRIPT_DEFAULT := $(shell mktemp /tmp/agent_bugfix_min_commands.XXXXXX.sh)
AGENT_PREFLIGHT_ARTIFACT ?= $(AGENT_PREFLIGHT_ARTIFACT_DEFAULT)
AGENT_SMOKE_ARTIFACT ?= $(AGENT_SMOKE_ARTIFACT_DEFAULT)
AGENT_SMOKE_SCRIPT ?= $(AGENT_SMOKE_SCRIPT_DEFAULT)
AGENT_ARTIFACT ?= $(AGENT_ARTIFACT_DEFAULT)
AGENT_RUN_SCRIPT ?= $(AGENT_RUN_SCRIPT_DEFAULT)
AGENT_BUGFIX_ARTIFACT ?= $(AGENT_BUGFIX_ARTIFACT_DEFAULT)
AGENT_BUGFIX_SCRIPT ?= $(AGENT_BUGFIX_SCRIPT_DEFAULT)
DRY_RUN ?= 0
AGENT_DRY_RUN ?= $(DRY_RUN)
AGENT_MIN_CONFIDENCE ?= 0

agent-preflight:
	./cmd/tools/agents/bootstrap_check.vsh --build-missing --rebuild-stale
	./cmd/tools/agents/validate_agent_contract.vsh --matrix-only
	./cmd/tools/agents/sync_agent_docs.vsh --check
	./cmd/tools/agents/suggest_tests.vsh --tier fast --json --require-non-fallback README.md > $(AGENT_PREFLIGHT_ARTIFACT)
	@echo "Wrote preflight summary artifact to $(AGENT_PREFLIGHT_ARTIFACT)"
	@echo "Preflight OK"

agent-smoke:
	./cmd/tools/agents/bootstrap_check.vsh --build-missing --rebuild-stale
	./cmd/tools/agents/validate_agent_contract.vsh
	./cmd/tools/agents/sync_agent_docs.vsh --check
	./cmd/tools/agents/suggest_tests.vsh --tier fast --json --strict-unmatched --require-non-fallback README.md > $(AGENT_SMOKE_ARTIFACT)
	./cmd/tools/agents/validate_agent_run_summary.vsh $(AGENT_SMOKE_ARTIFACT)
	./cmd/tools/agents/suggest_tests.vsh --tier fast --format sh --strict-unmatched --require-non-fallback README.md > $(AGENT_SMOKE_SCRIPT)
	bash $(AGENT_SMOKE_SCRIPT)
	./cmd/tools/agents/print_agent_run_summary.vsh $(AGENT_SMOKE_ARTIFACT)
	$(MAKE) agent-artifact-clean-check
	@echo "Wrote smoke summary artifact to $(AGENT_SMOKE_ARTIFACT)"
	@echo "Wrote smoke command script to $(AGENT_SMOKE_SCRIPT)"
	@echo "Agent smoke passed."

agent-run:
	./cmd/tools/agents/bootstrap_check.vsh --build-missing --rebuild-stale
	mkdir -p $(dir $(AGENT_ARTIFACT))
	mkdir -p $(dir $(AGENT_RUN_SCRIPT))
	./cmd/tools/agents/suggest_tests.vsh --strict-unmatched --require-non-fallback --fail-below-confidence $(AGENT_MIN_CONFIDENCE) --json $(ARGS) $(FILES) > $(AGENT_ARTIFACT)
	./cmd/tools/agents/validate_agent_run_summary.vsh $(AGENT_ARTIFACT)
	./cmd/tools/agents/suggest_tests.vsh --strict-unmatched --require-non-fallback --fail-below-confidence $(AGENT_MIN_CONFIDENCE) --format sh $(ARGS) $(FILES) > $(AGENT_RUN_SCRIPT)
ifeq ($(AGENT_DRY_RUN),1)
	@echo "Dry run enabled: not executing $(AGENT_RUN_SCRIPT)"
	@cat $(AGENT_RUN_SCRIPT)
else
	bash $(AGENT_RUN_SCRIPT)
endif
	./cmd/tools/agents/print_agent_run_summary.vsh $(AGENT_ARTIFACT)
	@echo "Wrote agent summary artifact to $(AGENT_ARTIFACT)"
	@echo "Wrote agent command script to $(AGENT_RUN_SCRIPT)"

agent-bugfix-min:
	./cmd/tools/agents/bootstrap_check.vsh
	./cmd/tools/agents/suggest_tests.vsh --tier targeted --strict-unmatched --require-non-fallback $(FILES)
	$(MAKE) agent-run ARGS='--tier targeted' FILES='$(FILES)' AGENT_ARTIFACT='$(AGENT_BUGFIX_ARTIFACT)' AGENT_RUN_SCRIPT='$(AGENT_BUGFIX_SCRIPT)' AGENT_DRY_RUN='$(AGENT_DRY_RUN)'

agent-doc-sync-check:
	./cmd/tools/agents/sync_agent_docs.vsh --check

agent-artifact-clean-check:
	@if ls cmd/tools/agents/tmp.* >/dev/null 2>&1; then \
		echo "runtime artifacts found under cmd/tools/agents/: cmd/tools/agents/tmp.*"; \
		echo "clean with: rm -f cmd/tools/agents/tmp.*"; \
		exit 1; \
	fi

agent-clean-local:
	rm -f cmd/tools/agents/tmp.*
	rm -f /tmp/agent_preflight_smoke*.json
	rm -f /tmp/agent_smoke_summary*.json /tmp/agent_smoke_commands*.sh
	rm -f /tmp/agent_run_summary*.json /tmp/agent_run_summary*.sh
	rm -f /tmp/agent_run_dry*.json /tmp/agent_run_dry*.sh
	rm -f /tmp/agent_bugfix_min*.json /tmp/agent_bugfix_min*.sh

etags:
	./v$(EXE_EXT) -print-v-files cmd/v | grep -v :parse_text| etags -L -

ctags:
	./v$(EXE_EXT) -print-v-files cmd/v | grep -v :parse_text| ctags -L -
