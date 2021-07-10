# Saner makefile
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

include Makevars

# This file contains a list of all packages we want to include
# We will get metadata from them including static eval call sites
PACKAGES := packages.txt

# the 13 packages that comes with R inc base
PACKAGES_CORE_FILE := packages-core.txt

# Environment
CRAN_LOCAL_MIRROR  := file://$(CRAN_DIR)
CRAN_SRC_DIR       := $(CRAN_DIR)/extracted
CRAN_ZIP_DIR       := $(CRAN_DIR)/src/contrib
RUNR_DIR           := $(R_DIR)/library/runr
RUNR_TASKS_DIR     := $(RUNR_DIR)/tasks

# A subset of $(PACKAGES); only packages with call sites to eval
CORPUS             := $(RUN_DIR)/corpus.txt
CORPUS_DETAILS     := $(RUN_DIR)/corpus.fst

# Where to fetch the libraries - override if need to clone using SSH
REPO_BASE_URL ?= "https://github.com"
# Our libraries required for the experiment
LIBS := injectr instrumentr evil runr

# Remote execution
ifeq ($(CLUSTER), 1)
    MAP_EXTRA=--sshloginfile $(SSH_LOGIN_FILE)
    JOBS=100%
endif

# The number of jobs to run in parallel
# It is used for GNU parallel and for Ncpus parameter in install.packages
JOBS          ?= $(shell sysctl -n hw.ncpu 2>/dev/null || nproc -a 2>/dev/null || grep -c processor /proc/cpuinfo 2>/dev/null || echo 1)
# The timeout used for both the individual tasks in GNU parallel and in the run-r-file.sh
TIMEOUT       ?= 35m
# Max scripts to run for tracing evals in the base package
BASE_SCRIPTS_TO_RUN_SIZE := 25000

# Tools
MAP				:= $(RUNR_DIR)/map.sh -j $(JOBS) $(MAP_EXTRA)
MERGE     := $(RSCRIPT) $(RUNR_DIR)/merge-files.R
ROLLBACK  := $(SCRIPTS_DIR)/rollback.sh
CAT       := $(SCRIPTS_DIR)/cat.R

# A template that is used to wrap the extracted runnable code from packages.
TRACE_EVAL_WRAP_TEMPLATE_FILE := $(SCRIPTS_DIR)/trace-eval-wrap-template.R
# Tracing results to be merged
TRACE_EVAL_RESULTS := \
  calls.fst \
  code.fst \
  dependencies.fst \
  reads.fst \
  reflection.fst \
  writes.fst \
  resolved-expressions.fst \
  provenances.fst

.PHONY: FORCE
########################################################################
# TASKS OUTPUTS
########################################################################

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
PACKAGE_COVERAGE_STATS := $(PACKAGE_COVERAGE_DIR)/parallel.csv
PACKAGE_COVERAGE_CSV   := $(PACKAGE_COVERAGE_DIR)/coverage.csv

# static eval
PACKAGE_EVALS_STATIC_DIR		:= $(RUN_DIR)/package-evals-static
PACKAGE_EVALS_STATIC_STATS	:= $(PACKAGE_EVALS_STATIC_DIR)/parallel.csv
PACKAGE_EVALS_STATIC_CSV		:= $(PACKAGE_EVALS_STATIC_DIR)/package-evals-static.csv

# runnable code
PACKAGE_RUNNABLE_CODE_DIR		:= $(RUN_DIR)/package-runnable-code
PACKAGE_RUNNABLE_CODE_CSV		:= $(PACKAGE_RUNNABLE_CODE_DIR)/runnable-code.csv
PACKAGE_RUNNABLE_CODE_STATS := $(PACKAGE_RUNNABLE_CODE_DIR)/parallel.csv

# runnable code eval
PACKAGE_RUNNABLE_CODE_EVAL_DIR	 := $(RUN_DIR)/package-runnable-code-eval
PACKAGE_RUNNABLE_CODE_EVAL_CSV	 := $(PACKAGE_RUNNABLE_CODE_EVAL_DIR)/runnable-code.csv
PACKAGE_RUNNABLE_CODE_EVAL_STATS := $(PACKAGE_RUNNABLE_CODE_EVAL_DIR)/parallel.csv

# code run
PACKAGE_RUN_DIR   := $(RUN_DIR)/package-run
PACKAGE_RUN_STATS := $(PACKAGE_RUN_DIR)/parallel.csv

# trace
PACKAGE_TRACE_EVAL_DIR         := $(RUN_DIR)/package-trace-eval
PACKAGE_TRACE_EVAL_STATS       := $(PACKAGE_TRACE_EVAL_DIR)/parallel.csv
PACKAGE_TRACE_EVAL_FILES       := $(patsubst %,$(PACKAGE_TRACE_EVAL_DIR)/%,$(TRACE_EVAL_RESULTS))
PACKAGE_TRACE_EVAL_CALLS       := $(PACKAGE_TRACE_EVAL_DIR)/calls.fst
PACKAGE_TRACE_EVAL_CODE        := $(PACKAGE_TRACE_EVAL_DIR)/code.fst
PACKAGE_TRACE_EVAL_REFLECTION  := $(PACKAGE_TRACE_EVAL_DIR)/reflection.fst
PACKAGE_TRACE_EVAL_WRITES      := $(PACKAGE_TRACE_EVAL_DIR)/writes.fst
PACKAGE_TRACE_EVAL_PROVENANCES := $(PACKAGE_TRACE_EVAL_DIR)/provenances.fst
PACKAGE_SCRIPTS_TO_RUN_TXT     ?= $(RUN_DIR)/package-scripts-to-run.txt
PACKAGE_EVALS_TO_TRACE         := $(RUN_DIR)/package-evals-to-trace.txt

