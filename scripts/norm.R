#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(dplyr))
library(fst)
library(optparse)
suppressPackageStartupMessages(library(evil))

args <- parse_args(OptionParser(option_list = list(
    make_option(c("-f", "--file"), dest="file", metavar="FILE"))))

read_fst(args$file) %>% tibble() %>% select(-file) %>% unique() -> df

# <pointer> and similar do not parse, wrap'em in strings
r <- df$expr_resolved
r <- gsub("<pointe[^>]*>", "\"<POINTER>\"", r, perl=T, useBytes=T)
r <- gsub("<environment[^>]*>", "\"<ENVIRONMENT>\"", r, perl=T, useBytes=T)
r <- gsub("<weak reference>", "\"<WEAK REFERENCE>\"", r, fixed=T, useBytes= T)

normalize_it <- function(i) {
  e <- r[i]
  ast <- NA
  if(is.null(e)) stop("parse() can't deal with NULL")
  try(ast <- parse(text = e), silent = TRUE)
  if (!is.expression(ast))  ast <- parse(text = "X")
  # Parsing fails, when the expression is an operator such as +, semantically
  # this a lookup of the symbol '+', for our purposes we can replace with X.
  normalize(df$expr_resolved_hash[i], ast, strtrim(e, 50))
}

sapply(1:length(r), normalize_it, USE.NAMES = F) -> ignore


