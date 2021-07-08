#!/usr/bin/env Rscript

# Preprocess the dataset:
# - remove duplicates
# - correct src refs
# - add some columns (such as `eval_call_package`)
# - cut the dataset into smaller ones


suppressPackageStartupMessages(library(rlang))
library(purrr)
library(tidyr)
library(dplyr)
library(stringr)
library(fs)
library(readr)
library(fst)
library(optparse)

get_expr <- function(eval_call) {
  if (is.na(eval_call)) {
    return(NA_character_)
  }
  # Special case for expressions starting with _ (such as _inherit in ggproto)
  escaped_eval_call <- if (startsWith(eval_call, "_")) {
    paste0("`", eval_call, "`")
  }
  else {
    eval_call
  }

  exp <- NA_character_
  # Would fail for instance for
  # "`$<-`(new(\"C++Field\", .xData = <environment>), \"read_only\", TRUE)" (classInt package)
  try(exp <- parse(text = escaped_eval_call)[[1]], silent = TRUE)


  return(exp)
}


deduplicate <- function(dataset) {
  return(dataset %>% count(across(c(
    -eval_call_id, -starts_with("caller_stack")
  )), name = "nb_ev_calls"))
}


SEXP_TYPES <- tribble(
  ~sexp_type, ~name,
  0, "NILSXP",
  1, "SYMSXP",
  2, "LISTSXP",
  3, "CLOSXP",
  4, "ENVSXP",
  5, "PROMSXP",
  6, "LANGSXP",
  7, "SPECIALSXP",
  8, "BUILTINSXP",
  9, "CHARSXP",
  10, "LGLSXP",
  13, "INTSXP",
  14, "REALSXP",
  15, "CPLXSXP",
  16, "STRSXP",
  17, "DOTSXP",
  18, "ANYSXP",
  19, "VECSXP",
  20, "EXPRSXP",
  21, "BCODESXP",
  22, "EXTPTRSXP",
  23, "WEAKREFSXP",
  24, "RAWSXP",
  25, "S4SXP",
  30, "NEWSXP",
  31, "FREESXP",
  99, "FUNSXP"
)


SEXP_TYPES <- SEXP_TYPES %>% mutate(name = factor(name))

resolve_sexp_name <- function(df, var) {
  en_var <- enquo(var)
  by <- "sexp_type"
  names(by) <- as.character(substitute(var))
  df %>%
    left_join(SEXP_TYPES, by = by) %>%
    select(-!!en_var) %>%
    rename(!!en_var := name)
}


add_types <- function(dataset) {
  return(
    dataset %>%
      resolve_sexp_name(expr_expression_type) %>%
      resolve_sexp_name(expr_resolved_type) %>%
      resolve_sexp_name(enclos_type) %>%
      resolve_sexp_name(envir_type)
  )
}


# placeholder for the `parse_only` function of library xfun
parse_only <- function(code) {
}
.myparse <- function(text) {
}
parse_all <- function(x, filename, allow_error) {
}

extract_args_parse <- function(eval_call) {
  exp <- get_expr(eval_call)
  exp <- tryCatch(
    call_standardise(exp),
    error = function(c) {
      if (length(exp) >= 2 &&
        exp[[2]] == "...") {
        names(exp)[[2]] <- "dots"
        return(exp)
      }
      else {
        stop(paste0("extract_arg failed with: ", eval_call))
      }
    }
  )
  args <-
    map_chr(as.list(exp[-1]), function(chr) {
      paste(deparse(chr), collapse = "\n")
    })
  names(args) <-
    map_chr(names(args), function(chr) {
      paste0("parse_args_", chr)
    })

  return(args[str_detect(
    names(args),
    "^parse_args_(file|text|n|s|keep\\.source|srcfile|dots)$"
  )]) # "file|text|n|s|prompt|keep.source|srcfile|code"
}

add_parse_args <- function(dataset) {
  return(dataset %>% mutate(parse_args = map(expr_parsed_expression, function(e) {
    if (!is.na(e) &&
      str_starts(e, "(parse|str2lang|str2expression)\\(")) {
      extract_args_parse(e)
    } else {
      list()
    }
  })) %>% unnest_wider(parse_args))
}