# base static evals
BASE_EVALS_STATIC_DIR   := $(RUN_DIR)/base-evals-static
BASE_EVALS_STATIC_STATS := $(BASE_EVALS_STATIC_DIR)/parallel.csv
BASE_EVALS_STATIC_CSV   := $(BASE_EVALS_STATIC_DIR)/base-evals-static.csv

# base run
BASE_RUN_DIR   := $(RUN_DIR)/base-run
BASE_RUN_STATS := $(BASE_RUN_DIR)/parallel.csv

# base tracing
BASE_TRACE_EVAL_DIR     := $(RUN_DIR)/base-trace-eval
BASE_TRACE_EVAL_STATS   := $(BASE_TRACE_EVAL_DIR)/parallel.csv
BASE_TRACE_EVAL_FILES   := $(patsubst %,$(BASE_TRACE_EVAL_DIR)/%,$(TRACE_EVAL_RESULTS))
BASE_TRACE_EVAL_CALLS   := $(BASE_TRACE_EVAL_DIR)/calls.fst
BASE_TRACE_EVAL_REFLECTION   := $(BASE_TRACE_EVAL_DIR)/reflection.fst
BASE_SCRIPTS_TO_RUN_TXT := $(RUN_DIR)/base-scripts-to-run.txt

# based on the last run, except for:
# - leaf-classification/primenumber-random-forest (10hrs)
# - santander-product-recommendation/katerynad-know-your-data-part-2-products (>24h)
# all kernels finish within 2hrs. Given that we might add stuff to
# tracer, run other parallel tasks, we set the timeout to 4hrs
KAGGLE_TIMEOUT              := 4h
KAGGLE_KORPUS_DIR						:= $(RUN_DIR)/kaggle-korpus/notebooks/r/kernels
KAGGLE_KORPUS_METADATA_CSV  := $(KAGGLE_KORPUS_DIR)/kernels-metadata.csv
KAGGLE_DATASET_DIR					:= $(RUN_DIR)/kaggle-dataset

KAGGLE_KERNELS_DIR							:= $(RUN_DIR)/kaggle-kernels
KAGGLE_KERNELS_R								:= $(KAGGLE_KERNELS_DIR)/kernel.R
KAGGLE_KERNELS_CSV							:= $(KAGGLE_KERNELS_DIR)/kernel.csv
KAGGLE_KERNELS_EVALS_STATIC_CSV := $(KAGGLE_KERNELS_DIR)/kaggle-evals-static.csv
KAGGLE_KERNELS_STATS						:= $(KAGGLE_KERNELS_DIR)/parallel.csv
KAGGLE_SCRIPTS_TO_RUN_TXT       := $(RUN_DIR)/kaggle-scripts-to-run.txt
KAGGLE_CORPUS_FILE              := $(KAGGLE_KERNELS_DIR)/corpus.txt

KAGGLE_RUN_DIR   := $(RUN_DIR)/kaggle-run
KAGGLE_RUN_STATS := $(KAGGLE_RUN_DIR)/parallel.csv

KAGGLE_TRACE_EVAL_DIR   := $(RUN_DIR)/kaggle-trace-eval
KAGGLE_TRACE_EVAL_STATS := $(KAGGLE_TRACE_EVAL_DIR)/parallel.csv
KAGGLE_TRACE_EVAL_FILES := $(patsubst %,$(KAGGLE_TRACE_EVAL_DIR)/%,$(TRACE_EVAL_RESULTS))
KAGGLE_TRACE_EVAL_CALLS := $(KAGGLE_TRACE_EVAL_DIR)/calls.fst
KAGGLE_TRACE_EVAL_REFLECTION := $(KAGGLE_TRACE_EVAL_DIR)/reflection.fst

########################################################################
# MACROS
########################################################################

define PKG_INSTALL_FROM_FILE
	$(call LOG,Installing packages from file: $(1))
	$(R) --quiet --no-save -e 'install.packages(if (Sys.getenv("FORCE_INSTALL")=="1") readLines("$(1)") else setdiff(readLines("$(1)"), installed.packages("$(R_LIBS)")[,1]), dependencies=TRUE, repos="$(CRAN_MIRROR)", destdir="$(CRAN_ZIP_DIR)", Ncpus=$(JOBS))'
	$(call LOG,Extracting package source)
	@for f in $$(find $(CRAN_ZIP_DIR) -name "*.tar.gz"); do \
		d=$(CRAN_SRC_DIR)/$$(basename $$f | sed 's/\([^_]*\).*/\1/'); \
		[ -d $$d ] || { echo "- $$(basename $$f)"; tar xfz $$f -C $(CRAN_SRC_DIR); } \
	done
endef

define INSTALL_EVALR_LIB
	$(call LOG,Installing evalr library: $(1))
	make -C $(1) clean install
endef

# note: the extra new-line at the end of the macro is important
#       because it is called from a foreach macro
define CLONE_REPO
  $(call LOG,Repo $(REPO_BASE_URL)/$(1)/$(2))
	if [ -d $(2) ]; then git -C $(2) pull; else git clone $(REPO_BASE_URL)/$(1)/$(2); fi

endef

define ASSERT_NOT_IN_DOCKER
	@if [ -n "$$IN_DOCKER" ]; then echo "This make target ($@) should not be run in docker!"; exit 1; fi
endef

########################################################################
# PACKAGES related targets
########################################################################

