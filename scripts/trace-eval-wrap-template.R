stopifnot(Sys.getenv("EVALS_TO_TRACE_FILE") != "")

traces <- evil::trace_code(
  evals_to_trace=readLines(Sys.getenv("EVALS_TO_TRACE_FILE")),
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
  cat("*** ERROR:", error$message, "\n")
  cat("*** SOURCE:", error$source, "\n")
  cat("*** CALL:", format(error$call), "\n")
  q(status=2, save="no")
}