eval_base_functions <-
  c(
    "autoload",
    "autoloader",
    "bquote",
    "by.default",
    "by.data.frame",
    "invokeRestartInteractively",
    "Ops.data.frame",
    "dget",
    "eval",
    "eval.parent",
    "evalq",
    "local",
    "with.default",
    "within.data.frame",
    "within.list",
    "replicate",
    "subset.data.frame",
    "subset.matrix",
    "transform.data.frame",
    "match.arg",
    "char.expand",
    "max.col",
    "parseNamespaceFile",
    "source",
    "sys.source",
    "stopifnot",
    "as.data.frame.table",
    "match.fun",
    "trace",
    "untrace",
    ".doTrace",
    "Vectorize"
  )

# match eval that are not called (but passed to a higher order function)
is_eval <- function(s) {
  return(!is.na(s) &&
    str_detect(s, "(eval(q|\\.parent)?|local)[^\\(_\\.q]"))
}

# To use if srcref is NA and caller_function is not one of the base ones
# Will not always work but should work for lapply ones
package_name_from_call_stack <-
  function(caller_stack_expr,
           caller_stack_expr_srcref) {
    stack_expr <- str_split(caller_stack_expr, fixed("\n"))
    stack_srcref <- str_split(caller_stack_expr_srcref, fixed("\n"))

    eval_pos <- detect_index(stack_expr[[1]], is_eval)
    if (eval_pos != 0) {
      srcref <- stack_srcref[[1]][[eval_pos]]
      return(if (srcref == "NA") {
        "base?"
      } else {
        srcref
      })
    }

    return("base?")
  }


extract_package_name <- function(src_ref, file) {
  # There are 5 possibilities for a srcref:
  # - NA
  # - /tmp/Rtmp..../R.INSTALL....../packagename/R/file:linenumbers
  # - mnt/ocfs_vol_00/project-evalR/library/4.0/instrumentr/srcref/packagename/4.0.4/file:linenumbers
  # - /R/* : core packages (we cannot distinguish between them yet so we write core for the package name)
  # - /testit/... or /testthat/... : it is the testit or testthat packages
  # - :/R : extract the package name from the file path in the column path
  # - .../kaggle-run/<id>/run.R:...
  case_when(
    is.na(src_ref) ~ "base?",
    str_starts(src_ref, fixed("./R/")) ~ "core",
    str_starts(src_ref, fixed("/tmp/")) ~ str_match(src_ref, "/tmp.*/Rtmp[^/]*/R\\.INSTALL[^/]*/([^/]+)/R/.*$")[[2]], # path problem here
    str_starts(src_ref, fixed("/mnt/ocfs_vol")) ~ "base", # depends on where the shared is mounted!
    str_starts(src_ref, fixed("::")) ~ str_match(src_ref, "::([^:]*)::.*")[[2]],
    str_starts(src_ref, ".*::") ~ str_match(src_ref, "([^:]*)::.*")[[2]],
    str_starts(src_ref, fixed("test")) ~ str_match(src_ref, "([^/]*)/.*")[[2]],
    str_starts(src_ref, fixed("/:")) ~ str_match(file, "[^/]*/[^/]*/([^/]*)/.*")[[2]],
    TRUE ~ "unknown"
  )
}

