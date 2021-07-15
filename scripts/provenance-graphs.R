#!/usr/bin/env Rscript

# Various operations to deal with the provenance graphs


library(optparse)
library(stringr)

extract_dot_files <- function(dot_dir) {
  list.files(dot_dir, pattern = ".*\\.dot", recursive = TRUE, full.names = TRUE)
}

create_unique_name <- function(dot_file_path) {
  components <- str_split(dot_file_path, fixed("/"))[[1]]
  paste(tail(components, n = 4), collapse = "-")
}

to_images <- function(dot_files, output_dir) {
  
  dir.create(output_dir)
  nb_dot_files <- length(dot_files)
  
  for(i in seq_along(dot_files)) {
    cat("\r", i, "/", nb_dot_files)
    dot_file <- dot_files[[i]]
    image_name <- str_replace(create_unique_name(dot_file), "\\.dot$", ".png") 
    image_path <- file.path(output_dir, image_name)
    system2("dot", list("-o", image_path, dot_file))
  }
}

gather_dots <- function(dot_files, output_dir) {
  dir.create(output_dir)
  nb_dot_files <- length(dot_files)
  
  for(i in seq_along(dot_files)) {
    cat("\r", i, "/", nb_dot_files)
    dot_file <- dot_files[[i]]
    new_name <- create_unique_name(dot_file)
    new_path <- file.path(output_dir, new_name)
    file.copy(dot_file, new_path)
  }
}

parse_function_arguments <- function() {
  option_list <- list(
    make_option(
      c("--to-images"),
      action = "store_true", dest = "to_images", default = FALSE,
      help = "Generate images from the DOT files"
    ),
    make_option(
      c("--gather"),
      action = "store_true", dest = "gather", default = FALSE,
      help = "Gather and rename all the DOT files in one place"
    ),
    make_option(
      c("--add-eval"),
      action = "store_true", dest = "add_eval", default = FALSE,
      help = "Add the eval call in the graph"
    ),
    make_option(
      c("--output"),
      action = "store",
      dest = "output_dir", 
      metavar = "DIRECTORY",
      default = "provenance_graphs",
      help = "Output directory."
    )
  )
  
  opt_parser <- OptionParser(option_list = option_list, description = "Various operations to deal with the provenance graphs")
  arguments <- parse_args(opt_parser, positional_arguments = 1)
  
  arguments
}

main <- function() {
  arguments <- parse_function_arguments()

  
  run_dir <- arguments$args[1]
  dot_dir <- file.path(run_dir, "package-trace-eval")
  dot_files <- extract_dot_files(dot_dir)
  
  output_dir <- arguments$options$output_dir
  
  if(arguments$options$gather) {
    gather_dots(dot_files, output_dir)
  }
  else if(arguments$options$to_images) {
    to_images(dot_files, output_dir)
  }
  invisible()
}


main()