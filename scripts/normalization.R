#!/usr/bin/env Rscript

# - deduplicate the given expressions
# - normalize them

suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(purrr))
suppressPackageStartupMessages(library(tidyr))
library(stringr)
library(fst)
library(optparse)
library(pbapply)

with_timeout <- function(expr, elapsed) {
  expr <- substitute(expr)
  envir <- parent.frame()
  setTimeLimit(cpu = elapsed, elapsed = elapsed, transient = TRUE)
  on.exit(setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE))
  eval(expr, envir = envir)
}


arith_op <- c("/", "-", "*", "+", "^", "log", "sqrt", "exp", "max", "min", "cos", "sin", "abs", "atan", ":")
str_op <- c("paste", "paste0", "str_c")
comp_op <- c("<", ">", "<=", ">=", "==", "!=")
bool_op <- c("&", "&&", "|", "||", "!")

canonic_expr <- function(exp, with.names = FALSE) {
  if (is.call(exp)) {
    function_name <- exp[[1]]
    function_args <- exp[-1]
    res <- map(function_args, canonic_expr, with.names) # TODO: rather directly compute canonic_expr on function_args?
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
    else if (length(function_name) == 1 && as.character(function_name) %in% c("c", "list") && length(res) > 1 && n_distinct(res) == 1 && res[[1]] %in% c("BOOL", "NUM", "STR", "VAR")) {
      str_c(as.character(function_name), "(", res[[1]], ")")
    }
    else if (length(function_name) == 1 && function_name == "::") { # we drop the namespace
      as.character(function_args[[2]])
    }
    else {
      function_name <- if (length(function_name) == 1) {
        func_name <- as.character(function_name)
        function_name <- if (func_name %in% arith_op) {
          "OP"
        }
        else if (func_name %in% comp_op) {
          "COMP"
        }
        else if (func_name %in% bool_op) {
          "LOGI"
        }
        else {
          func_name
        }
      }
      else {
        canonic_expr(function_name, with.names)
      }

      # It might have been transformed by canonic_expr in the recursive call above
      # it should always have length one
      res <- if (length(function_name) == 1) {
        func_name <- as.character(function_name)
        # VAR is absorbing: if there is at least one, we propagate to all of them
        res <- if (func_name %in% c("COMP", "LOGI", "OP") && "VAR" %in% res) {
          rep.int("VAR", length(res))
        }
        else if (func_name == "model.frame") { # special case
          # We keep the 1st two arguments (usually formula and data)
          # and subset if it is there
          subset_arg <- if ("subset" %in% names(res)) {
            subset_s <- as.character(res["subset"])
            res["subset"] <- NULL
            str_c("subset = ", subset_s)
          }
          else {
            "subset = NULL"
          }
          first_args <- if (length(res) > 1) {
            res[1:2]
          }
          else {
            c(res[[1]], "NULL")
          }
          c(first_args, subset_arg)
        }
        else {
          res
        }
      }

      fun_args <- if (with.names) {
        str_c(names(res), if_else(names(res) == "", "", " = "), res, collapse = ", ")
      }
      else {
        str_c(res, collapse = ", ")
      }

      return(str_c(str_c(function_name, collapse = ", "), "(", fun_args, ")"))
    }
  }
  else if (is.symbol(exp)) {
    return("VAR")
  }
  else if (is.expression(exp)) {
    return(str_c(map(exp, canonic_expr, with.names), collapse = ", "))
  }
  else if (typeof(exp) %in% c("integer", "double", "complex")) {
    return("NUM")
  }
  else if (typeof(exp) == "logical") {
    return("BOOL")
  }
  else if (typeof(exp) == "character") {
    if (is.na(exp)) {
      return("STR")
    }
    if (exp == "<POINTER>") {
      return("PTR")
    }
    else if (exp == "<WEAK REFERENCE>") {
      return("WREF")
    }
    else if (exp == "<ENVIRONMENT>") {
      return("ENV")
    }
    else {
      return("STR")
    }
  }
  else {
    return(deparse1(exp))
  }
}

bacticky <- function(e) {
  paste0("`", e, "`", collapse = "")
}

