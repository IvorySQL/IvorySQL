# IvorySQL + orafce migration compatibility contract

This integration builds the pinned orafce 4.16.7 source tag against IvorySQL
5.4 and exercises Oracle migration behavior on a running database. It turns a
representative compatibility surface into a versioned, machine-audited
contract instead of treating successful extension installation as sufficient.

The contract covers:

- a PL/iSQL procedure calling an orafce null-handling function;
- Oracle month-end, weekday, ISO-week, parsing, and formatting behavior;
- Oracle substring, search, padding, trimming, conversion, and regexp behavior;
- NVL, NVL2, DECODE, LNNVL, NANVL, BITAND, MOD, LISTAGG, and MEDIAN;
- VARCHAR2 byte semantics and NVARCHAR2 character semantics with UTF-8 data;
- DBMS_ASSERT, DBMS_OUTPUT, and DBMS_RANDOM package behavior;
- DUAL, USER_TABLES, USER_TAB_COLUMNS, PRODUCT_COMPONENT_VERSION, and triggers
  that normalize Oracle empty-string semantics.

Each case has a stable identifier, category, expected JSON value, rationale,
and migration risk in `compatibility_contract.json`. The SQL workload records
only actual values. The Python auditor independently joins those results to the
manifest, rejects missing, duplicate, and unknown cases, verifies version and
server metadata, and emits a complete JSON report.

## Run

Copy the environment template, replace the password, then run:

    cp .env.example .env
    make preflight
    make config
    make up
    make verify
    make report

`make clean` removes the database and report volumes. Run the policy and parser
tests without Docker with:

    python3 -m unittest discover -s tests -v

## Migration guidance

The contract is a compatibility gate for the covered surface, not a claim of
complete Oracle equivalence. Application teams should add cases for their own
NLS settings, package usage, implicit casts, exception behavior, and PL/iSQL
program units before cutover. Keep function calls schema-qualified when an
orafce function competes with a `pg_catalog` function. Review `UTL_FILE` and
other server-side I/O packages separately because they require explicit
filesystem and privilege policy.

The image pins the IvorySQL and orafce source tags. Updating either pin should
be handled as a contract change: rebuild, run every case, inspect changed
values, and update expected results only when the new behavior is intentional.
