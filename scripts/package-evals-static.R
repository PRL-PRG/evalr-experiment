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

  srcref <- attr(call, "csid")
  if (is.null(srcref)) {
    srcref <- attr(call, "srcref")
  }
  if (is.null(srcref)) {
    srcref <- NA
  }

  tibble(fun_name, srcref, call_fun_name, args)
}

make_rows <- function(calls, fun_name) {
  map_dfr(calls, make_row, fun_name=fun_name)
}

process_fun <- function(fun, fun_name, package_name) {
  body <- tryCatch({
    csid_prefix <- evil:::create_csid_prefix(package_name, fun_name)
    evil:::wrap_evals(body(fun), csid_prefix)
  }, error=function(e) {
    message("error in:", fun_name, ":", e$message)
    body(fun)
  })

  search_function_calls(body, functions=FUNCTIONS)
}

run_package <- function(package, package_name=if (is.environment(package)) getNamespaceName(package) else package) {
  ns <-
    if (is.environment(package)) {
      package
    } else {
      getNamespace(package)
    }

  ns <- as.list(ns, all.names=TRUE)
  funs <- keep(ns, is.function)
  calls <- imap(funs, ~process_fun(.x, .y, package_name))
  calls <- discard(calls, ~is.null(.) || length(.) == 0)

  imap_dfr(calls, make_rows)
}

run_file <- function(file) {
  env <- new.env(parent=emptyenv())
  ast <- parse(file)
  env$main <- as.function(list(as.call(c(as.name("{"), as.list(ast)))))
  run_package(env, basename(file))
}

option_list <- list(
  make_option(
    c("--out"),
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

df <-  switch(
  opts$options$type,
  package=run_package(opts$args),
  file=run_file(opts$args),
  stop("Type must be a 'package' or a 'file'")
)

out_file <- opts$options$out_file
if (is.null(out_file)) {
  out_file <- stdout()
}

if (nrow(df) > 0) {
  write.csv(df, out_file, row.names=FALSE)
}
