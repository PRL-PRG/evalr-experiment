#!/usr/bin/env Rscript

library(rjson)
library(runr)
library(stringr)

extract_kernel_code <- function(source_file, target_file) {
  if (str_ends(source_file, "\\.[rR]$")) {
    file.copy(source_file, target_file, overwrite=TRUE)
  } else if (str_ends(source_file, "\\.Rmd")) {
    knitr::purl(source_file, target_file, quiet=TRUE)
  } else if (str_ends(source_file, "\\.irnb") || str_ends(source_file, "\\.ipynb")) {
    tmp <- tempfile(fileext = "Rmd")
    rmarkdown:::convert_ipynb(source_file, tmp)
    knitr::purl(tmp, target_file, quiet=TRUE)
  } else {
    stop("Unsupported file type: ", source_file)
  }

  ## if (file.exists(target_file)) {
  ##   tmp <- read_file(target_file)
  ##   tmp <- wrap(target_file, tmp)
  ##   write_file(tmp, target_file)
  ## }

  target_file
}

run <- function(path) {
  metadata_file <- file.path(path, "script", "kernel-metadata.json")
  if (file.access(metadata_file, 4) != 0) {
    stop(metadata_file, ": cannot access")
  }

  metadata <- fromJSON(file=metadata_file)
  metadata_df <- data.frame(
    id=str_replace(metadata$id, "/", "-"),
    language=metadata$language,
    kernel_type=metadata$kernel_type,
    competition=metadata$competition
  )

  source_file <- file.path(path, "script", metadata$code_file)
  target_file <- "kernel.R"

  df <- tryCatch({
    extract_kernel_code(source_file, target_file)
    sloc_df <- runr::cloc(target_file, by_file=TRUE, r_only=TRUE)
    cbind(metadata_df, subset(sloc_df, select=c(-language, -filename)), error=NA)
  }, error=function(e) {
    cbind(metadata_df, error=e$message)
  })

  write.csv(df, "kernel.csv", row.names=FALSE)
}

args <- commandArgs(trailingOnly=TRUE)
if (length(args) != 1) {
  stop("Missing path to a kaggle kernel")
}

run(args[1])
