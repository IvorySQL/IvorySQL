# Copyright (c) 2024, PostgreSQL Global Development Group

test_dsm_registry_sources = files(
  'test_dsm_registry.c',
)

if host_system == 'windows'
  test_dsm_registry_sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'test_dsm_registry',
    '--FILEDESC', 'test_dsm_registry - test code for the DSM registry',])
endif

test_dsm_registry = shared_module('test_dsm_registry',
  test_dsm_registry_sources,
  kwargs: pg_test_mod_args,
)
test_install_libs += test_dsm_registry

test_install_data += files(
  'test_dsm_registry.control',
  'test_dsm_registry--1.0.sql',
)

# No Oracle regress registration: this module defines no ORA_REGRESS in the GNU
# Make build either, and both its source and expected output are stale
# PostgreSQL-only copies that drift under an Oracle-mode instance. Re-enable
# only as part of an Oracle-compatible test subset.