$(PACKAGE_METADATA_STATS): $(PACKAGES)
	$(call LOG,PACKAGE METADATA)
	-$(MAP) -t $(TIMEOUT) --override -f $< -o $(@D) -e $(RUNR_TASKS_DIR)/package-metadata.R \
    -- --types metadata,functions,revdeps,sloc \
       --cran-mirror $(CRAN_LOCAL_MIRROR) \
       $(CRAN_DIR)/extracted/{1}

$(PACKAGE_FUNCTIONS_CSV): $(PACKAGE_METADATA_STATS)
	$(call LOG,MERGING $(@F))
	$(MERGE) --in $(@D) --csv-cols "clllc" --key package --key-use-dirname $(@F)

$(PACKAGE_METADATA_CSV): $(PACKAGE_METADATA_STATS)
	$(call LOG,MERGING $(@F))
	$(MERGE) --in $(@D) --csv-cols "cccdl" --key package --key-use-dirname $(@F)

$(PACKAGE_SLOC_CSV): $(PACKAGE_METADATA_STATS)
	$(call LOG,MERGING $(@F))
	$(MERGE) --in $(@D) --csv-cols "ciciii" --key package --key-use-dirname $(@F)

$(PACKAGE_REVDEPS_CSV): $(PACKAGE_METADATA_STATS)
	$(call LOG,MERGING $(@F))
	$(MERGE) --in $(@D) --csv-cols "c" --key package --key-use-dirname $(@F)

$(PACKAGE_COVERAGE_STATS): $(PACKAGES)
	$(call LOG,PACKAGE COVERAGE)
	-$(MAP) -t $(TIMEOUT) --override -f $< -o $(@D) -e $(RUNR_TASKS_DIR)/package-coverage.R \
    -- --type all $(CRAN_DIR)/extracted/{1}

$(PACKAGE_COVERAGE_CSV): $(PACKAGE_COVERAGE_STATS)
	$(call LOG,MERGING $(@F))
	$(MERGE) --in $(@D) --csv-cols "ccdd" --key package --key-use-dirname $(@F)

$(PACKAGE_EVALS_STATIC_STATS): $(PACKAGES)
	$(call LOG,PACKAGE STATIC EVALS)
	-$(MAP) -t $(TIMEOUT) --override -f $< -o $(@D) -e $(SCRIPTS_DIR)/package-evals-static.R \
    -- --type package --out $(notdir $(PACKAGE_EVALS_STATIC_CSV)) {1}

$(PACKAGE_EVALS_STATIC_CSV): $(PACKAGE_EVALS_STATIC_STATS)
	$(call LOG,MERGING $(@F))
	$(MERGE) --in $(@D) --csv-cols "cccc" --key "package" --key-use-dirname $(@F)

$(PACKAGE_RUNNABLE_CODE_STATS): $(PACKAGES)
	$(call LOG,PACKAGE RUNNABLE CODE)
	-$(MAP) -t $(TIMEOUT) --override -f $< -o $(@D) -e $(RUNR_TASKS_DIR)/package-runnable-code.R \
    -- $(CRAN_DIR)/extracted/{1}

$(PACKAGE_RUNNABLE_CODE_CSV): $(PACKAGE_RUNNABLE_CODE_STATS)
	$(call LOG,MERGING $(@F))
	$(MERGE) --in $(@D) --csv-cols "ccciii" --key "package" --key-use-dirname $(@F)

$(PACKAGE_RUNNABLE_CODE_EVAL_STATS): $(PACKAGES)
	$(call LOG,PACKAGE RUNNABLE CODE FOR EVAL TRACING)
	-$(MAP) -t $(TIMEOUT) --override -f $< -o $(@D) -e $(RUNR_TASKS_DIR)/package-runnable-code.R \
    -- $(CRAN_DIR)/extracted/{1} --wrap $(TRACE_EVAL_WRAP_TEMPLATE_FILE)

$(PACKAGE_RUNNABLE_CODE_EVAL_CSV): $(PACKAGE_RUNNABLE_CODE_EVAL_STATS)
	$(call LOG,MERGING $(@F))
	$(MERGE) --in $(@D) --csv-cols "ccciii" --key "package" --key-use-dirname $(@F)

$(CORPUS) $(CORPUS_DETAILS): $(PACKAGE_METADATA_FILES) $(PACKAGE_RUNNABLE_CODE_EVAL_CSV) $(PACKAGE_EVALS_STATIC_CSV)
	$(call LOG,CORPUS)
	$(RSCRIPT) $(SCRIPTS_DIR)/corpus.R \
    --metadata $(PACKAGE_METADATA_CSV) \
    --functions $(PACKAGE_FUNCTIONS_CSV) \
    --revdeps $(PACKAGE_REVDEPS_CSV) \
    --sloc $(PACKAGE_SLOC_CSV) \
    --coverage $(PACKAGE_COVERAGE_CSV) \
    --runnable-code $(PACKAGE_RUNNABLE_CODE_EVAL_CSV) \
    --evals-static $(PACKAGE_EVALS_STATIC_CSV) \
    --out-corpus $(CORPUS) \
    --out-corpus-details $(CORPUS_DETAILS)

$(PACKAGE_SCRIPTS_TO_RUN_TXT): $(PACKAGE_RUNNABLE_CODE_EVAL_CSV)
	$(call LOG,LIST OF SCRIPTS TO RUN)
	$(CAT) -c package,file -d '/' --no-header $< > $@

