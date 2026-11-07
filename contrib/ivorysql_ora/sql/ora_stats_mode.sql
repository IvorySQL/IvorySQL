--
-- ora_stats_mode.sql: test Oracle-compatible STATS_MODE aggregate function
--

CREATE TABLE stats_mode_test (
    deptno   INTEGER,
    sal      NUMBER(10,2),
    job      VARCHAR2(10),
    hiredate DATE
);
INSERT INTO stats_mode_test VALUES (10, 1300, 'CLERK',   DATE '2026-01-01');
INSERT INTO stats_mode_test VALUES (10, 2450, 'MANAGER', DATE '2026-01-01');
INSERT INTO stats_mode_test VALUES (10, 2450, 'CLERK',   DATE '2026-02-01');
INSERT INTO stats_mode_test VALUES (20, 3000, 'ANALYST', DATE '2026-03-01');
INSERT INTO stats_mode_test VALUES (20, 3000, 'ANALYST', NULL);
INSERT INTO stats_mode_test VALUES (20, 1100, 'CLERK',   NULL);
INSERT INTO stats_mode_test VALUES (30, NULL, NULL,      NULL);

-- Most frequent value for NUMBER, VARCHAR2 and DATE arguments
SELECT STATS_MODE(sal), STATS_MODE(job), STATS_MODE(hiredate)
FROM stats_mode_test;

-- The result has the same data type as the argument
SELECT pg_typeof(STATS_MODE(sal)), pg_typeof(STATS_MODE(job)),
       pg_typeof(STATS_MODE(hiredate))
FROM stats_mode_test;

-- GROUP BY usage
SELECT deptno, STATS_MODE(sal), STATS_MODE(job)
FROM stats_mode_test GROUP BY deptno ORDER BY deptno;

-- NULLs are ignored, even when NULL is the most frequent value
SELECT STATS_MODE(hiredate) FROM stats_mode_test WHERE deptno = 20;

-- When several values are equally frequent, the smallest one is returned
SELECT STATS_MODE(x)
FROM (SELECT 2 x FROM dual UNION ALL SELECT 1 FROM dual
      UNION ALL SELECT 2 FROM dual UNION ALL SELECT 1 FROM dual) s;

-- All-NULL input returns NULL
SELECT STATS_MODE(sal) IS NULL FROM stats_mode_test WHERE deptno = 30;

-- Empty input returns NULL
SELECT STATS_MODE(sal) IS NULL FROM stats_mode_test WHERE deptno = 99;

-- Analytic form
SELECT deptno, sal, STATS_MODE(sal) OVER (PARTITION BY deptno) AS mode_sal
FROM stats_mode_test ORDER BY deptno, sal;

-- Works in PG mode too
SET ivorysql.compatible_mode = pg;
SELECT sys.stats_mode(job) FROM stats_mode_test;
RESET ivorysql.compatible_mode;

DROP TABLE stats_mode_test;
