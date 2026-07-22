# VectorChord vector-search integration

This integration builds the current stable IvorySQL 5.4 release (PostgreSQL
18.4 ABI), pgvector 0.8.5, and VectorChord 1.1.1 from source. It creates a
deterministic embedding dataset, builds a configurable `vchordrq` index, and
audits search quality and operational cost.

Copy `.env.example` to `.env`, replace the password, then run:

```sh
make preflight
make config
make up
make verify
```

The verifier evaluates exact ground truth through VectorChord's recall helper,
runs analyzed approximate queries, and fails on average/minimum recall, p95
latency, missing index scans, invalid index state, dataset drift, or excessive
index-to-table size ratio. A full JSON report is stored in the report volume.

Cosine search defaults to residual quantization and spherical centroids. The
list/probe/epsilon settings are explicit so recall-versus-latency tradeoffs are
repeatable instead of hidden behind defaults. L2 and inner-product modes are
also supported; spherical centroids are rejected for those metrics.

The shipped profile probes every configured list with the most conservative
distance bound. This establishes a quality-first compatibility baseline; lower
probe and epsilon values can then be evaluated against the same recall and
latency gates for workload-specific tuning.

The integration intentionally targets `IvorySQL_5.4`, the stable PostgreSQL 18
based release supported by VectorChord 1.1.1. IvorySQL `master` tracks
PostgreSQL 19 development, which VectorChord does not yet expose as a build
feature. Change `IVORYSQL_REF` only together with a compatible VectorChord
release.

Run the standard-library unit suite without Docker:

```sh
python3 -m unittest discover -s tests -v
```