# need to explicitly state the dependency on PACKAGE_RUNNABLE_CODE_STATS because
# the PACKAGE_SCRIPTS_TO_RUN_TXT is generated from the eval data
.PRECIOUS: $(PACKAGE_RUN_STATS)
$(PACKAGE_RUN_STATS): $(PACKAGE_RUNNABLE_CODE_STATS) $(PACKAGE_SCRIPTS_TO_RUN_TXT)
	$(call LOG,PACKAGE RUN)
	-$(MAP) -f $(PACKAGE_SCRIPTS_TO_RUN_TXT) -o $(@D) -e $(SCRIPTS_DIR)/run-r-file.sh --no-exec-wrapper \
    -- -t $(TIMEOUT) $(PACKAGE_RUNNABLE_CODE_DIR)/{1}

$(PACKAGE_EVALS_TO_TRACE): $(CORPUS) $(PACKAGE_EVALS_STATIC_CSV)
	$(call LOG,LIST OF EVALS TO TRACE)
	$(SCRIPTS_DIR)/package-evals-static-summary.R \
    --corpus $(CORPUS) \
    --evals-static $(PACKAGE_EVALS_STATIC_CSV) > $@

.PRECIOUS: $(PACKAGE_TRACE_EVAL_STATS)
$(PACKAGE_TRACE_EVAL_STATS): export EVALS_TO_TRACE=packages
$(PACKAGE_TRACE_EVAL_STATS): export EVALS_IMPUTE_SRCREF_FILE=$(realpath $(PACKAGE_EVALS_TO_TRACE))
$(PACKAGE_TRACE_EVAL_STATS): $(PACKAGE_EVALS_TO_TRACE) $(PACKAGE_SCRIPTS_TO_RUN_TXT)
	$(call LOG,PACKAGE EVAL TRACING)
	@echo "- Tracing evals (EVALS_TO_TRACE): $$EVALS_TO_TRACE"
	@echo "- Evals srcref (EVALS_IMPUTE_SRCREF_FILE): $$EVALS_IMPUTE_SRCREF_FILE"
	-$(MAP) -f $(PACKAGE_SCRIPTS_TO_RUN_TXT) -o $(@D) -e $(SCRIPTS_DIR)/run-r-file.sh --no-exec-wrapper \
    --env EVALS_TO_TRACE \
    --env EVALS_IMPUTE_SRCREF_FILE \
    -- -t $(TIMEOUT) $(PACKAGE_RUNNABLE_CODE_EVAL_DIR)/{1}

$(PACKAGE_TRACE_EVAL_FILES): $(PACKAGE_TRACE_EVAL_STATS)
	$(call LOG,MERGING $(@F))
	$(MERGE) --in $(@D) $(@F)

########################################################################
## BASE related targets
########################################################################

$(BASE_EVALS_STATIC_STATS): $(PACKAGES_CORE_FILE)
	$(call LOG,EXTRACT EVAL CALLSITES: $(@F))
	-$(MAP) -t $(TIMEOUT) -f $< -o $(@D) -e $(SCRIPTS_DIR)/package-evals-static.R \
    -- --type package --out $(notdir $(BASE_EVALS_STATIC_CSV)) {1}

$(BASE_EVALS_STATIC_CSV): $(BASE_EVALS_STATIC_STATS)
	$(call LOG,MERGING $(@F))
	$(MERGE) --in $(@D) --csv-cols "cccc" --key "package" --key-use-dirname $(@F)

$(BASE_SCRIPTS_TO_RUN_TXT): $(PACKAGE_RUNNABLE_CODE_EVAL_CSV)
	$(call LOG,LIST OF SCRIPTS TO RUN: $(@F))
	$(CAT) --limit $(BASE_SCRIPTS_TO_RUN_SIZE) --shuffle --no-header --columns package,file --delim '/' $< > $@

.PRECIOUS: $(BASE_RUN_STATS)
$(BASE_RUN_STATS): $(BASE_SCRIPTS_TO_RUN_TXT)
	-$(MAP) -f $< -o $(@D) -e $(SCRIPTS_DIR)/run-r-file.sh --no-exec-wrapper \
    -- -t $(TIMEOUT) $(PACKAGE_RUNNABLE_CODE_DIR)/{1}

.PRECIOUS: $(BASE_TRACE_EVAL_STATS)
$(BASE_TRACE_EVAL_STATS): export EVALS_TO_TRACE=base
$(BASE_TRACE_EVAL_STATS): export EVALS_IMPUTE_SRCREF_FILE=$(realpath $(PACKAGES_CORE_FILE))
$(BASE_TRACE_EVAL_STATS): $(BASE_SCRIPTS_TO_RUN_TXT)
	$(call LOG,EVAL TRACING $(@F))
	-$(MAP) -f $< -o $(@D) -e $(SCRIPTS_DIR)/run-r-file.sh --no-exec-wrapper \
    --env EVALS_TO_TRACE \
    --env EVALS_IMPUTE_SRCREF_FILE \
    -- -t $(TIMEOUT) $(PACKAGE_RUNNABLE_CODE_EVAL_DIR)/{1}

$(BASE_TRACE_EVAL_FILES): $(BASE_TRACE_EVAL_STATS)
	$(call LOG,MERGING $(@F))
	$(MERGE) --in $(@D) $(@F)

########################################################################
# KAGGLE related targets
########################################################################
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
	$(call LOG,KORPUS METADATA: $(@F))
	$(SCRIPTS_DIR)/kaggle-metadata-json2csv.R $(KAGGLE_KORPUS_DIR) $(KAGGLE_KORPUS_METADATA_CSV)

