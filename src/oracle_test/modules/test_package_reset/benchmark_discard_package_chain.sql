-- Reproduce the synthetic worst case for DISCARD PACKAGE dependency cleanup.
--
-- Run this in an Oracle-compatible database from an IvorySQL psql client:
--
--   psql -X -v ON_ERROR_STOP=1 -v package_count=1600 \
--     -f benchmark_discard_package_chain.sql DATABASE
--
-- Repeat with increasing package_count values (for example 400, 800, 1600)
-- against the base and patched revisions.  Only the timed DISCARD PACKAGE
-- statement is part of the measurement.  Package bodies are created in
-- reverse order while each body depends on its predecessor, deliberately
-- producing the order that maximizes repeated scans in the old algorithm.

\set ON_ERROR_STOP 1
\if :{?package_count}
\else
\set package_count 800
\endif

SET client_min_messages = warning;

SELECT format(
           'CREATE PACKAGE %1$I AS FUNCTION value RETURN NUMBER; END %1$I;',
           'discard_bench_pkg_' || package_no)
FROM generate_series(1, :package_count) AS package_no
\gexec

SELECT CASE
           WHEN package_no = 1 THEN
               format(
                   'CREATE PACKAGE BODY %1$I AS '
                   'FUNCTION value RETURN NUMBER AS BEGIN RETURN 1; END; '
                   'END %1$I;',
                   'discard_bench_pkg_' || package_no)
           ELSE
               format(
                   'CREATE PACKAGE BODY %1$I AS '
                   'FUNCTION value RETURN NUMBER AS BEGIN RETURN %2$I.value(); END; '
                   'END %1$I;',
                   'discard_bench_pkg_' || package_no,
                   'discard_bench_pkg_' || (package_no - 1))
       END
FROM generate_series(:package_count, 1, -1) AS package_no
\gexec

-- Compile and cache every package without recursing through the whole chain.
\o /dev/null
SELECT format('SELECT %I.value() FROM dual;',
              'discard_bench_pkg_' || package_no)
FROM generate_series(1, :package_count) AS package_no
\gexec
\o

\echo Measuring DISCARD PACKAGE with :package_count cached packages
\timing on
DISCARD PACKAGE;
\timing off

SELECT format('DROP PACKAGE %I;', 'discard_bench_pkg_' || package_no)
FROM generate_series(:package_count, 1, -1) AS package_no
\gexec
