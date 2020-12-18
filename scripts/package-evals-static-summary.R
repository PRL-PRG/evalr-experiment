#!/usr/bin/env Rscript

library(optparse)

option_list <- list(
  make_option(
    c("--evals-static"),
    help="CSV file with the static evals",
    dest="evals_static_file", metavar="FILE"
  ),
  make_option(
    c("--corpus"),
    help="TXT file with name of packages to consider",
    dest="corpus_file", metavar="FILE"
  )
)

opt_parser <- OptionParser(option_list=option_list)
opts <- parse_args(opt_parser)

all_evals <- read.csv(opts$evals_static_file)
corpus <- readLines(opts$corpus_file)

evals <- subset(all_evals, package %in% corpus)

funs <- paste0(evals$package, "::", evals$fun_name)
funs <- unique(funs)

cat(funs, sep="\n")
