#!/bin/bash

while (( "$#" )); do
  case "${1-}" in
    -n | --no-repeat)
      NO_REPEAT=1
      shift
      ;;
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
path=$(realpath "$1")
output="$cwd/task-output.txt"
status="$cwd/task-status.csv"

if [ -f "$status" -a -n "$NO_REPEAT" ]; then
  exitval=$(sed 's/\([0-9]\+\),.*/\1/' "$status")
  echo "$1 already ran with $exitval, skipping"
  exit $exitval
fi

rm -f "$output" "$status"

cd "$dir"

cmd=""

[ -n "$TIMEOUT" ] && cmd="timeout $TIMEOUT"

cmd="$cmd R -f $file --no-save --no-echo --quiet --no-readline"

SECONDS=0

if [ -n "$VERBOSE" ]; then
    $cmd | tee "$output" 2>&1
    exitval=$?
else
    $cmd >> "$output" 2>&1
    exitval=$?
fi

echo "running: $0 $@" >> $output
echo "exit: $exitval" >> $output
echo "$exitval,$SECONDS,\"$(hostname)\",\"$path\"" > $status

exit $exitval
