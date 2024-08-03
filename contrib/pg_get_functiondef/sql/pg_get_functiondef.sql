CREATE EXTENSION pg_get_functiondef;

SELECT pg_get_functiondef(1, 2, 3);
SELECT * FROM pg_get_functiondef(1, 2, 3);
SELECT pg_get_functiondef('sum');
SELECT * FROM pg_get_functiondef('sum');
SELECT pg_get_functiondef('pg_get_functiondef');
SELECT * FROM pg_get_functiondef('pg_get_functiondef');
SELECT pg_get_functiondef('char_length', 'substring');
SELECT * FROM pg_get_functiondef('char_length', 'substring');