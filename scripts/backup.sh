#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 2 ]]; then
  echo "Usage: $0 SOURCE_DB OUTPUT_DIRECTORY" >&2
  exit 2
fi

if [[ ! $1 =~ ^[a-z][a-z0-9_]{0,62}$ ]]; then
  echo "Use a PostgreSQL database name with lowercase letters, digits or underscores." >&2
  exit 2
fi

umask 077
mkdir -p -- "$2"
bundle=$(mktemp -d "$2/pg-backup.XXXXXXXX")
ready=false
trap 'if [[ $ready == false ]]; then rm -f -- "$bundle/dump.pgcustom" "$bundle/SHA256"; rmdir -- "$bundle"; fi' EXIT

pg_dump --no-password --format=custom --no-owner --no-acl --file="$bundle/dump.pgcustom" --dbname="$1"
pg_restore --list "$bundle/dump.pgcustom" >/dev/null
(
  cd -- "$bundle"
  shasum -a 256 dump.pgcustom > SHA256
)
ready=true
printf '%s\n' "$bundle"
