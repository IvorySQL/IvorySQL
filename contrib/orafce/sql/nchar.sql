/* type nchar test */

set compatible_mode to oracle;

create table nchar_t1 (id int, name nchar(32));
insert into nchar_t1 values (1,'ab'),(2,'as');
select * from nchar_t1 where name = 'ab';
select * from nchar_t1 where name = 'as';
select * from nchar_t1 where name = 'ab     ';
select * from nchar_t1 where name = 'ab'or name = 'as';
select * from nchar_t1 where name = 'ab'or name = 'as';
select * from nchar_t1 where name <> 'ab';
select * from nchar_t1 where name <> 'cc';

select * from nchar_t1 where name > 'ac';
select * from nchar_t1 where name >= 'ac';
select * from nchar_t1 where name < 'ac';
select * from nchar_t1 where name <= 'ac';

select * from nchar_t1 where name ~ 'ac';
select * from nchar_t1 where name ~ 'ab';
select * from nchar_t1 where name ~ 'a';
select * from nchar_t1 where name !~ 'ac';
select * from nchar_t1 where name !~ 'ab';
select * from nchar_t1 where name !~ 'a';

select * from nchar_t1 where name ~~ 'ab';
select * from nchar_t1 where name !~~ 'ab';
select * from nchar_t1 where name ~* 'ab';
select * from nchar_t1 where name !~* 'ab';
select * from nchar_t1 where name ~~* 'ab';
select * from nchar_t1 where name !~~* 'ab';
select * from nchar_t1 where name ~<~ 'ab';
select * from nchar_t1 where name ~<=~ 'ab';
select * from nchar_t1 where name ~>~ 'ab';
select * from nchar_t1 where name ~>=~ 'ab';

create table char_t11 (id int, name char(32));
insert into char_t11 values (1,'ab'),(2,'as');
select * from char_t11 where name = 'ab';
select * from char_t11 where name = 'as';
select * from char_t11 where name = 'ab     ';
select * from char_t11 where name = 'ab'or name = 'as';
select * from char_t11 where name = 'ab'or name = 'as';
select * from char_t11 where name <> 'ab';
select * from char_t11 where name <> 'cc';

select * from char_t11 where name > 'ac';
select * from char_t11 where name >= 'ac';
select * from char_t11 where name < 'ac';
select * from char_t11 where name <= 'ac';

select * from char_t11 where name ~ 'ac';
select * from char_t11 where name ~ 'ab';
select * from char_t11 where name ~ 'a';
select * from char_t11 where name !~ 'ac';
select * from char_t11 where name !~ 'ab';
select * from char_t11 where name !~ 'a';

select * from char_t11 where name ~~ 'ab';
select * from char_t11 where name !~~ 'ab';
select * from char_t11 where name ~* 'ab';
select * from char_t11 where name !~* 'ab';
select * from char_t11 where name ~~* 'ab';
select * from char_t11 where name !~~* 'ab';
select * from char_t11 where name ~<~ 'ab';
select * from char_t11 where name ~<=~ 'ab';
select * from char_t11 where name ~>~ 'ab';
select * from char_t11 where name ~>=~ 'ab';

drop table nchar_t1, char_t11;

create or replace function nchartestfunc1(str nchar)
returns nchar as $$
begin
	return 'this is a nchar type, value: ' || str;
end;
$$ language plpgsql;

create or replace function nchartestfunc11(str char)
returns char as $$
begin
	return 'this is a char type, value: ' || str;
end;
$$ language plpgsql;

create table tb_text (name text);
insert into tb_text values ('haha');
select nchartestfunc1(name) from tb_text;
drop table tb_text;

create table tb_bpchar (name char(32));
insert into tb_bpchar values ('haha');
select nchartestfunc1(name) from tb_bpchar;
drop table tb_bpchar;

create table tb_char (name "char");
insert into tb_char values ('A');
select nchartestfunc1(name) from tb_char;
select nchartestfunc11(name) from tb_char;
drop table tb_char;

create table tb_varchar (name varchar(32));
insert into tb_varchar values ('haha');
select nchartestfunc1(name) from tb_varchar;
drop table tb_varchar;

create table tb_name (name name);
insert into tb_name values ('haha');
select nchartestfunc1(name) from tb_name;
select nchartestfunc11(name) from tb_name;
drop table tb_name;

create table tb_bool (name bool);
insert into tb_bool values ('true');
select nchartestfunc1(name) from tb_bool;
select nchartestfunc11(name) from tb_bool;
drop table tb_bool;

create table tb_varchar2 (name varchar2);
insert into tb_varchar2 values ('haha');
select nchartestfunc1(name) from tb_varchar2;
drop table tb_varchar2;

create table tb_nvarchar2 (name nvarchar2);
insert into tb_nvarchar2 values ('haha');
select nchartestfunc1(name) from tb_nvarchar2;
drop table tb_nvarchar2;

drop FUNCTION nchartestfunc1;
drop FUNCTION nchartestfunc11;
