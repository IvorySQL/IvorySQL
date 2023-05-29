/*
 * length/lengthb
 */
-- char
CREATE TABLE TEST_ORACHAR(a char(5 byte), b char(5 char));

INSERT INTO TEST_ORACHAR VALUES('aaa', 'bbb');

INSERT INTO TEST_ORACHAR VALUES('aaa ', 'bbb ');

SELECT a, b, LENGTH(a), LENGTH(b) FROM TEST_ORACHAR;

SELECT a, b, LENGTHB(a), LENGTHB(b) FROM TEST_ORACHAR;

--varchar2
CREATE TABLE TEST_ORAVARCHAR(a varchar2(5 char), b varchar2(5 byte));

INSERT INTO TEST_ORAVARCHAR VALUES('aaa', 'bbb');

INSERT INTO TEST_ORAVARCHAR VALUES('aaa ', 'bbb ');

SELECT a, b, LENGTH(a), LENGTH(b) FROM TEST_ORAVARCHAR;

SELECT a, b, LENGTHB(a), LENGTHB(b) FROM TEST_ORAVARCHAR;

-- drop table
DROP TABLE TEST_ORACHAR;
DROP TABLE TEST_ORAVARCHAR;

/*
 * ||
 */
--test bug#792
SET nls_date_format = 'DD-MON-YY';
SET nls_timestamp_format = 'DD-MON-YY HH24:MI:SS.US';
create table test_concat(id number,id2 integer,id3 timestamp,id4 date);

--insert a row
insert into test_concat values(1,2,'01-FEB-21','01-FEB-21');

--integer || number
select id || id2 from test_concat;

--integer || timestamp
select id || id3 from test_concat;

--timestamp || date
select id3 || id4 from test_concat;

--integer || number || timestamp || date
select id || id2 || id3 || id4 from test_concat;

--as a table column
create table test_concat1 as select id || id2 as test from test_concat;

--column type
select attname,atttypid from pg_attribute attr left join pg_class r on r.oid = attr.attrelid where r.relname='test_concat1' and attname='test' order by attname;

create table test_concat2 as select id|| id4 as test from test_concat;

select attname,atttypid from pg_attribute attr left join pg_class r on r.oid = attr.attrelid where r.relname='test_concat2' and attname='test' order by attname;

create table test_concat3 as select id3 || id4 as test from test_concat;

select attname,atttypid from pg_attribute attr left join pg_class r on r.oid = attr.attrelid where r.relname='test_concat3' and attname='test' order by attname;

insert into test_concat(id) values(2);

--integer || null
select id || id2 from test_concat;

--null || number
select  id2 || id from test_concat;

--clean data
drop table test_concat;
drop table test_concat1;
drop table test_concat2;
drop table test_concat3;

/*
 * lpad/rpad
 */
--bug#997
--create test table
create table test_lpad(id integer);

--ok
select lpad('*', (select count(*) from test_lpad), '*') from dual;

--ok
select rpad('*', (select count(*) from test_lpad), '*') from dual;

--insert one row
insert into test_lpad values(1);

--*
select lpad('*', (select count(*) from test_lpad), '*') from dual;

--*
select rpad('*', (select count(*) from test_lpad), '*') from dual;

--insert another
insert into test_lpad values(2);

--1*
select lpad('*', (select count(*) from test_lpad), '1') from dual;

--*1
select rpad('*', (select count(*) from test_lpad), '1') from dual;

--x *welcome
select 'x' || lpad('*', (select count(*) from test_lpad)) ||'welceom' from dual;

--x* welcome
select 'x' || rpad('*', (select count(*) from test_lpad)) ||'welceom' from dual;

--001234
select lpad(1234,6,'0') from dual;

--123400
select rpad(1234,6,'0') from dual;

--null
select lpad(NULL,6,'0') from dual;

--null
select rpad(NULL,6,'0') from dual;

--create view
create table test_t(id varchar2(23));

insert into test_t values('sfljdsf');

