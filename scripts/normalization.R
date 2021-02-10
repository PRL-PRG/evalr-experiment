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
library(evil)

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

canonic_expr_str <- function(exp, with.names = FALSE) {
  ast <- NA
  try(ast <- parse(text = exp)[[1]], silent = TRUE)
  # some expr_resolved have been truncated so we mark them as FALSE (even though they could be true)
  if (is.symbol(ast) || is.language(ast) || length(ast) > 1 || !is.na(ast)) {
    return(canonic_expr(ast, with.names))
  }
  else {
    return(NA_character_)
  }
}

bacticky <- function(e) {
    paste0("`", e, "`", collapse="")
}

normalize_expr_str <- function(expr, with.names = FALSE) {
    exp <- if (!is.na(expr) && startsWith(expr, "_")) {
        bacticky(expr)
    } else {
        expr
    }

    ast <- NA
    try(ast <- parse(text = exp)[[1]], silent = TRUE)
    # some expr_resolved have been truncated so we mark them as FALSE (even though they could be true)
    if (is.symbol(ast) || is.language(ast) || length(ast) > 1 || !is.na(ast)) {
        return(normalize_stats_expr(ast))
    }


    # It failed
    # Put `` Should always parse after that!
    try(ast <- parse(text = bacticky(exp))[[1]], silent = TRUE)
    if (is.symbol(ast) || is.language(ast) || length(ast) > 1 || !is.na(ast)) {
        return(normalize_stats_expr(ast))
    }

    # This is hopeless.
    # We return NA
    # But it should never happen!

    return(list(str_rep = NA_character_, call_nesting = 0, nb_assigns = 0, root_function = NA_character_))
}



simplify <- function(expr_resolved) {
  # Numbers
  res <- gsub(x = expr_resolved, pattern = "(?=[^[:alpha:]])(?:(?:NA|-?\\d+(\\.\\d*)?L?),\\s*)*(?:NA|-?\\d+(\\.\\d*)?L?)", replacement = "1", perl = TRUE, useBytes = TRUE) # will not detect .55
  # Hexadecimals
  res <- gsub(x = expr_resolved, pattern = "(?=[^[:alpha:]])(?:(?:NA|-?0x[abcdef\\d]+),\\s*)*(?:NA|-?0x[abcdef\\d]+)", replacement = "1", perl = TRUE, useBytes = TRUE) # will not detect .55
  # Strings
  res <- gsub(x = res, pattern = "(?=[^\\\\])(?:\"[^\"]*\",\\s*)*\"[^\"]*\"", replacement = "\"\"", perl = TRUE, useBytes = TRUE)
  # Booleans
  res <- gsub(x = res, pattern = "(?:(?:TRUE|FALSE),\\s*)*(?:TRUE|FALSE)", replacement = "TRUE", perl = TRUE, useBytes = TRUE)
  res
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
            c("--quicker"),
            action = "store_true", dest = "quicker", default = FALSE,
        ),
        make_option(
            c("--parallel"),
            action = "store_true", dest = "parallel", default = FALSE,
        ),
        make_option(
            c("--simplify"),
            action = "store_true", dest = "simplify", default = FALSE,
        ),
        make_option(
            c("--benchmark"),
            action = "store_true", dest = "benchmark", default = FALSE,
        ),
        make_option(
            c("--debug"),
            action = "store_true", dest = "debug", default = FALSE,
        )
    )
    opt_parser <- OptionParser(option_list = option_list)
    arguments <- parse_args(opt_parser)

    arguments
}

time_it <- function(arg, f) {
  now <- Sys.time()

  res <- "ABORTED"
  # Would be nice to also get GC time here
  try(res <- with_timeout(f(arg), elapsed = 60 * 5))

  end <- Sys.time()
  return(list(result = res, duration = end - now))
}

benchmark <- function(dataset, f, name) {
    i <- nrow(dataset)
    dataset %>%
        mutate(expr_canonic_res = pbsapply(expr_prepass, time_it, f, simplify = FALSE, USE.NAMES = TRUE)) %>%
        unnest_wider(expr_canonic_res) %>%
        rename(expr_canonic = result) %>%
        mutate(sample_size = i, size = str_length(expr_prepass)) %>%
        mutate(function_name = name)
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

    if (arguments$simplify) {
        now <- Sys.time()
        cat("Simplify \n")
        expressions <- expressions %>%
            mutate(expr_prepass = simplify(expr_resolved))
        res <- difftime(Sys.time(), now)
        cat("Done in ", res, units(res), "\n")
    }


    now <- Sys.time()
    cat("Sanitize \n")
    expressions <- if (arguments$simplify) {
        expressions %>%
            mutate(expr_prepass = sanitize_specials(expr_prepass))
    }
    else {
        expressions %>%
            mutate(expr_prepass = sanitize_specials(expr_resolved))
    }

    res <- difftime(Sys.time(), now)
    cat("Done in ", res, units(res), "\n")

    if (arguments$benchmark) {
        cat("Benchmarking\n")
        cat("R implementation vs C implementation\n")
        df_res <- list()
        for (i in 10^(3:5)) {
            cat("With ", i, " rows\n")
            df <- expressions %>% slice_sample(n = i)
            cat("R implementation: \n")
            gc()
            df1 <- benchmark(df, canonic_expr_str, "R")
            df_res[[paste0(i, "R")]] <- df1
            cat("C implementation: \n")
            gc()
            df2 <- benchmark(df, normalize_expr_str, "C")
            df_res[[paste0(i, "C")]] <- df2
        }

        timings <- bind_rows(df_res) %>% select(-expr_resolved)

        cat("Output benchmark data\n")
        timins <- timings %>% unnest_wider(expr_canonic)
        timings %>% write_fst(arguments$normalized_expr)

        return(NULL)
    }

    now <- Sys.time()
    cat("Normalize \n")
    if (arguments$errors) {
        expressions <- expressions %>%
            mutate(expr_canonic_res = map(expr_prepass, safely(canonic_expr_str))) %>%
            unnest_wider(expr_canonic_res) %>%
            rename(expr_canonic = result)
    }
    else if (arguments$quicker) {
        cl <- if (arguments$parallel) {
            parallel::detectCores() - 1
        } else {
            1
        }
        # It is actually much slower in parallel
        cat("Using ", cl, " cores.\n")
        expressions <- expressions %>%
            mutate(expr_canonic_res = pbsapply(expr_prepass, normalize_expr_str, simplify = FALSE, USE.NAMES = FALSE, cl = cl)) %>%
            unnest_wider(expr_canonic_res) %>%
            rename(expr_canonic = str_rep)

        if (!arguments$debug) {
            expressions <- expressions %>% select(-expr_prepass, -expr_resolved)
        }
    }
    else {
        expressions <- expressions %>%
            mutate(expr_canonic = map_chr(expr_prepass, canonic_expr_str)) %>%
            select(-expr_prepass)
    }
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