## 1. Extracts the kernel code into `kernel.R` and its metadata including file
##    hash and source lines of code into `kernel.csv` as well as the static eval
##    call sites.
## 2. Link the downloaded datasets into kaggle-kernel so the ../input works
$(KAGGLE_KERNELS_STATS): $(KAGGLE_KORPUS_METADATA_CSV)
	$(call LOG,EXTRACTING KERNELS: $(@F))
	-$(CAT) -c competition,id $< | \
     $(MAP) -f - -o $(@D) -w $(@D)/{1}/{2} -e $(SCRIPTS_DIR)/kaggle.sh \
     -C ',' --skip-first-line \
     -- $(KAGGLE_KORPUS_DIR)/{2}/script/kernel-metadata.json \
        $(notdir $(KAGGLE_KERNELS_R)) \
        $(notdir $(KAGGLE_KERNELS_CSV)) \
        $(notdir $(KAGGLE_KERNELS_EVALS_STATIC_CSV)) \
				$(TRACE_EVAL_WRAP_TEMPLATE_FILE)
	fd --type d --max-depth 1 . $(KAGGLE_DATASET_DIR) -x ln -sfT {} $(KAGGLE_KERNELS_DIR)/{/}/input

$(KAGGLE_KERNELS_CSV): $(KAGGLE_KERNELS_STATS)
	$(call LOG,MERGING: $(@F))
	$(MERGE) --in $(@D) --csv-cols "ccccciiic" --key "package" --key-use-dirname $(@F)

$(KAGGLE_KERNELS_EVALS_STATIC_CSV): $(KAGGLE_KERNELS_STATS)
	$(call LOG,MERGING: $(@F))
	$(MERGE) --in $(@D) --csv-cols "cccc" --key "package" --key-use-dirname $(@F)

$(KAGGLE_SCRIPTS_TO_RUN_TXT): $(KAGGLE_KERNELS_CSV) $(KAGGLE_KERNELS_EVALS_STATIC_CSV)
	$(call LOG,LIST OF SCRIPTS TO RUN: $(@F))
	$(SCRIPTS_DIR)/kaggle-scripts-to-run.R --metadata $(KAGGLE_KERNELS_CSV) --evals-static $(KAGGLE_KERNELS_EVALS_STATIC_CSV) > $@

$(KAGGLE_CORPUS_FILE): $(KAGGLE_SCRIPTS_TO_RUN_TXT)
	parallel -a $< -j 1 basename > $@

.PRECIOUS: $(KAGGLE_RUN_STATS)
$(KAGGLE_RUN_STATS): $(KAGGLE_SCRIPTS_TO_RUN_TXT) $(KAGGLE_DATASET_DIR)
	$(call LOG,KAGGLE RUN: $(@F))
	-$(MAP) -f $(KAGGLE_SCRIPTS_TO_RUN_TXT) -o $(@D) -e $(SCRIPTS_DIR)/run-r-file.sh --no-exec-wrapper \
    -- -t $(KAGGLE_TIMEOUT) $(KAGGLE_KERNELS_DIR)/{1}/kernel-original.R

.PRECIOUS: $(KAGGLE_TRACE_EVAL_STATS)
$(KAGGLE_TRACE_EVAL_STATS): export EVALS_TO_TRACE=global
$(KAGGLE_TRACE_EVAL_STATS): $(KAGGLE_SCRIPTS_TO_RUN_TXT) $(KAGGLE_DATASET_DIR)
	$(call LOG,KAGGLE EVAL TRACING: $(@F))
	-$(MAP) -f $(KAGGLE_SCRIPTS_TO_RUN_TXT) -o $(@D) -e $(SCRIPTS_DIR)/run-r-file.sh --no-exec-wrapper \
    --env EVALS_TO_TRACE \
    -- -t $(KAGGLE_TIMEOUT) $(KAGGLE_KERNELS_DIR)/{1}/kernel.R

$(KAGGLE_TRACE_EVAL_FILES): $(KAGGLE_TRACE_EVAL_STATS)
	$(call LOG,MERGING: $(@F))
	$(MERGE) --in $(@D) $(@F)

########################################################################
# PREPROCESS
########################################################################
PREPROCESS_TYPE ?= "all"

PACKAGE_PREPROCESS_DIR			:= $(PREPROCESS_DIR)/package
PACKAGE_SUM_FILE						:= $(PACKAGE_PREPROCESS_DIR)/summarized.fst
PACKAGE_SUM_EXTERNALS_FILE	:= $(PACKAGE_PREPROCESS_DIR)/summarized-externals.fst
PACKAGE_SUM_UNDEFINED_FILE	:= $(PACKAGE_PREPROCESS_DIR)/undefined.fst
PACKAGE_PREPROCESS_FILES    := \
  $(PACKAGE_SUM_FILE) $(PACKAGE_SUM_EXTERNALS_FILE) $(PACKAGE_SUM_UNDEFINED_FILE)
PACKAGE_NORMALIZED_EXPR_FILE := $(PACKAGE_PREPROCESS_DIR)/normalized-expressions.csv
PACKAGE_RESOLVED_EXPRESSIONS := $(PACKAGE_TRACE_EVAL_DIR)/resolved-expressions.fst
PACKAGE_SIDE_EFFECTS_FILE    := $(PACKAGE_PREPROCESS_DIR)/side-effects.fst

