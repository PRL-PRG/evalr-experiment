# saner makefile
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

include Makevars

# extra parameters
PACKAGES_FILE ?= packages-1.txt
JOBS          ?= 1
TIMEOUT       ?= 30m
CORPUS_SIZE   ?= 500

CORPUS_S1         := corpus-stage1.txt
CORPUS_S2         := corpus-stage2.txt
CORPUS_S2_REVDEPS := corpus-stage2-revdeps.txt

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

# client code
CLIENT_CODE_PACKAGES := client-code-packages.txt
CLIENT_CODE_FILE ?= client-code.txt

# code run
PACKAGE_CODE_RUN_DIR := $(RUN_DIR)/package-code-run
PACKAGE_CODE_RUN_STATS := $(PACKAGE_CODE_RUN_DIR)/task-stats.csv

# code run eval
TRACE_EVAL_DIR := $(RUN_DIR)/trace-eval
TRACE_EVAL_STATS := $(TRACE_EVAL_DIR)/task-stats.csv

.PHONY: \
  lib \
	libs \
  package-coverage \
  package-metadata \
  package-runnable-code \
  package-runnable-code-eval \
  package-code-run \
  trace-eval

lib/%:
	R CMD INSTALL $*

libs: lib/injectr lib/instrumentr lib/runr lib/evil

$(CORPUS_S2) $(CORPUS_S2_REVDEPS): $(PACKAGE_REVDEPS_CSV) $(PACKAGE_COVERAGE_CSV)
	$(RSCRIPT) $(SCRIPTS_DIR)/corpus-stage2.R \
    --coverage $(PACKAGE_COVERAGE_CSV) \
    --revdeps $(PACKAGE_REVDEPS_CSV) \
    --num $(CORPUS_SIZE) \
    --out-packages $(CORPUS_S2) \
    --out-revdeps $(CORPUS_S2_REVDEPS)

$(CLIENT_CODE_PACKAGES): $(CORPUS_S2) $(CORPUS_S2_REVDEPS)
	cat $(CORPUS_S2) $(CORPUS_S2_REVDEPS) > $(CLIENT_CODE_PACKAGES)

$(CLIENT_CODE_FILE): $(CLIENT_CODE_PACKAGES) $(PACKAGE_RUNNABLE_CODE_CSV)
	$(RSCRIPT) $(SCRIPTS_DIR)/client-code.R \
    --runnable-code $(PACKAGE_RUNNABLE_CODE_CSV) \
    --packages $(CLIENT_CODE_PACKAGES) \
    --out $(CLIENT_CODE_FILE)

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

$(PACKAGE_CODE_RUN_STATS): $(CLIENT_CODE_FILE)
	$(MAP) -f $(CLIENT_CODE_FILE) -o $(@D) -e $(SCRIPTS_DIR)/run-r-file.sh -- $(PACKAGE_RUNNABLE_CODE_DIR)/{1}
#	$(MAP) -f $(CLIENT_CODE_FILE) -o $(@D) -e $(RUNR_TASKS_DIR)/run-file.R -- $(PACKAGE_RUNNABLE_CODE_DIR)/{1}

$(TRACE_EVAL_STATS): $(CLIENT_CODE_FILE)
	EVAL_PACKAGES_FILE=$(realpath $(CORPUS_S2)) \
  $(MAP) --env EVAL_PACKAGES_FILE -f $(CLIENT_CODE_FILE) -o $(@D) -e $(SCRIPTS_DIR)/run-r-file.sh -- $(PACKAGE_RUNNABLE_CODE_EVAL_DIR)/{1}

package-metadata: $(PACKAGE_METADATA_FILES) $(PACKAGE_METADATA_STATS)
package-coverage: $(PACKAGE_COVERAGE_CSV) $(PACKAGE_COVERAGE_STATS)
package-runnable-code: $(PACKAGE_RUNNABLE_CODE_CSV) $(PACKAGE_RUNNABLE_CODE_STATS)
package-runnable-code-eval: $(PACKAGE_RUNNABLE_CODE_EVAL_CSV) $(PACKAGE_RUNNABLE_CODE_EVAL_STATS)
package-code-run: $(PACKAGE_CODE_RUN_STATS)
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
