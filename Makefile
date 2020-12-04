# saner makefile
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

include Makevars

# extra parameters
PACKAGES_FILE ?= packages-1.txt
JOBS          ?= 1
TIMEOUT       ?= 30m
CORPUS_SIZE   ?= 500

CORPUS_S1          := corpus-stage1.txt
CORPUS_S2          := corpus-stage2.txt
CORPUS_S2_DETAILS  := corpus-stage2.fst
CORPUS_ALL_DETAILS := corpus-all.fst

PROJECT_BASE_DIR ?= /mnt/ocfs_vol_00/project-evalr
RUN_DIR          ?= $(CURDIR)/run

# environment
R_DIR              := $(PROJECT_BASE_DIR)/R-dyntrace
PACKAGES_SRC_DIR   := $(PROJECT_BASE_DIR)/CRAN/extracted
PACKAGES_ZIP_DIR   := $(PROJECT_BASE_DIR)/CRAN/src/contrib
CRAN_LOCAL_MIRROR  := file://$(PROJECT_BASE_DIR)/CRAN
R_BIN              := $(R_DIR)/bin/R

RUNR_DIR           := $(CURDIR)/runr
RUNR_TASKS_DIR     := $(RUNR_DIR)/inst/tasks
SCRIPTS_DIR        := $(CURDIR)/scripts
DATA_DIR           := $(CURDIR)/data

# remote execution
ifeq ($(CLUSTER), 1)
    MAP_EXTRA=--sshloginfile $(SSH_LOGIN_FILE)
    JOBS=100%
endif

# tools
MAP				:= $(RUNR_DIR)/inst/map.sh -j $(JOBS) -t $(TIMEOUT) $(MAP_EXTRA)
R					:= R_LIBS=$(LIBRARY_DIR) $(R_DIR)/bin/R
RSCRIPT		:= R_LIBS=$(LIBRARY_DIR) $(R_DIR)/bin/Rscript
MERGE_CSV := $(RSCRIPT) $(RUNR_DIR)/inst/merge-csv.R

# the 13 packages that comes with R inc base
PACKAGES_CORE_FILE  := packages-core.txt
# all additional packages
PACKAGES_CRAN_FILE  := packages-cran.txt

## tasks outputs

# metadata
PACKAGE_METADATA_DIR   := $(RUN_DIR)/package-metadata
PACKAGE_METADATA_STATS := $(PACKAGE_METADATA_DIR)/task-stats.csv
PACKAGE_FUNCTIONS_CSV  := $(PACKAGE_METADATA_DIR)/functions.csv
PACKAGE_METADATA_CSV   := $(PACKAGE_METADATA_DIR)/metadata.csv
PACKAGE_REVDEPS_CSV    := $(PACKAGE_METADATA_DIR)/revdeps.csv
PACKAGE_SLOC_CSV       := $(PACKAGE_METADATA_DIR)/sloc.csv
PACKAGE_S3_CLASSES_CSV := $(PACKAGE_METADATA_DIR)/s3-classes.csv
PACKAGE_METADATA_FILES := $(PACKAGE_FUNCTIONS_CSV) $(PACKAGE_METADATA_CSV) $(PACKAGE_REVDEPS_CSV) $(PACKAGE_SLOC_CSV) $(PACKAGE_S3_CLASSES_CSV)

# coverage
PACKAGE_COVERAGE_DIR   := $(RUN_DIR)/package-coverage
PACKAGE_COVERAGE_CSV   := $(PACKAGE_COVERAGE_DIR)/coverage.csv
PACKAGE_COVERAGE_STATS := $(PACKAGE_COVERAGE_DIR)/task-stats.csv

# runnable code
PACKAGE_RUNNABLE_CODE_DIR		:= $(RUN_DIR)/package-runnable-code
PACKAGE_RUNNABLE_CODE_CSV		:= $(PACKAGE_RUNNABLE_CODE_DIR)/runnable-code.csv
PACKAGE_RUNNABLE_CODE_STATS := $(PACKAGE_RUNNABLE_CODE_DIR)/task-stats.csv

