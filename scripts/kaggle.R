#!/usr/bin/env Rscript

library(optparse)
library(purrr)
library(rjson)
library(stringr)
library(tibble)

for (x in c(
  "dplyr",
  "DT",
  "fs",
  "fst",
  "knitr",
  "purrr",
  "pbapply",
  "readr",
  "rjson",
  "rmarkdown",
  "runr",
  "stringr",
  "tibble"
)) {
  suppressPackageStartupMessages(library(x, character.only=TRUE))
}

pboptions(type="txt")

KERNEL_CSV <- "kernel.csv"
KERNEL_R <- "kernel.R"

kaggle_metadata <- function(file) {
  json <- fromJSON(file=file)
  tibble(
    id=str_replace(json$id, "/", "-"),
    language=json$language,
    kernel_type=json$kernel_type,
    competition=json$competition_sources,
    code_file=json$code_file
  )
}

run <- function(dataset_dir, korpus_dir, kernels_dir, options) {
  run_one <- function(file) {
    tryCatch({
      metadata <- kaggle_metadata(file)

      source_dir <- dirname(file)
      target_dir <- file.path(kernels_dir, metadata$competition, metadata$id)
      dir.create(target_dir, recursive=TRUE)
      file.copy(source_dir, target_dir)

      source_code_file <- file.path(target_dir, metadata$code_file)
      target_code_file <- file.path(target_dir, KERNEL_R)
      runr::extract_kaggle_code(source_code_file, target_code_file)
      file.remove(source_code_file)

      sloc_df <- runr::cloc(target_code_file, by_file=TRUE, r_only=TRUE)
      hash <- runr::file_sha1(target_code_file)

      cbind(
        metadata_df,
        subset(sloc_df, select=c(-language, -filename)),
        hash,
        error=NA
      )
    })

  }


  metadata_files <- list.files(korpus_dir, "kernel-metadata\\.json$", full.names=TRUE, recursive=TRUE)
  metadata <- pblapply(metadata_files, run_one)

  kernels <-
    metadata %>%
    mutate(
      path=path(kernels_dir, competition, id)
    ) %>%
    filter(dir_exists(path))
}




known_competitions <- semi_join(kernels, tibble(competition=params$competitions), by="competition")

if (dir_exists(KAGGLE_RUN_DIR)) {
  warning("*** ", KAGGLE_RUN_DIR, " exists")
}

extraction_lst <- pbapply::pbapply(known_competitions, 1, cl=16, function(x) {
  tryCatch({
    tibble(id=x["id"], run_file=extract_kernel_code(x["path"], x["code_file"], x["competition"]))
  }, error=function(e) {
    tibble(id=x["id"], error=e$message)
  })
})
extraction <- bind_rows(extraction_lst)

kernels_supported <-
  known_competitions %>%
  left_join(extraction, by="id") %>%
  filter(file_exists(run_file))

sloc <- map_dfr(path(KAGGLE_RUN_DIR, params$competitions), function(x) {
  out <- system2("cloc", c("--include-lang=R", "--by-file-by-lang", "-q", "--csv", shQuote(x)), stdout = TRUE)
  out_r <- out[startsWith(out, "R,")]
  out_csv <- c("language,filename,blank,comment,code", out_r)
  df <- read_csv(out_csv)
}) %>%
  mutate(
    kernel=basename(dirname(filename))
  ) %>%
  select(kernel, code)

stopifnot(any(!duplicated(sloc$kernel)))

kernels_supported <-
  kernels_supported %>%
  left_join(sloc, by=c("id"="kernel")) %>%
  mutate(runnable=ifelse(is.na(code), FALSE, code > 0))

kernels_runnable <- filter(kernels_supported, runnable)
write_csv(kernels_supported, KERNELS_FILE)
write_lines(dirname(kernels_runnable$run_file), SCRIPTS_FILE)

dataset_inputs <- path(KAGGLE_DATASETS_DIR, params$competitions)
dataset_outpus <- path(KAGGLE_RUN_DIR, params$competitions, "input")
dir_copy(dataset_inputs, dataset_outpus, overwrite = TRUE)

print(count(kernels_supported, runnable))
