#!/usr/bin/env Rscript

# Preprocess the dataset:
# - remove duplicates
# - correct src refs
# - add some columns (such as `eval_call_package`)
# - cut the dataset into smaller ones


suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(rlang))
library(fs)
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


# we try to find a same combination of caller_package, caller_function and eval_call_expression in both datasets
# if yes, we inditifed a call site
# data set undefined should be the packages with missing srcref and which caller_function is not in base
package_name_from_static <- function(dataset_undefined, static_data) {
  dataset_undefined %>%
    semi_join(static_data, by = c("eval_call_expression", "caller_package")) %>%
    count(eval_call_expression, caller_package, caller_function)
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
    str_starts(src_ref, fixed("test")) ~ str_match(src_ref, "([^/]*)/.*")[[2]],
    str_starts(src_ref, fixed("/:")) ~ str_match(file, "[^/]*/[^/]*/([^/]*)/.*")[[2]],
    TRUE ~ "unknown"
  )
}


find_package_name <-
  function(caller_function,
           caller_package,
           caller_expression,
           srcref,
           file) {
    if (caller_function %in% eval_base_functions) {
      return("core")
    } # "Actually base but we generalize
    else {
      tempPack <- extract_package_name(srcref, file)
      # It would indicate that one of the regex has failed and
      # so that probably assumptions made on the paths in the srcref are no longer valid
      stopifnot(!is.na(tempPack))
      if (tempPack == "base?")
      # It means the srcref was NA
        {
          if (caller_package == "foreach" &&
            caller_expression == "e$fun(obj, substitute(ex), parent.frame(), e$data)") {
            # This eval is defined in function doSEQ in do.R of package foreach
            return("foreach")
          }
          else {
            return("base?")
          }
        }
      else {
        return(tempPack)
      }
    }
  }

find_package_name_second_chance <-
  function(file,
           caller_stack_expr,
           caller_stack_expr_srcref) {
    new_srcref <-
      package_name_from_call_stack(caller_stack_expr, caller_stack_expr_srcref)
    return(extract_package_name(new_srcref, file))
  }

add_eval_source <- function(dataset, dataset_with_stacks) {
  dataset_c <- dataset %>%
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

  # dataset_stacks <- dataset_c %>% filter(eval_source == "base?") %>%
  #     left_join(select(dataset_with_stacks, -ends_with("_type"))) %>%
  #     select(-eval_call_id, -caller_stack_expression_raw) %>%
  #     distinct()
  # dataset_stacks <- dataset_stacks %>%
  #   distinct(file, caller_stack_expression, caller_stack_expression_srcref) %>%
  #   mutate(eval_source = pmap_chr(list(file, caller_stack_expression, caller_stack_expression_srcref),
  #                                 find_package_name_second_chance)) %>%
  #   select(-starts_with("caller_stack_")) %>%
  #   distinct() # There might be a problem with duplicated rows with same nb_ev_calls?

  # dataset_c <- bind_rows(dataset_c %>% filter(eval_source != "base?"), dataset_stacks)

  return(dataset_c)
}

add_eval_source_type <- function(dataset) {
  return(dataset %>%
    mutate(
      eval_source_type = case_when(
        eval_source %in% c("base", "core") ~ "core",
        eval_source == "base?" ~ "<undefined>",
        TRUE ~ "package"
      )
    ))
}


add_fake_srcref <- function(dataset) {
  return(dataset %>%
    mutate(
      eval_call_srcref = if_else(
        is.na(eval_call_srcref) & eval_source_type != "<undefined>",
        str_c(eval_source, caller_function, eval_call_expression,
          sep =
            "::"
        ),
        eval_call_srcref
      )
    ))
}


add_ast_size <- function(dataset) {
  print("Creating cluster")
  cluster <- new_cluster(parallel::detectCores() - 10)
  print("Cluster created. Copying functiond and libraries.")
  cluster_copy(cluster, "get_expr")
  cluster_copy(cluster, "expr_size")
  cluster_copy(cluster, "expr_size_str")
  cluster_library(cluster, "tidyverse")
  print("Functions and libraries copied. Partitionning.")
  dataset_c <-
    dataset %>%
    select(expr_resolved) %>%
    distinct() %>%
    group_by(expr_resolved) %>%
    partition(cluster)
  print("Partionned. Computing.")
  dataset_c <- dataset_c %>%
    mutate(expr_resolved_ast_size = map_int(expr_resolved, expr_size_str)) %>%
    collect()
  print("Finished computing. Left joining.")
  dataset <- dataset %>% left_join(dataset_c)
  print("Finished.")
  return(dataset)
}

