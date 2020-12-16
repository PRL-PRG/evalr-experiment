#!/bin/sh
SCRIPTS_DIR=$(dirname $(realpath $0))

if [ $# -ne 5 ]; then
  echo "Usage: $0 <kernel-metadata.json> <kernel.R> <kernel.csv> <kernel-evals-static.csv> <wrap-template>"
  exit 1
fi

KERNEL_METADATA_JSON="$1"
KERNEL_FILE="$2"
KERNEL_CSV="$3"
KERNEL_EVALS_STATIC="$4"
WRAP_TEMPLATE_FILE="$5"

$SCRIPTS_DIR/kaggle-runnable-code.R \
    --kernel "$KERNEL_METADATA_JSON" \
    --code "$KERNEL_FILE" \
    --metadata "$KERNEL_CSV" \
    --wrap "$WRAP_TEMPLATE_FILE"

[ -s $KERNEL_FILE ] && $SCRIPTS_DIR/package-evals-static.R \
    --out "$KERNEL_EVALS_STATIC" \
    --type file "$KERNEL_FILE"
