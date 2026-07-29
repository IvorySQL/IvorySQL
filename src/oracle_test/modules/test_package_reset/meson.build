# Copyright (c) 2022-2026, PostgreSQL Global Development Group

test_package_reset_sources = files(
  'test_package_reset.c',
)

if host_system == 'windows'
  test_package_reset_sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'test_package_reset',
    '--FILEDESC', 'test_package_reset - test extension for PLiSQL package reset API',])
endif

test_package_reset = shared_module('test_package_reset',
  test_package_reset_sources,
  kwargs: pg_test_mod_args,
)
test_install_libs += test_package_reset

tests += {
  'name': 'test_package_reset',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'regress': {
    'sql': [
      'test_package_reset',
      'test_reset_one_oid',
      'test_reset_all',
      'test_reset_defaults',
    ],
  },
}