create view test_view as select lpad('*', (select count(*) from test_lpad), '*') || id as name from test_t;

select *from test_view order by name;

--clean data
drop view test_view;
drop table test_t;
drop table test_lpad;

/*
 * trim/ltrim/rtrim
 */
select rtrim('123 '::number);	--bug#796
SELECT LTRIM('<=====>BROWNING<=====>', '<>=') "LTRIM Example" FROM DUAL;
SELECT RTRIM('<=====>BROWNING<=====>', '<>=') "RTRIM Example" FROM DUAL;
--test bug#833
create table test_trim(id number);
select trim(id) from test_trim;
insert into test_trim values(124.35);
select trim(id) from test_trim;
select trim('35' from id) from test_trim;
--clean data
drop table test_trim;

/*
 * regexp_replace
 */
set enable_emptystring_to_null to on;
--Return empty

select regexp_replace('', '[0-9]+','') from  dual;

select regexp_replace(NULL, '[0-9]+',NULL) from  dual;

select regexp_replace('', '[0-9]+','A') from  dual;

select regexp_replace(NULL, '[0-9]+','A') from  dual;

select regexp_replace('', '[a-z]+','',1,3,'i') from  dual;

select regexp_replace(NULL, '[a-z]+',NULL,1,3,'i') from  dual;

select regexp_replace('', '[0-9]+', '', 1, 3, 'i') from  dual;

select regexp_replace(NULL, '[0-9]+', NULL, 1, 3, 'i') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', '') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', NULL) from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 1, '') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 1, NULL) from  dual;

--Too few parameters

select regexp_replace('') from  dual;

select regexp_replace(NULL) from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172') from  dual;

--Return source string

select regexp_replace('662 regEXP_REplaCe TEst 172', '') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', NULL) from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '','AA',1,1,'i') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', NULL,'AA',1,1,'i') from  dual;

--Remove matching characters from the source string

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+','') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', NULL) from  dual;

--Return source string

select regexp_replace('662 regEXP_REplaCe TEst 172', '', 'ZZZ') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', NULL, 'ZZZ') from  dual;

--Replace 2 or more spaces with a space

select regexp_replace('500   Oracle     Parkway,    Redwood  Shores, CA', '( ){2,}', ' ') from dual;

--Replace the matched substring with a new string

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ') from  dual;

--Look backwards from the specified location 8

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 8) from  dual;

--Remove matching characters from the source string

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', '', 8) from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', NULL, 8) from  dual;

--Incorrect parameter type

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', '', a) from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', NULL, a) from  dual;

--Searched position is less than 1 out of range

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 0) from  dual;

--Replace all strings that match

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 1, 0) from  dual;

--Replace the second matching string starting with the third character

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 3, 2) from  dual;

--Match string is less than 0 out of range

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 5, -1) from  dual;

--specifies case-insensitive matching

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 1, 1, '') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 1, 1, NULL) from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[a-c]+', 'ZZZ', 1, 1, 'i')  from  dual;

--specifies case-sensitive matching.

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 4, 3, 'c')  from  dual;

--allows the period (.), which is the match-any-character character

select regexp_replace('662 regEXP_REplaCe TEst 172', '[A-C]+', 'ZZZ', 1, 1, 'n')  from  dual;

--treats the source string as multiple lines

select regexp_replace('662 regEXP_REplaCe TEst 172', '[A-C]+', 'ZZZ', 1, 1, 'm')  from  dual;

--ignores whitespace characters

select regexp_replace('662 regEXP_REplaCe TEst 172', '[A-C]+', 'ZZZ', 1, 1, 'x')  from  dual;

--Match only the last character

select regexp_replace('662 regEXP_REplaCe TEst 172', '[A-C]+', 'ZZZ', 1, 1, 'ic')  from  dual;

--Wrong matching pattern

select regexp_replace('662 regEXP_REplaCe TEst 172', '[A-C]+', 'ZZZ', 1, 1, 'a')  from  dual;

