/*-------------------------------------------------------------------------
 * Copyright 2026 IvorySQL Global Development Team
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
 *
 * dbms_metadata--1.0.sql
 *
 * Oracle-compatible DBMS_METADATA package (GET_DDL subset).
 *
 * DBMS_METADATA is the Oracle "object DDL extraction" package used by
 * migration / backup tooling to turn an existing schema into re-creatable
 * CREATE statements.  This implementation provides the core entry point:
 *
 *     DBMS_METADATA.GET_DDL(object_type, name[, schema])
 *
 * supported object types (MVP):
 *   TABLE, VIEW, MATERIALIZED VIEW, SEQUENCE, INDEX,
 *   FUNCTION, PROCEDURE, TRIGGER
 *
 * Design notes
 * ------------
 * 1. Pure SQL/PL-iSQL implementation.  DDL is assembled from the system
 *    catalogs with the help of the core helper functions
 *    (format_type, pg_get_expr, pg_get_viewdef, pg_get_indexdef,
 *    pg_get_functiondef, pg_get_triggerdef).  No C code is required.
 *
 * 2. Identifier presentation follows Oracle's SQL*Plus/DBMS_METADATA rules:
 *    every emitted identifier is double-quoted and case-transformed with
 *    sys.ora_case_trans (all-lowercase stored names render UPPERCASE, which
 *    matches what an unquoted CREATE TABLE on Oracle would have produced).
 *    Type names are emitted in upper case as well (format_type is already
 *    Oracle-flavoured for the built-in Oracle data types, e.g. NUMBER(4,0),
 *    VARCHAR2(10), DATE).
 *
 * 3. Name lookup is forgiving on case: the given schema/object name is
 *    matched against the catalog both exactly and case-folded (upper and
 *    lower), so GET_DDL('TABLE','EMP') and GET_DDL('TABLE','emp') resolve
 *    the same underlying object regardless of the case it was created in
 *    (quoted mixed-case names still match exactly).
 *
 * 4. Errors follow Oracle's message texts:
 *      ORA-31603: object "SCHEMA"."NAME" of type "TYPE" does not exist
 *      ORA-31600: invalid input value for parameter OBJECT_TYPE in function GET_DDL
 *    NULL object_type/name and unsupported object types raise ORA-31600;
 *    a missing object of a supported type raises ORA-31603.
 *
 * 5. Tables additionally emit COMMENT ON ... statements collected from
 *    pg_description (Oracle GET_DDL does the same for table/column
 *    comments).
 *
 * Known differences from Oracle (documented, roundtrip-safe):
 *   - VIEW / MATERIALIZED VIEW bodies, CHECK expressions, partial-index
 *     predicates and FUNCTION/PROCEDURE/TRIGGER text are emitted in their
 *     native catalog form (PG-flavoured where the helper function renders
 *     it so), rather than being re-deparsed with Oracle formatting.  The
 *     output is always a valid statement that can be re-executed.
 *   - Constraint backing indexes (PK / UNIQUE) are not emitted as standalone
 *     INDEX objects (they are part of the TABLE constraint, as in Oracle).
 *   - TRIGGER output does not carry ENABLE/DISABLE state; FUNCTION emission
 *     picks the first overload (oldest by OID) when several share a name.
 *   - Serial-column DEFAULT expressions preserve the original nextval(...)
 *     reference; identity columns lose their GENERATED ... AS IDENTITY
 *     attribute (a plain NOT NULL column is emitted instead).
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_metadata/dbms_metadata--1.0.sql
 *
 *-------------------------------------------------------------------------
 */

-- ---------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------

/*
 * sys.ora_dbms_metadata_ident - render an identifier in Oracle style.
 *
 * Always double-quoted, inner double quotes are doubled, and the spelling
 * is normalized through sys.ora_case_trans so that a plain lowercase
 * catalog name (the normal PG storage for an unquoted CREATE) shows up as
 * its Oracle-canonical UPPERCASE form.
 */
CREATE FUNCTION sys.ora_dbms_metadata_ident(identifier text)
RETURNS text
AS $$ SELECT '"' || replace(sys.ora_case_trans(identifier)::text, '"', '""') || '"' $$
LANGUAGE sql IMMUTABLE;

