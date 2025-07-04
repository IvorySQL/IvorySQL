-- TEST CREATE DATABASE
create database gb18030_2022 encoding='gb18030' LC_COLLATE='C' LC_CTYPE ='C' TEMPLATE=template0;
\c gb18030_2022

-- TEST create extension
load 'gb18030_2022';

show server_encoding;
set client_encoding = 'UTF8';
show client_encoding;

-- 1. the character gb18030 map to unicode being changed：
-- non-changed character：
select convert_to('中国', 'GB18030');
 
--insert character the conversion being changed beteen gb18030 and unicode
create table tb_test(id int, content text);
 
insert into tb_test (id , content)
select 1, convert_from('\xA8BC', 'GB18030');
 
insert into tb_test (id , content)
select 2, convert_from('\xA6D9', 'GB18030');
 
insert into tb_test (id , content)
select 3, convert_from('\xA6DA', 'GB18030');
 
insert into tb_test (id , content)
select 4, convert_from('\xA6DB', 'GB18030');
 
insert into tb_test (id , content)
select 5, convert_from('\xA6DC', 'GB18030');
 
insert into tb_test (id , content)
select 6, convert_from('\xA6DD', 'GB18030');
 
insert into tb_test (id , content)
select 7, convert_from('\xA6DE', 'GB18030');
 
insert into tb_test (id , content)
select 8, convert_from('\xA6DF', 'GB18030');
 
insert into tb_test (id , content)
select 9, convert_from('\xA6EC', 'GB18030');
 
insert into tb_test (id , content)
select 10, convert_from('\xA6ED', 'GB18030');
 
insert into tb_test (id , content)
select 11, convert_from('\xA6F3', 'GB18030');
 
insert into tb_test (id , content)
select 12, convert_from('\xFE59', 'GB18030');
 
insert into tb_test (id , content)
select 13, convert_from('\xFE61', 'GB18030');
 
insert into tb_test (id , content)
select 14, convert_from('\xFE66', 'GB18030');
 
insert into tb_test (id , content)
select 15, convert_from('\xFE67', 'GB18030');
 
insert into tb_test (id , content)
select 16, convert_from('\xFE6D', 'GB18030');
 
insert into tb_test (id , content)
select 17, convert_from('\xFE7E', 'GB18030');
 
insert into tb_test (id , content)
select 18, convert_from('\xFE90', 'GB18030');
 
insert into tb_test (id , content)
select 19, convert_from('\xFEA0', 'GB18030');
 
insert into tb_test (id , content) select 20, convert_from('\x8135F437', 'GB18030');
insert into tb_test (id , content) select 21, convert_from('\x84318236', 'GB18030');
insert into tb_test (id , content) select 22, convert_from('\x84318238', 'GB18030');
insert into tb_test (id , content) select 23, convert_from('\x84318237', 'GB18030');
insert into tb_test (id , content) select 24, convert_from('\x84318239', 'GB18030');
insert into tb_test (id , content) select 25, convert_from('\x84318330', 'GB18030');
insert into tb_test (id , content) select 26, convert_from('\x84318331', 'GB18030');
insert into tb_test (id , content) select 27, convert_from('\x84318332', 'GB18030');
insert into tb_test (id , content) select 28, convert_from('\x84318333', 'GB18030');
insert into tb_test (id , content) select 29, convert_from('\x84318334', 'GB18030');
insert into tb_test (id , content) select 30, convert_from('\x84318335', 'GB18030');
insert into tb_test (id , content) select 31, convert_from('\x82359037', 'GB18030');
insert into tb_test (id , content) select 32, convert_from('\x82359038', 'GB18030');
insert into tb_test (id , content) select 33, convert_from('\x82359039', 'GB18030');
insert into tb_test (id , content) select 34, convert_from('\x82359130', 'GB18030');
insert into tb_test (id , content) select 35, convert_from('\x82359131', 'GB18030');
insert into tb_test (id , content) select 36, convert_from('\x82359132', 'GB18030');
insert into tb_test (id , content) select 37, convert_from('\x82359133', 'GB18030');
insert into tb_test (id , content) select 38, convert_from('\x82359134', 'GB18030');

--display these character 
select * from tb_test order by id;
--display gb18030 coding
select convert_to(content, 'GB18030') from tb_test order by id;
--convert to utf8 encoding
select convert_to(content, 'utf8') from tb_test order by id;


--2. new character in gb18030 test

select convert_from('\x95328236', 'GB18030');
select convert_from('\x9835F336', 'GB18030');

