#!/bin/sh
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=
trap 'rm -f "$tmp"' 0
trap 'exit 1' HUP INT TERM

for checksum in "$ROOT"/*.sh.md5
do
  [ -f "$checksum" ] || continue
  script=${checksum%.md5}
  name=${script##*/}

  if [ ! -f "$script" ]
  then
    printf 'ERROR: no matching script for %s\n' "$checksum" >&2
    exit 1
  fi

  tmp=$(mktemp "$ROOT/.md5sync.XXXXXX")
  (cd "$ROOT" && md5sum "$name") > "$tmp"
  mv "$tmp" "$checksum"
  tmp=
  printf 'Updated %s.md5\n' "$name"
done