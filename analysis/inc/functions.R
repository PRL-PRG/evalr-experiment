read_parallel_task_result <- function(path, drop_hostname=FALSE) {
  file <- if (dir.exists(path)) file.path(path, "parallel.csv") else path
  
  df <- read_csv(file, col_types=cols()) %>% 
    select(-Seq, -Send, -Receive, -Signal, -Stdout, -Stderr) %>% 
    rename_all(tolower) %>%
    rename(hostname=host, runtime=jobruntime) %>%
    mutate(
      hostname=purrr::map_chr(str_split(hostname, " "), ~tail(., 1)),
      starttime=lubridate::as_datetime(starttime),
      endtime=lubridate::as_datetime(starttime+runtime),
      runtime=lubridate::as.duration(runtime),
      exitval=as.integer(exitval)
    )
  
  if (drop_hostname) {
    df <- select(df, -hostname)
  }
  
  df
}

read_run_r_file_error <- Vectorize(function(path) {
  empty <- tibble(error=NA, source=NA, call=NA)
  
  if (!file.exists(path)) {
    return(empty)
  }
  
  l <- readLines(path)
  if (length(l) < 3) {
    return(empty)
  }
  
  ret <- empty
  for (x in c("ERROR", "SOURCE", "CALL")) {
    s <- l[str_detect(l, paste0("^\\*\\*\\* ", x, ": "))]
    s <- if (length(s) == 1) {
      trimws(str_sub(s, 4 + nchar(x) + 2), "both")
    } else {
      NA
    }
    ret[tolower(x)] <- s
  }

  ret  
}, "path", SIMPLIFY=FALSE, USE.NAMES=FALSE)

read_trace_log <- function(path, read_errors=FALSE, ...) {
  df <- read_parallel_task_result(path, ...) %>%
    rename(program=v1) %>%
    select(starttime, endtime, runtime, exitval, program)
 
  task_output <- file.path(path, df$program, "task-output.txt")  
  df <- cbind(df, task_output=task_output)
    
  if (read_errors) {
    errors <- read_run_r_file_error(df$task_output)
    df <- cbind(df, do.call(rbind, errors))
  }
  
  df
}

cs_count <- function(df, var) {
  n_rows = nrow(df)
  var = enquo(var)
  count(df, !!var, sort=TRUE) %>%
    mutate(p=n/n_rows*100, cp=cumsum(p))
}

show_url <- Vectorize(function(path, name=basename(path), base_url=params$http_base_url) {
  str_glue('<a target="_blank" href="{base_url}{URLencode(path)}">{name}</a>')
}, vectorize.args=c("path", "name"))