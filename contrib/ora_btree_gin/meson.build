# Copyright (c) 2022-2023, PostgreSQL Global Development Group

btree_gin_sources = files(
  'ora_btree_gin.c',
)

if host_system == 'windows'
  btree_gin_sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'ora_btree_gin',
    '--FILEDESC', 'ora_btree_gin - B-tree equivalent GIN operator classes',])
endif

ora_btree_gin = shared_module('ora_btree_gin',
  btree_gin_sources,
  kwargs: contrib_mod_args,
)
contrib_targets += ora_btree_gin

install_data(
  'ora_btree_gin.control',
  'ora_btree_gin--1.0.sql',
  kwargs: contrib_data_args,
)

tests += {
  'name': 'ora_btree_gin',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'regress': {
    'sql': [
      'init',
      'number',
      'varchar2',
      'binary_float',
      'binary_double',
      'date',
      'timestamp',
      'timestamptz',
      'timestampltz',
    ],
  },
}
