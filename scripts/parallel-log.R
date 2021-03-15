#!/usr/bin/env Rscript

library(optparse)

run <- function(path, print_summary, print_failed, print_time) {
  log_file <- if (dir.exists(path)) {
    log_file <- file.path(path, "parallel.log")
  } else {
    path
  }

  if (!file.exists(log_file)) {
    stop(log_file, ": no such file")
  }

  suppressPackageStartupMessages(library(readr))
  suppressPackageStartupMessages(library(dplyr))
  library(stringr)

  log <- read_tsv(
    log_file,
    col_types=cols(
      Seq = col_double(),
      Host = col_character(),
      Starttime = col_double(),
      JobRuntime = col_double(),
      Send = col_double(),
      Receive = col_double(),
      Exitval = col_double(),
      Signal = col_double(),
      Command = col_character()
    )
  )

  if (nrow(log) == 0) {
    print("Empty!")
    return()
  }

 log <- log %>%
    rename_all(tolower) %>%
    mutate(
      endtime=starttime+jobruntime
    )

  if (print_summary) {
    jobs <- nrow(log)
    jobs_succ <- sum(log$exitval == 0)
    jobs_fail <- jobs - jobs_succ

    cat(sprintf("Duration: %.2f (sec)\n", max(log$endtime)-min(log$starttime)))
    cat(sprintf("Average job time: %.2f (sec)\n", mean(log$jobruntime)))
    cat(sprintf("Number of hosts: %d\n", length(unique(log$host))))
    cat(sprintf("Number of jobs: %d\n", jobs))
    cat(sprintf("Number of success jobs: %d (%.2f%%)\n", jobs_succ, jobs_succ / jobs * 100))
    cat(sprintf("Number of failed jobs: %d (%.2f%%)\n", jobs_fail, jobs_fail / jobs * 100))

    exit_vals <-
      log %>%
      count(exitval) %>%
      mutate(p=n/nrow(log)*100)

    cat("\nExit codes:\n")
    cat(sprintf("%3d: %5d (%3.2f%%)\n", exit_vals$exitval, exit_vals$n, exit_vals$p))
  }

  if (print_failed) {
    failed <- filter(log, exitval != 0)
    if (nrow(failed) > 0) {
      cat("\nFailed:\n")
      cat(sprintf("%3d: %s\n", failed$exitval, failed$command))
    }
  }

  if (print_time) {
    time <- arrange(log, desc(jobruntime))
      cat("\nTime:\n")
    cat(sprintf("%5.2f: %d: %s\n", time$jobruntime, time$exitval, time$command))
  }
}

option_list <- list(
  make_option("--no-summary", action="store_false", dest="print_summary", default=TRUE),
  make_option("--print-failed", action="store_true", default=FALSE),
  make_option("--print-time", action="store_true", default=FALSE)
)
opt_parser <- OptionParser(option_list=option_list)
opts <- parse_args(
  opt_parser,
  positional_arguments=1,
  convert_hyphens_to_underscores=TRUE
)

run(
  path=opts$args,
  print_summary=opts$options$print_summary,
  print_failed=opts$options$print_failed,
  print_time=opts$options$print_time
)
