#!/usr/bin/env Rscript

library(dplyr)
library(optparse)
library(readr)

option_list <- list(
  make_option("--coverage", help="File with coverage", metavar="FILE"),
  make_option("--revdeps", help="File with revdeps", metavar="FILE"),
  make_option("--num", help="Number of packages", metavar="NUM", type="integer"),
  make_option("--out-packages", help="Output packages file", dest="out_packages", metavar="FILE"),
  make_option("--out-revdeps", help="Output revdeps file", dest="out_revdeps", metavar="FILE")
)

opt_parser <- OptionParser(option_list=option_list)
opts <- parse_args(opt_parser)

coverage <- read_csv(opts$coverage)
revdeps <- read_csv(opts$revdeps)

packages <-
  count(revdeps, package) %>%
  semi_join(
    filter(coverage, !is.na(coverage_expression)),
    by="package"
  ) %>%
  top_n(opts$num, n) %>%
  head(opts$num) %>%
  arrange(desc(n))

packages_revdeps <-
  semi_join(revdeps, packages, by="package") %>%
  .$revdep %>%
  unique()

writeLines(packages$package, opts$out_packages)
writeLines(packages_revdeps, opts$out_revdeps)