BASE_PREPROCESS_DIR			 := $(PREPROCESS_DIR)/base
BASE_SUM_FILE						 := $(BASE_PREPROCESS_DIR)/summarized.fst
BASE_SUM_EXTERNALS_FILE	 := $(BASE_PREPROCESS_DIR)/summarized-externals.fst
BASE_SUM_UNDEFINED_FILE	 := $(BASE_PREPROCESS_DIR)/undefined.fst
BASE_PREPROCESS_FILES    := \
  $(BASE_SUM_FILE) $(BASE_SUM_EXTERNALS_FILE) $(BASE_SUM_UNDEFINED_FILE)
BASE_NORMALIZED_EXPR_FILE := $(BASE_PREPROCESS_DIR)/normalized-expressions.csv
BASE_RESOLVED_EXPRESSIONS := $(BASE_TRACE_EVAL_DIR)/resolved-expressions.fst

KAGGLE_PREPROCESS_DIR			 := $(PREPROCESS_DIR)/kaggle
KAGGLE_SUM_FILE						 := $(KAGGLE_PREPROCESS_DIR)/summarized.fst
KAGGLE_SUM_EXTERNALS_FILE	 := $(KAGGLE_PREPROCESS_DIR)/summarized-externals.fst
KAGGLE_SUM_UNDEFINED_FILE	 := $(KAGGLE_PREPROCESS_DIR)/undefined.fst
KAGGLE_PREPROCESS_FILES    := \
  $(KAGGLE_SUM_FILE) $(KAGGLE_SUM_EXTERNALS_FILE) $(KAGGLE_SUM_UNDEFINED_FILE)
KAGGLE_NORMALIZED_EXPR_FILE := $(KAGGLE_PREPROCESS_DIR)/normalized-expressions.csv
KAGGLE_RESOLVED_EXPRESSIONS := $(KAGGLE_TRACE_EVAL_DIR)/resolved-expressions.fst

$(PACKAGE_SIDE_EFFECTS_FILE): $(PACKAGE_TRACE_EVAL_CALLS) $(PACKAGE_TRACE_EVAL_WRITES)
	$(call LOG,PREPROCESSING SIDE EFFECTS)
	-mkdir -p $(@D)
	$(RSCRIPT) $(SCRIPTS_DIR)/preprocess-side-effects.R \
    --calls $(PACKAGE_TRACE_EVAL_CALLS) \
    --writes $(PACKAGE_TRACE_EVAL_WRITES) \
    --out-side-effects $(PACKAGE_SIDE_EFFECTS_FILE)

$(PACKAGE_PREPROCESS_FILES): $(CORPUS) $(PACKAGE_TRACE_EVAL_CALLS) $(PACKAGE_TRACE_EVAL_CODE) $(PACKAGE_TRACE_EVAL_REFLECTION)
	$(call LOG,PREPROCESSING PACKAGE DATA)
	-mkdir -p $(@D)
	$(RSCRIPT) $(SCRIPTS_DIR)/preprocess.R \
	  $(PREPROCESS_TYPE) \
    --corpus $(CORPUS) \
    --calls $(PACKAGE_TRACE_EVAL_CALLS) \
    --reflection $(PACKAGE_TRACE_EVAL_REFLECTION) \
    --out-summarized $(PACKAGE_SUM_FILE) \
    --out-summarized-externals $(PACKAGE_SUM_EXTERNALS_FILE) \
    --out-undefined $(PACKAGE_SUM_UNDEFINED_FILE)

$(PACKAGE_NORMALIZED_EXPR_FILE): $(PACKAGE_RESOLVED_EXPRESSIONS)
	$(call LOG,PACKAGE NORMALIZATION $(@F))
	$(RSCRIPT) $(SCRIPTS_DIR)/norm.R -f $< > $@

$(BASE_NORMALIZED_EXPR_FILE): $(BASE_RESOLVED_EXPRESSIONS)
	$(call LOG,BASE NORMALIZATION $(@F))
	$(RSCRIPT) $(SCRIPTS_DIR)/norm.R -f $< > $@

$(KAGGLE_NORMALIZED_EXPR_FILE): $(KAGGLE_RESOLVED_EXPRESSIONS)
	$(call LOG,KAGGLE NORMALIZATION $(@F))
	$(RSCRIPT) $(SCRIPTS_DIR)/norm.R -f $< > $@

$(BASE_PREPROCESS_FILES): $(PACKAGES_CORE_FILE) $(BASE_TRACE_EVAL_CALLS)
	$(call LOG,PREPROCESSING BASE DATA)
	-mkdir -p $(@D)
	$(RSCRIPT) $(SCRIPTS_DIR)/preprocess.R \
    $(PREPROCESS_TYPE) \
    --corpus $(PACKAGES_CORE_FILE) \
    --calls $(BASE_TRACE_EVAL_CALLS) \
    --reflection $(BASE_TRACE_EVAL_REFLECTION) \
    --out-summarized $(BASE_SUM_FILE) \
    --out-summarized-externals $(BASE_SUM_EXTERNALS_FILE) \
    --out-undefined $(BASE_SUM_UNDEFINED_FILE)

$(KAGGLE_PREPROCESS_FILES): $(PACKAGES_CORE_FILE) $(KAGGLE_TRACE_EVAL_CALLS) $(KAGGLE_CORPUS_FILE)
	$(call LOG,PREPROCESSING KAGGLE DATA)
	-mkdir -p $(@D)
	$(RSCRIPT) $(SCRIPTS_DIR)/preprocess.R \
    $(PREPROCESS_TYPE) \
    --corpus $(KAGGLE_CORPUS_FILE) \
    --calls $(KAGGLE_TRACE_EVAL_CALLS) \
    --reflection $(KAGGLE_TRACE_EVAL_REFLECTION) \
    --out-summarized $(KAGGLE_SUM_FILE) \
    --out-summarized-externals $(KAGGLE_SUM_EXTERNALS_FILE) \
    --out-undefined $(KAGGLE_SUM_UNDEFINED_FILE) \
    --kaggle

