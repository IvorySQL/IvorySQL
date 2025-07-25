# Copyright 2025 IvorySQL Global Development Team
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Portions Copyright (c) 2023-2025, IvorySQL Global Development Team

ora_parser_sources = files(
  'liboracle_parser.c',
  'ora_keywords.c',
)

ora_parser_kwlist = custom_target('ora_kwlist',
  input: files('../../include/oracle_parser/ora_kwlist.h'),
  output: 'ora_kwlist_d.h',
  command: [perl, '-I', '@SOURCE_ROOT@/src/tools', files('../../tools/ora_gen_keywordlist.pl'),
      '--extern', '--output', '@OUTDIR@', '@INPUT@'])
generated_sources += ora_parser_kwlist
ora_parser_sources += ora_parser_kwlist


ora_backend_scanner = custom_target('ora_scan',
  input: 'ora_scan.l',
  output: 'ora_scan.c',
  command: [flex_cmd, '--no-backup', '--fix-warnings', '--', '-CF', '-p', '-p'],
)
generated_sources += ora_backend_scanner
ora_parser_sources += ora_backend_scanner

ora_backend_parser = custom_target('ora_gram',
  input: 'ora_gram.y',
  kwargs: bison_kw,
)
generated_sources += ora_backend_parser.to_list()
ora_parser_sources += ora_backend_parser


liboracle_parser = shared_module('liboracle_parser',
  ora_parser_sources,
  c_pch: pch_postgres_h,
  include_directories: [postgres_inc, include_directories('.')],
  kwargs: pg_mod_args,
)
backend_targets += liboracle_parser

ora_parser = static_library('ora_parser',
  ora_parser_sources,
  c_pch: pch_postgres_h,
  include_directories: [postgres_inc, include_directories('.')],
  kwargs: pg_mod_args
)
backend_link_with += ora_parser
