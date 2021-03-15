#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)

if (length(args) != 1) {
  stop("Expected path to run results")
}

run_dir  <- args[1]

if (!dir.exists(run_dir)) {
  stop("Run dir ", run_dir, " does not exist")
}

base_dir <- dirname(normalizePath(dirname(runr::current_script()), mustWork = TRUE))
notebook <- file.path(base_dir, "analysis", "missing-evals.Rmd")
output   <- file.path(base_dir, run_dir, "missing-evals.md")

print(base_dir)
print(output)

rmarkdown::render(
  notebook, 
  output_file=output,
  params=list(
    base_dir=base_dir,
    run_dir=run_dir
  ), 
  quiet=TRUE
)

cat(readLines(output), sep="\n")