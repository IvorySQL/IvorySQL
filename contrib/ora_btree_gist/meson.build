# Copyright (c) 2022-2024, PostgreSQL Global Development Group

btree_gist_sources = files(
  'btree_binary_double.c',
  'btree_binary_float.c',
  'btree_dsinterval.c',
  'btree_gist.c',
  'btree_interval.c',
  'btree_number.c',
  'btree_timestamp.c',
  'btree_utils_num.c',
  'btree_utils_var.c',
  'btree_varcharchar.c',
  'btree_yminterval.c',
)

if host_system == 'windows'
  btree_gist_sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'ora_btree_gist',
    '--FILEDESC', 'btree_gist - B-tree equivalent GiST operator classes',])
endif

ora_btree_gist = shared_module('ora_btree_gist',
  btree_gist_sources,
  c_pch: pch_postgres_h,
  kwargs: contrib_mod_args,
)
contrib_targets += ora_btree_gist

install_data(
  'ora_btree_gist.control',
  'ora_btree_gist--1.0.sql',
  kwargs: contrib_data_args,
)

tests += {
  'name': 'ora_btree_gist',
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
      'yminterval',
      'dsinterval',
    ],
  },
}
