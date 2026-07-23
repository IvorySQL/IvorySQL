#!/usr/bin/env python3
"""Guard orafce 4.16.7's private pg_re_flags copy for PG18 headers."""

from __future__ import annotations

import argparse
from pathlib import Path


ORIGINAL = """/* all the options of interest for regex functions */
typedef struct pg_re_flags
{
\tint\t\t\tcflags;\t\t\t/* compile flags for Spencer's regex code */
\tbool\t\tglob;\t\t\t/* do it globally (for each occurrence) */
} pg_re_flags;
"""

REPLACEMENT = """/* all the options of interest for regex functions */
#if PG_VERSION_NUM < 180000
typedef struct pg_re_flags
{
\tint\t\t\tcflags;\t\t\t/* compile flags for Spencer's regex code */
\tbool\t\tglob;\t\t\t/* do it globally (for each occurrence) */
} pg_re_flags;
#endif
"""


def patch_source(path: Path) -> None:
    source = path.read_text(encoding="utf-8")
    occurrences = source.count(ORIGINAL)
    if occurrences != 1:
        raise ValueError(
            "expected exactly one unguarded orafce 4.16.7 pg_re_flags block; "
            f"found {occurrences}"
        )
    updated = source.replace(ORIGINAL, REPLACEMENT)
    if updated.count(REPLACEMENT) != 1:
        raise ValueError("guarded pg_re_flags block was not produced exactly once")
    path.write_text(updated, encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    options = parser.parse_args()
    patch_source(options.source)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
