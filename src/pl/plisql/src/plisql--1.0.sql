/*
 * Copyright 2025 IvorySQL Global Development Team
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/* src/pl/plisql/src/plisql--1.0.sql */
/* Portions Copyright (c) 2023-2025, IvorySQL Global Development Team */

-- The language object, but not the functions, can be owned by a non-superuser.
ALTER LANGUAGE plisql OWNER TO @extowner@;

COMMENT ON LANGUAGE plisql IS 'PL/iSQL procedural language';
