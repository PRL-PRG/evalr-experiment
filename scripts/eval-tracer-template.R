evil::trace_to_file(file.path(Sys.getenv('RUNR_CWD'), '{package}', '{type}', '{basename(file)}'), {{
  {body}
}})
