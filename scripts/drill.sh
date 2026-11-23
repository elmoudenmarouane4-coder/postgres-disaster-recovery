#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "$0")"
scratch=$(mktemp -d)
suffix="${scratch##*.}"
suffix=$(printf '%s' "$suffix" | tr '[:upper:]' '[:lower:]')
source_db="drill_source_$suffix"
target_db="drill_restore_$suffix"
mkdir -p "$scratch/backups"

# The test creates unique databases and removes only those it creates.
source_created=false
target_created=false
cleanup() {
  if [[ $source_created == true ]]; then
    dropdb --no-password --if-exists -- "$source_db" || true
  fi
  if [[ $target_created == true ]]; then
    dropdb --no-password --if-exists -- "$target_db" || true
  fi
  rm -rf -- "$scratch"
}
trap cleanup EXIT

createdb --no-password -- "$source_db"
source_created=true
psql --no-password --dbname="$source_db" -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE orders (
  id integer PRIMARY KEY,
  amount_cents integer NOT NULL CHECK (amount_cents > 0)
);
INSERT INTO orders SELECT id, 1000 + id FROM generate_series(1, 25) id;
SQL

fingerprint() {
  psql --no-password --dbname="$1" -At -v ON_ERROR_STOP=1 -c \
    "SELECT count(*) || ':' || md5(string_agg(id || ':' || amount_cents, ',' ORDER BY id)) FROM orders"
}

before=$(fingerprint "$source_db")
bundle=$(./backup.sh "$source_db" "$scratch/backups")
psql --no-password --dbname="$source_db" -v ON_ERROR_STOP=1 -c 'DELETE FROM orders'

start=$(date +%s)
./restore.sh "$bundle" "$target_db"
target_created=true
after=$(fingerprint "$target_db")
[[ $before == "$after" ]]
printf 'Recovery verified: %s rows, matching fingerprint, restore and verification in %ss\n' \
  "${after%%:*}" "$(( $(date +%s) - start ))"

if ./restore.sh "$bundle" "$target_db"; then
  echo "Restore unexpectedly replaced an existing database" >&2
  exit 1
fi
[[ $(fingerprint "$target_db") == "$before" ]]

printf 'corruption' >> "$bundle/dump.pgcustom"
if ./restore.sh "$bundle" "drill_corrupt_$suffix" 2>"$scratch/rejection.log"; then
  echo "Restore unexpectedly accepted a corrupted backup" >&2
  exit 1
fi
grep -q 'Backup checksum mismatch' "$scratch/rejection.log"
printf 'Safety checks passed: existing target and corrupted backup rejected\n'