--Too many parameters

select regexp_replace('662 regEXP_REplaCe TEst 172', '[A-C]+', 'ZZZ', 1, 1, 'ic',8)  from  dual;

--Replace all uppercase letters

select regexp_replace('regexp_REPLACE 4567', '[[:upper:]]', 'x-', 1, 0, 'ic')  from  dual;

--Replace all letters, numbers

select regexp_replace('regexp-23-replace 345', '[[:alnum:]]', 'x:') from  dual;

--Replace the specified string

select regexp_replace('for,forty,horse,morning,sport', 'or', '!') from  dual;

--Replace plus sign

select regexp_replace('(19 + 35 * 2 + 8 - 3) / 2', '\+', '-', 1, 1) from  dual;

--Separate each letter

select regexp_replace('australia', '(.)', '\1 ') from dual;

--Match to the specified format

select regexp_replace('515.123.4444 515.123.4888','([[:digit:]]{3})\.([[:digit:]]{3})\.([[:digit:]]{4})','(\1) \2-\3') from dual;

/*
 * regexp_substr
 */
--Return empty
select regexp_substr('', '[0-9]+','') from  dual;

select regexp_substr(NULL, '[0-9]+',NULL) from  dual;

select regexp_substr('', '[0-9]+','') from  dual;

select regexp_substr(NULL, '[0-9]+','') from  dual;

select regexp_substr('', '[a-z]+',1,3,'i') from  dual;

select regexp_substr(NULL, '[a-z]+',1,3,'i') from  dual;

select regexp_substr('345 REGEXP_substr 789', '') from  dual;

select regexp_substr('345 REGEXP_substr 789', NULL) from  dual;

select regexp_substr('345 REGEXP_substr 789', '', 1) from  dual;

select regexp_substr('345 REGEXP_substr 789', NULL, 1) from  dual;

select regexp_substr('345 REGEXP_substr 789', '',1,1,'i') from  dual;

select regexp_substr('345 REGEXP_substr 789', NULL,1,1,'i') from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', '') from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', NULL) from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', 1, '') from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', 1, NULL) from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', 1, 1, 'i', '') from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', 1, 1, 'i', NULL) from  dual;

--Too few parameters

select regexp_substr('') from  dual;

select regexp_substr(NULL) from  dual;

select regexp_substr('345 REGEXP_substr 789') from  dual;

--Returns the first string matched

select regexp_substr('345 REGEXP_substr 789', '[0-9]+') from  dual;

--Return the first string that matches to the specified position

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', 8) from  dual;

--Incorrect parameter type

select regexp_substr('345 REGEXP_substr 789', '[0-9]+',  a) from  dual;

--Searched position is less than 1 out of range

select regexp_substr('345 REGEXP_substr 789', '[0-9]+',  0) from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+',  1, 0) from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', 5, -1) from  dual;

--specifies case-insensitive matching

select regexp_substr('345 REGEXP_substr 789', '[a-z]+', 1, 1, '') from  dual;

select regexp_substr('345 REGEXP_substr 789', '[a-z]+', 1, 1, NULL) from  dual;

select regexp_substr('345 REGEXP_substr 789', '[a-z]+', 1, 1, 'i')  from  dual;

--specifies case-sensitive matching.

select regexp_substr('345 REGEXP_substr 789', '[a-z]+', 4, 3, 'c')  from  dual;

--allows the period (.), which is the match-any-character character

select regexp_substr('345 REGEXP_substr 789', '[A-Z]+', 1, 1, 'n')  from  dual;

--treats the source string as multiple lines

select regexp_substr('345 REGEXP_substr 789', '[A-Z]+', 1, 1, 'm')  from  dual;

--ignores whitespace characters

select regexp_substr('345 REGEXP_substr 789', '[A-Z]+', 1, 1, 'x')  from  dual;

--Match only the last character

select regexp_substr('345 REGEXP_substr 789', '[A-Z]+', 1, 1, 'ic')  from  dual;

