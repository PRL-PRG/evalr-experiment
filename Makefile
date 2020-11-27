# saner makefile
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

include Makevars

# extra parameters
PACKAGES_FILE ?= package-8.txt
JOBS          ?= 1
TIMEOUT       ?= 30m

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

.PHONY: \
  lib \
	libs \
  package-coverage \
  package-metadata

lib/%:
	R CMD INSTALL $*

libs: lib/injectr lib/instrumentr lib/runr lib/evil

# $(PACKAGE_CODE_SIGNATR_CSV) $(PACKAGE_CODE_SIGNATR_STATS): export OUTPUT_DIR=$(@D)
# $(PACKAGE_CODE_SIGNATR_CSV) $(PACKAGE_CODE_SIGNATR_STATS):
# 	$(ON_EACH_PACKAGE) TASK=$(SIGNATR_DIR)/inst/package-runnable-code-signatr.R
# 	$(MERGE_CSV) "$(OUTPUT_DIR)" $(@F) $(notdir $(PACKAGE_CODE_SIGNATR_STATS))

# $(SIGNATR_GBOV_RUN_CSV) $(SIGNATR_GBOV_STATS): $(PACKAGE_CODE_SIGNATR_CSV)
# $(SIGNATR_GBOV_RUN_CSV) $(SIGNATR_GBOV_STATS): export OUTPUT_DIR=$(@D)
# $(SIGNATR_GBOV_RUN_CSV) $(SIGNATR_GBOV_STATS): export START_XVFB=1
# $(SIGNATR_GBOV_RUN_CSV) $(SIGNATR_GBOV_STATS):
# 	$(ON_EACH_PACKAGE) R_DIR=$(RDT_DIR) TASK=$(RUNR_TASKS_DIR)/run-extracted-code.R ARGS="$(dir $(PACKAGE_CODE_SIGNATR_CSV))/{1/}"
# 	$(MERGE_CSV) "$(OUTPUT_DIR)" $(@F) $(notdir $(SIGNATR_GBOV_STATS))

$(PACKAGE_COVERAGE_CSV) $(PACKAGE_COVERAGE_STATS):
	-$(MAP) -f $(PACKAGES_FILE) -o $(PACKAGE_COVERAGE_DIR) -e $(RUNR_TASKS_DIR)/package-coverage.R -- $(CRAN_DIR)/extracted/{1} --type all
	$(MERGE_CSV) $(@D) $(@F) $(notdir $(PACKAGE_COVERAGE_STATS))

$(PACKAGE_METADATA_FILES) $(PACKAGE_METADATA_STATS):
	$(MAP) -f $(PACKAGES_FILE) -o $(PACKAGE_METADATA_DIR) -e $(RUNR_TASKS_DIR)/package-metadata.R -- $(CRAN_DIR)/extracted/{1}
	$(MERGE_CSV) $(@D) $(notdir $(PACKAGE_METADATA_FILES)) $(notdir $(PACKAGE_METADATA_STATS))

package-coverage: $(PACKAGE_COVERAGE_CSV) $(PACKAGE_COVERAGE_STATS)
package-metadata: $(PACKAGE_METADATA_FILES) $(PACKAGE_METADATA_STATS)
# package-code-signatr: $(PACKAGE_CODE_SIGNATR_CSV) $(PACKAGE_CODE_SIGNATR_STATS)
# signatr-gbov: $(SIGNATR_GBOV_RUN_CSV) $(SIGNATR_GBOV_STATS)

# on-each-package:
# 	@[ "$(TASK)" ] || ( echo "*** Undefined TASK"; exit 1 )
# 	@[ -x "$(TASK)" ] || ( echo "*** $(TASK): no such file"; exit 1 )
# 	@[ "$(OUTPUT_DIR)" ] || ( echo "*** Undefined OUTPUT_DIR"; exit 1 )
# 	-if [ -n "$(START_XVFB)" ]; then  \
#      nohup Xvfb :6 -screen 0 1280x1024x24 >/dev/null 2>&1 & \
#      export DISPLAY=:6; \
#   fi; \
#   export R_TESTS=""; \
#   export R_BROWSER="false"; \
#   export R_PDFVIEWER="false"; \
#   export R_BATCH=1; \
#   export NOT_CRAN="true"; \
#   echo "*** DISPLAY=$$DISPLAY"; \
#   echo "*** PATH=$$PATH"; \
#   echo "*** R_LIBS=$$R_LIBS"; \
#   mkdir -p "$(OUTPUT_DIR)"; \
#   export PATH=$$R_DIR/bin:$$PATH; \
#   parallel \
#     -a $(PACKAGES_FILE) \
#     --bar \
#     --env PATH \
#     --jobs $(JOBS) \
#     --results "$(OUTPUT_DIR)/parallel.csv" \
#     --tagstring "$(notdir $(TASK)) - {/}" \
#     --timeout $(TIMEOUT) \
#     --workdir "$(OUTPUT_DIR)/{/}/" \
#     $(RUNR_DIR)/inst/run-task.sh \
#       $(TASK) "$(PACKAGES_SRC_DIR)/{1/}" $(ARGS)

.PHONY: local-env
local-env:
	@echo "export R_LIBS=$(LIBRARY_DIR)"
	@echo "export PATH=$(R_DIR):$$PATH"
