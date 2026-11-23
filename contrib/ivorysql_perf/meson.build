# Copyright 2026 IvorySQL Global Development Team
perf_sources = files('ivorysql_perf.c')
if host_system == 'windows'
  perf_sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', 'ivorysql_perf', '--FILEDESC', 'ivorysql_perf - performance reports'])
endif
perf_module = shared_module('ivorysql_perf', perf_sources, kwargs: contrib_mod_args)
contrib_targets += perf_module
install_data('ivorysql_perf.control', 'ivorysql_perf--1.0.sql', kwargs: contrib_data_args)
tests += {
  'name': 'ivorysql_perf',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'tap': {'tests': ['t/001_perf.pl']},
}
