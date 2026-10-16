#!/usr/bin/env bash
# Enable the repository's pre-commit hook and prebuild pg_bsd_indent.
# Usage: bash tools/enable-git-hooks.sh

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$repo_root" ]]; then
  echo "Please run this script inside a Git repository." >&2
  exit 1
fi
cd "$repo_root"

echo "[enable-git-hooks] Setting core.hooksPath=.githooks ..."
git config --local core.hooksPath .githooks

# Optional: support tools that only check .git/hooks
if [[ ! -e .git/hooks/pre-commit ]]; then
  mkdir -p .git/hooks
  ln -s ../.githooks/pre-commit .git/hooks/pre-commit || true
fi

if [[ -x src/tools/pg_bsd_indent/pg_bsd_indent ]]; then
  echo "[enable-git-hooks] pg_bsd_indent already present; skipping build."
else
  echo "[enable-git-hooks] Building pg_bsd_indent ..."
  if ! make -C src/tools/pg_bsd_indent -j$(nproc 2>/dev/null || echo 2) >/dev/null; then
    echo "[enable-git-hooks] Warning: build failed. you can build manually: make -C src/tools/pg_bsd_indent pg_bsd_indent"
  fi
fi

echo "[enable-git-hooks] Done. Commits will now auto-run pgindent."

