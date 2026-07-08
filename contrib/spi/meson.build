# Copyright (c) 2022-2026, PostgreSQL Global Development Group

autoinc_sources = files(
  'autoinc.c',
)

if host_system == 'windows'
  autoinc_sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'autoinc',
    '--FILEDESC', 'spi - examples of using SPI and triggers',])
endif

autoinc = shared_module('autoinc',
  autoinc_sources,
  kwargs: contrib_mod_args,
)
contrib_targets += autoinc

install_data('autoinc.control', 'autoinc--1.0.sql',
  kwargs: contrib_data_args,
)

install_data('autoinc.example',
  kwargs: contrib_doc_args,
)


insert_username_sources = files(
  'insert_username.c',
)

if host_system == 'windows'
  insert_username_sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'insert_username',
    '--FILEDESC', 'spi - examples of using SPI and triggers',])
endif

insert_username = shared_module('insert_username',
  insert_username_sources,
  kwargs: contrib_mod_args,
)
contrib_targets += insert_username

install_data(
  'insert_username.control',
  'insert_username--1.0.sql',
  kwargs: contrib_data_args,
)

install_data('insert_username.example',
  kwargs: contrib_doc_args,
)


moddatetime_sources = files(
  'moddatetime.c',
)

if host_system == 'windows'
  moddatetime_sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'moddatetime',
    '--FILEDESC', 'spi - examples of using SPI and triggers',])
endif

moddatetime = shared_module('moddatetime',
  moddatetime_sources,
  kwargs: contrib_mod_args,
)
contrib_targets += moddatetime

install_data(
  'moddatetime.control',
  'moddatetime--1.0.sql',
  kwargs: contrib_data_args,
)

install_data('moddatetime.example',
  kwargs: contrib_doc_args,
)


tests += {
  'name': 'spi',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'regress': {
    'sql': [
      'autoinc',
    ],
  },
}
