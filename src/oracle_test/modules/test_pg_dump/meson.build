# Copyright (c) 2022-2026, PostgreSQL Global Development Group

test_install_data += files(
  'test_pg_dump.control',
  'test_pg_dump--1.0.sql',
)

# No Oracle regress registration: this module defines no ORA_REGRESS in the GNU
# Make build either, and its expected output is PostgreSQL-only. The TAP test
# passes under the Oracle Meson setup, so it is kept.
tests += {
  'name': 'test_pg_dump',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'tap': {
    'tests': [
      't/001_base.pl',
    ],
  },
}
