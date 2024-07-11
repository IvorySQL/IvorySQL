# Copyright (c) 2022-2023, PostgreSQL Global Development Group

plisql_sources = files(
  'pl_comp.c',
  'pl_exec.c',
  'pl_funcs.c',
  'pl_handler.c',
  'pl_scanner.c',
  'pl_subproc_function.c',
)

pl_gram = custom_target('gram',
  input: 'pl_gram.y',
  kwargs: bison_kw,
)
generated_sources += pl_gram.to_list()
plisql_sources += pl_gram

gen_plerrcodes = files('generate-plerrcodes.pl')
pl_errcodes = custom_target('plerrcodes',
  input: ['../../../../src/backend/utils/ora_errcodes.txt'],
  output: ['plerrcodes.h'],
  command: [perl, gen_plerrcodes, '@INPUT0@'],
  capture: true,
)
generated_sources += pl_errcodes
plisql_sources += pl_errcodes

gen_keywordlist = files('../../../../src/tools/ora_gen_keywordlist.pl')
pl_reserved = custom_target('pl_reserved_kwlist',
  input: ['pl_reserved_kwlist.h'],
  output: ['pl_reserved_kwlist_d.h'],
  command: [perl, '-I', '@SOURCE_ROOT@/src/tools', gen_keywordlist, '--output', '@OUTDIR@', '--varname', 'ReservedPLKeywords', '@INPUT@']
)
generated_sources += pl_reserved
plisql_sources += pl_reserved

pl_unreserved = custom_target('pl_unreserved_kwlist',
  input: ['pl_unreserved_kwlist.h'],
  output: ['pl_unreserved_kwlist_d.h'],
  command: [perl, '-I', '@SOURCE_ROOT@/src/tools', gen_keywordlist, '--output', '@OUTDIR@', '--varname', 'UnreservedPLKeywords', '@INPUT@']
)
generated_sources += pl_unreserved
plisql_sources += pl_unreserved

if host_system == 'windows'
  plisql_sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'plisql',
    '--FILEDESC', 'PL/iSQL - procedural language',])
endif

plisql = shared_module('plisql',
  plisql_sources,
  c_pch: pch_postgres_h,
  include_directories: include_directories('.'),
  link_with: ora_parser,
  kwargs: pg_mod_args,
)
pl_targets += plisql

install_data(
  'plisql.control',
  'plisql--1.0.sql',
  install_dir: dir_data_extension,
)

install_headers(
  'plisql.h',
  install_dir: dir_include_server
)


tests += {
  'name': 'plisql',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'regress': {
    'sql': [
      'plisql_array',
      'plisql_call',
      'plisql_control',
      'plisql_copy',
      'plisql_domain',
      'plisql_record',
      'plisql_cache',
      'plisql_simple',
      'plisql_transaction',
      'plisql_trap',
      'plisql_trigger',
      'plisql_varprops',
    ],
  },
}

subdir('po', if_found: libintl)
