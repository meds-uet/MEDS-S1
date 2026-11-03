# Copyright 2026 Maktab-e-Digital Systems Lahore.
# SPDX-License-Identifier: Apache-2.0
#
# MEDS-S1 top-level Makefile -- the single entry point for everything.
#
#   make help                 what you can do
#   make check-tools          what you are missing
#   make check                repository conventions   (fast, run before every push)
#   make lint                 lint + elaborate
#   make test-unit            unit testbenches
#   make ci                   everything the PR gate runs
#   make docs                 specification PDF
#
# Growth slots -- these targets exist and explain who is implementing them, so
# that enabling a CI job is a one-line change rather than a new pipeline.

PY      ?= python3
CONFIG  ?= s1_base
BOARD   ?= verilator
TB      ?=
SCRIPTS := scripts
DOCS    := docs
FIGS    := $(DOCS)/figures
PDF     := $(DOCS)/MEDS-S1-Specification.pdf
SPEC    := specs/MEDS-S1-SPECIFICATION.md
BUILD   := build
VERIBLE_DIRS := rtl verif
VERIBLE_VERSION ?= v0.0-4250-gc1fe2daf
VERILATOR_VERSION ?= 5.020
PRE_COMMIT_VERSION ?= 4.6.2
VERIBLE_FORMAT_FLAGS := --flagfile=.verible-format.flags

# Packages must be compiled before anything that imports them.
RTL_PKGS  := $(shell find rtl -name '*_pkg.sv' 2>/dev/null | sort)
RTL_MODS  := $(shell find rtl -name '*.sv' ! -name '*_pkg.sv' 2>/dev/null | sort)
RTL_SRCS  := $(RTL_PKGS) $(RTL_MODS)
CFG_FILE  := configs/$(CONFIG).yaml
VERIBLE_SRCS := $(shell find $(VERIBLE_DIRS) \( -name '*.sv' -o -name '*.svh' \) 2>/dev/null | sort)

export PUPPETEER_EXECUTABLE_PATH ?= $(shell command -v google-chrome || command -v chromium || command -v chromium-browser)

.DEFAULT_GOAL := help

# =============================================================================
# Help
# =============================================================================
.PHONY: help
help:
	@echo "MEDS-S1 -- make targets"
	@echo
	@echo "  Everyday"
	@echo "    check          repository conventions (structure + docs gates)"
	@echo "    lint           lint and elaborate CONFIG=$(CONFIG)"
	@echo "    test-unit      run unit testbenches      [TB=<name> for one]"
	@echo "    ci             everything the PR gate runs"
	@echo "    hooks          install git pre-commit hook (once per clone)"
	@echo
	@echo "  Documentation"
	@echo "    docs           figures + specification PDF"
	@echo "    figures        regenerate docs/figures/*.svg"
	@echo "    catalogue      rebuild the project catalogue PDF"
	@echo "    projects       regenerate PROJECTS.md from the catalogue"
	@echo
	@echo "  Not implemented yet -- each names its owning project"
	@echo "    gen            SoC generator            (R-04)"
	@echo "    sw             build the BSP and apps   (T-06)"
	@echo "    run            run PROG on BOARD        (T-06 / R-06)"
	@echo "    cosim          Spike co-simulation      (R-05)"
	@echo "    riscof         ACT / architectural tests(M-11 / T-07)"
	@echo "    bench          benchmark suite          (M-07 / M-08)"
	@echo "    formal         riscv-formal             (R-01 / T-07)"
	@echo "    synth          FPGA synthesis           (T-08)"
	@echo
	@echo "  Variables: CONFIG=$(CONFIG)  BOARD=$(BOARD)"
	@echo "  Configs:   $(patsubst configs/%.yaml,%,$(wildcard configs/*.yaml))"

