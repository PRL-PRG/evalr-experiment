#!/usr/bin/env Rscript

library(optparse)
library(stringr)

read_file <- function(file) {
  switch(
    tools::file_ext(file),
    csv=readr::read_csv(file, col_types=readr::cols()),
    fst=fst::read_fst(file),
    stop("unsupported file format: ", file)
  )
}

run <- function(columns, delim, header, file) {
  df <- read_file(file)
  df_cols <- colnames(df)

  if (length(columns) > 0) {
    missing_cols <- columns[!(columns %in% df_cols)]
    if (length(missing_cols) > 0) {
      stop(
        "Columns: ",
        str_c(missing_cols, collapse=", "),
        " are not part of the input (",
        str_c(df_cols, collapse=", "),
        ")"
      )
    }
    df_cols <- columns
  }

  if (header) {
    cat(str_c(df_cols, collapse=delim), "\n")
  }

  str <- str_c("{", df_cols, "}", collapse=delim)

  cat(str_glue(str, .envir=df), sep="\n")
}

option_list <- list(
  make_option(
    c("-c", "--columns"), default="",
    help="Comma-separated list of columns to select",
    dest="columns", metavar="COLS"
  ),
  make_option(
    c("-d", "--delim"),
    help="Column delimeter", default=",",
    dest="delim", metavar="STR"
  ),
  make_option(
    c("--no-header"),
    help="Omit the header", action="store_false", default=TRUE,
    dest="header"
  )
)

opt_parser <- OptionParser(option_list=option_list)
opts <- parse_args(opt_parser, positional_arguments=1)

run(
  columns=trimws(strsplit(opts$options$columns, ",")[[1]], which="both"),
  delim=opts$options$delim,
  header=opts$options$header,
  file=opts$args
)
