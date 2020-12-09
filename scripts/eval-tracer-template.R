evil::trace_to_file(
  writer=function(file, df) fst::write_fst(df, file.path(Sys.getenv("RUNR_CWD", getwd()), paste0(file, ".fst"))),
  packages=readLines("/mnt/ocfs_vol_00/project-evalr/evalr-experiment/corpus.txt"),
  code={{
    {body}
  }}
)
