--
-- DBA_TAB_COMMENTS / DBA_COL_COMMENTS
--
SET IVORYSQL.COMPATIBLE_MODE TO ORACLE;

CREATE TABLE test_dba_comments (id INT, name VARCHAR2(10));
COMMENT ON TABLE test_dba_comments IS 'table comment';
COMMENT ON COLUMN test_dba_comments.id IS 'id comment';

CREATE VIEW test_dba_comments_v AS SELECT * FROM test_dba_comments;
COMMENT ON VIEW test_dba_comments_v IS 'view comment';
COMMENT ON COLUMN test_dba_comments_v.name IS 'view name comment';

SELECT table_name, table_type, comments
FROM SYS.DBA_TAB_COMMENTS
WHERE owner = SYS.ORA_CASE_TRANS(CURRENT_USER::VARCHAR2)
  AND table_name IN ('TEST_DBA_COMMENTS', 'TEST_DBA_COMMENTS_V')
ORDER BY table_name;

SELECT table_name, column_name, comments
FROM SYS.DBA_COL_COMMENTS
WHERE owner = SYS.ORA_CASE_TRANS(CURRENT_USER::VARCHAR2)
  AND table_name IN ('TEST_DBA_COMMENTS', 'TEST_DBA_COMMENTS_V')
ORDER BY table_name, column_name;

DROP VIEW test_dba_comments_v;
DROP TABLE test_dba_comments;