# There are 5 main possibilities for a srcref:
# - NA
# - /tmp/Rtmp..../R.INSTALL....../packagename/R/file:linenumbers
# - mnt/ocfs_vol_00/project-evalR/library/4.0/instrumentr/srcref/packagename/4.0.4/file:linenumbers
# - /R/* : core packages (we cannot distinguish between them yet so we write core for the package name)
# - /testit/... or /testthat/... : it is the testit or testthat packages
# - :/R : extract the package name from the file path in the column path
# - .../kaggle-trace-eval/.../.../calls.fst
add_eval_source <- function(df) {
  df <- df %>% mutate(
    eval_source = case_when(
      is.na(eval_call_srcref) & caller_function %in% eval_base_functions ~ "base",
      is.na(eval_call_srcref) & caller_package == "foreach" & caller_expression == "e$fun(obj, substitute(ex), parent.frame(), e$data)" ~ "foreach",
      is.na(eval_call_srcref) ~ "base?",
      str_starts(eval_call_srcref, fixed("./R/refClass.R")) ~ "methods",
      str_starts(eval_call_srcref, fixed("./R/")) ~ "base",
      str_starts(eval_call_srcref, fixed("/R/")) ~ str_match(eval_call_srcref, "/R/R-dyntrace/library/([^/]*)/R/.*$")[, 2],
      str_starts(eval_call_srcref, fixed("/tmp")) ~ str_match(eval_call_srcref, "/tmp.*/Rtmp[^/]*/R\\.INSTALL[^/]*/([^/]+)/R/.*$")[, 2],
      str_detect(file, fixed("kaggle-trace-eval")) ~ str_match(file, ".*/kaggle-trace-eval/[^/]*/([^/]*)/calls.fst")[, 2],
      str_starts(eval_call_srcref, fixed("/mnt/ocfs_vol")) ~ "base", # depends on where the shared is mounted!
      str_starts(eval_call_srcref, fixed("::")) ~ str_match(eval_call_srcref, "::([^:]*)::.*")[, 2],
      str_starts(eval_call_srcref, ".*::") ~ str_match(eval_call_srcref, "([^:]*)::.*")[, 2],
      str_starts(eval_call_srcref, fixed("test")) ~ str_match(eval_call_srcref, "([^/]*)/.*")[, 2],
      str_starts(eval_call_srcref, fixed("/:")) ~ str_match(file, "[^/]*/[^/]*/([^/]*)/.*")[, 2],
      TRUE ~ "unknown"
    )
  )
  stopifnot(!is.na(df$eval_source))
  return(df)
}

find_package_name <- function(caller_function,
                              caller_package,
                              caller_expression,
                              srcref,
                              file) {
  if (caller_function %in% eval_base_functions) {
    "core"
  } # "Actually base but we generalize
  else {
    tempPack <- extract_package_name(srcref, file)
    ## It would indicate that one of the regex has failed and
    ## so that probably assumptions made on the paths in the srcref are no longer valid
    stopifnot(!is.na(tempPack))
    ## It means the srcref was NA
    if (tempPack == "base?") {
      ## This eval is defined in function doSEQ in do.R of package foreach
      if (caller_package == "foreach" && caller_expression == "e$fun(obj, substitute(ex), parent.frame(), e$data)") {
        "foreach"
      }
      else if (str_detect(file, fixed("kaggle-trace-eval"))) {
        str_match(file, ".*/kaggle-trace-eval/(.*)/calls.fst")[[2]]
      }
      else {
        "base?"
      }
    }
    else {
      tempPack
    }
  }
}

add_eval_source2 <- function(df) {
  df %>%
    mutate(eval_source = pmap_chr(
      list(
        caller_function,
        caller_package,
        caller_expression,
        eval_call_srcref,
        file
      ),
      find_package_name
    ))
  stopifnot(!is.na(df$eval_source))
  return(df)
}

compute_fake_srcref <- function(eval_source,
                                caller_function,
                                eval_call_expression) {
  str_c(eval_source, str_replace_na(caller_function), eval_call_expression, sep = "::")
}

add_fake_srcref <- function(df) {
  stopifnot(!is.na(df$eval_source))
  df_na <-
    df %>%
    filter(is.na(eval_call_srcref)) %>%
    mutate(eval_call_srcref = str_c(eval_source, str_replace_na(caller_function), if_else(caller_function %in% eval_base_functions, "", eval_call_expression), sep = "::"))

  df %>%
    filter(!is.na(eval_call_srcref)) %>%
    bind_rows(df_na) %>%
    mutate(eval_call_srcref=if_else(eval_call_expression=="eval(handler$expr, handler$envir)", "::withr::execute_handlers::1", eval_call_srcref)) %>%
    mutate(eval_call_srcref=if_else(eval_call_srcref=="/tmp/RtmpX0d2E3/R.INSTALLce274ec00947/ggplot2/R/ggproto.r:76:5:76:31", "::ggplot2::ggproto::1", eval_call_srcref))
}

keep_only_corpus <- function(dataset, corpus_files) {
  dataset %>%
    semi_join(corpus_files, by = c("eval_source" = "package"))
}