--Wrong matching pattern

select regexp_substr('345 REGEXP_substr 789', '[A-Z]+', 1, 1, 'a')  from  dual;

-- find the first uppercase letters

select regexp_substr('regexp_REPLACE 4567', '[[:upper:]]', 1, 1, 'ic')  from  dual;

--Return the first character found or this number

select regexp_substr('regexp-23-replace 345', '[[:alnum:]]') from  dual;

select regexp_substr('(19 + 35 * 2 + 8 - 3) / 2', '\+', 1, 1) from  dual;

select regexp_substr('australia', '(.)') from dual;

select regexp_substr('515.123.4444 515.123.4888','([[:digit:]]{3})\.([[:digit:]]{3})\.([[:digit:]]{4})') from dual;

--Returns the first string found by the regular expression

select regexp_substr('500 Oracle Parkway, Redwood Shores, CA',',[^,]+,') from dual;

select regexp_substr('http://www.example.com/products','http://([[:alnum:]]+\.?){3,4}/?') from dual;

--Use the subexpr argument to return a specific subexpression of pattern

select regexp_substr('barbar', 'b[^b]+',1,1,'i',0) from dual;

select regexp_substr('barbar', 'b[^b]+',1,1,'i',1) from dual;

select regexp_substr('barbar', '(b[^b]+)',1,1,'i',0) from dual;

select regexp_substr('barbar', '(b[^b]+)',1,1,'i',1) from dual;

select regexp_substr('foobarbequebazilbarfbonk', '(b[^b]+)(b[^b]+)', 1, 1, 'i',2) from dual;

select regexp_substr('345 REGEXP_substr 789', '[A-Z]+', 1, 1, 'ic',8)  from  dual;

select regexp_substr('foobarbequebazilbarfbonk', '(b[^b]+)(b[^b]+)', 1, 1, 'i',3) from dual;

select regexp_substr('123456789010', '(1(2)3)(4(5(6))(7(8))(9(0)(10)))', 1, 1, 'i',8) from dual;

select regexp_substr('123456789010', '(1(2)3)(4(5(6))(7(8))(9(0)(10)))', 1, 1, 'i',9) from dual;

--The number of submodes is more than 9 and returns empty

select regexp_substr('123456789010', '(1(2)3)(4(5(6))(7(8))(9(0)(10)))', 1, 1, 'i',10) from dual;

--Too many parameters

select regexp_substr('foobarbequebazilbarfbonk', '(b[^b]+)(b[^b]+)', 1, 1, 'i',2,8) from dual;


/*
 * regexp_instr
 */
--Return empty or error
----two parameters
select regexp_instr('', '[0-9]+') from dual;

select regexp_instr('345 REGEXP_instr 789', '') from dual;

select regexp_instr('345 REGEXP_instr 789', '') from dual;

select regexp_instr('345 REGEXP_instr 789', NULL) from dual;

----three parameters
select regexp_instr('345 REGEXP_instr 789', '[a-z]+',0) from dual;	--fail

select regexp_instr('345 REGEXP_instr 789', '[a-z]+',-1) from dual; --fail
 
select regexp_instr('', '[0-9]+','') from dual;

select regexp_instr(NULL, '[0-9]+',NULL) from dual;

select regexp_instr('', '[0-9]+',NULL) from dual;

select regexp_instr(NULL, '[0-9]+','') from dual;

select regexp_instr('345 REGEXP_instr 789', '', 1) from dual;

select regexp_instr('345 REGEXP_instr 789', NULL, 1) from dual;

select regexp_instr('345 REGEXP_instr 789', '[0-9]+', '') from dual;

select regexp_instr('345 REGEXP_instr 789', '[0-9]+', NULL) from dual;

----four parameters
select regexp_instr('345 REGEXP_instr 789', '[a-z]+',1,0) from dual;	--fail

select regexp_instr('345 REGEXP_instr 789', '[a-z]+',1,-1) from dual;	--fail

