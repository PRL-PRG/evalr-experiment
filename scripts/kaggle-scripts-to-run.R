#!/usr/bin/env Rscript

library(optparse)

run <- function(metadata_file, evals_static_file) {
  kernels <- read.csv(metadata_file)
  evals <- read.csv(evals_static_file)
  df <- subset(kernels, package %in% evals$package)
  df <- df[!duplicated(df$hash), ]

  cat(paste(df$competition, df$package, sep=","), sep="\n")
}

option_list <- list(
  make_option(
    c("--metadata"),
    help="CSV metadata file",
    dest="metadata_file", metavar="FILE"
  ),
  make_option(
    c("--evals-static"),
    help="CSV evals static file",
    dest="evals_static_file", metavar="FILE"
  )
)

opt_parser <- OptionParser(option_list=option_list)
opts <- parse_args(opt_parser)

run(
  metadata_file=opts$metadata_file,
  evals_static_file=opts$evals_static_file
)