get_externals <- function(dataset, corpus_files) {
  dataset %>%
    anti_join(corpus_files, by = c("eval_source" = "package"))
}

undefined_packages <- function(eval_calls) {
    eval_calls %>%
    filter(eval_source == "base?")
}

add_provenances <- function(df, provenances) {
  # Remove the old provenance columns
  df <- df %>% select(-expr_match_call, -expr_parsed_expression)
  
  # prepare the common columns
  df <- df %>% mutate(basepath = dirname(file))
  provenances <- provenances %>% mutate(basepath = dirname(file)) %>% select(-file)
  
  left_join(df, provenances, by = c("eval_call_id", "basepath")) %>% select(-basepath)
}


### Command line and preprocessing pipeline

add_package <- function(dataset) {
  dataset %>%
    mutate(package = basename(dirname(dirname(file))))
}

read_merged_file <- function(filepath) {
  df <- read_fst(filepath) %>%
    as_tibble() %>%
    add_package()

  df
}

preprocess_calls <- function(arguments) {
  corpus_file <- arguments$corpus_file
  calls_file <- arguments$calls_file
  provenance_file <- arguments$provenance_file
  evals_undefined_file <- arguments$evals_undefined_file
  evals_summarized_file <- arguments$evals_summarized_file
  evals_summarized_externals_file <- arguments$evals_summarized_externals_file
  trim_expressions <- arguments$trim_expressions
  keep_caller_package <- arguments$keep_caller_package
  out_name <- arguments$out_name
  is_kaggle <- arguments$kaggle

  now_first <- Sys.time()

  cat("Reading ", calls_file, "\n")

  eval_calls_raw <- read_merged_file(calls_file)

  res <- difftime(Sys.time(), now_first)

  cat("Finished in ", res, units(res), "\n")

  ## Preprocessing pipeline

  cat("Preprocessing ", calls_file, "\n")
  
  if(!is.na(provenance_file)) {
    cat("Reading provenances\n")
    now <- Sys.time()
    provenances <- read_fst(provenance_file) %>% as_tibble()
    res <- difftime(Sys.time(), now)
    cat("Done in ", res, units(res), "\n")
    
    cat("Adding provenances\n")
    now <- Sys.time()
    eval_calls_raw <- eval_calls_raw %>% add_provenances(provenances)
    res <- difftime(Sys.time(), now)
    cat("Done in ", res, units(res), "\n")
  }
  


  cat("Deduplicating from ", nrow(eval_calls_raw), " rows")
  now <- Sys.time()
  eval_calls <- eval_calls_raw %>% deduplicate()
  cat(" to ", nrow(eval_calls), " rows\n")
  res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")

  cat("Compute source packages\n")
  now <- Sys.time()
  eval_calls <- eval_calls %>% add_eval_source()
  res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")


  cat("Correcting srcrefs\n")
  now <- Sys.time()
  eval_calls <- eval_calls %>% add_fake_srcref()
  # We manually corrected the src ref for that withr function so now we need
  # to correct its eval source manually!
  eval_calls <- eval_calls %>% mutate(eval_source = if_else(eval_call_srcref == "::withr::execute_handlers::1", "withr", eval_source))
  if(is_kaggle) {
    cat("Fixing kaggle srcref\n")
    stopifnot(str_starts(eval_calls$eval_call_srcref, fixed("::global")))

    eval_calls <- eval_calls %>%
      mutate(eval_call_srcref = str_replace(eval_call_srcref, fixed("::global::"), paste0("::", eval_source, "::")))
  }
  else {
    cat("Removing eval directly in the source of an example, a vignette...\n")
    eval_calls <- eval_calls %>%
      filter(!str_starts(eval_call_srcref, fixed("::global::")))
  }
  res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")

  if(!keep_caller_package) {
    eval_calls <- eval_calls %>% select(-caller_package)
  }

  # Trim expressions if needed
  if (trim_expressions) {
    cat("Trim expressions\n")
    now <- Sys.time()
    eval_calls <- eval_calls %>% mutate(across(contains("expression"), ~ str_sub(., end = 120L)))
    res <- difftime(Sys.time(), now)
    cat("Done in ", res, units(res), "\n")
  }

  cat("Undefined calls per package\n")
  now <- Sys.time()
  undefined_per_package <- undefined_packages(eval_calls)
  eval_calls <- eval_calls %>% filter(eval_source != "base?")
  res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")

  if (!is.na(corpus_file)) {
    cat("Only keep eval in corpus\n")
    now <- Sys.time()
    corpus <- readLines(corpus_file)
    corpus_files <- tibble(package=corpus)
    eval_calls_corpus <- eval_calls %>% keep_only_corpus(corpus_files)
    eval_calls_externals <- eval_calls %>% get_externals(corpus_files)
    eval_calls <- eval_calls_corpus
    res <- difftime(Sys.time(), now)
    cat("Done in ", res, units(res), "\n")
  }
  else {
    eval_calls_externals <- eval_calls %>% head(0) # to get all the same columns
  }



  # Write output files
  cat("Writing output files\n")
  if (!is.na(out_name)) {
    evals_undefined_file <- paste0(out_name, "-undefined.fst")
    evals_summarized_file <- paste0(out_name, "-summarized.fst")
    evals_summarized_externals_file <- paste0(out_name, "-externals.fst")
  }

  now <- Sys.time()
  write_fst(undefined_per_package, evals_undefined_file)

  write_fst(eval_calls, evals_summarized_file)

  write_fst(eval_calls_externals, evals_summarized_externals_file)

  res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")

  res <- difftime(Sys.time(), now_first)
  cat("Total processing time in ", res, units(res), "\n")

  return(0)
}

