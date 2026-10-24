--
-- DBMS_ROWID
--
-- Regression tests for Oracle-compatible DBMS_ROWID package:
--   - Package constants: rowid_type_restricted, rowid_type_extended,
--                        rowid_is_valid, rowid_is_invalid
--   - ROWID_CREATE (Extended & Restricted)
--   - ROWID_TYPE
--   - ROWID_OBJECT
--   - ROWID_RELATIVE_FNO
--   - ROWID_BLOCK_NUMBER
--   - ROWID_ROW_NUMBER
--   - ROWID_TO_ABSOLUTE_FNO
--   - ROWID_TO_EXTENDED
--   - ROWID_TO_RESTRICTED
--   - ROWID_VERIFY
--   - Boundary checks, error conditions, and catalog ACL checks
--

-- Package constants
SELECT dbms_rowid.rowid_type_restricted;
SELECT dbms_rowid.rowid_type_extended;
SELECT dbms_rowid.rowid_is_valid;
SELECT dbms_rowid.rowid_is_invalid;

-- Extended ROWID creation
-- obj=73842, rfile=4, block=12039, row=15
SELECT dbms_rowid.rowid_create(dbms_rowid.rowid_type_extended, 73842, 4, 12039, 15);

-- Restricted ROWID creation
SELECT dbms_rowid.rowid_create(dbms_rowid.rowid_type_restricted, 0, 4, 12039, 15);

-- Extended ROWID parsing
SELECT dbms_rowid.rowid_type('AAASByAAEAAAC8HAAP');
SELECT dbms_rowid.rowid_object('AAASByAAEAAAC8HAAP');
SELECT dbms_rowid.rowid_relative_fno('AAASByAAEAAAC8HAAP');
SELECT dbms_rowid.rowid_block_number('AAASByAAEAAAC8HAAP');
SELECT dbms_rowid.rowid_row_number('AAASByAAEAAAC8HAAP');
SELECT dbms_rowid.rowid_to_absolute_fno('AAASByAAEAAAC8HAAP');

-- Restricted ROWID parsing (with dots)
SELECT dbms_rowid.rowid_type('00002F07.000F.0004');
SELECT dbms_rowid.rowid_object('00002F07.000F.0004');
SELECT dbms_rowid.rowid_relative_fno('00002F07.000F.0004');
SELECT dbms_rowid.rowid_block_number('00002F07.000F.0004');
SELECT dbms_rowid.rowid_row_number('00002F07.000F.0004');
SELECT dbms_rowid.rowid_to_absolute_fno('00002F07.000F.0004');

-- Restricted ROWID parsing (16 hex chars without dots)
SELECT dbms_rowid.rowid_type('00002F07000F0004');
SELECT dbms_rowid.rowid_block_number('00002F07000F0004');
SELECT dbms_rowid.rowid_row_number('00002F07000F0004');
SELECT dbms_rowid.rowid_relative_fno('00002F07000F0004');

-- Conversions
-- Restricted to Extended
SELECT dbms_rowid.rowid_to_extended('00002F07.000F.0004');

-- Extended to Extended (idempotent)
SELECT dbms_rowid.rowid_to_extended('AAASByAAEAAAC8HAAP');

-- Extended to Restricted
SELECT dbms_rowid.rowid_to_restricted('AAASByAAEAAAC8HAAP');

-- Restricted to Restricted (idempotent)
SELECT dbms_rowid.rowid_to_restricted('00002F07.000F.0004');

-- Verification
SELECT dbms_rowid.rowid_verify('AAASByAAEAAAC8HAAP');
SELECT dbms_rowid.rowid_verify('00002F07.000F.0004');
SELECT dbms_rowid.rowid_verify('INVALID_ROWID');
SELECT dbms_rowid.rowid_verify('');

-- Zero / boundary value ROWIDs
SELECT dbms_rowid.rowid_create(1, 0, 0, 0, 0);
SELECT dbms_rowid.rowid_object('AAAAAAAAAAAAAAAAAA');
SELECT dbms_rowid.rowid_relative_fno('AAAAAAAAAAAAAAAAAA');
SELECT dbms_rowid.rowid_block_number('AAAAAAAAAAAAAAAAAA');
SELECT dbms_rowid.rowid_row_number('AAAAAAAAAAAAAAAAAA');

-- Out of range / invalid input errors
SELECT dbms_rowid.rowid_create(999, 1, 1, 1, 1);
SELECT dbms_rowid.rowid_create(1, -1, 1, 1, 1);
SELECT dbms_rowid.rowid_create(0, 0, -1, 1, 1);
SELECT dbms_rowid.rowid_type('TOO_SHORT');
SELECT dbms_rowid.rowid_object('INVALID_CHARACTERS!!');

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_rowid_rowid_create',
                     'dbms_rowid_rowid_type',
                     'dbms_rowid_rowid_object',
                     'dbms_rowid_rowid_relative_fno',
                     'dbms_rowid_rowid_block_number',
                     'dbms_rowid_rowid_row_number',
                     'dbms_rowid_rowid_to_absolute_fno',
                     'dbms_rowid_rowid_to_extended',
                     'dbms_rowid_rowid_to_restricted',
                     'dbms_rowid_rowid_verify')
 ORDER BY p.proname;
