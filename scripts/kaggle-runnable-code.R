#!/usr/bin/env Rscript

library(fs)
library(optparse)
library(rjson)
library(runr)
library(stringr)

run <- function(metadata_json_file, metadata_file, code_file, wrap_template_file) {
  if (file.access(metadata_json_file, 4) != 0) {
    stop(metadata_json_file, ": cannot access")
  }

  source_path <- dirname(metadata_json_file)

  metadata_json <- fromJSON(file=metadata_json_file)
  metadata <- data.frame(
    id=str_replace(metadata_json$id, "/", "-"),
    language=metadata_json$language,
    kernel_type=metadata_json$kernel_type,
    competition=metadata_json$competition
  )

  target_path <- getwd() #file.path(metadata$competition, metadata$id)
  fs::dir_copy(source_path, target_path, overwrite = TRUE)

  source_code_file <- file.path(source_path, metadata_json$code_file)
  code_file <- file.path(target_path, "kernel.R")

  runr::extract_kaggle_code(source_code_file, code_file)

  sloc_df <- runr::cloc(code_file, by_file=TRUE, r_only=TRUE)

  hash <- runr::file_sha1(code_file)

  if (!is.null(wrap_template_file)) {
    runr::wrap_files(
      package=metadata$id,
      file=code_file,
      type="kaggle",
      wrap_fun=runr::wrap_using_template(runr::read_file(wrap_template_file)),
      quiet=FALSE
    )
  }

  df <- cbind(
    file=code_file,
    metadata,
    subset(sloc_df, select=c(-language, -filename)),
    hash
  )

  write.csv(df, metadata_file, row.names=FALSE)
}

option_list <- list(
  make_option(
    c("--kernel"),
    help="Kaggle kernel-metadata.json",
    dest="metadata_json_file", metavar="FILE"
  ),
  make_option(
    c("--metadata"),
    help="CSV metadata output",
    dest="metadata_file", metavar="FILE"
  ),
  make_option(
    c("--code"),
    help="Kernel code output",
    dest="code_file", metavar="FILE"
  ),
  make_option(
    c("--wrap"),
    help="Wrap code file using the given template",
    dest="wrap_template_file", metavar="FILE"
  )
)

opt_parser <- OptionParser(option_list=option_list)
opts <- parse_args(opt_parser)

run(
  metadata_json_file=opts$metadata_json_file,
  metadata_file=opts$metadata_file,
  code_file=opts$code_file,
  wrap_template_file=opts$wrap_template_file
)
