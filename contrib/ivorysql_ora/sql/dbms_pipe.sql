--
-- DBMS_PIPE
--
-- Regression tests for Oracle-compatible DBMS_PIPE package:
--   - Package constants
--   - CREATE_PIPE
--   - PACK_MESSAGE / SEND_MESSAGE
--   - RECEIVE_MESSAGE / UNPACK_MESSAGE
--   - PURGE procedure
--   - RESET_BUFFER procedure
--   - REMOVE_PIPE function
--   - Error handling (NULL parameter checks, buffer underflow)
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- Package constants
SELECT dbms_pipe.success;
SELECT dbms_pipe.timeout;
SELECT dbms_pipe.overflow;
SELECT dbms_pipe.interrupt;

-- Create pipe
SELECT dbms_pipe.create_pipe('test_pipe_1', 8192, false);

-- Verify definition in catalog
SELECT pipename, maxsize, is_private FROM sys.pipe_definitions WHERE pipename = 'test_pipe_1';

-- Pack and send message
CALL dbms_pipe.pack_message('first_pipe_message');
CALL dbms_pipe.pack_message('second_pipe_message');
SELECT dbms_pipe.send_message('test_pipe_1');

-- Receive and unpack message
SELECT dbms_pipe.receive_message('test_pipe_1');

DO $$
DECLARE
    msg1 VARCHAR2(100);
    msg2 VARCHAR2(100);
BEGIN
    dbms_pipe.unpack_message(msg1);
    dbms_pipe.unpack_message(msg2);
    RAISE NOTICE 'Unpacked items: % and %', msg1, msg2;
END;
$$;

-- Receive on empty pipe returns timeout (1)
SELECT dbms_pipe.receive_message('test_pipe_1', 0);

-- Reset buffer
CALL dbms_pipe.reset_buffer();

-- Purge pipe
CALL dbms_pipe.pack_message('to_be_purged');
SELECT dbms_pipe.send_message('test_pipe_1');
CALL dbms_pipe.purge('test_pipe_1');
SELECT COUNT(*) FROM sys.pipe_messages WHERE pipename = 'test_pipe_1';

-- Remove pipe
SELECT dbms_pipe.remove_pipe('test_pipe_1');
SELECT COUNT(*) FROM sys.pipe_definitions WHERE pipename = 'test_pipe_1';

-- Error handling: NULL parameter checks
SELECT sys.dbms_pipe_create_pipe_internal(NULL, 4096, false);
SELECT sys.dbms_pipe_send_message_internal(NULL, 100, 4096);
SELECT sys.dbms_pipe_receive_message_internal(NULL, 100);
SELECT sys.dbms_pipe_purge_internal(NULL);
SELECT sys.dbms_pipe_remove_pipe_internal(NULL);

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_pipe_create_pipe_internal',
                     'dbms_pipe_pack_message_text_internal',
                     'dbms_pipe_unpack_message_text_internal',
                     'dbms_pipe_send_message_internal',
                     'dbms_pipe_receive_message_internal',
                     'dbms_pipe_reset_buffer_internal',
                     'dbms_pipe_purge_internal',
                     'dbms_pipe_remove_pipe_internal')
 ORDER BY p.proname;