################################################################################
## REFLECTION DATA PREPROCESSING
################################################################################

time <- function(df, message, fun) {
  force(df)
  cat("# ", message, "\n")
  t <- system.time(df <- fun(df))
  print(t)
  cat("\n")
  df
}

preprocess_reflection <- function(arguments) {
  reflection <-
    arguments$reflection_file %>%
    time("Reading merged file", read_merged_file) %>%
    time("Adding eval source", add_eval_source) %>%
    time("Adding fake srcref", add_fake_srcref)

  write_fst(reflection, arguments$reflection_summarized_file)
}


################################################################################
## ARGUMENT PARSING AND DRIVER CODE
################################################################################

parse_program_arguments <- function() {
  option_list <- list(
    make_option(
      c("--corpus"),
      dest = "corpus_file", metavar = "FILE",
      help = "Corpus file"
    ),
    make_option(
      c("--calls"),
      dest = "calls_file", metavar = "FILE",
      help = "Calls file"
    ),
    make_option(
      c("--reflection"),
      dest = "reflection_file", metavar = "FILE",
      help = "Reflection file"
    ),
    make_option(
      c("--provenance"),
      dest = "provenance_file", metavar = "FILE",
      help = "Add provenances"
    ),
    make_option(
      c("--out-undefined"),
      dest = "evals_undefined_file", metavar = "FILE"
    ),
    make_option(
      c("--out-summarized"),
      dest = "evals_summarized_file", metavar = "FILE"
    ),
    make_option(
      c("--out-summarized-externals"),
      dest = "evals_summarized_externals_file", metavar = "FILE"
    ),
    make_option(
      c("--trim"),
      action = "store_true", dest = "trim_expressions", default = TRUE,
    ),
    make_option(
      c("--kaggle"),
      action = "store_true", dest = "kaggle", default = FALSE,
    ),
    make_option(
      c("--keep-caller-package"),
      action = "store_true", dest = "keep_caller_package", default = FALSE,
    ),
    make_option(
      c("--out"),
      action = "store", dest = "out_name", default = NA, type = "character",
      help = "Use that name to build all the output file names."
    )
  )

  opt_parser <- OptionParser(option_list = option_list)
  arguments <- parse_args(opt_parser, positional_arguments = 1)
  arguments$options$help <- NULL

  arguments
}

main <- function() {
  arguments <- parse_program_arguments()

  str(arguments)

  cat("\n")

  if (arguments$args[1] %in% c("calls", "all")) {
    preprocess_calls(arguments$options)
  }
  else if (arguments$args[1] %in% c("reflection", "all")) {
    preprocess_reflection(arguments$options)
  }

  invisible(NULL)
}

main()
