#!/usr/bin/env Rscript

for (x in c(
  "dplyr",
  "DT",
  "fs",
  "fst",
  "lubridate",
  "optparse",
  "readr",
  "purrr",
  "stringr",
  "tidyr"
  )) {
  suppressPackageStartupMessages(library(x, character.only=TRUE))
}

process_metadata <- function(raw) {
  raw
}

process_functions <- function(raw) {
  raw %>%
    count(package, exported) %>%
    mutate(exported=ifelse(exported, "funs_public", "funs_private")) %>%
    pivot_wider(
      names_from=exported,
      values_from=n,
      values_fill=list(n=0)
    )
}

process_sloc <- function(raw) {
  df <- raw %>%
    filter(path == "R" | path == "src") %>%
    select(-blank, -comment, -files, -path) %>%
    mutate(language=case_when(
      language == "R" ~ "package_r_code",
      language == "C" ~ "package_native_code",
      language == "C/C++ Header" ~ "package_native_code",
      language == "C++" ~ "package_native_code",
      startsWith(language, "Fortran") ~ "package_native_code",
      TRUE ~ as.character(NA)
    )) %>%
    filter(!is.na(language)) %>%
    group_by(package, language) %>%
    summarise(code=sum(code)) %>%
    spread(key=language, value=code, fill=0L) %>%
    ungroup()

  # it could happen that one of these will be missing
  defs <- c(package_r_code=0L, package_native_code=0L)

  tibble::add_column(df, !!!defs[setdiff(names(defs), names(df))])
}

process_revdeps <- function(raw) {
  raw %>%
    count(package) %>%
    rename(revdeps=n)
}

process_coverage <- function(raw) {
  raw %>%
    filter(type=="all") %>%
    select(
      package,
      coverage=coverage_expression
    )
}

process_runnable_code <- function(raw) {
  df <- raw %>%
    filter(language=="R") %>%
    group_by(package, type) %>%
    summarise(files=n(), code=sum(code)) %>%
    pivot_wider(
      names_from=type,
      values_from=c(code, files),
      values_fill=list(code=0, files=0),
      names_glue="runnable_{.value}_{type}"
    )

  for (col in c("examples", "tests", "vignettes")) {
    crc <- str_c("runnable_code_", col)

    if (!(crc %in% colnames(df))) {
      df <- mutate(df, "runnable_code_{col}" := 0, "runnable_files_{col}" := 0)
    }
  }

  df %>%
    mutate(
      runnable_code=runnable_code_examples + runnable_code_tests + runnable_code_vignettes,
      runnable_files=runnable_files_examples + runnable_files_tests + runnable_files_vignettes
    ) %>%
    select(
      package,
      runnable_code,
      runnable_files,
      everything()
    ) %>%
    ungroup()
}

process_evals_static <- function(raw) {
  raw %>%
    count(package, fun_name) %>%
    group_by(package) %>%
    summarise(funs_with_eval=length(unique(fun_name)), evals=sum(n))
}

run <- function(metadata_file,
                functions_file,
                sloc_file,
                revdeps_file,
                coverage_file,
                runnable_code_file,
                evals_static_file,
                out_corpus_file,
                out_corpus_details_file) {

  metadata <- process_metadata(read_csv(metadata_file, col_types=cols(
    package = col_character(),
    name = col_character(),
    version = col_character(),
    title = col_character(),
    size = col_double(),
    loadable = col_logical()
  )))

  functions <- process_functions(
    read_csv(
      functions_file, col_types=cols(
        package = col_character(),
        fun = col_character(),
        exported = col_logical(),
        is_s3_dispatch = col_logical(),
        is_s3_method = col_logical(),
        params = col_character()
      )
    )
  )

  sloc <- process_sloc(
    read_csv(
      sloc_file,
      col_types=cols(
        package = col_character(),
        path = col_character(),
        files = col_double(),
        language = col_character(),
        blank = col_integer(),
        comment = col_integer(),
        code = col_integer()
      )
    )
  )

  revdeps <- if (file.exists(revdeps_file)) {
    process_revdeps(
      read_csv(
        revdeps_file,
        col_types=cols(
          package = col_character(),
          revdep = col_character()
        )
      )
    )
  } else {
    tibble(package=character(0), revdeps=integer(0))
  }

  coverage <- if (file.exists(coverage_file)) {
    process_coverage(
      read_csv(
        coverage_file,
        col_types=cols(
          package = col_character(),
          type = col_character(),
          error = col_character(),
          coverage_line = col_double(),
          coverage_expression = col_double()
        )
      )
    )
  } else {
    tibble(package=character(0), coverage=double(0))
  }

  runnable_code <- process_runnable_code(
    read_csv(
      runnable_code_file,
      col_types=cols(
        package = col_character(),
        file = col_character(),
        type = col_character(),
        language = col_character(),
        blank = col_integer(),
        comment = col_integer(),
        code = col_integer()
      )
    )
  )

  evals_static <- if (file.exists(evals_static_file)) {
    process_evals_static(
      read_csv(
        evals_static_file,
        col_types=cols(
          package = col_character(),
          fun_name = col_character(),
          srcref = col_character(),
          call_fun_name = col_character(),
          args = col_character()
        )
      )
    )
  } else {
    tibble(package=character(0), funs_with_eval=integer(0), evals=integer(0))
  }

  all <- metadata %>%
    left_join(functions, by="package") %>%
    left_join(sloc, by="package") %>%
    left_join(revdeps, by="package") %>%
    left_join(coverage, by="package") %>%
    left_join(runnable_code, by="package") %>%
    left_join(evals_static, by="package")

  corpus <-
    all %>%
      mutate(in_corpus=loadable & evals > 0) %>%
      arrange(desc(revdeps))

  write_lines(filter(corpus, in_corpus)$package, out_corpus_file)
  write_fst(corpus, out_corpus_details_file)
}

option_list <- list(
  make_option("--metadata", help="File with metadata",
              dest="metadata_file", metavar="FILE"),
  make_option("--functions", help="File with metadata",
              dest="functions_file", metavar="FILE"),
  make_option("--revdeps", help="File with revdeps",
              dest="revdeps_file", metavar="FILE"),
  make_option("--coverage", help="File with coverage",
              dest="coverage_file", metavar="FILE"),
  make_option("--sloc", help="File with revdeps",
              dest="sloc_file", metavar="FILE"),
  make_option("--runnable-code", help="File with runnable code",
              dest="runnable_code_file", metavar="FILE"),
  make_option("--evals-static", help="File with evals static",
              dest="evals_static_file", metavar="FILE"),
  make_option("--out-corpus", help="Output corpus.txt file",
              dest="out_corpus_file", metavar="FILE"),
  make_option("--out-corpus-details", help="Output corpus.fst file",
              dest="out_corpus_details_file", metavar="FILE")
)

opt_parser <- OptionParser(option_list=option_list)
opts <- parse_args(opt_parser)

opts$help <- NULL

do.call(run, opts)