########################################################################
# TASKS
########################################################################

.PHONY: package-install
package-install:
	$(call PKG_INSTALL_FROM_FILE,$(PACKAGES))

.PHONY: package-metadata
package-metadata: $(PACKAGE_METADATA_FILES) $(PACKAGE_METADATA_STATS)

.PHONY: package-coverage
package-coverage: $(PACKAGE_COVERAGE_CSV)

.PHONY: package-runnable-code
package-runnable-code:
	$(ROLLBACK) $(PACKAGE_RUNNABLE_CODE_DIR)
	@$(MAKE) $(PACKAGE_RUNNABLE_CODE_CSV) $(PACKAGE_RUNNABLE_CODE_STATS)

.PHONY: package-runnable-code-eval
package-runnable-code-eval:
	$(ROLLBACK) $(PACKAGE_RUNNABLE_CODE_DIR)
	@$(MAKE) $(PACKAGE_RUNNABLE_CODE_EVAL_CSV) $(PACKAGE_RUNNABLE_CODE_EVAL_STATS)

.PHONY: package-evals-static
package-evals-static:
	$(ROLLBACK) $(PACKAGE_EVALS_STATIC_DIR)
	@$(MAKE) $(PACKAGE_EVALS_STATIC_CSV)

.PHONY: package-corpus
package-corpus: $(CORPUS) $(CORPUS_DETAILS)

.PHONY: package-run
package-run:
	$(ROLLBACK) $(PACKAGE_RUN_DIR)
	@$(MAKE) $(PACKAGE_RUN_STATS)

.PHONY: package-trace-eval
package-trace-eval:
	$(ROLLBACK) $(PACKAGE_TRACE_EVAL_DIR)
	@$(MAKE) $(PACKAGE_TRACE_EVAL_FILES)

.PHONY: package-normalization
package-normalization:
	@$(MAKE) $(PACKAGE_NORMALIZED_EXPR_FILE)

.PHONY: package-preprocess
package-preprocess: $(CORPUS) \
	$(CORPUS_DETAILS) \
	$(PACKAGE_EVALS_STATIC_CSV) \
	$(PACKAGE_TRACE_EVAL_STATS) \
	$(PACKAGE_RUN_STATS) \
	$(PACKAGE_RUNNABLE_CODE_EVAL_CSV)

	$(ROLLBACK) $(PACKAGE_PREPROCESS_DIR)
	@$(MAKE) $(PACKAGE_PREPROCESS_FILES) $(PACKAGE_SIDE_EFFECTS_FILE)
	@$(MAKE) $(PACKAGE_NORMALIZED_EXPR_FILE)
	cp -f $(CORPUS) $(PACKAGE_PREPROCESS_DIR)/corpus.txt
	cp -f $(CORPUS_DETAILS) $(PACKAGE_PREPROCESS_DIR)/corpus.fst
	cp -f $(PACKAGE_EVALS_STATIC_CSV) $(PACKAGE_PREPROCESS_DIR)/evals-static.csv
	cp -f $(PACKAGE_TRACE_EVAL_STATS) $(PACKAGE_PREPROCESS_DIR)/trace-log.csv
	cp -f $(PACKAGE_RUN_STATS) $(PACKAGE_PREPROCESS_DIR)/run-log.csv
	cp -f $(PACKAGE_RUNNABLE_CODE_EVAL_CSV) $(PACKAGE_PREPROCESS_DIR)/runnable-code.csv

package-all: package-install package-trace-eval package-run package-coverage

.PHONY: kaggle-kernels
kaggle-kernels: $(KAGGLE_KERNELS_CSV) $(KAGGLE_KERNELS_EVALS_STATIC_CSV) $(KAGGLE_KERNELS_STATS)

.PHONY: kaggle-run
kaggle-run:
	$(ROLLBACK) $(KAGGLE_RUN_DIR)
	@$(MAKE) $(KAGGLE_RUN_STATS)

.PHONY: kaggle-trace-eval
kaggle-trace-eval:
	$(ROLLBACK) $(KAGGLE_TRACE_EVAL_DIR)
	@$(MAKE) $(KAGGLE_TRACE_EVAL_FILES)

.PHONY: kaggle-preprocess
kaggle-preprocess: $(KAGGLE_CORPUS_FILE) $(KAGGLE_KERNELS_CSV) $(KAGGLE_TRACE_EVAL_STATS)
	$(ROLLBACK) $(KAGGLE_PREPROCESS_DIR)
	@$(MAKE) $(KAGGLE_PREPROCESS_FILES)
	@$(MAKE) $(KAGGLE_NORMALIZED_EXPR_FILE)
	@$(MAKE) $(KAGGLE_CORPUS_FILE)
	cp -f $(KAGGLE_CORPUS_FILE) $(KAGGLE_PREPROCESS_DIR)/corpus.txt
	$(RSCRIPT) -e 'x <- read.csv("$(KAGGLE_KERNELS_EVALS_STATIC_CSV)"); x[, "srcref"] <- paste0(x[, "package"],  x[, "srcref"]); write.csv(x, "$(KAGGLE_PREPROCESS_DIR)/evals-static.csv", row.names=F)'
	cp -f $(KAGGLE_KERNELS_CSV) $(KAGGLE_PREPROCESS_DIR)
	cp -f $(KAGGLE_TRACE_EVAL_STATS) $(KAGGLE_PREPROCESS_DIR)/trace-log.csv

