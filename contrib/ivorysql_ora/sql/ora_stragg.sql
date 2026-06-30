--
-- ora_stragg.sql: test Oracle-compatible STRAGG aggregate function
--

-- Basic usage
CREATE TABLE stragg_test (dept TEXT, name TEXT);
INSERT INTO stragg_test VALUES ('HR', 'Alice');
INSERT INTO stragg_test VALUES ('HR', 'Bob');
INSERT INTO stragg_test VALUES ('HR', 'Carol');
INSERT INTO stragg_test VALUES ('IT', 'Dave');
INSERT INTO stragg_test VALUES ('IT', 'Eve');

-- Simple aggregation (sort result for determinism)
SELECT sys.stragg(name ORDER BY name) FROM stragg_test WHERE dept = 'HR';

-- GROUP BY usage (sort for determinism)
SELECT dept, sys.stragg(name ORDER BY name) FROM stragg_test GROUP BY dept ORDER BY dept;

-- NULL handling: NULLs are ignored
INSERT INTO stragg_test VALUES ('HR', NULL);
SELECT sys.stragg(name ORDER BY name) FROM stragg_test WHERE dept = 'HR';

-- All-NULL input returns NULL
SELECT sys.stragg(name) IS NULL FROM stragg_test WHERE name IS NULL;

-- Empty set returns NULL
SELECT sys.stragg(name) IS NULL FROM stragg_test WHERE dept = 'NONE';

-- Single value (no comma)
SELECT sys.stragg(name) FROM stragg_test WHERE dept = 'IT' AND name = 'Dave';

-- Works in PG mode too
SET ivorysql.compatible_mode = pg;
SELECT sys.stragg(name ORDER BY name) FROM stragg_test WHERE dept = 'HR';
RESET ivorysql.compatible_mode;

DROP TABLE stragg_test;