# runnable code eval
PACKAGE_RUNNABLE_CODE_EVAL_DIR		:= $(RUN_DIR)/package-runnable-code-eval
PACKAGE_RUNNABLE_CODE_EVAL_CSV		:= $(PACKAGE_RUNNABLE_CODE_EVAL_DIR)/runnable-code.csv
PACKAGE_RUNNABLE_CODE_EVAL_STATS := $(PACKAGE_RUNNABLE_CODE_EVAL_DIR)/task-stats.csv

# code run
PACKAGE_CODE_RUN_DIR := $(RUN_DIR)/package-code-run
PACKAGE_CODE_RUN_STATS := $(PACKAGE_CODE_RUN_DIR)/task-stats.csv

# code run eval
TRACE_EVAL_DIR := $(RUN_DIR)/trace-eval
TRACE_EVAL_STATS := $(TRACE_EVAL_DIR)/task-stats.csv

# static eval
PACKAGE_EVALS_STATIC_DIR		:= $(RUN_DIR)/package-evals-static
PACKAGE_EVALS_STATIC_STATS	:= $(PACKAGE_EVALS_STATIC_DIR)/task-stats.csv
PACKAGE_EVALS_STATIC_CSV		:= $(PACKAGE_EVALS_STATIC_DIR)/package-evals-static.csv

.PHONY: \
  lib \
	libs \
  package-coverage \
  package-metadata \
  package-runnable-code \
  package-runnable-code-eval \
  package-code-run \
  package-evals-static \
  trace-eval

lib/%:
	R CMD INSTALL $*

libs: lib/injectr lib/instrumentr lib/runr lib/evil

$(CORPUS_S2) $(CORPUS_S2_DETAILS) $(CORPUS_ALL_DETAILS): $(PACKAGE_METADATA_FILES) $(PACKAGE_COVERAGE_CSV) $(PACKAGE_RUNNABLE_CODE_EVAL_CSV)
	$(RSCRIPT) $(SCRIPTS_DIR)/corpus-stage2.R \
    --num $(CORPUS_SIZE) \
    --metadata $(PACKAGE_METADATA_CSV) \
    --functions $(PACKAGE_FUNCTIONS_CSV) \
    --revdeps $(PACKAGE_REVDEPS_CSV) \
    --sloc $(PACKAGE_SLOC_CSV) \
    --coverage $(PACKAGE_COVERAGE_CSV) \
    --runnable-code $(PACKAGE_RUNNABLE_CODE_EVAL_CSV) \
    --out-corpus $(CORPUS_S2) \
    --out-corpus-details $(CORPUS_S2_DETAILS) \
    --out-all-details $(CORPUS_ALL_DETAILS)

$(PACKAGES_CRAN_FILE):
	$(RSCRIPT) -e 'writeLines(setdiff(installed.packages()[, 1], readLines("$(PACKAGES_CORE_FILE)")), "$@")'

$(PACKAGE_COVERAGE_CSV) $(PACKAGE_COVERAGE_STATS):
	-$(MAP) -f $(PACKAGES_FILE) -o $(@D) -e $(RUNR_TASKS_DIR)/package-coverage.R -- $(CRAN_DIR)/extracted/{1} --type all
	$(MERGE_CSV) $(@D) $(@F) $(notdir $(PACKAGE_COVERAGE_STATS))

$(PACKAGE_METADATA_FILES) $(PACKAGE_METADATA_STATS):
	$(MAP) -f $(PACKAGES_FILE) -o $(@D) -e $(RUNR_TASKS_DIR)/package-metadata.R -- $(CRAN_DIR)/extracted/{1}
	$(MERGE_CSV) $(@D) $(notdir $(PACKAGE_METADATA_FILES)) $(notdir $(PACKAGE_METADATA_STATS))

