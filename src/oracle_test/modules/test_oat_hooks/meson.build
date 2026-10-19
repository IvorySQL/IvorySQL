# Copyright (c) 2022-2026, PostgreSQL Global Development Group

test_oat_hooks_sources = files(
  'test_oat_hooks.c',
)

if host_system == 'windows'
  test_oat_hooks_sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'test_oat_hooks',
    '--FILEDESC', 'test_oat_hooks - example use of object access hooks',])
endif

test_oat_hooks = shared_module('test_oat_hooks',
  test_oat_hooks_sources,
  kwargs: pg_test_mod_args,
)
test_install_libs += test_oat_hooks

# No Oracle regress registration: this module defines no ORA_REGRESS in the GNU
# Make build either, and its --no-locale regress needs a fresh cluster whose
# auxiliary database creation is unreliable under the Oracle Meson setup.
# Re-enable only as part of an Oracle-compatible test subset.
