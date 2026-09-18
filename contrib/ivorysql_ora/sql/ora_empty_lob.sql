--
-- EMPTY_CLOB / EMPTY_BLOB
--
-- Oracle-compatible LOB constructors: return a zero-length, non-NULL LOB
-- value.  Oracle treats the empty string as NULL, so these constructors are
-- the only way to initialize a LOB that is not NULL.
--
-- Semantics verified against Oracle 23ai Free.
--

-- constructors return non-NULL zero-length values
SELECT empty_clob() IS NULL AS clob_is_null;
SELECT empty_blob() IS NULL AS blob_is_null;
SELECT length(empty_clob()) AS clob_len;
SELECT octet_length(empty_blob()) AS blob_len;

-- usable for nclob targets as well
SELECT length(empty_clob()::nclob) AS nclob_len;

-- concatenation yields a non-NULL, non-empty value
SELECT '[' || empty_clob() || ']' AS bracketed;
SELECT length(empty_clob() || 'abc') AS concat_len;

-- stored values are not NULL and compare accordingly
CREATE TABLE lob_empty_test (id int, c clob, nc nclob, b blob);
INSERT INTO lob_empty_test VALUES (1, empty_clob(), empty_clob(), empty_blob());

SELECT id, c IS NULL AS c_is_null, nc IS NULL AS nc_is_null, b IS NULL AS b_is_null
FROM lob_empty_test WHERE id = 1;

SELECT id, length(c) AS c_len, length(nc) AS nc_len, octet_length(b) AS b_len
FROM lob_empty_test WHERE id = 1;

SELECT count(*) AS not_null_rows FROM lob_empty_test WHERE c IS NOT NULL;

-- the plain empty string is NULL, so it does not produce an empty LOB
INSERT INTO lob_empty_test VALUES (2, '', '', '');
SELECT id, c IS NULL AS c_is_null FROM lob_empty_test WHERE id = 2;

-- assigning the constructor clears the LOB to empty (not NULL)
UPDATE lob_empty_test SET c = empty_clob() WHERE id = 2;
SELECT id, c IS NULL AS c_is_null, length(c) AS c_len
FROM lob_empty_test WHERE id = 2;

DROP TABLE lob_empty_test;