.PHONY: base-evals-static
base-evals-static: $(BASE_EVALS_STATIC_CSV)

.PHONY: base-run
base-run:
	$(ROLLBACK) $(BASE_RUN_DIR)
	@$(MAKE) $(BASE_RUN_STATS)

.PHONY: base-trace-eval
base-trace-eval:
	$(ROLLBACK) $(BASE_TRACE_EVAL_DIR)
	@$(MAKE) $(BASE_TRACE_EVAL_FILES)

.PHONY: base-preprocess
base-preprocess: $(BASE_EVALS_STATIC_CSV)
	$(ROLLBACK) $(BASE_PREPROCESS_DIR)
	@$(MAKE) $(BASE_PREPROCESS_FILES)
	@$(MAKE) $(BASE_NORMALIZED_EXPR_FILE)
	@$(MAKE) $(BASE_EVALS_STATIC_CSV)
	cp -f $(PACKAGES_CORE_FILE) $(BASE_PREPROCESS_DIR)/corpus.txt
	cp -f $(BASE_EVALS_STATIC_CSV) $(BASE_PREPROCESS_DIR)/evals-static.csv

.PHONY: preprocess
preprocess: package-preprocess base-preprocess kaggle-preprocess

.PHONY: libs-dependencies
libs-dependencies: $(DEPENDENCIES_TXT)
	$(call ASSERT_NOT_IN_DOCKER)
	$(call PKG_INSTALL_FROM_FILE,$(DEPENDENCIES_TXT))

.PHONY: injectr
injectr:
	$(call INSTALL_EVALR_LIB,$@)

.PHONY: instrumentr
instrumentr:
	$(call INSTALL_EVALR_LIB,$@)

.PHONY: runr
runr:
	$(call INSTALL_EVALR_LIB,$@)

.PHONY: evil
evil:
	$(call INSTALL_EVALR_LIB,$@)

.PHONY: libs-install
libs-install: $(LIBS)

.PHONY: libs-clone
libs-clone:
	@$(foreach repo,$(LIBS),$(call CLONE_REPO,PRL-PRG,$(repo)))

.PHONY: libs
libs: libs-clone libs-install

define INFO
  @echo "$(1)=$($(1))"
endef

.PHONY: info
info:
	$(call INFO,CRAN_DIR)
	$(call INFO,CRAN_LOCAL_MIRROR)
	$(call INFO,CURDIR)
	$(call INFO,R_LIBS)
	$(call INFO,R_BIN)
	$(call INFO,RUN_DIR)
	@echo "---"
	$(call INFO,JOBS)
	$(call INFO,TIMEOUT)

.PHONY: package-analysis
package-analysis:
	$(MAKE) -C analysis package

.PHONY: base-anlysis
base-analysis:
	$(MAKE) -C analysis base

.PHONY: analysis
analysis:
	$(MAKE) -C analysis all

DOCKER_SHELL_CONTAINER_NAME := $$USER-evalr-shell
# default shell command
SHELL_CMD ?= bash

.PHONY: shell
shell:
	$(call ASSERT_NOT_IN_DOCKER)
	@[ -d $(R_LIBS) ] || mkdir -p $(R_LIBS)
	@[ -d $(CRAN_ZIP_DIR) ] || mkdir -p $(CRAN_ZIP_DIR)
	@[ -d $(CRAN_SRC_DIR) ] || mkdir -p $(CRAN_SRC_DIR)
	docker run \
    --rm \
    --name $(DOCKER_SHELL_CONTAINER_NAME)-$$RANDOM \
    --privileged \
    -ti \
    -v $(CURDIR):$(CURDIR) \
    -v $$($(READLINK) $(CRAN_DIR)):$(CRAN_DIR) \
    -v $$($(READLINK) $(R_LIBS)):$(R_LIBS) \
    -e USER_ID=$$(id -u) \
    -e GROUP_ID=$$(id -g) \
    -e R_LIBS=$(R_LIBS) \
    -e TZ=Europe/Prague \
    -w $(CURDIR) \
    $(DOCKER_IMAGE_NAME) \
    $(SHELL_CMD)

.PHONY: rstudio
rstudio:
	$(call ASSERT_NOT_IN_DOCKER)
	if [ -z "$$PORT" ]; then echo "Missing PORT"; exit 1; fi
	docker run \
    --rm \
    --name "$$USER-evalr-rstudio-$$PORT" \
    -d \
    -p "$$PORT:8787" \
    -v $(CURDIR):$(CURDIR) \
    -e USERID=$$(id -u) \
    -e GROUPID=$$(id -g) \
    -e ROOT=true \
    -e DISABLE_AUTH=true \
    $(DOCKER_RSTUDIO_IMAGE_NAME)

.PHONY: docker-image
docker-image:
	$(call ASSERT_NOT_IN_DOCKER)
	$(MAKE) -C docker-image

.PHONY: update-all
update-all:
	$(call ASSERT_NOT_IN_DOCKER)
	docker pull prlprg/r-dyntrace:r-4.0.2
	$(MAKE) docker-image
	$(MAKE) libs-clone
	$(MAKE) shell SHELL_CMD="make libs"

.PHONY: httpd
httpd:
	$(call ASSERT_NOT_IN_DOCKER)
	docker run \
    --rm \
    -d \
    --name evalr-httpd \
    -p 80:80 \
    -v $(PROJECT_BASE_DIR):/usr/local/apache2/htdocs$(PROJECT_BASE_DIR) \
    httpd:2.4
