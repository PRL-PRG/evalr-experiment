res <- evil::trace_to_file(
  writer=function(file, df) {{
    fst::write_fst(df, file.path(Sys.getenv("RUNR_CWD", getwd()), paste0(gsub("_", "-", file), ".fst")))
  }},
  packages="global",
  code={{
    {body}
  }}
)

if (instrumentr::is_error(res$result)) {
  cat("*** ERROR:", res$result$error$message, "\n")
  cat("*** SOURCE:", res$result$error$source, "\n")
  cat("*** CALL:", format(res$result$error$call), "\n")
  q(status=2, save="no")
}
