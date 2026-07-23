# pg_repack online maintenance integration

This integration builds IvorySQL 5.4 and pg_repack 1.5.3, creates measurable
heap and index bloat, and proves that an online repack reclaims storage while
foreground writes continue.

The verifier:

- creates a schema-qualified table with a primary key and two secondary indexes;
- loads deterministic payloads, deletes a configured percentage, and performs a
  normal VACUUM so free pages remain allocated;
- captures relation, heap, index, row-count, stable-row checksum, index-validity,
  extension-version, and server-version evidence before maintenance;
- runs a timed concurrent writer while pg_repack rebuilds the table;
- captures the same evidence after repack and independently audits shrinkage,
  stable data, concurrent writes, latency, timeline overlap, and index health.

## Run

Copy the environment template, replace the password, and execute:

    cp .env.example .env
    make preflight
    make config
    make up
    make verify
    make report

The final report is stored in the repack-reports volume. make clean removes all
test data and reports.

## Operational policy

The default profile requires at least 8 MiB before maintenance, at least 4 MiB
reclaimed, and a final total-relation-size ratio no greater than 0.55. At least
30 foreground transactions must succeed, their maximum latency must remain
under five seconds, and their execution interval must overlap the repack.

The stable subset checksum must not change. Final row count must equal the
pre-repack count plus successful writer inserts. Every table index must remain
valid and ready, and pg_repack must leave no repack-log relation behind.

The harness rejects system schemas, unsafe identifiers, weak passwords,
unbounded wait timeouts, trivial datasets, unrealistic shrink thresholds,
unsafe deletion percentages, and broad report paths.

This sample uses --no-kill-backend. It does not terminate application sessions
to obtain the final lock. Production operators should choose a maintenance
window, monitor long-running transactions, retain backups, and rehearse the
exact table and extension versions before execution.

Run the standard-library tests without Docker:

    python3 -m unittest discover -s tests -v
