/*-------------------------------------------------------------------------
 *
 * oracle_compat_views.sql
 *    Oracle compatible USER_CONS_COLUMNS view for IvorySQL
 *
 *-------------------------------------------------------------------------
 */

CREATE OR REPLACE VIEW public.user_cons_columns AS
SELECT
    current_user::varchar(128) AS owner,
    tc.table_name::varchar(128) AS table_name,
    tc.constraint_name::varchar(128) AS constraint_name,
    kcu.column_name::varchar(128) AS column_name,
    CASE tc.constraint_type
        WHEN 'PRIMARY KEY' THEN 'P'
        WHEN 'UNIQUE' THEN 'U'
        WHEN 'FOREIGN KEY' THEN 'F'
        WHEN 'CHECK' THEN 'C'
        ELSE tc.constraint_type
    END AS constraint_type,
    kcu.ordinal_position AS position,
    CASE a.data_type
        WHEN 'numeric' THEN 'NUMBER'
        WHEN 'character varying' THEN 'VARCHAR2'
        WHEN 'national character varying' THEN 'NVARCHAR2'
        WHEN 'character' THEN 'CHAR'
        WHEN 'national character' THEN 'NCHAR'
        WHEN 'timestamp without time zone' THEN 'DATE'
        WHEN 'timestamp with time zone' THEN 'TIMESTAMP WITH TIME ZONE'
        WHEN 'integer' THEN 'NUMBER(10)'
        WHEN 'bigint' THEN 'NUMBER(19)'
        WHEN 'smallint' THEN 'NUMBER(5)'
        WHEN 'boolean' THEN 'NUMBER(1)'
        ELSE a.data_type
    END AS data_type
FROM
    information_schema.table_constraints tc
JOIN
    information_schema.key_column_usage kcu
ON
    tc.constraint_name = kcu.constraint_name
    AND tc.table_name = kcu.table_name
    AND tc.table_schema = kcu.table_schema
LEFT JOIN
    information_schema.columns a
ON
    a.table_name = tc.table_name
    AND a.column_name = kcu.column_name
    AND a.table_schema = tc.table_schema
WHERE
    tc.table_schema = current_schema()
ORDER BY
    tc.table_name, tc.constraint_name, kcu.ordinal_position;

GRANT SELECT ON public.user_cons_columns TO public;