# =============================================================================
# Environment
# =============================================================================
.PHONY: check-tools
check-tools:
	@ok=1; \
	need() { printf "  %-28s " "$$1"; \
	         if command -v $$1 >/dev/null 2>&1; then echo "OK"; \
	         else echo "MISSING -- $$2"; ok=0; fi; }; \
	opt()  { printf "  %-28s " "$$1"; \
	         if command -v $$1 >/dev/null 2>&1; then echo "OK"; \
	         else echo "absent -- $$2"; fi; }; \
	echo "Required:"; \
	need $(PY)                     "everything"; \
	opt pre-commit                 "git hooks (pip install pre-commit)"; \
	[ -f .git/hooks/pre-commit ] \
	  && echo "  git hook                     OK" \
	  || echo "  git hook                     absent -- run: make hooks"; \
		if command -v pre-commit >/dev/null 2>&1; then \
	  found=$$(pre-commit --version | awk '{print $$2}'); \
	  printf "  %-28s " "pre-commit version"; \
	  if [ "$$found" = "$(PRE_COMMIT_VERSION)" ]; then \
	    echo "OK ($$found)"; \
	  else \
	    echo "MISMATCH -- expected $(PRE_COMMIT_VERSION), found $$found"; \
	    ok=0; \
	  fi; \
	fi; \
	need verilator                 "simulation and lint"; \
	if command -v verilator >/dev/null 2>&1; then \
	  found=$$(verilator --version | awk '{print $$2}'); \
	  printf "  %-28s " "verilator version"; \
	  if [ "$$found" = "$(VERILATOR_VERSION)" ]; then \
	    echo "OK ($$found)"; \
	  else \
		echo "WARNING: expected $(VERILATOR_VERSION), found $$found (CI uses $(VERILATOR_VERSION))"; \
	  fi; \
	fi; \
	opt verible-verilog-lint       "style lint"; \
	opt verible-verilog-format     "formatting"; \
	if command -v verible-verilog-lint >/dev/null 2>&1; then \
	  found=$$(verible-verilog-lint --version | head -n 1 | awk '{print $$2}'); \
	  printf "  %-28s " "verible version"; \
	  if [ "$$found" = "$(VERIBLE_VERSION)" ]; then echo "OK ($$found)"; \
	  else echo "MISMATCH -- expected $(VERIBLE_VERSION), found $$found"; fi; \
	fi; \
	echo "Software (T-06 onward):"; \
	opt riscv64-unknown-elf-gcc    "building software"; \
	echo "Verification (R-05, M-11, T-07):"; \
	opt spike                      "co-simulation reference"; \
	opt riscof                     "architectural tests"; \
	opt sail_riscv_sim             "ACT golden reference (sail-riscv)"; \
	echo "Documentation:"; \
	opt pandoc                     "specification PDF"; \
	opt google-chrome              "PDF rendering"; \
	opt mmdc                       "mermaid diagrams (optional)"; \
	echo; \
	[ $$ok -eq 1 ] && echo "required toolchain OK" || \
	  { echo "missing required tools -- see docs/guidelines/ONBOARDING.md"; exit 1; }

# =============================================================================
# Conventions and lint -- the PR gate
# =============================================================================
.PHONY: check check-structure check-docs check-projects
check: check-structure check-docs check-projects

check-projects:
	@$(PY) $(SCRIPTS)/gen_projects_index.py --check

check-structure:
	@$(PY) $(SCRIPTS)/check_structure.py

check-docs:
	@$(PY) $(SCRIPTS)/check_docs.py

.PHONY: lint
lint: $(CFG_FILE)
	@echo "lint + elaborate: CONFIG=$(CONFIG)"
	@verilator --lint-only -Wall --timing \
	  $(addprefix -I,$(sort $(dir $(RTL_SRCS)))) \
	  verif/verilator.vlt $(RTL_SRCS) \
	  && echo "  lint clean"

.PHONY: verible-lint verible-format-check verible-format verible-check

verible-lint:
	@echo "verible lint: $(words $(VERIBLE_SRCS)) files"
	@verible-verilog-lint --waiver_files lint.waiver $(VERIBLE_SRCS) \
	  && echo "  verible lint clean"

