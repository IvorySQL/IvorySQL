#!/usr/bin/env python3

"""Check the surviving C/C++ files changed by a pull request."""

import os
from pathlib import PurePosixPath
import subprocess
import sys


def changed_files(base):
    # Keep Git's NUL-delimited path names intact, including whitespace and
    # quoting characters. Deleted files cannot be passed to pgindent.
    output = subprocess.check_output([
        "git", "diff", "--name-only", "-z", "--diff-filter=ACMR",
        f"{base}..HEAD", "--",
    ])
    return [
        os.fsdecode(path) for path in output.split(b"\0") if path
        and PurePosixPath(os.fsdecode(path)).suffix.lower() in
        {".c", ".h", ".cpp", ".hpp"}
        and not path.startswith(b"src/tools/pg_bsd_indent/")
    ]


def main(base):
    files = changed_files(base)
    if not files:
        print("[FormatCheck] No C/C++ changes detected; skipping.")
        return 0

    # Prefix paths so a leading '-' cannot be interpreted as an option.
    files = ["./" + path for path in files]
    pgindent = "./src/tools/pgindent/pgindent"
    print("[FormatCheck] Running pgindent --check...", flush=True)
    result = subprocess.call([pgindent, "--check", *files])
    if result:
        print("[FormatCheck] Unformatted changes detected; suggested patch below:",
              flush=True)
        subprocess.call([pgindent, "--diff", *files])
        return result

    print("[FormatCheck] Passed.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: check_format.py BASE")
    sys.exit(main(sys.argv[1]))
