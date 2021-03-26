#!/usr/bin/env Rscript

library(optparse)
library(stringr)

read_file <- function(file) {
  switch(
    tools::file_ext(file),
    csv=readr::read_csv(file, col_types=readr::cols()),
    fst=fst::read_fst(file),
    txt=data.frame(value=readLines(file)),
    stop("unsupported file format: ", file)
  )
}

run <- function(columns, delim, header, file, limit, shuffle) {
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

  max_rows <- nrow(df)
  rows <- seq(max_rows)

  if (shuffle) {
    rows <- sample(rows)
  }

  if (limit > 0) {
    max_rows <- min(max_rows, limit)
    rows <- head(rows, max_rows)
    df <- df[rows, , drop=FALSE]
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
  ),
  make_option(
    c("--limit"), default=0,
    help="Limit the number of rows printed",
    dest="limit", metavar="INT"
  ),
  make_option(
    c("--shuffle"),
    action="store_true", default=FALSE,
    help="Shuffle the output rows",
    dest="shuffle"
  )
)

opt_parser <- OptionParser(option_list=option_list)
opts <- parse_args(opt_parser, positional_arguments=1)

options <- opts$options
options$help <- NULL
options$file <- opts$args
options$columns <- trimws(strsplit(opts$options$columns, ",")[[1]], which="both")

do.call(run, options)
