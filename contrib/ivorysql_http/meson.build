# Copyright 2026 IvorySQL Global Development Team
http_curl = dependency('libcurl', version: '>=7.85', required: false)
if not http_curl.found()
  subdir_done()
endif
http_sources = files('ivorysql_http.c')
if host_system == 'windows'
  http_sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'ivorysql_http', '--FILEDESC', 'ivorysql_http - Oracle-style HTTP'])
endif
http_module = shared_module('ivorysql_http', http_sources,
  kwargs: contrib_mod_args + {'dependencies': contrib_mod_args['dependencies'] + [http_curl]})
contrib_targets += http_module
install_data('ivorysql_http.control', 'ivorysql_http--1.0.sql', kwargs: contrib_data_args)
tests += {
  'name': 'ivorysql_http',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'tap': {'tests': ['t/001_http.pl']},
}
