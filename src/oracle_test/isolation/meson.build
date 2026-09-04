# Copyright (c) 2022-2026, PostgreSQL Global Development Group

# oracle_pg_regress_c helpfully provided by regress/meson.build

oracle_isolation_sources = oracle_pg_regress_c + files(
  'isolation_main.c',
)

oracle_isolationtester_sources = files(
  'isolationtester.c',
)

oracle_spec_scanner = custom_target('specscanner',
  input: 'specscanner.l',
  output: 'specscanner.c',
  command: flex_cmd,
)
oracle_isolationtester_sources += oracle_spec_scanner
generated_sources += oracle_spec_scanner

oracle_spec_parser = custom_target('specparse',
  input: 'specparse.y',
  kwargs: bison_kw,
)
oracle_isolationtester_sources += oracle_spec_parser
generated_sources += oracle_spec_parser.to_list()

if host_system == 'windows'
  oracle_isolation_sources += rc_bin_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'pg_isolation_regress',
    '--FILEDESC', 'pg_isolation_regress - multi-client test driver',])
endif

oracle_pg_isolation_regress = executable('pg_isolation_regress',
  oracle_isolation_sources,
  c_args: oracle_pg_regress_cflags,
  include_directories: oracle_pg_regress_inc,
  dependencies: [frontend_code, libpq],
  kwargs: default_bin_args + {
    'install_dir': dir_pgxs / 'src/oracle_test/isolation',
  },
)
bin_targets += oracle_pg_isolation_regress


if host_system == 'windows'
  oracle_isolationtester_sources += rc_bin_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'isolationtester',
    '--FILEDESC', 'isolationtester - multi-client test driver',])
endif

oracle_isolationtester = executable('isolationtester',
  oracle_isolationtester_sources,
  include_directories: include_directories('.'),
  dependencies: [frontend_code, libpq],
  kwargs: default_bin_args + {
    'install_dir': dir_pgxs / 'src/oracle_test/isolation',
  },
)
bin_targets += oracle_isolationtester

tests += {
  'name': 'isolation',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'isolation': {
    'schedule': files('isolation_schedule'),
    'test_kwargs': {
      'priority': 40,
      'timeout': 1000,
    },
    'dbname': 'isolation_regression',
  },
}
