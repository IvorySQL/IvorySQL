#!/usr/bin/env bash
set -Eeuo pipefail

readonly report=/reports/vectorchord-benchmark.json

main() {
    python3 /usr/local/libexec/vector_harness.py preflight
    python3 /usr/local/libexec/vector_harness.py setup
    python3 /usr/local/libexec/vector_harness.py smoke
    python3 /usr/local/libexec/vector_harness.py audit --output "$report"
    test -s "$report"
    printf 'VectorChord recall, latency, plan, and storage checks passed.\n'
}

main "$@"
