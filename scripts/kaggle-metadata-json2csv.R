#!/usr/bin/env Rscript

library(purrr)
library(rjson)
library(stringr)

args <- commandArgs(trailingOnly=TRUE)
if (length(args) != 2) {
  stop("Usage: <kaggle-korpus-dir> <kernel-metadata.csv>")
}

input_dir <- args[1]
output_file <- args[2]

files <- list.files(
  input_dir,
  pattern="kernel-metadata\\.json$",
  recursive=TRUE,
  full.names=TRUE
)

metadata_json <- map(files, ~fromJSON(file=.))

cat("Loaded kernels: ", length(metadata_json), "\n")

metadata_json_keep <- keep(metadata_json, function(x) {
  length(x$competition_sources) == 1 &&
  length(x$dataset_source) == 0 &&
  length(x$kernel_sources) ==0
})
cat("Single competition kernels: ", length(metadata_json_keep), "\n")

df <- map_dfr(
  metadata_json_keep,
  ~data.frame(
    id=str_replace(.$id, "/", "-"),
    language=.$language,
    kernel_type=.$kernel_type,
    competition=.$competition_sources
  )
)

write.csv(df, output_file, row.names=FALSE)
