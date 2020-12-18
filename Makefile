# saner makefile
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

include Makevars

CORPUS             := corpus.txt
CORPUS_DETAILS     := corpus.fst
CORPUS_ALL_DETAILS := corpus-all.fst

# the 13 packages that comes with R inc base
PACKAGES_CORE_FILE  := packages-core.txt
# all additional packages
PACKAGES_CRAN_FILE  := packages-cran.txt
# just base
PACKAGES_BASE_FILE  := packages-base.txt

# extra parameters
PACKAGES_FILE ?= $(PACKAGES_CRAN_FILE)
JOBS          ?= 1
TIMEOUT       ?= 35m
CORPUS_SIZE   ?= 500

PROJECT_BASE_DIR   ?= /mnt/ocfs_vol_00/project-evalr
RUN_DIR            ?= $(CURDIR)/run

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
MERGE     := $(RSCRIPT) $(RUNR_DIR)/inst/merge-files.R

# A template that is used to wrap the extracted runnable code from packages.
TRACE_EVAL_WRAP_TEMPLATE_FILE := $(SCRIPTS_DIR)/trace-eval-wrap-template.R
TRACE_EVAL_RESULTS := calls.fst \
  code.fst \
  dependencies.fst \
  lookups.fst \
  reflection.fst \
  side-effects.fst

## tasks outputs

# metadata
PACKAGE_METADATA_DIR   := $(RUN_DIR)/package-metadata
PACKAGE_METADATA_STATS := $(PACKAGE_METADATA_DIR)/parallel.csv
PACKAGE_FUNCTIONS_CSV  := $(PACKAGE_METADATA_DIR)/functions.csv
PACKAGE_METADATA_CSV   := $(PACKAGE_METADATA_DIR)/metadata.csv
PACKAGE_REVDEPS_CSV    := $(PACKAGE_METADATA_DIR)/revdeps.csv
PACKAGE_SLOC_CSV       := $(PACKAGE_METADATA_DIR)/sloc.csv
PACKAGE_METADATA_FILES := \
  $(PACKAGE_FUNCTIONS_CSV) \
  $(PACKAGE_METADATA_CSV) \
  $(PACKAGE_REVDEPS_CSV) \
  $(PACKAGE_SLOC_CSV)

# coverage
PACKAGE_COVERAGE_DIR   := $(RUN_DIR)/package-coverage
PACKAGE_COVERAGE_CSV   := $(PACKAGE_COVERAGE_DIR)/coverage.csv
PACKAGE_COVERAGE_STATS := $(PACKAGE_COVERAGE_DIR)/task-stats.csv

# runnable code
PACKAGE_RUNNABLE_CODE_DIR		:= $(RUN_DIR)/package-runnable-code
PACKAGE_RUNNABLE_CODE_CSV		:= $(PACKAGE_RUNNABLE_CODE_DIR)/runnable-code.csv
PACKAGE_RUNNABLE_CODE_STATS := $(PACKAGE_RUNNABLE_CODE_DIR)/task-stats.csv

# runnable code eval
PACKAGE_RUNNABLE_CODE_EVAL_DIR	 := $(RUN_DIR)/package-runnable-code-eval
PACKAGE_RUNNABLE_CODE_EVAL_CSV	 := $(PACKAGE_RUNNABLE_CODE_EVAL_DIR)/runnable-code.csv
PACKAGE_RUNNABLE_CODE_EVAL_STATS := $(PACKAGE_RUNNABLE_CODE_EVAL_DIR)/task-stats.csv

# code run
PACKAGE_CODE_RUN_DIR   := $(RUN_DIR)/package-code-run
PACKAGE_CODE_RUN_STATS := $(PACKAGE_CODE_RUN_DIR)/task-stats.csv

# code run eval
TRACE_EVAL_DIR   := $(RUN_DIR)/trace-eval
TRACE_EVAL_STATS := $(TRACE_EVAL_DIR)/task-stats.csv

# base tracing
BASE_TRACE_EVAL_DIR         := $(RUN_DIR)/base-trace-eval
BASE_TRACE_EVAL_SCRIPTS_TXT := $(BASE_TRACE_EVAL_DIR)/scripts.txt
BASE_TRACE_EVAL_STATS       := $(BASE_TRACE_EVAL_DIR)/parallel.csv
BASE_TRACE_EVAL_FILES := $(patsubst %,$(BASE_TRACE_EVAL_DIR)/%,$(TRACE_EVAL_RESULTS))

# static eval
PACKAGE_EVALS_STATIC_DIR		:= $(RUN_DIR)/package-evals-static
PACKAGE_EVALS_STATIC_STATS	:= $(PACKAGE_EVALS_STATIC_DIR)/task-stats.csv
PACKAGE_EVALS_STATIC_CSV		:= $(PACKAGE_EVALS_STATIC_DIR)/package-evals-static.csv