select regexp_instr('345 REGEXP_instr 789', '[0-9]+', 1, '') from dual;

select regexp_instr('345 REGEXP_instr 789', '[0-9]+', 1, NULL) from dual;

----five parameters
select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, -1) from dual; --fail

select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, -2) from dual; --fail

select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, -100) from dual; --fail

select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, '') from dual;

select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, NULL) from dual;

----six parameters
select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, 'q') from dual;	--fail

select regexp_instr('', '[a-z]+', 1, 1, 0, 'i') from dual;

select regexp_instr(NULL, '[a-z]+', 1, 1, 0, 'i') from dual;

select regexp_instr('345 REGEXP_instr 789', '', 1, 1, 0, 'i') from dual;

select regexp_instr('345 REGEXP_instr 789', NULL, 1, 1, 0, 'i') from dual;

----seven parameters
select regexp_instr('345 REGEXP_instr 789', '[0-9]+', 1, 1, 0, 'i', -1) from dual; --fail

select regexp_instr('345 REGEXP_instr 789', '[0-9]+', 1, 1, 0, 'i', '') from dual;

select regexp_instr('345 REGEXP_instr 789', '[0-9]+', 1, 1, 0, 'i', NULL) from dual;

select regexp_instr('', '[0-9]+', 1, 1, 0, 'i', 1) from dual;

select regexp_instr(NULL, '[0-9]+', 1, 1, 0, 'i', 1) from dual;

select regexp_instr('345 REGEXP_instr 789', '', 1, 1, 0, 'i', 1) from dual;

select regexp_instr('345 REGEXP_instr 789', NULL, 1, 1, 0, 'i', 1) from dual;


--Too few parameters
select regexp_instr('') from dual;	--fail

select regexp_instr(NULL) from dual;--fail

select regexp_instr('345 REGEXP_instr 789') from dual;


--Returns the first string location matched
select regexp_instr('345 REGEXP_instr 789', '[0-9]+') from dual;


--Return the first string location that matches to the specified position
select regexp_instr('345 REGEXP_instr 789', '[0-9]+', 8) from dual;


--Incorrect parameter type
select regexp_instr('345 REGEXP_instr 789', '[0-9]+',  a) from dual;	  --fail


--Searched position is less than 1 out of range
select regexp_instr('345 REGEXP_instr 789', '[0-9]+',  0) from dual;	  --fail

select regexp_instr('345 REGEXP_instr 789', '[0-9]+',  -1) from dual;	  --fail

select regexp_instr('345 REGEXP_instr 789', '[0-9]+',  1, 0) from dual;   --fail

select regexp_instr('345 REGEXP_instr 789', '[0-9]+', 5, -1) from dual;	  --fail


--verify case-insensitive matching
select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, '') from dual;

select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, NULL) from dual;

select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, 'i') from dual;


--specifies case-sensitive matching.
select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, 'c') from dual;


--allows the period (.), which is the match-any-character character
select regexp_instr('345 REGEXP_instr 789', '[A-Z]+', 1, 1, 0, 'n') from dual;


--treats the source string as multiple lines
select regexp_instr('345 REG^EX$P_instr 789', '[A-Z]+', 1, 1, 0, 'm')  from dual;

select regexp_instr('34^5 REG$EXP_instr 789', '[A-Z]+', 1, 1, 0, 'm')  from dual;


--ignores whitespace characters
select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, 'x')  from dual;


--If specify multiple contradictory values, then Match only the last character.
select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, 'ic')  from dual;

select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, 'ci')  from dual;


--Wrong matching pattern
select regexp_instr('345 REGEXP_instr 789', '[A-Z]+', 1, 1, 0, 'a')  from dual;	--fail


--Too many parameters
select regexp_instr('foobarbequebazilbarfbonk', '(b[^b]+)(b[^b]+)', 1, 1, 0, 'i', 0, 3) from dual;	--fail


