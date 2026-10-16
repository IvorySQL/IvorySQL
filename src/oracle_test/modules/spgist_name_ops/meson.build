# Copyright (c) 2022-2026, PostgreSQL Global Development Group

spgist_name_ops_sources = files(
  'spgist_name_ops.c',
)

if host_system == 'windows'
  spgist_name_ops_sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'spgist_name_ops',
    '--FILEDESC', 'spgist_name_ops - test opclass for SP-GiST',])
endif

spgist_name_ops = shared_module('spgist_name_ops',
  spgist_name_ops_sources,
  kwargs: pg_test_mod_args,
)
test_install_libs += spgist_name_ops

test_install_data += files(
  'spgist_name_ops.control',
  'spgist_name_ops--1.0.sql',
)
# No Oracle regress registration: this module defines no ORA_REGRESS in the GNU
# Make build either, and its expected output is PostgreSQL-only (it drifts
# under an Oracle-mode instance). Re-enable only as part of an
# Oracle-compatible test subset.