KAGGLE_KORPUS_DIR						:= $(RUN_DIR)/kaggle-korpus/notebooks/r/kernels
KAGGLE_KORPUS_METADATA_CSV  := $(KAGGLE_KORPUS_DIR)/kernels-metadata.csv
KAGGLE_DATASET_DIR					:= $(RUN_DIR)/kaggle-dataset

KAGGLE_KERNELS_DIR							:= $(RUN_DIR)/kaggle-kernels
KAGGLE_KERNELS_R								:= $(KAGGLE_KERNELS_DIR)/kernel.R
KAGGLE_KERNELS_CSV							:= $(KAGGLE_KERNELS_DIR)/kernel.csv
KAGGLE_KERNELS_EVALS_STATIC_CSV := $(KAGGLE_KERNELS_DIR)/kaggle-evals-static.csv
KAGGLE_KERNELS_STATS						:= $(KAGGLE_KERNELS_DIR)/task-stats.csv
KAGGLE_KERNELS_TO_RUN_TXT       := $(KAGGLE_KERNELS_DIR)/kernels-to-run.txt


KAGGLE_RUN_DIR   := $(RUN_DIR)/kaggle-run
KAGGLE_RUN_STATS := $(KAGGLE_RUN_DIR)/parallel.csv

KAGGLE_TRACE_EVAL_DIR   := $(RUN_DIR)/kaggle-trace-eval
KAGGLE_TRACE_EVAL_STATS := $(KAGGLE_TRACE_EVAL_DIR)/parallel.csv
KAGGLE_TRACE_EVAL_FILES := $(patsubst %,$(KAGGLE_TRACE_EVAL_DIR)/%,$(TRACE_EVAL_RESULTS))

.PHONY: \
  lib \
	libs \
  package-coverage \
  package-metadata \
  package-runnable-code \
  package-runnable-code-eval \
  package-code-run \
  package-evals-static \
  trace-eval \
  kaggle-kernels

lib/%:
	R CMD INSTALL $*

libs: lib/injectr lib/instrumentr lib/runr lib/evil

# Output all installed packages except for the ones that are part
# of R core
$(PACKAGES_CRAN_FILE):
	$(RSCRIPT) -e 'writeLines(setdiff(installed.packages()[, 1], readLines("$(PACKAGES_CORE_FILE)")), "$@")'

$(PACKAGE_METADATA_STATS):
	-$(MAP) -f $(PACKAGES_FILE) -o $(@D) -e $(RUNR_TASKS_DIR)/package-metadata.R \
    -- --types metadata,functions,revdeps,sloc \
       --cran-mirror $(CRAN_LOCAL_MIRROR) \
       $(CRAN_DIR)/extracted/{1}

$(PACKAGE_FUNCTIONS_CSV): $(PACKAGE_METADATA_STATS)
	$(MERGE) --in $(@D) --csv-cols "clllc" --key package --key-use-dirname $(@F)

$(PACKAGE_METADATA_CSV): $(PACKAGE_METADATA_STATS)
	$(MERGE) --in $(@D) --csv-cols "cccdl" --key package --key-use-dirname $(@F)

$(PACKAGE_SLOC_CSV): $(PACKAGE_METADATA_STATS)
	$(MERGE) --in $(@D) --csv-cols "ciciii" --key package --key-use-dirname $(@F)

$(PACKAGE_REVDEPS_CSV): $(PACKAGE_METADATA_STATS)
	$(MERGE) --in $(@D) --csv-cols "c" --key package --key-use-dirname $(@F)

$(CORPUS) $(CORPUS_DETAILS) $(CORPUS_ALL_DETAILS): $(PACKAGE_METADATA_FILES) $(PACKAGE_COVERAGE_CSV) $(PACKAGE_RUNNABLE_CODE_EVAL_CSV) $(PACKAGE_EVALS_STATIC_CSV)
	$(RSCRIPT) $(SCRIPTS_DIR)/corpus.R \
    --metadata $(PACKAGE_METADATA_CSV) \
    --functions $(PACKAGE_FUNCTIONS_CSV) \
    --revdeps $(PACKAGE_REVDEPS_CSV) \
    --sloc $(PACKAGE_SLOC_CSV) \
    --coverage $(PACKAGE_COVERAGE_CSV) \
    --runnable-code $(PACKAGE_RUNNABLE_CODE_EVAL_CSV) \
    --evals-static $(PACKAGE_EVALS_STATIC_CSV) \
    --out-corpus $(CORPUS) \
    --out-corpus-details $(CORPUS_DETAILS) \
    --out-all-details $(CORPUS_ALL_DETAILS)

