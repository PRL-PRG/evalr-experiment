suppressPackageStartupMessages(library(evil))

cat("*** EVALS_TO_TRACE: '", Sys.getenv("EVALS_TO_TRACE"), "'\n", sep="")

traces <- evil::trace_code(
  evals_to_trace={
    tmp <- Sys.getenv("EVALS_TO_TRACE", NA)
    if (!is.na(tmp)) {
      if (file.exists(tmp)) readLines(tmp) else tmp
    } else {
      NULL
    }
  },
  code={
    .BODY.
  }
)

evil::write_trace(
  traces,
  function(file, df) {
    if (nrow(df) > 0) {
      fst::write_fst(
        df,
        file.path(Sys.getenv("RUNR_CWD", getwd()), paste0(gsub("_", "-", file), ".fst"))
      )
    }
  }
)

if (instrumentr::is_error(traces$result)) {
  error <- traces$result$error
  cat("*** ERROR: ", error$message, "\n")
  cat("*** SOURCE: ", error$source, "\n")
  cat("*** CALL: ", format(error$call), "\n")
  q(status=2, save="no")
}
