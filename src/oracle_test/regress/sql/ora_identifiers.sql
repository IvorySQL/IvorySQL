--
-- Test Oracle-compatible identifier syntax
-- Issue #1002: Support # character in unquoted identifiers
--

-- Test # in column names
CREATE TABLE test_hash_ident (
    statistic# INT,
    col#1 INT,
    my#column INT
);

INSERT INTO test_hash_ident VALUES (1, 2, 3);
SELECT statistic#, col#1, my#column FROM test_hash_ident;

-- Test # in table names
CREATE TABLE test#table (id INT);
INSERT INTO test#table VALUES (100);
SELECT * FROM test#table;
DROP TABLE test#table;

-- Test $ in identifiers (already supported, verify no regression)
CREATE TABLE test$table (col$1 INT);
INSERT INTO test$table VALUES (200);
SELECT col$1 FROM test$table;
DROP TABLE test$table;

-- Test mixed special characters
CREATE TABLE test_mixed (
    col_1 INT,
    col$2 INT,
    col#3 INT,
    col_$#4 INT
);
INSERT INTO test_mixed VALUES (1, 2, 3, 4);
SELECT col_1, col$2, col#3, col_$#4 FROM test_mixed;
DROP TABLE test_mixed;

-- Verify # XOR operator still works (both with and without spaces)
SELECT 5 # 3 AS xor_result;
SELECT 5#3 AS xor_no_spaces;
SELECT B'1010' # B'1100' AS bit_xor;

-- Verify JSON path operators work without spaces (issue was potential conflict)
SELECT '{"a":1}'::json#>'{a}' AS json_path_no_space;
SELECT '{"b":2}'::jsonb#>>'{b}' AS jsonb_path_no_space;

-- Clean up
DROP TABLE test_hash_ident;
