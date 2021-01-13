#!/bin/bash

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <file or dir to rollback>"
    exit 1
fi

source="$1"

if [ ! -e "$source" ]; then
    exit 0
fi

count=$(find $(dirname "$source") -name $(basename $source)'*' | wc -l)

if [ $count -gt 0 ]; then
    target="$source.$count"
    if [ -f "$target" ]; then
        echo "$target: already exists!"
        exit 1
    fi
    mv $source $target
fi
