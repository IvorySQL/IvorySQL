# IvorySQL with pg_show_plans

This integration verifies that
[pg_show_plans](https://github.com/cybertec-postgresql/pg_show_plans)
can display the execution plan of a query that is currently running on
IvorySQL.

The image pins both upstream revisions:

- IvorySQL 5.4:
  `a45b0457520007970848fc33198d876807b98f55`
- pg_show_plans 2.1.8:
  `92ecb21f8f2307a4bc7db8f01623599e75930fc2`

## Run the integration

Docker with the Compose plugin is required.

```sh
cd tools/ecosystem/pg_show_plans
make build
make verify
make down
```

`make verify` starts an IvorySQL 5.4 cluster with `pg_show_plans` in
`shared_preload_libraries`, creates the extension, and starts a query that
sleeps inside a `generate_series` scan. A second connection must observe the
active query and its `Function Scan on generate_series` plan through
`pg_show_plans_q`.

The check also verifies the IvorySQL server and extension versions. The image
build rejects either source checkout unless it matches the pinned commit.

## Operational notes

`pg_show_plans` stores plans in a fixed-size shared-memory hash table and
requires a server restart when it is added to `shared_preload_libraries`.
The extension documentation reports a measurable overhead under read-heavy
benchmarks, so enable it deliberately and size
`pg_show_plans.max_plan_length` for the workload.

IvorySQL `master` currently follows PostgreSQL 19 development, whose
`ShmemInitHash` API is not supported by pg_show_plans 2.1.8. This integration
therefore targets the released IvorySQL 5.4 / PostgreSQL 18.4 combination
rather than carrying a downstream patch for the third-party extension.