--Returns the character or number location about string found by the regular expression
select regexp_instr('500 Oracle Parkway, Redwood Shores, CA',',[^,]+,') from dual;

select regexp_instr('http://www.example.com/products','/([[:alnum:]]+\.?){3,4}/?') from dual;

select regexp_instr('515.123.4444 515.123.4888','([[:digit:]]{3})\.([[:digit:]]{3})', 1, 2, 0) from dual;


--If the number of subexpression is more than 9, then returns zero
select regexp_instr('123456789010', '(1(2)3)(4(5(6))(7(8))(9(0)(10)))', 1, 1, 0, 'i',10) from dual;


--Use the subexpr argument to return a specific subexpression of pattern
select regexp_instr('barbar', 'b[^b]+', 1, 1, 0, 'i',0) from dual;

select regexp_instr('barbar', 'b[^b]+', 1, 1, 1, 'i',0) from dual;

select regexp_instr('barbar', '(b[^b]+)', 1, 2, 0, 'i',0) from dual;

select regexp_instr('barbar', '(b[^b]+)', 1, 2, 1, 'i',0) from dual;

select regexp_instr('foobarbequebazilbarfbonk', '(b[^b]+)(b[^b]+)', 1, 1, 0, 'i') from dual;

select regexp_instr('345 REGEXP_instr 789', '[A-Z]+', 1, 1, 0, 'ic')  from dual;

select regexp_instr('123456789010', '(1(2)3)(4(5(6))(7(8))(9(0)(10)))', 1, 1, 0, 'i',8) from dual;

select regexp_instr('123456789010', '(1(2)3)(4(5(6))(7(8))(9(0)(10)))', 1, 1, 0, 'i',9) from dual;

/*
 * regexp_like
 */
create table t_regexp_like
(
  id varchar(4),
  value varchar(10)
);

insert into t_regexp_like values ('1','1234560');
insert into t_regexp_like values ('2','1234560');
insert into t_regexp_like values ('3','1b3b560');
insert into t_regexp_like values ('4','abc');
insert into t_regexp_like values ('5','abcde');
insert into t_regexp_like values ('6','ADREasx');
insert into t_regexp_like values ('7','123  45');
insert into t_regexp_like values ('8','adc  de');
insert into t_regexp_like values ('9','adc,.de');
insert into t_regexp_like values ('10','1B');
insert into t_regexp_like values ('10','abcbvbnb');
insert into t_regexp_like values ('11','11114560');
insert into t_regexp_like values ('11','11124560');
-------------------------------------------------------
select * from t_regexp_like where regexp_like(value,'ABC', 'i');
select * from t_regexp_like where regexp_like(value,'ABC', 'n');
select * from t_regexp_like where regexp_like(value,'ABC', 'p');
select * from t_regexp_like where regexp_like(value,'ABC', 'c');
select * from t_regexp_like where regexp_like(value,'a b c', 'x');
select * from t_regexp_like where value like '1____60';
select * from t_regexp_like where regexp_like(value,'1....60');
select * from t_regexp_like where regexp_like(value,'1[0-9]{4}60');
select * from t_regexp_like where regexp_like(value,'1[[:digit:]]{4}60');
select * from t_regexp_like where regexp_like(value, '^[[:digit:]]+[[:alpha:]]+.*[[:digit:]]+$');
select * from t_regexp_like where regexp_like(value,'^[^[:digit:]]+$');
select * from t_regexp_like where regexp_like(value,'^1[2b]','i');
select * from t_regexp_like where regexp_like(value,'^1[2B]');
select * from t_regexp_like where regexp_like(value,'[[:space:]]');
select * from t_regexp_like where regexp_like(value,'^([a-z]+|[0-9]+)$');
select * from t_regexp_like where regexp_like(value,'[[:punct:]]');

select * from t_regexp_like where regexp_like('','');
select * from t_regexp_like where regexp_like(null, '');
select * from t_regexp_like where regexp_like('', null);
select * from t_regexp_like where regexp_like(null, null);
select * from t_regexp_like where regexp_like(null, null, null);

