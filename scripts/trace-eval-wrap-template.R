suppressPackageStartupMessages(library(evil))

cat("*** EVALS_IMPUTE_SRCREF_FILE: '", Sys.getenv("EVALS_IMPUTE_SRCREF_FILE"), "'\n", sep="")
cat("*** EVALS_TO_TRACE: '", Sys.getenv("EVALS_TO_TRACE"), "'\n", sep="")

if (!is.na(Sys.getenv("EVALS_IMPUTE_SRCREF_FILE", NA))) {
  evil::setup_eval_wrapping_hook_from_file(Sys.getenv("EVALS_IMPUTE_SRCREF_FILE"))
}

traces <- evil::trace_code(
  evals_to_trace=Sys.getenv("EVALS_TO_TRACE", ""),
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
