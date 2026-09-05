#!/bin/sh
# Convert repository text files from Windows CRLF to Unix LF.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

for file in "$ROOT"/*; do
  [ -f "$file" ] || continue
  case "$file" in
    *.sh|*.service|*.timer|*.conf|*.md|*.gitattributes)
      sed -i 's/\r$//' "$file"
      printf 'normalized: %s\n' "${file##*/}"
      ;;
  esac
done
