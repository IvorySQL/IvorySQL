--
-- crypt() and gen_salt(): crypt-des
--

SET ivorysql.enable_emptystring_to_null to off;
SELECT crypt('', 'NB');

SELECT crypt('foox', 'NB');

-- We are supposed to pass in a 2-character salt.
-- error since salt is too short:
SELECT crypt('password', 'a');

CREATE TABLE ctest (data text, res text, salt text);
INSERT INTO ctest VALUES ('password', '', '');

UPDATE ctest SET salt = gen_salt('des');
UPDATE ctest SET res = crypt(data, salt);
SELECT res = crypt(data, res) AS "worked"
FROM ctest;
RESET ivorysql.enable_emptystring_to_null;

DROP TABLE ctest;
