# Copyright (c) 2022-2024, PostgreSQL Global Development Group

run_command(
  [ln,
   '-s',
   '../backend/oracle_parser/ora_keywords.c'],
  check:false)

fe_utils_sources = files(
  'archive.c',
  'cancel.c',
  'conditional.c',
  'connect_utils.c',
  'mbprint.c',
  'option_utils.c',
  'parallel_slot.c',
  'print.c',
  'query_utils.c',
  'recovery_gen.c',
  'simple_list.c',
  'string_utils.c',
  'ora_keywords.c',
  'ora_string_utils.c',
)

ora_parser_kwlist = custom_target('ora_kwlist',
  input: files('../include/oracle_parser/ora_kwlist.h'),
  output: 'ora_kwlist_d.h',
  command: [perl, '-I', '@SOURCE_ROOT@/src/tools', files('../tools/ora_gen_keywordlist.pl'),
      '--extern', '--output', '@OUTDIR@', '@INPUT@'])
generated_sources += ora_parser_kwlist
fe_utils_sources += ora_parser_kwlist

psqlscan = custom_target('psqlscan',
  input: 'psqlscan.l',
  output: 'psqlscan.c',
  command: [flex_cmd, '--no-backup', '--fix-warnings', '--', '-Cfe', '-p', '-p'],
)
generated_sources += psqlscan
fe_utils_sources += psqlscan

fe_utils = static_library('libpgfeutils',
  fe_utils_sources + generated_headers,
  c_pch: pch_postgres_fe_h,
  include_directories: [postgres_inc, libpq_inc],
  c_args: host_system == 'windows' ? ['-DFD_SETSIZE=1024'] : [],
  dependencies: frontend_common_code,
  kwargs: default_lib_args,
)
