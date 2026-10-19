# Copyright (c) 2022-2026, PostgreSQL Global Development Group

# also used by isolationtester and ecpg tests
oracle_pg_regress_c = files('pg_regress.c')
oracle_pg_regress_inc = include_directories('.')

oracle_regress_sources = oracle_pg_regress_c + files(
  'pg_regress_main.c'
)

# Need make up something roughly like x86_64-pc-mingw64. resultmap matches on
# patterns like ".*-.*-mingw.*". We probably can do better, but for now just
# replace 'gcc' with 'mingw' on windows.
oracle_host_tuple_cc = cc.get_id()
if host_system == 'windows' and oracle_host_tuple_cc == 'gcc'
  oracle_host_tuple_cc = 'mingw'
elif host_system == 'cygwin' and oracle_host_tuple_cc == 'gcc'
  oracle_host_tuple_cc = 'cygwin'
endif
oracle_host_tuple = '@0@-@1@-@2@'.format(
  host_cpu, host_system, oracle_host_tuple_cc)

oracle_pg_regress_cflags = [
  '-DHOST_TUPLE="@0@"'.format(oracle_host_tuple),
  '-DSHELLPROG="/bin/sh"',
]

if host_system == 'windows'
  oracle_regress_sources += rc_bin_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'pg_regress',
    '--FILEDESC', 'pg_regress - test driver',])
endif

oracle_pg_regress = executable('pg_regress',
  oracle_regress_sources,
  c_args: oracle_pg_regress_cflags,
  dependencies: [frontend_code, libpq],
  kwargs: default_bin_args + {
    'install_dir': dir_pgxs / 'src/oracle_test/regress',
  },
)
bin_targets += oracle_pg_regress

oracle_regress_module = shared_module('oraregress',
  ['regress.c'],
  kwargs: pg_test_mod_args,
)
test_install_libs += oracle_regress_module


tests += {
  'name': 'regress',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'regress': {
    'schedule': files('parallel_schedule'),
    'test_kwargs': {
      'priority': 50,
      'timeout': 1000,
    },
    'dbname': 'regression',
  },
}

subdir('po', if_found: libintl)
