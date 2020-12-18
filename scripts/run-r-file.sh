#!/bin/bash

set -Eeo pipefail

while (( "$#" )); do
  case "${1-}" in
    -v | --verbose)
      VERBOSE=1
      shift
      ;;
    -t | --timeout)
      TIMEOUT="${2-}"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

export LANGUAGE=en
export LC_COLLATE=C
export LC_TIME=C
export LC_ALL=C
export SRCDIR=.
export R_TESTS=""
export R_BROWSER=false
export R_PDFVIEWER=false
export R_KEEP_PKG_SOURCE=yes
export R_KEEP_PKG_PARSE_DATA=yes
export RUNR_CWD="$(pwd)"
export R_ENABLE_JIT=0
export R_COMPILE_PKGS=0
export R_DISABLE_BYTECODE=1
export OMP_NUM_THREADS=1
unset R_LIBS_SITE
unset R_LIBS_USER

cwd="$(pwd)"
file=$(basename "$1")
dir=$(dirname "$1")
output="$cwd/task-output.txt"

cd "$dir"

cmd=""

[ -n "$TIMEOUT" ] && cmd="timeout $TIMEOUT"

cmd="$cmd R -f $file --no-save --quiet --no-readline"

if [ -n "$VERBOSE" ]; then
    $cmd | tee "$output" 2>&1
    exitval=$?
else
    $cmd >> "$output" 2>&1
    exitval=$?
fi

echo "running: $0 $@" >> $output
echo "exit: $exitval" >> $output

exit $exitval