select convert_from('\x82358F33', 'GB18030');
select convert_from('\x82359636', 'GB18030');

select convert_from('\x9835F738', 'GB18030');
select convert_from('\x98399E36', 'GB18030');

select convert_from('\x98399F38', 'GB18030');
select convert_from('\x9839B539', 'GB18030');

select convert_from('\x9839B632', 'GB18030');
select convert_from('\x9933FE33', 'GB18030');

select convert_from('\x99348138', 'GB18030');
select convert_from('\x9939F730', 'GB18030');

select convert_from('\x81398B32', 'GB18030');
select convert_from('\x8139A035', 'GB18030');

select convert_from('\x8134F932', 'GB18030');
select convert_from('\x81358437', 'GB18030');

select convert_from('\x81358B32', 'GB18030');
select convert_from('\x81359933', 'GB18030');

select convert_from('\x82369535', 'GB18030');
select convert_from('\x82369A32', 'GB18030');

select convert_from('\x9034C538', 'GB18030');
select convert_from('\x9034C730', 'GB18030');

select convert_from('\x9232C636', 'GB18030');
select convert_from('\x9232D635', 'GB18030');
 
create table in_test(id int, content text);
 
insert into in_test (id , content)
select 1,convert_from('\x95328236', 'GB18030');
 
insert into in_test (id , content)
select 2,convert_from('\x9835F336', 'GB18030');
 
insert into in_test (id , content)
select 3,convert_from('\x82358F33', 'GB18030');
 
insert into in_test (id , content)
select 4,convert_from('\x82359636', 'GB18030');
 
insert into in_test (id , content)
select 5,convert_from('\x9835F738', 'GB18030');
 
insert into in_test (id , content)
select 6,convert_from('\x98399E36', 'GB18030');
 
insert into in_test (id , content)
select 7,convert_from('\x98399F38', 'GB18030');
 
insert into in_test (id , content)
select 8,convert_from('\x9839B539', 'GB18030');
 
insert into in_test (id , content)
select 9,convert_from('\x9839B632', 'GB18030');
 
insert into in_test (id , content)
select 10,convert_from('\x9933FE33', 'GB18030');
 
insert into in_test (id , content)
select 11,convert_from('\x99348138', 'GB18030');
 
insert into in_test (id , content)
select 12,convert_from('\x9939F730', 'GB18030');
 
insert into in_test (id , content)
select 13,convert_from('\x81398B32', 'GB18030');
 
insert into in_test (id , content)
select 14,convert_from('\x8139A035', 'GB18030');
 
insert into in_test (id , content)
select 15,convert_from('\x8134F932', 'GB18030');
 
insert into in_test (id , content)
select 16,convert_from('\x81358437', 'GB18030');
 
insert into in_test (id , content)
select 17,convert_from('\x81358B32', 'GB18030');
 
insert into in_test (id , content)
select 18,convert_from('\x81359933', 'GB18030');
 
insert into in_test (id , content)
select 19,convert_from('\x82369535', 'GB18030');
 
insert into in_test (id , content)
select 20,convert_from('\x82369A32', 'GB18030');
 
insert into in_test (id , content)
select 21,convert_from('\x9034C538', 'GB18030');
 
insert into in_test (id , content)
select 22,convert_from('\x9034C730', 'GB18030');
 
insert into in_test (id , content)
select 23,convert_from('\x9232C636', 'GB18030');
 
insert into in_test (id , content)
select 24,convert_from('\x9232D635', 'GB18030');
 
select * from in_test order by id;
select convert_to(content, 'GB18030') from in_test order by id;
select convert_to(content, 'utf8') from in_test order by id;
 
drop table in_test;
drop table tb_test;


--3. common sql test
create table 表1(id int, 人名 name);
 
insert into 表1(id, 人名) values(1, '小明！');
select * from 表1;
 
alter table 表1 drop 人名;
select * from 表1;
 
alter table 表1 add 学校 text;
insert into 表1(id , 学校) select 2, convert_to('@青岛大学￥', 'GB18030');
select * from 表1;
 
drop table 表1;


--4. no conversion test
select convert('\xFD308130', 'GB18030', 'UTF8');
select convert('\xFE39FE39', 'GB18030', 'UTF8');

--5. character stuff
-- E021-03 character string literals
SELECT 'first line'
' - next line'
	' - third line'
	AS "Three lines to one";
 
-- illegal string continuation syntax
SELECT 'first line'
' - next line' /* this comment is not allowed here */
' - third line'
	AS "Illegal comment within continuation";
 
-- Unicode escapes
SET standard_conforming_strings TO on;
 