$(PACKAGE_COVERAGE_CSV) $(PACKAGE_COVERAGE_STATS):
	-$(MAP) -f $(PACKAGES_FILE) -o $(@D) -e $(RUNR_TASKS_DIR)/package-coverage.R -- $(CRAN_DIR)/extracted/{1} --type all
	$(MERGE) $(@D) $(@F) $(notdir $(PACKAGE_COVERAGE_STATS))

$(PACKAGE_EVALS_STATIC_CSV) $(PACKAGE_EVALS_STATIC_STATS):
	-$(MAP) -f $(PACKAGES_FILE) -o $(@D) -e $(SCRIPTS_DIR)/package-evals-static.R
	$(MERGE) $(@D) $(@F) $(notdir $(PACKAGE_EVALS_STATIC_STATS))

$(PACKAGE_RUNNABLE_CODE_STATS):
	-$(MAP) -f $(PACKAGES_FILE) -o $(@D) -e $(RUNR_TASKS_DIR)/package-runnable-code.R \
    -- $(CRAN_DIR)/extracted/{1}
	$(MERGE) --in $(@D) --csv-cols "iciic" --key "package" --key-use-dirname $(@F)

$(PACKAGE_RUNNABLE_CODE_CSV): $(PACKAGE_RUNNABLE_CODE_STATS)
	$(MERGE) --in $(@D) --csv-cols "ccciii" --key "package" --key-use-dirname $(@F)

$(PACKAGE_RUNNABLE_CODE_EVAL_STATS):
	-$(MAP) -f $(PACKAGES_FILE) -o $(@D) -e $(RUNR_TASKS_DIR)/package-runnable-code.R \
    -- $(CRAN_DIR)/extracted/{1} --wrap $(TRACE_EVAL_WRAP_TEMPLATE_FILE)
	$(MERGE) --in $(@D) --csv-cols "iciic" --key "package" --key-use-dirname $(@F)

$(PACKAGE_RUNNABLE_CODE_EVAL_CSV): $(PACKAGE_RUNNABLE_CODE_EVAL_STATS)
	$(MERGE) --in $(@D) --csv-cols "ccciii" --key "package" --key-use-dirname $(@F)

$(PACKAGE_CODE_RUN_STATS): $(PACKAGE_RUNNABLE_CODE_CSV)
	-csvcut -c package,file $< | \
    $(MAP) -f - -o $(@D) -e $(SCRIPTS_DIR)/run-r-file.sh --no-exec-wrapper \
    --csv --skip-first-line \
    -- $(PACKAGE_RUNNABLE_CODE_DIR)/{1}/{2}

$(TRACE_EVAL_STATS): $(PACKAGE_RUNNABLE_CODE_EVAL_CSV)
	-csvcut -c package,file $< | \
    $(MAP) -f - -o $(@D) -e $(SCRIPTS_DIR)/run-r-file.sh --no-exec-wrapper \
    --csv --skip-first-line \
    -- $(PACKAGE_RUNNABLE_CODE_EVAL_DIR)/{1}/{2}

############################
## BASE related targets   ##
############################
$(BASE_TRACE_EVAL_SCRIPTS_TXT): $(PACKAGE_RUNNABLE_CODE_EVAL_CSV)
	-@mkdir -p $(@D)
	-$(RSCRIPT) -e \
    'glue::glue("{package}/{file}", .envir=subset(read.csv("$<"), package %in% readLines("$(CORPUS)")[1:$(CORPUS_SIZE)]))' > $@

$(BASE_TRACE_EVAL_STATS): export EVALS_TO_TRACE_FILE=$(realpath $(PACKAGES_BASE_FILE))
$(BASE_TRACE_EVAL_STATS): $(BASE_TRACE_EVAL_SCRIPTS_TXT)
	-$(MAP) -f $< -o $(@D) -e $(SCRIPTS_DIR)/run-r-file.sh --no-exec-wrapper \
    --env EVALS_TO_TRACE_FILE \
    -- -t $(TIMEOUT) $(PACKAGE_RUNNABLE_CODE_EVAL_DIR)/{1}/{2}

$(BASE_TRACE_EVAL_FILES): $(BASE_TRACE_EVAL_STATS)
	$(MERGE) --in $(@D) $(@F)

############################
## KAGGLE related targets ##
############################
##
## - in the case of kaggle a `package` in the form of
##   <competition>/<id>
## - the reason for this naming is that kaggle competitions organize the data
##   in `../input` which we link into the appropriate dir in kaggle-datasets
## - the run directory structure
##   - run/kaggle-korpus -- this is the source of all the kernels from a repo
##   - run/kaggle-datasets -- all data (cf. Makefile.kaggle)
##   - run/kaggle-kernels -- the extracted kernels
##   - run/kaggle-kernels/<package>

