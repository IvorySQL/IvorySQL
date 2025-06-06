# Portions Copyright (c) 2023-2025, IvorySQL Global Development Team

ora_fe_utils_sources = files(
  'ora_string_utils.c',
)

ora_psqlscan = custom_target('ora_psqlscan',
  input: 'ora_psqlscan.l',
  output: 'ora_psqlscan.c',
  command: [flex_cmd, '--no-backup', '--fix-warnings', '--', '-Cfe', '-p', '-p'],
)
generated_sources += ora_psqlscan
ora_fe_utils_sources += ora_psqlscan

ora_fe_utils = static_library('liborafeutils',
  ora_fe_utils_sources + generated_headers,
  c_pch: pch_postgres_fe_h,
  include_directories: [postgres_inc, libpq_inc],
  c_args: host_system == 'windows' ? ['-DFD_SETSIZE=1024'] : [],
  dependencies: frontend_common_code,
  kwargs: default_lib_args,
)
