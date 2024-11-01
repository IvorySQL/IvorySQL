--
-- ALTER_SEQUENCE
--

ALTER SEQUENCE fkey_table_seq
  MINVALUE 10
  START WITH 20
  CACHE 1
  NOCYCLE;

ALTER SEQUENCE fkey_table_seq
  RENAME TO fkey_table_seq_renamed;

ALTER SEQUENCE fkey_table_seq_renamed
  SET SCHEMA foo;
