# pgBackRest backup and recovery integration

This integration builds IvorySQL from the current checkout and configures
pgBackRest WAL archiving, encrypted repositories, retention, full/differential/
incremental backups, repository audits, and isolated restore verification.

Copy `.env.example` to `.env` and replace both secrets. Then run:

```sh
make preflight
make config
make up
make verify
make restore-verify
```

`make verify` creates a deterministic validation dataset, creates and checks the
stanza, takes an encrypted full backup, and audits backup age, WAL coverage,
size, dependency references, and repository health. `make restore-verify`
restores the latest backup into a separate Docker volume and proves that the
dataset is queryable from a promoted IvorySQL instance.

The harness also supports S3 repositories through `BACKUP_REPO_TYPE=s3` and
the `BACKUP_S3_*` variables. TLS verification defaults to enabled. Secrets are
written only to a mode-0600 pgBackRest configuration and are not accepted as
command-line arguments.

Restore commands reject broad data paths, validate target time/LSN/XID/name,
and require interactive confirmation or `--yes`. Preview a point-in-time
restore without changing data:

```sh
python3 backup_harness.py restore --type time \
  --target '2026-07-22T10:00:00+08:00' --dry-run
```

Run the standard-library test suite without Docker:

```sh
python3 -m unittest discover -s tests -v
```
