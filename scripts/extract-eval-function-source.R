#!/usr/bin/env Rscript

# Extract only the source of the functions with an eval function in their body

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

process_fun <- function(fun, fun_name) {
  search_function_calls(body(fun), functions=FUNCTIONS)
}

run_package <- function(package, output_dir, package_name=if (is.environment(package)) getNamespaceName(package) else package) {
  calls <- extract_calls(package)
  
  output_file <- file.path(output_dir, paste0(package_name, ".R"))
  for(func in names(calls)) {
    func_str <- paste0(func, " <- ", paste0(deparse(calls[[func]], control = "all"), collapse = "\n"), "\n\n")
    write(func_str, file = output_file, append = TRUE)
  }
}

extract_calls <- function(package) {
  
  # extract all calls
  ns <-
    if (is.environment(package)) {
      package
    } else {
      getNamespace(package)
    }
  
  ns <- as.list(ns, all.names=TRUE)
  funs <- keep(ns, is.function)
  # There could also be eval in functions not stored at the root
  # of the package but rather in environments...
  
  calls <- imap(funs, process_fun)
  calls <- discard(calls, ~is.null(.) || length(.) == 0)
  
  # keep only the functions with at least one ineteresting call
  funs <- funs[names(calls)]
  
  return(funs)
}

run_file <- function(file, output_dir) {
  env <- new.env(parent=emptyenv())
  ast <- parse(file)
  env$main <- as.function(list(as.call(c(as.name("{"), as.list(ast)))))
  run_package(env, output_dir, basename(file))
}

option_list <- list(
  make_option(
    c("--out"),
    help="Name of the output directory",
    dest="out_directory", metavar="FILE"
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

output_dir <- if(is.null(opts$options$out_directory)) "." else opts$options$out_directory

if(!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

df <-  switch(
  opts$options$type,
  package=run_package(opts$args, output_dir),
  file=run_file(opts$args, output_dir),
  stop("Type must be a 'package' or a 'file'")
)