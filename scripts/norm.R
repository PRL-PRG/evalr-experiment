#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(purrr))
suppressPackageStartupMessages(library(tidyr))
library(readr)
library(fst)
library(optparse)
library(evil)

normalize <- function(e) {
    ast <- NA
    if(is.null(e)) stop("parse() can't deal with NULL")
    try(ast <- parse(text = e), silent = TRUE)
    if (!is.expression(ast))  ast <- parse(text = "X")
    # Parsing fails, when the expression is an operator such as +, semantically
    # this a lookup of the symbol '+', for our purposes we can replace with X.
    return(normalize_stats_expr(ast))
}

opt_parser <- OptionParser(option_list = list(
    make_option(c("--f"), dest="file", metavar="FILE"),
    make_option(c("--o"), dest="out", metavar = "FILE")))
args <- parse_args(opt_parser)

args<- "ho"
args$file <- "data/resolved-expressions.fst"

read_fst(args$file) %>%
    tibble() %>%
    select(-file) %>%
    unique() -> df

# <pointer> and similar do not parse, wrap'em in strings
res <- df$expr_resolved
res <- gsub("<pointe[^>]*>", "\"<POINTER>\"", res, perl = TRUE, useBytes = TRUE)
res <- gsub("<environment[^>]*>", "\"<ENVIRONMENT>\"", res, perl = TRUE, useBytes = TRUE)
res <- gsub("<weak reference>", "\"<WEAK REFERENCE>\"", res, fixed = TRUE, useBytes = TRUE)

sapply(res, normalize,USE.NAMES = F)  -> ls

data.frame(ls) -> df2

df2 %>% write_csv(file=args$out)

unnest_wider(res) %>%
    rename(expr_canonic = str_rep) %>%
    write_csv(file=args$out)
