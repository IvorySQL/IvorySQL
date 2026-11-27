# Copyright (c) 2022-2026, PostgreSQL Global Development Group
# Portions Copyright (c) 2026, IvorySQL Global Development Team

# The runtime is compiled directly into this module rather than called
# through plisql.so: plisql is built with hidden symbol visibility, and the
# runtime is deliberately free of plisql compiler dependencies precisely so
# that it can be built and tested standalone like this.  Mirrors the vpath
# in this directory's Makefile.
test_plisql_collection_sources = files(
  'test_plisql_collection.c',
  '../../../pl/plisql/src/pl_collection_runtime.c',
)

if host_system == 'windows'
  test_plisql_collection_sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'test_plisql_collection',
    '--FILEDESC', 'test_plisql_collection - unit tests for the plisql collection runtime',])
endif

test_plisql_collection = shared_module('test_plisql_collection',
  test_plisql_collection_sources,
  c_args: ['-I@0@'.format(meson.project_source_root() / 'src/pl/plisql/src')],
  kwargs: pg_test_mod_args,
)
test_install_libs += test_plisql_collection

test_install_data += files(
  'test_plisql_collection.control',
  'test_plisql_collection--1.0.sql',
)

tests += {
  'name': 'test_plisql_collection',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'regress': {
    'sql': [
      'test_plisql_collection',
    ],
  },
}