DROP table t_regexp_like;

/*
 * regexp_count
 */
--following test cases from Oracle.
SELECT REGEXP_COUNT('123123123123123', '(12)3', 1, 'i') REGEXP_COUNT FROM DUAL;
SELECT REGEXP_COUNT('123123123123', '123', 3, 'i') COUNT FROM DUAL;
select regexp_count('ABC123', '[A-Z]'), regexp_count('A1B2C3', '[A-Z]') from dual;
select regexp_count('ABC123', '[A-Z][0-9]'), regexp_count('A1B2C3', '[A-Z][0-9]') from dual;
select regexp_count('ABC123', '^[A-Z][0-9]'), regexp_count('A1B2C3', '^[A-Z][0-9]') from dual;
select regexp_count('ABC123', '[A-Z][0-9]{2}'), regexp_count('A1B2C3', '[A-Z][0-9]{2}') from dual;
select regexp_count('ABC123', '([A-Z][0-9]){2}'), regexp_count('A1B2C3', '([A-Z][0-9]){2}') from dual;
select regexp_count('ABC123', '[A-Z]') Match_char_ABC_count, regexp_count('A1B2C3', '[A-Z]') Match_char_ABC_count from dual;
select regexp_count('ABC123', '[A-Z][0-9]') Match_string_C1_count, regexp_count('A1B2C3', '[A-Z][0-9]')  Match_strings_A1_B2_C3_count from dual;
select regexp_count('ABC123A5', '^[A-Z][0-9]') Char_num_like_A1_at_start, regexp_count('A1B2C3', '^[A-Z][0-9]') Char_num_like_A1_at_start from dual;
select regexp_count('ABC123', '[A-Z][0-9]{2}') Char_num_like_A12_anywhere, regexp_count('A1B2C34', '[A-Z][0-9]{2}') Char_num_like_A12_anywhere from dual;
select regexp_count('ABC12D3', '([A-Z][0-9]){2}') Char_num_within_2_places, regexp_count('A1B2C3', '([A-Z][0-9]){2}') Char_num_within_2_places from dual;

CREATE TABLE regexp_temp(empName varchar2(20));
INSERT INTO regexp_temp (empName) VALUES ('John Doe');
INSERT INTO regexp_temp (empName) VALUES ('Jane Doe');

SELECT empName, REGEXP_COUNT(empName, 'e', 1, 'c') "CASE_SENSITIVE_E" From regexp_temp;
SELECT empName, REGEXP_COUNT(empName, 'o', 1, 'c') "CASE_SENSITIVE_O" From regexp_temp;
SELECT empName, REGEXP_COUNT(empName, 'E', 1, 'i') "CASE_INSENSITIVE_E" From regexp_temp;
SELECT empName, REGEXP_COUNT(empName, 'do', 1, 'i') "CASE_INSENSITIVE_STRING" From regexp_temp;
SELECT empName, REGEXP_COUNT(empName, 'an', 1, 'c') "CASE_SENSITIVE_STRING" From regexp_temp;

DROP TABLE regexp_temp;

/*
 * substrb
 */
SELECT SUBSTRB('ABCDEFG',5,4.2) "Substring with bytes" FROM DUAL;
SELECT SUBSTRB('ABCDEFG',5) "Substring with bytes" FROM DUAL;

/*
 * instrb
 */
SELECT INSTRB('CORPORATE FLOOR','OR',5,2) "Instring in bytes" FROM DUAL;
SELECT INSTRB('CORPORATE FLOOR','OR',5) "Instring in bytes" FROM DUAL;
SELECT INSTRB('CORPORATE FLOOR','OR') "Instring in bytes" FROM DUAL;

/*
 * replace
 */
SELECT REPLACE('JACK and JUE','J','BL') "Changes" FROM DUAL;
SELECT REPLACE('JACK and JUE','J') "Changes" FROM DUAL;
