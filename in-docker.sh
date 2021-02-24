#!/bin/bash

if [ $# -eq 0 ]; then
    echo "Usage: $0 args"
    exit 1
fi

exec make shell SHELL_CMD="$*"
