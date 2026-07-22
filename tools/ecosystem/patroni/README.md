# Patroni high-availability integration for IvorySQL

This integration builds IvorySQL from the current checkout and runs a
three-member Patroni cluster backed by etcd. HAProxy exposes a primary endpoint
on port 5432 and a replica endpoint on port 5433. The harness validates that
there is exactly one writable leader, all expected replicas are running, lag is
within policy, SQL recovery roles match Patroni, and Oracle compatibility is
enabled on every member.

Copy `.env.example` to `.env`, replace all three passwords, then run:

```sh
make preflight
make config
make up
make verify
make status
```

`make switchover` performs a planned transition and waits for a new healthy
leader. `make failover` is intentionally separate because it invokes Patroni's
emergency failover endpoint. The Python commands prompt before either operation
unless `--yes` is supplied.

The generated Patroni files contain passwords and are written with mode 0600.
Do not commit the `generated/` directory or a populated `.env` file. The sample
is a reproducible validation environment, not a substitute for production DCS,
TLS, backup, monitoring, and network-isolation design.

Run the standard-library unit tests without Docker:

```sh
python3 -m unittest discover -s tests -v
```

Useful machine-readable commands are:

```sh
python3 patroni_harness.py --json preflight
python3 patroni_harness.py --json status
python3 patroni_harness.py --json wait --timeout 3m
```

The supported configuration variables are documented by `.env.example` and
validated before files are rendered. Patroni's timing invariant
`loop_wait + 2 * retry_timeout <= ttl` is enforced to reject unsafe settings.