/*
 * sys.ora_dbms_metadata_type - render a column type for DDL output.
 *
 * format_type() already yields the Oracle-flavoured spellings of the
 * Oracle-compatible types (number(4,0), varchar2(10), date, ...).  It is
 * upper-cased for a more Oracle-like presentation, except when the
 * rendering already carries a schema qualifier or a quoted identifier
 * (e.g. sys.clob, "MyDomain") in which case it is reproduced verbatim so
 * the statement stays re-creatable.
 */
CREATE FUNCTION sys.ora_dbms_metadata_type(typid oid, typmod integer)
RETURNS text
AS $$ SELECT CASE
    WHEN format_type(typid, typmod) LIKE '%"' OR format_type(typid, typmod) LIKE '%.%'
        THEN format_type(typid, typmod)
    ELSE upper(format_type(typid, typmod))
END $$
LANGUAGE sql STABLE;

/*
 * sys.ora_dbms_metadata_index_opts - render DESC / NULLS ordering clauses
 * for one index key column from the pg_index.indoption bitmask.
 *
 * Bit 0 = DESC, bit 1 = NULLS FIRST.  PostgreSQL defaults nulls ordering
 * to NULLS FIRST for descending and NULLS LAST for ascending columns, so
 * only non-default combinations are spelled out (the same rules pg_dump
 * uses, see dumpIndex in pg_dump.c).
 */
CREATE FUNCTION sys.ora_dbms_metadata_index_opts(option_bits integer)
RETURNS text
AS $$ SELECT CASE
    WHEN (option_bits & 1) = 1 AND (option_bits & 2) = 2 THEN ' DESC'
    WHEN (option_bits & 1) = 1 THEN ' DESC NULLS LAST'
    WHEN (option_bits & 2) = 2 THEN ' NULLS FIRST'
    ELSE ''
END $$
LANGUAGE sql IMMUTABLE;

-- ---------------------------------------------------------------------
-- per-object-type DDL assembly (all pure SQL over the catalogs)
-- ---------------------------------------------------------------------

/*
 * sys.ora_dbms_metadata_table_ddl
 *
 * Emits:
 *   CREATE TABLE "SCHEMA"."NAME" (
 *     "COL" TYPE [NOT NULL] [DEFAULT expr],
 *     ...
 *     CONSTRAINT "PK" PRIMARY KEY (...),
 *     CONSTRAINT "FK" FOREIGN KEY (...) REFERENCES "S"."T" (...)
 *                         [MATCH ...] [ON DELETE ...] [ON UPDATE ...],
 *     CONSTRAINT "CK" CHECK (...)
 *   )
 * followed by COMMENT ON TABLE / COMMENT ON COLUMN statements when
 * comments are present.
 *
 * NOT NULL is taken from attnotnull; the synthetic contype='n' constraint
 * rows that IvorySQL's oracle mode adds for NOT NULL are skipped.  The
 * NOT NULL / DEFAULT clauses are emitted inline, Oracle style.
 */
