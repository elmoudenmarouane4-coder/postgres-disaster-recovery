#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 2 ]]; then
  echo "Usage: $0 BACKUP_DIRECTORY NEW_TARGET_DB" >&2
  exit 2
fi

bundle=$1
target=$2
if [[ ! $target =~ ^[a-z][a-z0-9_]{0,62}$ ]]; then
  echo "Use a PostgreSQL database name with lowercase letters, digits or underscores." >&2
  exit 2
fi
if [[ ! -s "$bundle/SHA256" || ! -s "$bundle/dump.pgcustom" ]]; then
  echo "Incomplete backup bundle" >&2
  exit 1
fi
(
  cd -- "$bundle"
  if [[ $(shasum -a 256 dump.pgcustom) != "$(<SHA256)" ]]; then
    echo "Backup checksum mismatch" >&2
    exit 1
  fi
  pg_restore --list dump.pgcustom >/dev/null
)

# createdb fails if the target already exists. No existing database is replaced.
createdb --no-password -- "$target"
pg_restore --no-password --single-transaction --exit-on-error --no-owner --no-acl \
  --dbname="$target" -- "$bundle/dump.pgcustom"
printf 'Restored into %s\n' "$target"
