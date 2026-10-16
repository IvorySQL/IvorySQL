# Copyright (c) 2022-2024, PostgreSQL Global Development Group
# Portions Copyright (c) 2023-2026, IvorySQL Global Development Team

ivorysql_ora_sources = files(
  'src/ivorysql_ora.c',
  'src/guc/guc.c',
  'src/datatype/oracharchar.c',
  'src/datatype/oracharbyte.c',
  'src/datatype/oravarcharchar.c',
  'src/datatype/oravarcharbyte.c',
  'src/datatype/oradate.c',
  'src/datatype/oratimestamp.c',
  'src/datatype/oratimestamptz.c',
  'src/datatype/oratimestampltz.c',
  'src/datatype/yminterval.c',
  'src/datatype/dsinterval.c',
  'src/datatype/compatible_oracle_precedence.c',
  'src/datatype/common_datatypes.c',
  'src/datatype/raw_long.c',
  'src/datatype/binary_float.c',
  'src/datatype/binary_double.c',
  'src/builtin_functions/character_datatype_functions.c',
  'src/builtin_functions/datetime_datatype_functions.c',
  'src/builtin_functions/numeric_datatype_functions.c',
  'src/builtin_functions/misc_functions.c',
  'src/builtin_packages/dbms_output/dbms_output.c',
  'src/builtin_packages/utl_file/utl_file.c',
  'src/merge/ora_merge.c',
  'src/sysview/sysview_functions.c',
  'src/xml_functions/ora_xml_functions.c',
  'src/builtin_packages/dbms_utility/dbms_utility.c',
  'src/builtin_packages/dbms_lock/dbms_lock.c',
  'src/builtin_packages/utl_raw/utl_raw.c',
  'src/builtin_packages/utl_encode/utl_encode.c',
  'src/builtin_packages/utl_url/utl_url.c',
  'src/builtin_packages/dbms_session/dbms_session.c',
  'src/builtin_packages/dbms_transaction/dbms_transaction.c',
  'src/builtin_packages/dbms_random/dbms_random.c',
  'src/builtin_packages/utl_match/utl_match.c',
  'src/builtin_packages/dbms_scheduler/dbms_scheduler.c',
  'src/builtin_packages/dbms_scheduler/scheduler_calendar.c',
  'src/builtin_packages/dbms_scheduler/scheduler_launcher.c',
  'src/builtin_packages/dbms_scheduler/scheduler_worker.c'
)

if host_system == 'windows'
  ivorysql_ora_sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'ivorysql_ora',
    '--FILEDESC', 'ivorysql_ora - Oracle Compatible extension on Postgres Database',])
endif

custom_target('ivorysql_ora--1.0.sql',
  output: 'ivorysql_ora--1.0.sql',
  command: [perl, files('gensql.pl'), 'meson', '1.0'],
  # the merge list and the files it names: keep in step with ivorysql_ora_merge_sqls
  depend_files: files(
    'ivorysql_ora_merge_sqls',
    'src/datatype/datatype--1.0.sql',
    'src/builtin_functions/builtin_functions--1.0.sql',
    'src/builtin_packages/dbms_output/dbms_output--1.0.sql',
    'src/builtin_packages/utl_file/utl_file--1.0.sql',
    'src/sysview/sysview--1.0.sql',
    'src/xml_functions/xml_functions--1.0.sql',
    'src/builtin_packages/dbms_utility/dbms_utility--1.0.sql',
    'src/builtin_packages/dbms_lock/dbms_lock--1.0.sql',
    'src/builtin_packages/utl_raw/utl_raw--1.0.sql',
    'src/builtin_packages/utl_encode/utl_encode--1.0.sql',
    'src/builtin_packages/utl_url/utl_url--1.0.sql',
    'src/builtin_packages/dbms_session/dbms_session--1.0.sql',
    'src/builtin_packages/dbms_transaction/dbms_transaction--1.0.sql',
    'src/builtin_packages/dbms_random/dbms_random--1.0.sql',
    'src/builtin_packages/utl_match/utl_match--1.0.sql',
    'src/builtin_packages/dbms_scheduler/dbms_scheduler--1.0.sql',
  ),
  capture: true,
  install: true,
  install_dir: contrib_data_args['install_dir'],
)

ivorysql_ora = shared_module('ivorysql_ora',
  ivorysql_ora_sources,
  kwargs: contrib_mod_args,
)
contrib_targets += ivorysql_ora

install_data(
  'ivorysql_ora.control',
  kwargs: contrib_data_args,
)

install_data(
  'preload_ora_misc.sql',
  install_dir: dir_data,
)

# The extension's Oracle-mode suite: the same list as ORA_REGRESS in the
# Makefile, run with the Oracle-mode driver and template, which the 'oracle'
# flag selects.  The database is UTF8 for the same reason the Makefile sets
# ENCODING: utl_url exercises multibyte input and charset conversions.
tests += {
  'name': 'ivorysql_ora',
  'oracle': true,
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'regress': {
    'sql': [
      'ora_character',
      'ora_datetime',
      'ora_interval',
      'ora_number',
      'ora_binary_float',
      'ora_binary_double',
      'ora_nanvl',
      'ora_raw_long',
      'ora_character_datatype_functions',
      'ora_datetime_datatype_functions',
      'ora_misc_functions',
      'ora_vsize',
      'ora_merge',
      'datatype_and_func_bugs',
      'ora_sysview',
      'ora_like_operator',
      'ora_xml_functions',
      'dbms_utility',
      'ora_dbms_output',
      'ora_ascii',
      'ora_stragg',
      'dbms_lock',
      'utl_file',
      'utl_raw',
      'utl_encode',
      'utl_url',
      'dbms_session',
      'dbms_transaction',
      'dbms_random',
      'utl_match',
      'dbms_scheduler',
    ],
    'regress_args': ['--encoding=UTF8'],
  },
}