CREATE FUNCTION sys.ora_dbms_metadata_table_ddl(schema_name text, table_name text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
WITH
targets AS (
    SELECT c.oid, c.relname, n.nspname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = schema_name
      AND c.relname IN (table_name, upper(table_name), lower(table_name))
      AND c.relkind IN ('r', 'p')
),
cols AS (
    SELECT a.attnum,
           sys.ora_dbms_metadata_ident(a.attname::text) AS col_ident,
           sys.ora_dbms_metadata_type(a.atttypid, a.atttypmod) AS col_type,
           CASE WHEN a.attnotnull THEN ' NOT NULL' ELSE '' END AS notnull_clause,
           CASE WHEN d.adbin IS NOT NULL
                THEN ' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid)
                ELSE '' END AS default_clause
    FROM targets t
    JOIN pg_attribute a ON a.attrelid = t.oid
                       AND a.attnum > 0 AND NOT a.attisdropped
    LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
),
col_body AS (
    SELECT string_agg('  ' || col_ident || ' ' || col_type || notnull_clause || default_clause,
                      E',\n' ORDER BY attnum) AS body
    FROM cols
),
cons AS (
    SELECT c.conname, c.contype,
           c.conkey, c.confrelid, c.confkey,
           c.confdeltype, c.confupdtype, c.confmatchtype,
           c.condeferrable, c.condeferred,
           c.conbin, c.conrelid,
           CASE c.contype
             WHEN 'p' THEN 1
             WHEN 'u' THEN 2
             WHEN 'f' THEN 3
             ELSE 4
           END AS ord
    FROM targets t
    JOIN pg_constraint c ON c.conrelid = t.oid
    WHERE c.contype IN ('p', 'u', 'f', 'c')
),
cons_rows AS (
    SELECT c.ord, c.conname,
           CASE c.contype
             WHEN 'p' THEN
                 '  CONSTRAINT ' || sys.ora_dbms_metadata_ident(c.conname::text)
                     || ' PRIMARY KEY ('
                     || (SELECT string_agg(sys.ora_dbms_metadata_ident(pa.attname::text), ', ' ORDER BY k.ord)
                         FROM unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
                         JOIN pg_attribute pa ON pa.attrelid = c.conrelid AND pa.attnum = k.attnum)
                     || ')'
             WHEN 'u' THEN
                 '  CONSTRAINT ' || sys.ora_dbms_metadata_ident(c.conname::text)
                     || ' UNIQUE ('
                     || (SELECT string_agg(sys.ora_dbms_metadata_ident(pa.attname::text), ', ' ORDER BY k.ord)
                         FROM unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
                         JOIN pg_attribute pa ON pa.attrelid = c.conrelid AND pa.attnum = k.attnum)
                     || ')'
             WHEN 'f' THEN
                 '  CONSTRAINT ' || sys.ora_dbms_metadata_ident(c.conname::text)
                     || ' FOREIGN KEY ('
                     || (SELECT string_agg(sys.ora_dbms_metadata_ident(pa.attname::text), ', ' ORDER BY k.ord)
                         FROM unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
                         JOIN pg_attribute pa ON pa.attrelid = c.conrelid AND pa.attnum = k.attnum)
                     || ') REFERENCES '
                     || (SELECT sys.ora_dbms_metadata_ident(rn.nspname::text)
                                || '.' || sys.ora_dbms_metadata_ident(rc.relname::text)
                         FROM pg_class rc
                         JOIN pg_namespace rn ON rn.oid = rc.relnamespace
                         WHERE rc.oid = c.confrelid)
                     || ' ('
                     || (SELECT string_agg(sys.ora_dbms_metadata_ident(pa.attname::text), ', ' ORDER BY k.ord)
                         FROM unnest(c.confkey) WITH ORDINALITY AS k(attnum, ord)
                         JOIN pg_attribute pa ON pa.attrelid = c.confrelid AND pa.attnum = k.attnum)
                     || ')'
                     || CASE c.confmatchtype WHEN 'f' THEN ' MATCH FULL' ELSE '' END
                     || CASE c.confdeltype WHEN 'c' THEN ' ON DELETE CASCADE'
                                           WHEN 'n' THEN ' ON DELETE SET NULL'
                                           WHEN 'd' THEN ' ON DELETE SET DEFAULT'
                                           WHEN 'r' THEN ' ON DELETE RESTRICT'
                                           ELSE '' END
                     || CASE c.confupdtype WHEN 'c' THEN ' ON UPDATE CASCADE'
                                           WHEN 'n' THEN ' ON UPDATE SET NULL'
                                           WHEN 'd' THEN ' ON UPDATE SET DEFAULT'
                                           WHEN 'r' THEN ' ON UPDATE RESTRICT'
                                           ELSE '' END
                     || CASE WHEN c.condeferrable THEN ' DEFERRABLE' ELSE '' END
                     || CASE WHEN c.condeferred THEN ' INITIALLY DEFERRED' ELSE '' END
             ELSE -- 'c'
                 '  CONSTRAINT ' || sys.ora_dbms_metadata_ident(c.conname::text)
                     || ' CHECK ' || pg_get_expr(c.conbin, c.conrelid)
           END AS constraint_text
    FROM cons c
),
cons_body AS (
    SELECT string_agg(constraint_text, E',\n' ORDER BY ord, conname) AS body
    FROM cons_rows
),
comments AS (
    SELECT string_agg(comment_text, E'\n' ORDER BY objsubid) AS body
    FROM (
        SELECT d.objsubid,
               CASE WHEN d.objsubid = 0
                    THEN 'COMMENT ON TABLE '
                         || sys.ora_dbms_metadata_ident(t.nspname::text)
                         || '.' || sys.ora_dbms_metadata_ident(t.relname::text)
                         || ' IS ' || quote_literal(d.description) || ';'
                    ELSE 'COMMENT ON COLUMN '
                         || sys.ora_dbms_metadata_ident(t.nspname::text)
                         || '.' || sys.ora_dbms_metadata_ident(t.relname::text)
                         || '.' || sys.ora_dbms_metadata_ident(a.attname::text)
                         || ' IS ' || quote_literal(d.description) || ';'
               END AS comment_text
        FROM targets t
        JOIN pg_description d ON d.objoid = t.oid
        LEFT JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.objsubid
        WHERE d.objsubid >= 0
    ) s
)
SELECT 'CREATE TABLE '
       || sys.ora_dbms_metadata_ident(t.nspname::text)
       || '.' || sys.ora_dbms_metadata_ident(t.relname::text)
       || E'\n(\n'
       || cb.body
       || CASE WHEN cb2.body IS NOT NULL THEN E',\n' || cb2.body ELSE '' END
       || E'\n)'
       || CASE WHEN cm.body IS NOT NULL THEN E'\n' || cm.body ELSE '' END
FROM targets t
CROSS JOIN (SELECT body FROM col_body) cb
CROSS JOIN (SELECT body FROM cons_body) cb2
CROSS JOIN (SELECT body FROM comments) cm
$$;

/*
 * sys.ora_dbms_metadata_view_ddl
 *
 *   CREATE VIEW "SCHEMA"."NAME" AS <pg_get_viewdef ...>
 *
 * The SELECT body is taken from pg_get_viewdef (pretty-printed).  The
 * qualification of cross-schema references inside the body follows the
 * caller's search_path (as with pg_dump); schemas not visible to the
 * caller are always fully qualified.
 */
CREATE FUNCTION sys.ora_dbms_metadata_view_ddl(schema_name text, view_name text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
WITH targets AS (
    SELECT c.oid, c.relname, n.nspname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = schema_name
      AND c.relname IN (view_name, upper(view_name), lower(view_name))
      AND c.relkind = 'v'
)
SELECT 'CREATE VIEW '
       || sys.ora_dbms_metadata_ident(t.nspname::text)
       || '.' || sys.ora_dbms_metadata_ident(t.relname::text)
       || ' AS' || E'\n' || btrim(pg_get_viewdef(t.oid, true))
FROM targets t
$$;

/*
 * sys.ora_dbms_metadata_matview_ddl
 *
 * Same as the view variant, for MATERIALIZED VIEW objects.
 */
CREATE FUNCTION sys.ora_dbms_metadata_matview_ddl(schema_name text, view_name text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
WITH targets AS (
    SELECT c.oid, c.relname, n.nspname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = schema_name
      AND c.relname IN (view_name, upper(view_name), lower(view_name))
      AND c.relkind = 'm'
)
SELECT 'CREATE MATERIALIZED VIEW '
       || sys.ora_dbms_metadata_ident(t.nspname::text)
       || '.' || sys.ora_dbms_metadata_ident(t.relname::text)
       || ' AS' || E'\n' || btrim(pg_get_viewdef(t.oid, true))
FROM targets t
$$;

/*
 * sys.ora_dbms_metadata_sequence_ddl
 *
 *   CREATE SEQUENCE "SCHEMA"."NAME"
 *     INCREMENT BY n
 *     START WITH n
 *     MINVALUE n
 *     MAXVALUE n
 *     CACHE n
 *     CYCLE
 *
 * Every clause is spelled out so repeated calls are byte-identical.
 */
CREATE FUNCTION sys.ora_dbms_metadata_sequence_ddl(schema_name text, sequence_name text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
SELECT 'CREATE SEQUENCE '
       || sys.ora_dbms_metadata_ident(s.schemaname::text)
       || '.' || sys.ora_dbms_metadata_ident(s.sequencename::text)
       || E'\n'
       || '  INCREMENT BY ' || s.increment_by::text || E'\n'
       || '  START WITH ' || s.start_value::text || E'\n'
       || '  MINVALUE ' || s.min_value::text || E'\n'
       || '  MAXVALUE ' || s.max_value::text || E'\n'
       || '  CACHE ' || s.cache_size::text
       || CASE WHEN s.cycle THEN E'\n  CYCLE' ELSE '' END
FROM pg_sequences s
WHERE s.schemaname = schema_name
  AND s.sequencename IN (sequence_name, upper(sequence_name), lower(sequence_name))
$$;

/*
 * sys.ora_dbms_metadata_index_ddl
 *
 *   CREATE [UNIQUE] INDEX "SCHEMA"."NAME" ON "SCHEMA"."TABLE"
 *     USING BTREE ("COL" [DESC ...][, ...])
 *     [WHERE predicate]
 *
 * Indexes that back a PRIMARY KEY / UNIQUE constraint are skipped: Oracle
 * tracks those constraints on the table itself, so GET_DDL('INDEX', ...)
 * must not return a duplicate object; the TABLE output carries the
 * constraint.  Expression columns are rendered through pg_get_indexdef and
 * the DESC/NULLS clauses are reconstructed from pg_index.indoption.
 */
CREATE FUNCTION sys.ora_dbms_metadata_index_ddl(schema_name text, index_name text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
WITH
targets AS (
    SELECT c.oid, c.relname, n.nspname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = schema_name
      AND c.relname IN (index_name, upper(index_name), lower(index_name))
      AND c.relkind = 'i'
      -- constraint backing indexes are not standalone objects
      AND NOT EXISTS (SELECT 1 FROM pg_constraint cc WHERE cc.conindid = c.oid)
),
idx AS (
    SELECT i.indexrelid, i.indrelid, i.indisunique, i.indpred,
           i.indnkeyatts, i.indkey, i.indoption,
           xi.relname AS idxname, n1.nspname AS idx_schema,
           t.relname AS tblname, n2.nspname AS tbl_schema,
           upper(am.amname) AS amname
    FROM targets ti
    JOIN pg_index i ON i.indexrelid = ti.oid
    JOIN pg_class xi ON xi.oid = i.indexrelid
    JOIN pg_namespace n1 ON n1.oid = xi.relnamespace
    JOIN pg_class t ON t.oid = i.indrelid
    JOIN pg_namespace n2 ON n2.oid = t.relnamespace
    JOIN pg_am am ON am.oid = xi.relam
),
cols AS (
    SELECT i.indexrelid,
           string_agg(key_text, ', ' ORDER BY pos) AS col_list
    FROM idx i
    CROSS JOIN LATERAL (
        SELECT n.ord AS pos,
               CASE WHEN i.indkey[n.ord - 1] > 0
                    THEN sys.ora_dbms_metadata_ident(pa.attname::text)
                         || sys.ora_dbms_metadata_index_opts(i.indoption[n.ord - 1])
                    ELSE '(' || pg_get_indexdef(i.indexrelid, n.ord, true) || ')'
                         || sys.ora_dbms_metadata_index_opts(i.indoption[n.ord - 1])
               END AS key_text
        FROM generate_series(1, i.indnkeyatts) AS n(ord)
        LEFT JOIN pg_attribute pa
               ON pa.attrelid = i.indrelid AND pa.attnum = i.indkey[n.ord - 1]
    ) x
    GROUP BY i.indexrelid
)
SELECT 'CREATE '
       || CASE WHEN i.indisunique THEN 'UNIQUE ' ELSE '' END
       || 'INDEX '
       || sys.ora_dbms_metadata_ident(i.idx_schema::text)
       || '.' || sys.ora_dbms_metadata_ident(i.idxname::text)
       || ' ON '
       || sys.ora_dbms_metadata_ident(i.tbl_schema::text)
       || '.' || sys.ora_dbms_metadata_ident(i.tblname::text)
       || ' USING ' || i.amname
       || ' (' || c.col_list || ')'
       || CASE WHEN i.indpred IS NOT NULL
               THEN ' WHERE ' || pg_get_expr(i.indpred, i.indrelid)
               ELSE '' END
FROM idx i
JOIN cols c ON c.indexrelid = i.indexrelid
$$;

/*
 * sys.ora_dbms_metadata_function_ddl / _procedure_ddl
 *
 * The function (or procedure) is rendered with pg_get_functiondef, which
 * already produces Oracle-flavoured output for PL/iSQL objects
 * (CREATE OR REPLACE FUNCTION ... RETURN ... IS ... END), including
 * schema-qualified names and argument/return types.
 *
 * Overloads: the oldest definition (lowest OID) is returned, mirroring
 * the "one object per name" semantics of GET_DDL; callers needing a
 * specific overload must handle that case separately.
 */
CREATE FUNCTION sys.ora_dbms_metadata_function_ddl(schema_name text, function_name text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
SELECT pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = schema_name
  AND p.proname IN (function_name, upper(function_name), lower(function_name))
  AND p.prokind = 'f'
ORDER BY p.oid
LIMIT 1
$$;

CREATE FUNCTION sys.ora_dbms_metadata_procedure_ddl(schema_name text, procedure_name text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
SELECT pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = schema_name
  AND p.proname IN (procedure_name, upper(procedure_name), lower(procedure_name))
  AND p.prokind = 'p'
ORDER BY p.oid
LIMIT 1
$$;

/*
 * sys.ora_dbms_metadata_trigger_ddl
 *
 * Trigger bodies are available in the catalogs only as their pg_rewrite /
 * pg_trigger text, so the DDL is rendered with pg_get_triggerdef (a
 * complete, re-creatable CREATE TRIGGER statement).  Internal triggers
 * (FK enforcement, etc.) are excluded; when several triggers share the
 * same name across tables, all of them are returned, separated by a
 * blank line.
 */
CREATE FUNCTION sys.ora_dbms_metadata_trigger_ddl(schema_name text, trigger_name text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
SELECT string_agg(pg_get_triggerdef(t.oid, true), E'\n' ORDER BY t.oid)
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = schema_name
  AND t.tgname IN (trigger_name, upper(trigger_name), lower(trigger_name))
  AND NOT t.tgisinternal
$$;

-- ---------------------------------------------------------------------
-- dispatcher: existence check + error semantics + type dispatch
-- ---------------------------------------------------------------------

/*
 * sys.ora_dbms_metadata_object_exists
 *
 * Boolean existence probe for one object type in one schema.  Used by the
 * dispatcher before it raises ORA-31603, keeping the catalog probing in
 * one place.  Mirrors the same relkind/name rules as the DDL builders
 * above, so a "found" object is always renderable.
 */
CREATE FUNCTION sys.ora_dbms_metadata_object_exists(object_type text, schema_name text, object_name text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
SELECT CASE upper(object_type)
    WHEN 'TABLE' THEN EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = schema_name
          AND c.relname IN (object_name, upper(object_name), lower(object_name))
          AND c.relkind IN ('r', 'p'))
    WHEN 'VIEW' THEN EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = schema_name
          AND c.relname IN (object_name, upper(object_name), lower(object_name))
          AND c.relkind = 'v')
    WHEN 'MATERIALIZED VIEW' THEN EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = schema_name
          AND c.relname IN (object_name, upper(object_name), lower(object_name))
          AND c.relkind = 'm')
    WHEN 'SEQUENCE' THEN EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = schema_name
          AND c.relname IN (object_name, upper(object_name), lower(object_name))
          AND c.relkind = 'S')
    WHEN 'INDEX' THEN EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = schema_name
          AND c.relname IN (object_name, upper(object_name), lower(object_name))
          AND c.relkind = 'i'
          AND NOT EXISTS (SELECT 1 FROM pg_constraint cc WHERE cc.conindid = c.oid))
    WHEN 'FUNCTION' THEN EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = schema_name
          AND p.proname IN (object_name, upper(object_name), lower(object_name))
          AND p.prokind = 'f')
    WHEN 'PROCEDURE' THEN EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = schema_name
          AND p.proname IN (object_name, upper(object_name), lower(object_name))
          AND p.prokind = 'p')
    WHEN 'TRIGGER' THEN EXISTS (
        SELECT 1 FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = schema_name
          AND t.tgname IN (object_name, upper(object_name), lower(object_name))
          AND NOT t.tgisinternal)
    ELSE false
END
$$;

/*
 * sys.ora_dbms_metadata_get_ddl - the GET_DDL engine.
 *
 * Normalizes the arguments, validates them, resolves the default schema,
 * probes existence (raising ORA-31603 when the object is missing) and
 * dispatches to the type specific builder.  Raised messages use Oracle's
 * ORA-31600 / ORA-31603 texts.
 */
CREATE FUNCTION sys.ora_dbms_metadata_get_ddl(object_type text,
                                              name text,
                                              schema text DEFAULT NULL)
RETURNS sys.clob
LANGUAGE plisql
AS $$
DECLARE
    v_objtype text := upper(object_type);
    v_schema  text := schema;
BEGIN
    IF object_type IS NULL OR object_type = '' THEN
        RAISE EXCEPTION 'ORA-31600: invalid input value for parameter OBJECT_TYPE in function GET_DDL';
    END IF;
    IF name IS NULL OR name = '' THEN
        RAISE EXCEPTION 'ORA-31600: invalid input value for parameter NAME in function GET_DDL';
    END IF;
    IF v_schema IS NULL OR v_schema = '' THEN
        SELECT current_schema() INTO v_schema;
    END IF;
    IF v_schema IS NULL THEN
        RAISE EXCEPTION 'ORA-31600: invalid input value for parameter SCHEMA in function GET_DDL';
    END IF;
    IF v_objtype NOT IN ('TABLE', 'VIEW', 'MATERIALIZED VIEW', 'SEQUENCE',
                         'INDEX', 'FUNCTION', 'PROCEDURE', 'TRIGGER') THEN
        RAISE EXCEPTION 'ORA-31600: invalid input value for parameter OBJECT_TYPE in function GET_DDL (unsupported object type "%")',
            object_type;
    END IF;
    IF NOT sys.ora_dbms_metadata_object_exists(v_objtype, v_schema, name) THEN
        RAISE EXCEPTION 'ORA-31603: object "%"."%" of type "%" does not exist',
            replace(sys.ora_case_trans(v_schema)::text, '"', '""'),
            replace(sys.ora_case_trans(name)::text, '"', '""'),
            v_objtype;
    END IF;

    IF v_objtype = 'TABLE' THEN
        RETURN sys.ora_dbms_metadata_table_ddl(v_schema, name)::sys.clob;
    ELSIF v_objtype = 'VIEW' THEN
        RETURN sys.ora_dbms_metadata_view_ddl(v_schema, name)::sys.clob;
    ELSIF v_objtype = 'MATERIALIZED VIEW' THEN
        RETURN sys.ora_dbms_metadata_matview_ddl(v_schema, name)::sys.clob;
    ELSIF v_objtype = 'SEQUENCE' THEN
        RETURN sys.ora_dbms_metadata_sequence_ddl(v_schema, name)::sys.clob;
    ELSIF v_objtype = 'INDEX' THEN
        RETURN sys.ora_dbms_metadata_index_ddl(v_schema, name)::sys.clob;
    ELSIF v_objtype = 'FUNCTION' THEN
        RETURN sys.ora_dbms_metadata_function_ddl(v_schema, name)::sys.clob;
    ELSIF v_objtype = 'PROCEDURE' THEN
        RETURN sys.ora_dbms_metadata_procedure_ddl(v_schema, name)::sys.clob;
    ELSIF v_objtype = 'TRIGGER' THEN
        RETURN sys.ora_dbms_metadata_trigger_ddl(v_schema, name)::sys.clob;
    END IF;

    RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------
-- public package
-- ---------------------------------------------------------------------

/*
 * DBMS_METADATA (Oracle PL/SQL Packages and Types Reference §60).
 *
 * MVP supplies GET_DDL; the open/fetch iteration API (OPEN, FETCH_CLOB,
 * CLOSE), XML flavours (GET_XML, SET_XML, PARSE_XML) and transform
 * management (ADD_TRANSFORM, SET_TRANSFORM_PARAM, SET_REMAP_PARAM,
 * DELETE_TRANSFORM) are intentionally out of scope for now.
 */
CREATE OR REPLACE PACKAGE sys.dbms_metadata IS
    FUNCTION get_ddl(object_type IN VARCHAR2,
                     name        IN VARCHAR2,
                     schema      IN VARCHAR2 DEFAULT NULL) RETURN CLOB;
END dbms_metadata;

CREATE OR REPLACE PACKAGE BODY sys.dbms_metadata IS
    FUNCTION get_ddl(object_type IN VARCHAR2,
                     name        IN VARCHAR2,
                     schema      IN VARCHAR2 DEFAULT NULL) RETURN CLOB IS
    BEGIN
        RETURN sys.ora_dbms_metadata_get_ddl(object_type, name, schema);
    END;
END dbms_metadata;