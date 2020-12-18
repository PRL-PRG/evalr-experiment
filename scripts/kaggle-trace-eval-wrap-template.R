res <- evil::trace_to_file(
  writer=function(file, df) {
    fst::write_fst(df, file.path(Sys.getenv("RUNR_CWD", getwd()), paste0(gsub("_", "-", file), ".fst")))
  },
  packages="global",
  code={
    .BODY.
  }
)

if (instrumentr::is_error(res$result)) {
  error <- res$result$error
  cat("*** ERROR:", error$message, "\n")
  cat("*** SOURCE:", error$source, "\n")
  cat("*** CALL:", format(error$call), "\n")
  q(status=2, save="no")
}
