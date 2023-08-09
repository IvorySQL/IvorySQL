--
-- crypt() and gen_salt(): md5
--

SET ivorysql.enable_emptystring_to_null to off;
SELECT crypt('', '$1$Szzz0yzz');

SELECT crypt('foox', '$1$Szzz0yzz');

CREATE TABLE ctest (data text, res text, salt text);
INSERT INTO ctest VALUES ('password', '', '');

UPDATE ctest SET salt = gen_salt('md5');
UPDATE ctest SET res = crypt(data, salt);
SELECT res = crypt(data, res) AS "worked"
FROM ctest;
RESET ivorysql.enable_emptystring_to_null;

DROP TABLE ctest;
