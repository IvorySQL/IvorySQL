# Portions Copyright (c) 2023-2026, IvorySQL Global Development Team

gb18030_2022_src_files = files(
  'utf8_and_gb18030_2022.c'
)

if host_system == 'windows'
  gb18030_2022_src_files += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'gb18030_2022',
    '--FILEDESC', 'gb18030_2022 - support gb18030 2022 with extension',])
endif

custom_target('gb18030_2022.bc',
  output: 'utf8_and_gb18030_2022.bc',
  command: [perl, '../contrib/ivorysql_ora/gensql.pl', 'meson', '1.0'],
  capture: true,
  install: true,
  install_dir: contrib_data_args['install_dir'],
)

foreach file : ['utf8_and_gb18030_2022.bc', 'gb18030_2022.bc']
  run_target(
    file,
    command: ['touch', meson.current_build_dir() / file]
  )
endforeach

gb18030_2022 = shared_module('gb18030_2022',
  gb18030_2022_src_files,
  kwargs: contrib_mod_args,
)
contrib_targets += gb18030_2022

install_data(
  'gb18030_2022.control',
  'gb18030_2022--1.0.sql',
  kwargs: contrib_data_args,
)

tests += {
  'name': 'gb18030_2022',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'regress': {
    'sql': [
      'gb18030_2022_and_utf8',
      'copy',
    ],
  },
}
