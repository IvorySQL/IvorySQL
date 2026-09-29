#!/usr/bin/env bash
# Enable the repository's pre-commit hook and prebuild pg_bsd_indent.
# Works in the main working tree and in linked worktrees.
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

# Optional: support tools that only check the hooks directory. Resolve paths
# through Git instead of assuming .git is a directory: in a linked worktree
# .git is a file, and both the config and the hooks directory are shared
# with the main working tree. Note: --git-path hooks is deliberately not
# used here; it follows core.hooksPath, which this script points elsewhere.
common_dir=$(git rev-parse --git-common-dir)
case $common_dir in
  /*) ;;
  *) common_dir="$repo_root/$common_dir" ;;
esac
hooks_dir="$common_dir/hooks"

# Point the link at the main working tree's checkout so it stays valid
# after linked worktrees are removed. Use an absolute target: the correct
# relative depth is not portable across layouts, and the previous
# ../.githooks/pre-commit link resolved to .git/.githooks/pre-commit and
# was therefore always dangling.
hook_target="$(dirname "$common_dir")/.githooks/pre-commit"

hook_path="$hooks_dir/pre-commit"
if [[ -e $hook_path && ! -L $hook_path ]]; then
  # A real file placed by the user or another tool: never replace it.
  echo "[enable-git-hooks] Keeping existing hook file: $hook_path"
elif [[ -f $hook_target ]]; then
  # -f also repairs the dangling link left by older versions of this script.
  mkdir -p "$hooks_dir"
  ln -sfn "$hook_target" "$hook_path"
else
  echo "[enable-git-hooks] Warning: $hook_target not found; skipping the hooks-directory link."
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

