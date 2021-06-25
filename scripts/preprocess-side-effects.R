suppressPackageStartupMessages(library(dplyr))
library(fst)
library(optparse)
library(stringr)
library(tidyr)

add_cid <- function(df, trace_dir) {
  df %>%
    mutate(
      cid=str_c(dirname(str_sub(file, start=nchar(trace_dir)+2)), "/", eval_call_id)
    ) %>%
    select(cid, eval_call_srcref, everything()) %>%
    select(-file, -eval_call_id)
}

task <- function(msg, thunk) {
  .time <- Sys.time()
  cat("Running:", msg, "...\n")
  res <- force(thunk)
  cat("Done in", as.numeric(Sys.time() - .time, unit="secs"), "\n")
  res
}

patch_srcref <- function(eval_call_srcref, expr_expression, envir_expression) {
  case_when(
    is.na(eval_call_srcref) & expr_expression == "handler$expr" & envir_expression == "handler$envir" ~ "::withr::execute_handlers::1",
    is.na(eval_call_srcref) & expr_expression == "quote({\n    old.options <- options(dplyr.summarise.inform = FALSE)\n    o" ~ "::dplyr::tally::1",
    is.na(eval_call_srcref) & expr_expression == "quote({\n    na.action <- attr(mf, \"na.action\")\n    why_omit <- attr(na.a" ~ "::estimatr::cleam_mode_data::1",
    str_ends(eval_call_srcref, "/R6/R/generator_funs.R:4:3:4:33") ~ "::R6::generator_funs::1",
    str_ends(eval_call_srcref, "/ggplot2/R/ggproto.r:76:5:76:31") ~ "::ggplot2::ggproto::1",
    str_ends(eval_call_srcref, "/data.table/R/onLoad.R:92:5:92:58") ~ "::data.table::.onLoad::1",
    str_ends(eval_call_srcref, "/data.table/R/data.table.R:2591:11:2591:74") ~ "::data.table::address::1",
    is.na(eval_call_srcref) ~ "???",
    TRUE ~ eval_call_srcref
  )
}

is_unit_test_framework <- function(eval_call_srcref) {
  str_starts(eval_call_srcref, fixed("::testthat::")) |
    str_starts(eval_call_srcref, fixed("::tinytest::")) |
    str_starts(eval_call_srcref, fixed("::RUnit::")) |
    str_starts(eval_call_srcref, fixed("::unitizer::"))
}

run <- function(calls_file, writes_file, side_effects_file) {
  E_raw_loaded <- task(str_c("Reading ", calls_file), read_fst(calls_file) %>% as_tibble())

  E_all_full <- task("Adding cid to calls", add_cid(E_raw_loaded, dirname(calls_file)))

  E_all_full <- task("Finding duplicate cids in calls", {
    E_dup_idx <- which(duplicated(E_all_full$cid))
    cat("Duplicated items in E:", length(E_dup_idx), "\n")
    
    if (length(E_dup_idx) > 0) {
      E_all_full[-E_dup_idx, ]
    } else {
      E_all_full
    }
  })

  E_all <-
    task("Subsetting calls", {
      E_all_full %>%
      select(
        cid,
        eval_call_srcref,
        eval_function,
        caller_package,
        caller_function,
        caller_srcref,
        environment_class,
        successful,
        expr_expression,
        expr_resolved,
        expr_resolved_type,
        expr_resolved_hash,
        expr_return,
        expr_return_type,
        expr_parsed_expression,
        envir_expression,
        envir_type,
        expr_match_call,
        enclos_expression,
        enclos_type,
        interp_eval
      ) %>%
      # patch srcrefs
      mutate(eval_call_srcref=patch_srcref(eval_call_srcref, expr_expression, envir_expression)) %>%
      # filter out unit tests
      filter(!is_unit_test_framework(eval_call_srcref)) %>%
      # fix caller_*
      mutate(
        caller_package_1=str_replace(eval_call_srcref, "^::(.*)::.*", "\\1"),
        caller_function_1=str_replace(eval_call_srcref, "^::.*::(.*)::.*", "\\1")
      ) %>%
      # trim strings
      mutate(across(where(is.character) & !c(cid, eval_call_srcref, caller_srcref), ~str_sub(., end=72L)))
    })

  W_raw_loaded <- task(str_c("Reading ", writes_file), read_fst(writes_file) %>% as_tibble())

  W_all <- task("Subsetting side-effects", {
    W_raw_loaded %>%
    rename(eval_call_id=eval_id) %>%
    select(
      -env_id,
      -parent_eval_id,
      -receiver_eval_id
    ) %>%
    # non-transitive
    filter(transitive==0) %>%
    # filter out unit tests
    filter(!is_unit_test_framework(eval_call_srcref)) %>%
    # fix source
    mutate(source=str_replace(source, "^call:.*::(.*)", "call:\\1"))
  })

  W_all <- task("Adding cid to writes", {
    add_cid(W_all, dirname(writes_file))
  })

  EW_all <- task("Join calls and writes", {
    tmp <- left_join(E_all, W_all, by="cid")
    d <- filter(tmp, eval_call_srcref.x != eval_call_srcref.y)
    message("Number of different srcrefs: ", nrow(d))
    select(tmp, eval_call_srcref=eval_call_srcref.x, -eval_call_srcref.y, everything())
  })

  SE <- task("Ignore internal evals", {
    ignore_env_se <-
      EW_all %>%
      filter(str_detect(variable, "env::\\d+")) %>%
      select(cid)

    ignore_random_seed <-
      EW_all %>%
      filter(variable == ".Random.seed") %>%
      filter(ifelse(is.na(expr_resolved), TRUE, !str_detect(expr_resolved, fixed("set.seed")))) %>%
      select(cid)

    ignore_internal <-
      EW_all %>%
      filter(str_starts(source, fixed("internal:"))) %>%
      select(cid)

    ignore <- bind_rows(
      ignore_env_se,
      ignore_random_seed,
      ignore_internal
    ) %>%
      distinct()

    anti_join(EW_all, ignore, by="cid")
  })

  SE_dedup <- task("Deduplicating", {
    SE %>%
    mutate(
      transitive=ifelse(transitive==0, F, T),
      in_envir=ifelse(in_envir==0, F, T),
      envir_expression=ifelse(envir_expression == "NA", NA, envir_expression)
    ) %>%
    count(across(everything()), name = "N")
  })

  task(str_c("Writing ", side_effects_file), write_fst(SE_dedup, side_effects_file))

  cat("Wrote", nrow(SE_dedup), "records (", nrow(SE), " side-effects) in ", side_effects_file, "(", file.size(side_effects_file)/1024/1024, " MB)\n")

  invisible(NULL)
}

option_list <- list(
  make_option(
    c("--calls"),
    dest = "calls_file", metavar = "FILE",
    help = "calls.fst"
  ),
  make_option(
    c("--writes"),
    dest = "writes_file", metavar = "FILE",
    help = "Writes file"
  ),
  make_option(
    c("--out-side-effects"),
    dest = "side_effects_file", metavar = "FILE",
    help = "Resulting side effects file"
  )
)

opt_parser <- OptionParser(option_list = option_list)
options <- parse_args(opt_parser)
options$help <- NULL
do.call(run, options)

