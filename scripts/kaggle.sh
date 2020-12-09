#!/bin/sh
SCRIPTS_DIR=$(dirname $(realpath $0))
KERNEL_FILE=kernel.R

$SCRIPTS_DIR/kaggle-runnable-code.R "$1"

[ -s $KERNEL_FILE ] && $SCRIPTS_DIR/package-evals-static.R --out kaggle-evals-static.csv --type file $KERNEL_FILE