add_package <- function(dataset) {
  mutate(dataset,
    package = basename(dirname(dirname(file)))
  )
}



keep_only_corpus <- function(dataset, corpus_files) {
  return(dataset %>%
    semi_join(corpus_files, by = c("eval_source" = "package")))
}

get_externals <- function(dataset, corpus_files) {
  return(dataset %>%
    anti_join(corpus_files, by = c("eval_source" = "package")))
}

undefined_packages <- function(eval_calls) {
  undefined_evals <-
    eval_calls %>% filter(eval_source_type == "<undefined>")
  undefined_per_package <-
    undefined_evals %>%
    group_by(package) %>%
    summarize(n = n_distinct(eval_call_expression))
  known_packages <-
    setdiff(eval_calls$package, undefined_per_package$package) %>% as_tibble_col(column_name = "package")
  known_packages <- known_packages %>% mutate(n = 0)

  undefined_per_package <-
    bind_rows(undefined_per_package, known_packages) %>% arrange(desc(n))

  return(undefined_per_package)
}


# This is performed directly in usage_metrics.Rmd
known_call_sites <- function(eval_calls_corpus, corpus_files) {
  call_sites_per_package <- eval_calls_corpus %>%
    filter(eval_source_type == "package", eval_source %in% corpus_files$package) %>%
    group_by(eval_source) %>%
    summarize(n = n_distinct(eval_call_srcref))

  known_packages <-
    setdiff(corpus_files, call_sites_per_package$eval_source) %>% as_tibble_col(column_name = "eval_source")

  known_packages <- known_packages %>% mutate(n = 0)

  call_sites_per_package <-
    bind_rows(call_sites_per_package, known_packages) %>%
    rename(package = eval_source) %>%
    arrange(desc(n))

  return(call_sites_per_package)
}

### Command line and preprocessing pipeline

usage <- function() {
  cat(
    "USAGE:
./preprocess <corpus_file> <calls_file> <kaggle_calls_file> <package_evals_dynamic_file> <evals_undefined_file> <evals_raw_file> <evals_summarized_core_file> <evals_summarized_pkgs_file> <evals_summarized_kaggle_file> <evals_summarized_externals_file>.

The command has 10 arguments. The first 3 ones are input files, the last 7 ones are output files. All files are assumed to be fst files.

Example:
./preprocess revalstudy/inst/data/corpus.fst run/package-evals-traced.4/calls.fst run/kaggle-run/calls.fst revalstudy/inst/data/evals-dynamic.fst run/package-evals-traced.4/summarized-evals-undefined.fst run/package-evals-traced.4/raws.fst run/package-evals-traced.4/summarized-core.fst run/package-evals-traced.4/summarized-packages.fst run/package-evals-traced.4/summarized-kaggle.fst run/package-evals-traced.4/summarized-externals.fst
\n"
  )
}

