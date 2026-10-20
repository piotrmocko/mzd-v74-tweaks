#!/bin/sh

SELF=$(readlink -f "$0") || exit 1
SCRIPT_DIR=$(dirname "$SELF")
sh "$SCRIPT_DIR/launcher.sh" "$@"
