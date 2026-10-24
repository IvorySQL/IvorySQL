--
-- Materialized views and ALTER TABLE ... ALTER COLUMN ... TYPE in Oracle mode
--
-- A materialized view owns a _RETURN rule just like a plain view, but unlike a
-- plain view it also owns the rows that rule produced.  Invalidating such a
-- relation when a column type changes used to turn the materialized view into
-- a force view, which drops its columns and leaves it unable to return its
-- rows.  The type change cannot rewrite the stored rows, so it has to be
-- refused here, just as it is in PostgreSQL mode.
--
SET ivorysql.compatible_mode TO ORACLE;
SHOW ivorysql.compatible_mode;

CREATE TABLE ora_mv_alter_t (a char(20), b int, c int);
INSERT INTO ora_mv_alter_t VALUES ('one', 1, 10);
CREATE MATERIALIZED VIEW ora_mv_alter_mv AS SELECT a, b FROM ora_mv_alter_t;

SELECT count(*) AS rows_before FROM ora_mv_alter_mv;

-- ora_mv_alter_mv depends on column a, so this is refused ...
ALTER TABLE ora_mv_alter_t ALTER COLUMN a TYPE char(25);

-- ... and the materialized view is left untouched and usable.
SELECT relkind, relispopulated FROM pg_class WHERE relname = 'ora_mv_alter_mv';
SELECT a, b FROM ora_mv_alter_mv;
REFRESH MATERIALIZED VIEW ora_mv_alter_mv;
SELECT a, b FROM ora_mv_alter_mv;

-- A column that no materialized view depends on can still be retyped.
ALTER TABLE ora_mv_alter_t ALTER COLUMN c TYPE bigint;
SELECT count(*) AS rows_after_unrelated_alter FROM ora_mv_alter_mv;

DROP MATERIALIZED VIEW ora_mv_alter_mv;
DROP TABLE ora_mv_alter_t;