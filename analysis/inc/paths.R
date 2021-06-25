################################################################################
# PATHS
################################################################################

DATA_DIR         <- params$base_dir
OUTPUT_DIR       <- params$output_dir
BASE_DATA_DIR    <- path(DATA_DIR, "base")
PACKAGE_DATA_DIR <- path(DATA_DIR, "package")
KAGGLE_DATA_DIR  <- path(DATA_DIR, "kaggle")

PAPER_DIR <- path(OUTPUT_DIR, "paper")
PLOT_DIR  <- path(PAPER_DIR, "img")
TAGS_DIR  <- path(PAPER_DIR, "tag")

if (!dir_exists(PLOT_DIR)) dir_create(PLOT_DIR)
if (!dir_exists(TAGS_DIR)) dir_create(TAGS_DIR)

BASE_CORPUS_FILE       <- path(BASE_DATA_DIR, "corpus.txt")
BASE_EVALS_STATIC_FILE <- path(BASE_DATA_DIR, "evals-static.csv")

PACKAGE_CORPUS_FILE       <- path(PACKAGE_DATA_DIR, "corpus.fst")
PACKAGE_SUM_CALLS_FILE    <- path(PACKAGE_DATA_DIR, "summarized.fst")
PACKAGE_UNDEFINED_FILE    <- path(PACKAGE_DATA_DIR, "undefined.fst")
PACKAGE_EVALS_STATIC_FILE <- path(PACKAGE_DATA_DIR, "evals-static.csv")
PACKAGE_CODE_FILE         <- path(PACKAGE_DATA_DIR, "code.fst")
PACKAGE_TRACE_LOG_FILE    <- path(PACKAGE_DATA_DIR, "trace-log.csv")
PACKAGE_SIDE_EFFECTS_FILE <- path(PACKAGE_DATA_DIR, "side-effects.fst")
PACKAGE_NORMALIZED_EXPRESSION_FILE <- path(PACKAGE_DATA_DIR, "normalized-expressions.csv")

KAGGLE_KERNEL_FILE       <- path(KAGGLE_DATA_DIR, "kernel.csv")
KAGGLE_EVALS_STATIC_FILE <- path(KAGGLE_DATA_DIR, "evals-static.csv")
KAGGLE_TRACE_LOG_FILE    <- path(KAGGLE_DATA_DIR, "trace-log.csv")

################################################################################
# GLOBALS
################################################################################

# R packages distributed with vanilla R
CORE_PACKAGES <- c(
  "base",
  "compiler",
  "graphics",
  "grDevices",
  "grid",
  "methods",
  "parallel",
  "profile",
  "splines",
  "stats",
  "stats4",
  "tcltk",
  "tools",
  "utils"
)
