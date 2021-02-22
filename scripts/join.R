#!/usr/bin/env Rscript


library(optparse)
library(readr)
library(fst)
suppressPackageStartupMessages(library(dplyr))



main <- function() {
    args <- parse_args(OptionParser(option_list = list(
        make_option(c("-i", "--input-calls"), dest="input_calls", metavar="FILE"),
        make_option(c("-n", "--input-normalized"), dest="input_normalized", metavar="FILE"),
        make_option(c("-o", "--output"), dest="output_file", metavar="FILE", help = "csv with optional extension .gz or .xz"))))

    calls <- read_fst(args$input_calls) %>% as_tibble()
    normalized <- read_csv(args$input_normalized)

    res <- calls %>% left_join(normalized, by=c("expr_resolved_hash", "hash")) %>% select(-trimmed)
    res %>% write_csv(args$output_file)
}

invisible(main())