$(PACKAGE_RUNNABLE_CODE_CSV) $(PACKAGE_RUNNABLE_CODE_STATS):
	-$(MAP) -f $(PACKAGES_FILE) -o $(@D) -e $(RUNR_TASKS_DIR)/package-runnable-code.R -- $(CRAN_DIR)/extracted/{1}
	$(MERGE_CSV) $(@D) $(@F) $(notdir $(PACKAGE_RUNNABLE_CODE_STATS))

$(PACKAGE_RUNNABLE_CODE_EVAL_CSV) $(PACKAGE_RUNNABLE_CODE_EVAL_STATS):
	-$(MAP) -f $(PACKAGES_FILE) -o $(@D) -e $(RUNR_TASKS_DIR)/package-runnable-code.R -- $(CRAN_DIR)/extracted/{1} --wrap $(SCRIPTS_DIR)/eval-tracer-template.R
	$(MERGE_CSV) $(@D) $(@F) $(notdir $(PACKAGE_RUNNABLE_CODE_EVAL_STATS))

$(PACKAGE_CODE_RUN_STATS): $(PACKAGE_RUNNABLE_CODE_CSV)
	csvcut -c package,file $< --no-header-row | \
    head -10 | \
    $(MAP) -f - -o $(@D) --no-exec-wrapper -e $(SCRIPTS_DIR)/run-r-file.sh -- $(PACKAGE_RUNNABLE_CODE_DIR)/{1}

$(PACKAGE_EVALS_STATIC_CSV) $(PACKAGE_EVALS_STATIC_STATS):
	-$(MAP) -f $(PACKAGES_FILE) -o $(@D) -e $(RUNR_TASKS_DIR)/package-evals-static.R
	$(MERGE_CSV) $(@D) $(@F) $(notdir $(PACKAGE_EVALS_STATIC_STATS))

$(TRACE_EVAL_STATS): $(PACKAGE_RUNNABLE_CODE_EVAL_CSV)
	csvcut -c package,file $< --no-header-row | \
    head -10 | \
    $(MAP) -j 75% -f - -o $(@D) --no-exec-wrapper -e $(SCRIPTS_DIR)/run-r-file.sh -- $(PACKAGE_RUNNABLE_CODE_DIR)/{1}

package-metadata: $(PACKAGE_METADATA_FILES) $(PACKAGE_METADATA_STATS)
package-coverage: $(PACKAGE_COVERAGE_CSV) $(PACKAGE_COVERAGE_STATS)
package-runnable-code: $(PACKAGE_RUNNABLE_CODE_CSV) $(PACKAGE_RUNNABLE_CODE_STATS)
package-runnable-code-eval: $(PACKAGE_RUNNABLE_CODE_EVAL_CSV) $(PACKAGE_RUNNABLE_CODE_EVAL_STATS)
package-code-run: $(PACKAGE_CODE_RUN_STATS)
package-evals-static: $(PACKAGE_EVALS_STATIC_CSV) $(PACKAGE_EVALS_STATIC_STATS)
corpus: $(CORPUS_S2) $(CORPUS_S2_DETAILS) $(CORPUS_ALL_DETAILS)
trace-eval: $(TRACE_EVAL_STATS)

.PHONY: local-env
local-env:
	@echo "export R_LIBS=$(LIBRARY_DIR)"
	@echo "export PATH=$(R_DIR):$$PATH"

rstudio:
	if [ -z "$$PORT" ]; then echo "Missing PORT"; exit 1; fi
	docker run \
    --rm \
    --name "$$USER-rstudio" \
    -d \
    -p "$$PORT:8787" \
    -v "$(CURDIR):$(CURDIR)" \
    -v "$(CRAN_DIR):$(CRAN_DIR)" \
    -v "$(LIBRARY_DIR):$(LIBRARY_DIR)" \
    -e USERID=$$(id -u) \
    -e GROUPID=$$(getent group r | cut -d: -f3) \
    -e ROOT=true \
    -e DISABLE_AUTH=true \
    fikovnik/rstudio:4.0.2