SELECT U&'d\0061t\+000061' AS U&"d\0061t\+000061";
SELECT U&'d!0061t\+000061' UESCAPE '!' AS U&"d*0061t\+000061" UESCAPE '*';
 
-- bytea
SET bytea_output TO hex;
SELECT E'\\xDeAdBeEf'::bytea;
SELECT E'\\x De Ad Be Ef '::bytea;
SELECT E'\\xDeAdBeE'::bytea;
SELECT E'\\xDeAdBeEx'::bytea;
SELECT E'\\xDe00BeEf'::bytea;
SELECT E'DeAdBeEf'::bytea;
SELECT E'De\\000dBeEf'::bytea;
SELECT E'De\123dBeEf'::bytea;
SELECT E'De\\123dBeEf'::bytea;
SELECT E'De\\678dBeEf'::bytea;
 
SET bytea_output TO escape;
SELECT E'\\xDeAdBeEf'::bytea;
SELECT E'\\x De Ad Be Ef '::bytea;
SELECT E'\\xDe00BeEf'::bytea;
SELECT E'DeAdBeEf'::bytea;
SELECT E'De\\000dBeEf'::bytea;
SELECT E'De\\123dBeEf'::bytea;
 
SET bytea_output TO hex;
 
SELECT CAST(name 'namefield' AS text) AS "text(name)";
 
-- E021-09 trim function
SELECT TRIM(BOTH FROM '  bunch o blanks  ') = 'bunch o blanks' AS "bunch o blanks";
 
-- E021-06 substring expression
SELECT SUBSTRING('1234567890' FROM 3) = '34567890' AS "34567890";
 
-- PostgreSQL extension to allow using back reference in replace string;
SELECT regexp_replace('1112223333', E'(\\d{3})(\\d{3})(\\d{4})', E'(\\1) \\2-\\3');
 
-- set so we can tell NULL from empty string
\pset null '\\N'
 
-- return all matches from regexp
SELECT regexp_matches('foobarbequebaz', $re$(bar)(beque)$re$);
 
-- split string on regexp
SELECT foo, length(foo) FROM regexp_split_to_table('the quick brown fox jumped over the lazy dog', $re$\s+$re$) AS foo;
SELECT regexp_split_to_array('the quick brown fox jumped over the lazy dog', $re$\s+$re$);
 
-- change NULL-display back
\pset null ''
 
-- E021-11 position expression
SELECT POSITION('4' IN '1234567890') = '4' AS "4";
 
SELECT POSITION('5' IN '1234567890') = '5' AS "5";
 
-- T312 character overlay function
SELECT OVERLAY('abcdef' PLACING '45' FROM 4) AS "abc45f";
 
-- E061-04 like predicate
SELECT 'hawkeye' LIKE 'h%' AS "true";
SELECT 'hawkeye' NOT LIKE 'h%' AS "false";
 
-- unused escape character
SELECT 'hawkeye' LIKE 'h%' ESCAPE '#' AS "true";
SELECT 'hawkeye' NOT LIKE 'h%' ESCAPE '#' AS "false";
 
--
-- test ILIKE (case-insensitive LIKE)
-- Be sure to form every test as an ILIKE/NOT ILIKE pair.
--
 
SELECT 'hawkeye' ILIKE 'h%' AS "true";
SELECT 'hawkeye' NOT ILIKE 'h%' AS "false";


--6. character function
select repeat('中国', 3);
 
select left('中国！number1', 7);
 
select length('中国！number1');
 
select reverse('中国！number1');
 
select md5('中国！number1');
 
-- test strpos
SELECT strpos('abcdef', 'cd') AS "pos_3";
SELECT strpos('abcdef', 'xy') AS "pos_0";
 
SELECT replace('yabadabadoo', 'ba', '123') AS "ya123da123doo";
 
select split_part('joeuser@mydatabase','@',3) AS "empty string";
 
select to_hex(256::bigint*256::bigint*256::bigint*256::bigint - 1) AS "ffffffff";
 
select ascii('xyz');
select ascii('中xyz');
select ascii('ḿxyz');


-- 7. conversion between gb18030 and utf8 in utf8 envriment
\c postgres
drop database gb18030_2022;
LOAD 'gb18030_2022';
select convert('中国', 'UTF8', 'GB18030');
 
select convert('ḿ', 'UTF8', 'GB18030');


show shared_preload_libraries;
\dx

SELECT count(0)
FROM pg_settings
WHERE name = 'shared_preload_libraries' and setting like '%gb18030_2022%';
