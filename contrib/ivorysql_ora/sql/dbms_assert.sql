--
-- dbms_assert.sql
--
-- tests for the DBMS_ASSERT package:
--   ENQUOTE_NAME / ENQUOTE_LITERAL / NOOP / SIMPLE_SQL_NAME /
--   QUALIFIED_SQL_NAME / SCHEMA_NAME / SQL_OBJECT_NAME
--

--
-- SIMPLE_SQL_NAME: valid names pass through unchanged
--
select dbms_assert.simple_sql_name('employees') as plain;
select dbms_assert.simple_sql_name('"Mixed Case"') as quoted;
select dbms_assert.simple_sql_name('_dollar$9') as odd_chars;
select dbms_assert.simple_sql_name('测试') as multibyte;

-- not simple names
select dbms_assert.simple_sql_name('a b') as has_space;
select dbms_assert.simple_sql_name('9abc') as leading_digit;
select dbms_assert.simple_sql_name('a;drop table x') as injection;
select dbms_assert.simple_sql_name('a;') as trailing_semi;
select dbms_assert.simple_sql_name('"unterminated') as unterminated;
select dbms_assert.simple_sql_name('') as empty;
-- with empty strings preserved (not folded to NULL), '' hits the
-- explicit empty-input validation instead
set ivorysql.enable_emptystring_to_NULL = off;
select dbms_assert.simple_sql_name('') as empty_preserved;
set ivorysql.enable_emptystring_to_NULL = on;
select dbms_assert.simple_sql_name('a.b') as dotted;

--
-- QUALIFIED_SQL_NAME: dot-separated chains pass
--
select dbms_assert.qualified_sql_name('schema.table') as two_part;
select dbms_assert.qualified_sql_name('db.schema.table') as three_part;
select dbms_assert.qualified_sql_name('"S"."T"') as quoted_parts;

-- not qualified names
select dbms_assert.qualified_sql_name('a..b') as empty_part;
select dbms_assert.qualified_sql_name('a b.c') as space_in_part;
select dbms_assert.qualified_sql_name('a;') as trailing_semi;

--
-- ENQUOTE_NAME: always returns a double-quoted identifier, with embedded
-- quotes doubled; the optional flag upper-cases the name before quoting
--
select dbms_assert.enquote_name('employees') as quoted;
select dbms_assert.enquote_name('employees', true) as capitalized;
select dbms_assert.enquote_name('MixedCase') as case_preserved;
select dbms_assert.enquote_name('MixedCase', true) as case_upper;
select dbms_assert.enquote_name('"Already"') as already_quoted;

--
-- ENQUOTE_LITERAL: doubles embedded single quotes
--
select dbms_assert.enquote_literal('it''s') as literal;
select dbms_assert.enquote_literal('plain') as plain_literal;

--
-- NOOP: returns the input untouched
--
select dbms_assert.noop('anything; goes -- here') as noop_out;

--
-- SCHEMA_NAME: must exist and be usable
--
select dbms_assert.schema_name('public') as public_schema;
select dbms_assert.schema_name('no_such_schema_777') as missing_schema;
select dbms_assert.schema_name('a.b') as dotted_schema;

--
-- SQL_OBJECT_NAME: must be an existing relation
--
create table assert_objects(id int);
select dbms_assert.object_name('assert_objects') as existing_table;
select dbms_assert.sql_object_name('assert_objects') as existing_table_oracle_name;
select dbms_assert.object_name('no_such_table_777') as missing_table;
drop table assert_objects;
