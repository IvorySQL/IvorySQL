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