verible-format-check:
	@fail=0; \
	for f in $(VERIBLE_SRCS); do \
	  verible-verilog-format $(VERIBLE_FORMAT_FLAGS) "$$f" | diff -q "$$f" - >/dev/null 2>&1 \
	    || { echo "NEEDS FORMAT: $$f"; fail=1; }; \
	done; \
	[ $$fail -eq 0 ] && echo "  format clean" || exit 1

verible-format:
	@verible-verilog-format $(VERIBLE_FORMAT_FLAGS) --inplace $(VERIBLE_SRCS)
	@echo "formatted $(words $(VERIBLE_SRCS)) files"

verible-check: verible-lint verible-format-check

.PHONY: hooks
hooks:
	@command -v pre-commit >/dev/null 2>&1 \
	  || { echo "pre-commit not found. Run: pip install pre-commit"; exit 1; }
	@pre-commit install
	@echo "pre-commit hook installed"

# =============================================================================
# Test
# =============================================================================
.PHONY: test-unit test
test-unit:
	@$(PY) $(SCRIPTS)/run_unit_tests.py $(if $(TB),--tb $(TB),)

test: test-unit

.PHONY: ci
ci: check lint verible-check test-unit
	@echo
	@echo "PR gate passed. Growth slots still disabled:"
	@grep -c 'if: false' .github/workflows/pr.yml | xargs -I{} echo "  pr.yml:      {} job(s)"
	@grep -c 'if: false' .github/workflows/nightly.yml | xargs -I{} echo "  nightly.yml: {} job(s)"

# =============================================================================
# Documentation
# =============================================================================
.PHONY: docs figures pdf html catalogue
docs: figures pdf

figures:
	@$(PY) $(SCRIPTS)/gen_diagrams.py

pdf: $(PDF)

$(PDF): $(SPEC) $(SCRIPTS)/build_pdf.py $(wildcard $(FIGS)/*.svg)
	@$(PY) $(SCRIPTS)/build_pdf.py

html:
	@$(PY) $(SCRIPTS)/build_pdf.py --gen --keep-html

catalogue:
	@$(PY) $(SCRIPTS)/gen_project_catalogue.py

.PHONY: projects
projects:
	@$(PY) $(SCRIPTS)/gen_projects_index.py

# =============================================================================
# Growth slots.  Each fails with the project that owns it, so nobody wastes an
# afternoon discovering the target is a stub.
# =============================================================================
define NOT_YET
	@echo "make $(1): not implemented yet."; \
	 echo "  Owner project: $(2)"; \
	 echo "  See: $(3)"; \
	 exit 2
endef

.PHONY: gen sw run cosim riscof bench formal synth coverage test-random bench-compare
gen:
	$(call NOT_YET,gen,R-04 (SoC generator),gen/README.md and SPEC section 26)

sw:
	$(call NOT_YET,sw,T-06 (board support package),sw/README.md)

run:
	$(call NOT_YET,run,T-06 / R-06 (BSP and debug module),SPEC section 27.1)

cosim:
	$(call NOT_YET,cosim,R-05 (RVFI + Spike co-simulation),verif/cosim/README.md)

riscof:
	$(call NOT_YET,riscof,M-11 / T-07 (ACT in CI),docs/guidelines/VERIFICATION_GUIDE.md section 6)

bench:
	$(call NOT_YET,bench,M-07 / M-08 (benchmark suites),sw/apps/README.md)

bench-compare:
	$(call NOT_YET,bench-compare,M-07 (benchmark harness),SPEC NFR-10)

formal:
	$(call NOT_YET,formal,R-01 / T-07 (formal verification),verif/formal/README.md)

coverage:
	$(call NOT_YET,coverage,T-07 (functional coverage),verif/README.md)

test-random:
	$(call NOT_YET,test-random,T-07 (constrained random),verif/README.md)

synth:
	$(call NOT_YET,synth,T-08 (KC705 port),boards/kc705/README.md)

# =============================================================================
.PHONY: clean distclean
clean:
	@rm -rf $(BUILD)
	@echo "cleaned build/"

distclean: clean
	@rm -f $(PDF) $(DOCS)/MEDS-S1-Specification.html
	@rm -rf $(FIGS) $(SCRIPTS)/__pycache__
	@echo "cleaned generated documentation"
