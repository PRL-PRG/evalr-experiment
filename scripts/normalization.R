#!/usr/bin/env Rscript

# - deduplicate the given expressions
# - normalize them

suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(purrr))
library(stringr)
library(fst)
library(optparse)


arith_op <- c("/", "-", "*", "+", "^", "log", "sqrt", "exp", "max", "min", "cos", "sin", "abs", "atan", ":")
str_op <- c("paste", "paste0", "str_c")
comp_op <- c("<", ">", "<=", ">=", "==", "!=")
bool_op <- c("&", "&&", "|", "||", "!")

canonic_expr <- function(exp) {
    if (is.call(exp)) {
        function_name <- exp[[1]]
        function_args <- exp[-1]
        res <- map(function_args, canonic_expr) # TODO: rather directly compute canonic_expr on function_args?
        # Function_name can be larger than one is a function with a namespace stats::model or another higher-order function
        # For instance, (function(x, y) x + y)(3, 4)
        if (length(function_name) == 1 && as.character(function_name) == "(") {
            return(res[[1]]) # (a) => (a)()
        }
        else if (length(function_name) == 1 && as.character(function_name) %in% arith_op && every(res, function(v) {
            v == "NUM"
        })) {
            return("NUM")
        }
        else if (length(function_name) == 1 && as.character(function_name) %in% str_op && every(res, function(v) {
            v == "STR"
        })) {
            return("STR")
        }
        else if (length(function_name) == 1 && as.character(function_name) %in% bool_op && every(res, function(v) {
            v == "BOOL"
        })) {
            return("BOOL")
        }
        else if (length(function_name) == 1 && as.character(function_name) %in% comp_op && every(res, function(v) {
            v == "NUM"
        })) {
            return("BOOL")
        }
        else if (length(function_name) == 1 && as.character(function_name) == "c" && length(res) > 1 && n_distinct(res) == 1 && res[[1]] %in% c("BOOL", "NUM", "STR")) {
            str_c("c(", res[[1]], ")")
        }
        else if (length(function_name) == 1 && function_name == "::") {
            str_c(as.character(function_args[[1]]), "::", as.character(function_args[[2]]))
        }
        else {
            function_name <- if (length(function_name) == 1) {
                as.character(function_name)
            }
            else {
                canonic_expr(function_name)
            }
            return(str_c(str_c(function_name, collapse = ", "), "(", str_c(res, collapse = ", "), ")"))
        }
    }
    else if (is.symbol(exp)) {
        return("VAR")
    }
    else if (is.expression(exp)) {
        return(str_c(map(exp, canonic_expr), collapse = ", "))
    }
    else if (typeof(exp) %in% c("integer", "double", "complex")) {
        return("NUM")
    }
    else if (typeof(exp) == "logical") {
        return("BOOL")
    }
    else if (typeof(exp) == "character") {
        return("STR")
    }
    else {
        return(deparse1(exp))
    }
}

canonic_expr_str <- function(exp) {
    ast <- NA
    try(ast <- parse(text = exp)[[1]], silent = TRUE)
    # some expr_resolved have been truncated so we mark them as FALSE (even though they could be true)
    if (is.symbol(ast) || is.language(ast) || length(ast) > 1 || !is.na(ast)) {
        return(canonic_expr(ast))
    }
    else {
        return("NORMALIZATION ERROR")
    }
}


parse_program_arguments <- function() {
    option_list <- list(
        make_option(
            c("--expr"),
            dest = "expressions_file", metavar = "FILE",
            help = "File with expressions"
        ),
        make_option(
            c("--out-expr"),
            dest = "normalized_expr", metavar = "FILE"
        )
    )
    opt_parser <- OptionParser(option_list = option_list)
    arguments <- parse_args(opt_parser)
    arguments$options$help <- NULL

    arguments
}

main <- function() {
    now_first <- Sys.time()
    arguments <- parse_program_arguments()

    str(arguments)

    cat("\n")

    now <- Sys.time()
    cat("Read and deduplicate ", arguments$expressions_file, "\n")
    expressions <- read_fst(arguments$expressions_file) %>%
        tibble() %>%
        select(-file) %>%
        unique()
    res <- difftime(Sys.time(), now)
    cat("Done in ", res, units(res), "\n")

    now <- Sys.time()
    cat("Normalize \n")
    expressions <- expressions %>%
        mutate(expr_canonic = map_chr(expr_resolved, canonic_expr_str)) # , .keep = "unused"
    res <- difftime(Sys.time(), now)
    cat("Done in ", res, units(res), "\n")

    now <- Sys.time()
    cat("Output to ", arguments$normalized_expr, "\n")
    expressions %>% write_fst(arguments$normalized_expr)
    res <- difftime(Sys.time(), now)
    cat("Done in ", res, units(res), "\n")

    res <- difftime(Sys.time(), now_first)
    cat("Total processing time in ", res, units(res), "\n")


    invisible(NULL)
}

main()
