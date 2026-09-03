# Copyright (c) 2022-2026, PostgreSQL Global Development Group

tests += {
  'name': 'unsafe_tests',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'regress': {
    # setconfig is dropped: its expected output drifts under an
    # Oracle-mode instance, while the remaining tests pass.
    'sql': [
      'rolenames',
      'alter_system_table',
      'guc_privs',
    ],
    'regress_args': ['--create-role=regress_authenticated_user_db_sr',
                     '--create-role=regress_authenticated_user_db_ssa',
                     '--create-role=regress_authenticated_user_sr',
                     '--create-role=regress_authenticated_user_ssa'],
    'runningcheck': false,
  },
}
