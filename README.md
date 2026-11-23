# PostgreSQL Disaster Recovery Drill

Practice recovering from accidental data loss. The drill seeds a disposable PostgreSQL database, takes a logical backup, deletes the seed rows, and restores into a new database. It verifies the restored row count and a deterministic fingerprint of the data.

```mermaid
flowchart LR
    Source["Source database"] --> Dump["Custom-format dump"]
    Dump --> Verify["Checksum validation"]
    Verify --> Target["Fresh recovery database"]
    Target --> Check["Row count and fingerprint"]
```

The restore rejects an existing target. It verifies the checksum before creating a database and restores the contents in a single transaction. If PostgreSQL rejects a restore after the target is created, the transaction is rolled back and the empty target is left for inspection. A SHA-256 checksum detects accidental corruption. Keep backup bundles private and use trusted backups.

## Run locally

Install PostgreSQL 16 client tools (`psql`, `pg_dump`, `pg_restore`, `createdb`, `dropdb`) and Docker Compose. Run against the disposable local service.

```sh
docker compose up -d --wait
export PGHOST=127.0.0.1 PGPORT=55432 PGUSER=drill PGPASSWORD=local-demo-only
./scripts/drill.sh
docker compose down
```

The drill reports how long restore and verification take. That measurement is for the tiny local dataset. This project demonstrates logical, point-in-time snapshots at backup time. Changes committed after the dump are outside that recovery point. Recovering to an arbitrary time between backups would require physical backups and WAL archiving.

## Use the scripts independently

```sh
bundle="$(./scripts/backup.sh orders backups)"
./scripts/restore.sh "$bundle" orders_recovered
```

Both scripts use standard PostgreSQL connection settings. The dump is tied to one database. Roles and other cluster-wide state need their own recovery workflow. CI runs the same complete drill against a PostgreSQL service container, including checksum and existing-target rejection.