main <- function(
  corpus_file,
  calls_file,
  kaggle_calls_file,
  evals_undefined_file,
  evals_raw_file,
  evals_summarized_core_file,
  evals_summarized_pkgs_file,
  evals_summarized_kaggle_file,
  evals_summarized_externals_file
) {

  cat("Reading and validating input files\n")

  now_first <- Sys.time()
  corpus <- read_fst(corpus_file)
  # stopifnot(length(corpus) == 29)
  stopifnot("package" %in% names(corpus)) # for preprocess, we mainly care about the package names

  eval_calls_raw <-
    read_fst(calls_file) %>%
    as_tibble() %>%
    mutate(
      package = basename(dirname(dirname(dirname(file)))),
      corpus = "cran"
    )
  # %>%
  # semi_join(corpus, by = "package") # There might be more packages traced than what is in the corpus
  # stopifnot(length(eval_calls_raw) == 52)

  eval_calls_kaggle_raw <-
    read_fst(kaggle_calls_file) %>%
    as_tibble() %>%
    mutate(
      package = basename(dirname(file)),
      corpus = "kaggle"
    )
  # stopifnot(length(eval_calls_kaggle_raw) == 52)

  # eval_calls_raw <- bind_rows(eval_calls_raw, eval_calls_kaggle_raw) # Kaggle has not the right format currently
  res <- difftime(Sys.time(), now_first)
  cat("Done in ", res, units(res), "\n")

  # Preprocessing pipeline

  cat("Deduplicating from ", nrow(eval_calls_raw), " rows")
  now <- Sys.time()
  eval_calls <- eval_calls_raw %>% deduplicate()
  cat(" to ", nrow(eval_calls), " rows\n")
  res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")

  # cat("Adding types\n")
  # eval_calls <- eval_calls %>% add_types() # This step is now useless as there are directly strings
  cat("Correcting srcrefs\n")
  now <- Sys.time()
  eval_calls <- eval_calls %>% add_eval_source(eval_calls_raw)
  eval_calls <- eval_calls %>% add_eval_source_type()
  eval_calls <- eval_calls %>% add_fake_srcref()
  res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")

  cat("Adding parse args\n")
  now <- Sys.time()
  eval_calls <- eval_calls %>% add_parse_args()
  res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")

  cat("only keep eval in corpus\n")
  now <- Sys.time()
  # This is probably useless as there already was a filtering at tracing time.
  # But this is a sanity check...
  # Keep if quick
  corpus_files <- select(corpus, package) %>% bind_rows(tribble(~package, "core", "base", "base?"))
  eval_calls_corpus <- eval_calls %>% keep_only_corpus(corpus_files)
  eval_calls_externals <- eval_calls %>% get_externals(corpus_files)
  # res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")

  # Separate datasets
  cat("Separating datasets\n")
  now <- Sys.time()
  eval_calls_core <-
    eval_calls_corpus %>% filter(eval_source_type == "core")
  eval_calls_packages <-
    eval_calls_corpus %>% filter(eval_source_type == "package")
  eval_calls_kaggle <-
    eval_calls_corpus %>% filter(eval_source_type == "kaggle")
  res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")

  # Some other interesting data
  cat("Undefined calls per package\n")
  now <- Sys.time()
  undefined_per_package <- undefined_packages(eval_calls)
  res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")

  # cat("Number of call sites per package\n")
  # now <- Sys.time()
  # calls_site_per_package <-
  #   known_call_sites(eval_calls_corpus, corpus_files)
  # res <- difftime(Sys.time(), now)
  # cat("Done in ", res, units(res), "\n")

  # Write output files
  cat("Writing output files\n")
  now <- Sys.time()
  write_fst(undefined_per_package, evals_undefined_file)

  write_fst(eval_calls, evals_raw_file)

  write_fst(eval_calls_core, evals_summarized_core_file)

  write_fst(eval_calls_packages, evals_summarized_pkgs_file)

  write_fst(eval_calls_kaggle, evals_summarized_kaggle_file)

  write_fst(eval_calls_externals, evals_summarized_externals_file)

  # write_fst(calls_site_per_package, package_evals_dynamic_file)
  res <- difftime(Sys.time(), now)
  cat("Done in ", res, units(res), "\n")

  res <- difftime(Sys.time(), now_first)
  cat("Total processing time in ", res, units(res), "\n")

  return(0)
}

option_list <- list(
  make_option(
    c("--corpus"), dest="corpus_file", metavar="FILE",
    help="Corpus file"
  ),
  make_option(
    c("--calls"), dest="calls_file", metavar="FILE",
    help="Calls file"
  ),
  make_option(
    c("--kaggle-calls"), dest="kaggle_calls_file", metavar="FILE",
    help="Kaggle calls file"
  ),
  make_option(
    c("--out-undefined"), dest="evals_undefined_file", metavar="FILE"
  ),
  make_option(
    c("--out-raw"), dest="evals_raw_file", metavar="FILE"
  ),
  make_option(
    c("--out-summarized-core"), dest="evals_summarized_core_file", metavar="FILE"
  ),
  make_option(
    c("--out-summarized-pkgs"), dest="evals_summarized_pkgs_file", metavar="FILE"
  ),
  make_option(
    c("--out-summarized-kaggle"), dest="evals_summarized_kaggle_file", metavar="FILE"
  ),
  make_option(
    c("--out-summarized-externals"), dest="evals_summarized_externals_file", metavar="FILE"
  )
)

opt_parser <- OptionParser(option_list=option_list)
opts <- parse_args(opt_parser)
opts$help <- NULL

# TODO: proper check of args
if (length(opts) != 9) {
  print_help(opt_parser)
  stop("Missing args")
}

do.call(main, opts)
