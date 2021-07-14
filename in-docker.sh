#!/bin/bash

if [ $# -gt 0 ]; then
  CMD="$*"
else
  CMD=bash
fi

exec make shell SHELL_CMD="$CMD"
