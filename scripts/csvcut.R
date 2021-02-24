#!/usr/bin/env Rscript

library(optparse)

run <- function(columns, delim, header, file) {
  library(readr)

  df <- read_csv(file, col_types = cols())
  df <- subset(df, select=columns)
  cat(format_delim(df, delim, col_names=header))
}

option_list <- list(
  make_option(
    c("-c", "--columns"),
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
opts <- parse_args(opt_parser,positional_arguments=1)

run(
  columns=trimws(strsplit(opts$options$columns, ",")[[1]], which="both"),
  delim=opts$options$delim,
  header=opts$options$header,
  file=opts$args
)