canonic_expr_str <- function(expr, with.names = FALSE) {
  exp <- if (!is.na(expr) && startsWith(expr, "_")) {
    bacticky(expr)
  } else {
    expr
  }
  ast <- NA
  try(ast <- parse(text = exp)[[1]], silent = TRUE)
  # some expr_resolved have been truncated so we mark them as FALSE (even though they could be true)
  if (is.symbol(ast) || is.language(ast) || length(ast) > 1 || !is.na(ast)) {
    return(canonic_expr(ast, with.names))
  }
  # It failed; probably was a special operators
  # Put `` Should always parse after that!
  try(ast <- parse(text = bacticky(exp))[[1]], silent = TRUE)
  if (is.symbol(ast) || is.language(ast) || length(ast) > 1 || !is.na(ast)) {
    return(canonic_expr(ast, with.names))
  }

  return(NA_character_)
}




sanitize_specials <- function(exp) {
  # everything printed as <blabla> out of a string won't be parse again
  # We wrap it into a string and then sanitize
  # There can be pointer, weak reference, and environment
  res <- gsub(x = exp, pattern = "<pointe[^>]*>", replacement = "\"<POINTER>\"", perl = TRUE, useBytes = TRUE)
  res <- gsub(x = res, pattern = "<environment[^>]*>", replacement = "\"<ENVIRONMENT>\"", perl = TRUE, useBytes = TRUE)
  gsub(x = res, pattern = "<weak reference>", replacement = "\"<WEAK REFERENCE>\"", fixed = TRUE, useBytes = TRUE)
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
    ),
    make_option(
      c("--keep-names"),
      action = "store_true", dest = "keep_names", default = FALSE,
    ),
    make_option(
      c("--validate"),
      action = "store_true", dest = "validate", default = FALSE,
    ),
    make_option(
      c("--keep-errors"),
      action = "store_true", dest = "errors", default = FALSE,
    ),
    make_option(
      c("--parallel"),
      action = "store_true", dest = "parallel", default = FALSE,
    ),
    make_option(
      c("--simplify"),
      action = "store_true", dest = "simplify", default = FALSE,
    )
  )
  opt_parser <- OptionParser(option_list = option_list)
  arguments <- parse_args(opt_parser)

  arguments
}


main <- function() {
  now_first <- Sys.time()
  op <- pboptions(type = "timer")
  arguments <- parse_program_arguments()

  cat("\n")

  now <- Sys.time()
  cat("Read ", arguments$expressions_file, "\n")
  expressions <- read_fst(arguments$expressions_file) %>%
    tibble() %>%
    select(-file)
  res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")

  now <- Sys.time()
  cat("Deduplicate from", nrow(expressions))
  expressions <- expressions %>%
    unique()
  res <- difftime(Sys.time(), now)
  cat(" to ", nrow(expressions), " rows.\nDone in ", res, units(res), "\n")


  now <- Sys.time()
  cat("Sanitize \n")
  expressions <- expressions %>%
    mutate(expr_prepass = sanitize_specials(expr_resolved))


  res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")


  now <- Sys.time()
  cat("Normalize \n")

  cl <- if (arguments$parallel) {
    parallel::detectCores() - 1
  } else {
    1
  }
  # It is actually much slower in parallel
  cat("Using ", cl, " cores.\n")
  expressions <- expressions %>%
    mutate(expr_canonic = pbsapply(expr_prepass, canonic_expr_str, simplify = TRUE, USE.NAMES = FALSE, cl = cl))


  res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")

  if (arguments$validate) {
    cat("Validate \n")
    stopifnot(is.na(expressions$expr_resolved) | !is.na(expressions$expr_canonic))
    res <- difftime(Sys.time(), now)
    cat("Done in ", res, units(res), "\n")
  }

  now <- Sys.time()
  cat("Output to ", arguments$normalized_expr, "\n")
  expressions %>% write_fst(arguments$normalized_expr)
  res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")

  res <- difftime(Sys.time(), now_first)
  cat("Total processing time in ", res, units(res), "\n")


  return(NULL)
}

invisible(main())
