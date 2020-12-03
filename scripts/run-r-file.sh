#!/bin/sh

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

file=$(basename "$1")
dir=$(dirname "$1")
output="$(pwd)/task-output.txt"

cd "$dir"
R -f "$file" --no-save --quiet --no-readline > "$output" 2>&1
exitval=$?
if [ $exitval -eq 0 ]; then
    rm "$output"
else
    echo "running: $0 $@" >> $output
    echo "exit: $exitval" >> $output
fi
exit $exitval