## turn the kernel metadata JSON file into CSV so it is easier to use
## I did not have much success with jq tool
$(KAGGLE_KORPUS_METADATA_CSV): $(KAGGLE_KORPUS_DIR)
	$(SCRIPTS_DIR)/kaggle-metadata-json2csv.R $(KAGGLE_KORPUS_DIR) $(KAGGLE_KORPUS_METADATA_CSV)

## 1. Extracts the kernel code into `kernel.R` and its metadata including file
##    hash and source lines of code into `kernel.csv` as well as the static eval
##    call sites.
## 2. Link the downloaded datasets into kaggle-kernel so the ../input works
$(KAGGLE_KERNELS_STATS): $(KAGGLE_KORPUS_METADATA_CSV)
	-csvcut -c competition,id $< | \
     $(MAP) -f - -o $(@D) -w $(@D)/{1}/{2} -e $(SCRIPTS_DIR)/kaggle.sh \
     --csv --skip-first-line --shuf \
     -- $(KAGGLE_KORPUS_DIR)/{2}/script/kernel-metadata.json \
        $(notdir $(KAGGLE_KERNELS_R)) \
        $(notdir $(KAGGLE_KERNELS_CSV)) \
        $(notdir $(KAGGLE_KERNELS_EVALS_STATIC_CSV)) \
				$(TRACE_EVAL_WRAP_TEMPLATE_FILE)
	$(MERGE) --in $(@D) --csv-cols "iciic" --key "package" --key-use-dirname $(@F)
	fd --type d --max-depth 1 . $(KAGGLE_DATASET_DIR) -x ln -sfT {} $(KAGGLE_KERNELS_DIR)/{/}/input

$(KAGGLE_KERNELS_CSV): $(KAGGLE_KERNELS_STATS)
	$(MERGE) --in $(@D) --csv-cols "ccccciiic" --key "package" --key-use-dirname $(@F)

$(KAGGLE_KERNELS_EVALS_STATIC_CSV): $(KAGGLE_KERNELS_STATS)
	$(MERGE) --in $(@D) --csv-cols "cciiiicc" --key "package" --key-use-dirname $(@F)

$(KAGGLE_KERNELS_TO_RUN_TXT): $(KAGGLE_KERNELS_CSV) $(KAGGLE_KERNELS_EVALS_STATIC_CSV)
	$(SCRIPTS_DIR)/kaggle-scripts-to-run.R --metadata $(KAGGLE_KERNELS_CSV) --evals-static $(KAGGLE_KERNELS_EVALS_STATIC_CSV) > $@

$(KAGGLE_RUN_STATS): $(KAGGLE_KERNELS_TO_RUN_TXT) $(KAGGLE_DATASET_DIR)
	-$(MAP) -f $(KAGGLE_KERNELS_TO_RUN_TXT) -o $(@D) -e $(SCRIPTS_DIR)/run-r-file.sh --no-exec-wrapper \
    -- $(KAGGLE_KERNELS_DIR)/{1}/kernel-original.R

$(KAGGLE_TRACE_EVAL_STATS): $(KAGGLE_KERNELS_TO_RUN_TXT) $(KAGGLE_DATASET_DIR)
	-$(MAP) -t 1d -f $(KAGGLE_KERNELS_TO_RUN_TXT) -o $(@D) -e $(SCRIPTS_DIR)/run-r-file.sh --no-exec-wrapper \
    -- $(KAGGLE_KERNELS_DIR)/{1}/kernel.R

$(KAGGLE_TRACE_EVAL_FILES): $(KAGGLE_TRACE_EVAL_STATS)
	$(MERGE) --in $(@D) $(@F)

package-metadata: $(PACKAGE_METADATA_FILES) $(PACKAGE_METADATA_STATS)
package-coverage: $(PACKAGE_COVERAGE_CSV) $(PACKAGE_COVERAGE_STATS)
package-runnable-code: $(PACKAGE_RUNNABLE_CODE_CSV) $(PACKAGE_RUNNABLE_CODE_STATS)
package-runnable-code-eval: $(PACKAGE_RUNNABLE_CODE_EVAL_CSV) $(PACKAGE_RUNNABLE_CODE_EVAL_STATS)
package-code-run: $(PACKAGE_CODE_RUN_STATS)
package-evals-static: $(PACKAGE_EVALS_STATIC_CSV) $(PACKAGE_EVALS_STATIC_STATS)
corpus: $(CORPUS) $(CORPUS_DETAILS) $(CORPUS_ALL_DETAILS)
trace-eval: $(TRACE_EVAL_STATS)
kaggle-kernels: $(KAGGLE_KERNELS_CSV) $(KAGGLE_KERNELS_EVALS_STATIC_CSV) $(KAGGLE_KERNELS_STATS)
kaggle-run: $(KAGGLE_RUN_STATS)
kaggle-trace-eval: $(KAGGLE_TRACE_EVAL_FILES)
base-trace-eval: $(BASE_TRACE_EVAL_STATS)

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
