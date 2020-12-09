#!/usr/bin/env Rscript

library(optparse)
library(purrr)
library(runr)
library(tibble)
library(withr)

FUNCTIONS <- c(
  "base:::eval",
  "base:::eval.parent",
  "base:::evalq",
  "base:::local"
)

make_row <- function(call, fun_name) {
  deparse_arg <- function(arg) {
    paste(deparse(arg, width.cutoff=180L), collapse="")
  }

  lst <- as.list(call)

  call_fun_name <- lst[[1L]]
  call_fun_name <- if (is.call(call_fun_name)) {
    if (length(call_fun_name) == 3) {
      as.character(call_fun_name)[3]
    } else {
      format(call_fun_name)
    }
  } else {
    as.character(call_fun_name)
  }
  args <- paste(map_chr(lst[-1L], deparse_arg), collapse=", ")

  line1 <- NA
  line2 <- NA
  col1 <- NA
  col2 <- NA
  file <- NA

  srcref <- attr(call, "srcref")
  if (!is.null(srcref)) {
    line1 <- srcref[1]
    col1 <- srcref[2]
    line2 <- srcref[3]
    col2 <- srcref[4]
    file <- attr(srcref, "srcfile")$filename
    if (is.null(file)) file <- NA
  }

  tibble(fun_name, file, line1, col1, line2, col2, call_fun_name, args)
}

make_rows <- function(calls, fun_name) {
  map_dfr(calls, make_row, fun_name=fun_name)
}

process_fun <- function(fun, fun_name) {
  g <- tryCatch({
    impute_fun_srcref(fun)
  }, error=function(e) {
    message("error in:", fun_name, ":", e$message)
    fun
  })

  search_function_calls(body(g), functions=FUNCTIONS)
}

run_package <- function(package, options) {
  ns <- if (is.environment(package)) {
          package
        } else {
          getNamespace(package)
        }

  ns <- as.list(ns)
  funs <- keep(ns, is.function)
  calls <- imap(funs, process_fun)
  calls <- discard(calls, ~is.null(.) || length(.) == 0)

  df <- imap_dfr(calls, make_rows)

  if (nrow(df) > 0) {
    write.csv(df, options$out_file, row.names=FALSE)
  }
}

run_file <- function(file, options) {
  env <- new.env(parent=emptyenv())
  ast <- parse(file)
  env$main <- as.function(list(ast))
  run_package(env, options)
}

option_list <- list(
  make_option(
    c("--out"), default="evals.csv",
    help="Name of the output file",
    dest="out_file", metavar="FILE"
  ),
  make_option(
    c("--type"),
    help="Type (package or file)",
    metavar="TYPE"
  )
)


opt_parser <- OptionParser(option_list=option_list)
opts <- parse_args(opt_parser, positional_arguments=1)

if (length(opts$args) != 1) {
  stop("Missing package name or filename")
}

switch(
  opts$options$type,
  package=run_package(opts$args, opts$options),
  file=run_file(opts$args, opts$options),
  stop("Type must be a 'package' or a 'file'")
)
