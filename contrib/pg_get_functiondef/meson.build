# Copyright (c) 2024, PostgreSQL Global Development Group

# .. so that includes of pg_get_functiondef work
pg_get_functiondef_inc = include_directories('.', '../')

pg_get_functiondef_sources = files(
  'pg_get_functiondef_extend.c',
  'pg_get_functiondef_mul.c',
  'pg_get_functiondef_no_input.c',
)

if host_system == 'windows'
  pg_get_functiondef__sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'pg_get_functiondef',
    '--FILEDESC', 'pg_get_functiondef - Enhancement of pg_get-functionaldef',])
endif

hstore = shared_module('pg_get_functiondef',
  pg_get_functiondef,
  kwargs: contrib_mod_args,
)
contrib_targets += pg_get_functiondef

install_data(
  'pg_get_functiondef.control',
  'pg_get_functiondef--1.0.sql',
  kwargs: contrib_data_args,
)


tests += {
  'name': 'pg_get_functiondef',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'regress': {
    'sql': [
      'pg_get_functiondef',
    ],
  },
}
