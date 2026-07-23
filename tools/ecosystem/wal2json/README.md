# wal2json change-data-capture integration

This integration builds the stable IvorySQL_5.4 release and wal2json at the
pinned PostgreSQL 18-compatible upstream commit. It exercises logical decoding
as an operational CDC contract rather than stopping at a successful extension
build.

The verifier creates a logical replication slot, runs deterministic
multi-transaction workloads, consumes format-version 2 JSON, and audits:

- explicit begin/commit transaction markers and transaction identifiers;
- INSERT, UPDATE, DELETE, and TRUNCATE coverage;
- schema-qualified allow-list filtering, including proof that a secret table
  never appears in the stream;
- typed columns, primary-key metadata, and old-row identity for mutations;
- transaction ordering, balanced boundaries, valid timestamps, and unique
  event fingerprints;
- replication-slot plugin, activity, restart/confirmed LSN order, and retained
  WAL against a configurable safety threshold.

## Run

Copy the example environment, replace the password, then start and verify:

    cp .env.example .env
    make preflight
    make config
    make up
    make verify
    make report

The JSONL event stream and final audit report are written to the cdc-reports
volume. make clean removes the database, slot, WAL, and report volumes.

## Safety and policy

CDC_TABLES is mandatory and schema-qualified. The harness rejects wildcards,
duplicate tables, system schemas, unsafe identifiers, weak passwords, broad
slot names, and unbounded WAL-retention policy. It emits wal2json options with
an explicit action list and allow-list instead of relying on plugin defaults.

The shipped profile includes only cdc.accounts and cdc.staging. The
verification workload also writes to private.customer_secrets; any appearance
of that table fails the audit. Update and delete records must carry identity
values so downstream consumers can build deterministic idempotency keys.

The workload uses SQL logical-slot consumption for a reproducible integration
test. Production consumers normally use the streaming replication protocol and
must persist confirmed offsets before acknowledging messages.

## Configuration

Important variables are:

- CDC_SLOT: logical slot identifier;
- CDC_TABLES: comma-separated schema-qualified allow-list;
- CDC_MIN_INSERTS, CDC_MIN_UPDATES, CDC_MIN_DELETES, CDC_MIN_TRUNCATES:
  minimum action coverage;
- CDC_MAX_SLOT_LAG: retained-WAL ceiling, supporting IEC units;
- CDC_REQUIRE_*: transaction, xid, timestamp, type, and key policy gates.

All variables are parsed and validated by the same Python harness used for the
offline tests and runtime audit.

Run the standard-library unit suite without Docker:

    python3 -m unittest discover -s tests -v
