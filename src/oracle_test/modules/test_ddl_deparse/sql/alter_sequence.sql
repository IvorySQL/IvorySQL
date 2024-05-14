--
-- ALTER_SEQUENCE
--

ALTER SEQUENCE fkey_table_seq
  MINVALUE 10
  RESTART START WITH 20
  NOCACHE
  NOCYCLE;

ALTER SEQUENCE fkey_table_seq
  RENAME TO fkey_table_seq_renamed;

ALTER SEQUENCE fkey_table_seq_renamed
  SET SCHEMA foo;
