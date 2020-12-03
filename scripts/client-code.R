#!/usr/bin/env Rscript

library(dplyr)
library(optparse)
library(readr)

option_list <- list(
  make_option(c("--runnable-code"), help="File with runnable code", dest="runnable_code", metavar="FILE"),
  make_option(c("--packages"), help="File with packages to include", metavar="FILE"),
  make_option(c("--out", help="Output file", meravar="FILE"))
)

opt_parser <- OptionParser(option_list=option_list)
opts <- parse_args(opt_parser)

runnable_code <- read_csv(opts$runnable_code)
packages <- tibble(package=read_lines(opts$packages))

df <-
  semi_join(runnable_code, packages, by="package") %>%
  arrange(desc(code))

writeLines(file.path(df$package, df$file), opts$out)
