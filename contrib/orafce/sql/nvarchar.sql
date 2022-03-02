/* type nvarchar test */

set compatible_mode to oracle;

create table nvarchar_t1 (id int, name nvarchar(32));
insert into nvarchar_t1 values (1,'ab'),(2,'as');
create table nvarchar_t2 (id int, name nchar(32));
insert into nvarchar_t2 values (1,'ab'),(2,'as');
select * from nvarchar_t1 where name = 'ab';
select * from nvarchar_t1 where name = 'as';
select * from nvarchar_t1 where name = 'ab     ';
select * from nvarchar_t1 where name = 'ab'or name = 'as';
select * from nvarchar_t1 where name = 'ab'or name = 'as';
select nvarchar_t1.name || nvarchar_t2.name from nvarchar_t1,nvarchar_t2;
select * from nvarchar_t1 where name <> 'ab';
select * from nvarchar_t1 where name <> 'cc';

select * from nvarchar_t1 where name > 'ac';
select * from nvarchar_t1 where name >= 'ac';
select * from nvarchar_t1 where name < 'ac';
select * from nvarchar_t1 where name <= 'ac';

select * from nvarchar_t1 where name ~ 'ac';
select * from nvarchar_t1 where name ~ 'ab';
select * from nvarchar_t1 where name ~ 'a';
select * from nvarchar_t1 where name !~ 'ac';
select * from nvarchar_t1 where name !~ 'ab';
select * from nvarchar_t1 where name !~ 'a';

select * from nvarchar_t1 where name ~~ 'ab';
select * from nvarchar_t1 where name !~~ 'ab';
select * from nvarchar_t1 where name ~* 'ab';
select * from nvarchar_t1 where name !~* 'ab';
select * from nvarchar_t1 where name ~~* 'ab';
select * from nvarchar_t1 where name !~~* 'ab';
select * from nvarchar_t1 where name ~<~ 'ab';
select * from nvarchar_t1 where name ~<=~ 'ab';
select * from nvarchar_t1 where name ~>~ 'ab';
select * from nvarchar_t1 where name ~>=~ 'ab';

create table varchar_t11 (id int, name varchar(32));
insert into varchar_t11 values (1,'ab'),(2,'as');
create table varchar_t22 (id int, name char(32));
insert into varchar_t22 values (1,'ab'),(2,'as');
select * from varchar_t11 where name = 'ab';
select * from varchar_t11 where name = 'as';
select * from varchar_t11 where name = 'ab     ';
select * from varchar_t11 where name = 'ab'or name = 'as';
select * from varchar_t11 where name = 'ab'or name = 'as';
select varchar_t11.name || varchar_t22.name from varchar_t11,varchar_t22;
select * from varchar_t11 where name <> 'ab';
select * from varchar_t11 where name <> 'cc';

select * from varchar_t11 where name > 'ac';
select * from varchar_t11 where name >= 'ac';
select * from varchar_t11 where name < 'ac';
select * from varchar_t11 where name <= 'ac';

select * from varchar_t11 where name ~ 'ac';
select * from varchar_t11 where name ~ 'ab';
select * from varchar_t11 where name ~ 'a';
select * from varchar_t11 where name !~ 'ac';
select * from varchar_t11 where name !~ 'ab';
select * from varchar_t11 where name !~ 'a';

select * from varchar_t11 where name ~~ 'ab';
select * from varchar_t11 where name !~~ 'ab';
select * from varchar_t11 where name ~* 'ab';
select * from varchar_t11 where name !~* 'ab';
select * from varchar_t11 where name ~~* 'ab';
select * from varchar_t11 where name !~~* 'ab';
select * from varchar_t11 where name ~<~ 'ab';
select * from varchar_t11 where name ~<=~ 'ab';
select * from varchar_t11 where name ~>~ 'ab';
select * from varchar_t11 where name ~>=~ 'ab';

drop table nvarchar_t1, varchar_t11;

create or replace function nvarchartestfunc1(str nvarchar)
returns nvarchar as $$
begin
	return 'this is a nvarchar type, value: ' || str;
end;
$$ language plpgsql;

create or replace function nvarchartestfunc11(str varchar)
returns varchar as $$
begin
	return 'this is a varchar type, value: ' || str;
end;
$$ language plpgsql;

create table tb_text (name text);
insert into tb_text values ('haha');
select nvarchartestfunc1(name) from tb_text;
drop table tb_text;

create table tb_bpchar (name char(32));
insert into tb_bpchar values ('haha');
select nvarchartestfunc1(name) from tb_bpchar;
drop table tb_bpchar;

create table tb_char (name "char");
insert into tb_char values ('A');
select nvarchartestfunc1(name) from tb_char;
select nvarchartestfunc11(name) from tb_char;
drop table tb_char;

create table tb_varchar (name varchar(32));
insert into tb_varchar values ('haha');
select nvarchartestfunc1(name) from tb_varchar;
drop table tb_varchar;

create table tb_name (name name);
insert into tb_name values ('haha');
select nvarchartestfunc1(name) from tb_name;
select nvarchartestfunc11(name) from tb_name;
drop table tb_name;

create table tb_bool (name bool);
insert into tb_bool values ('true');
select nvarchartestfunc1(name) from tb_bool;
select nvarchartestfunc11(name) from tb_bool;
drop table tb_bool;

create table tb_varchar2 (name varchar2);
insert into tb_varchar2 values ('haha');
select nvarchartestfunc1(name) from tb_varchar2;
drop table tb_varchar2;

create table tb_nvarchar2 (name nvarchar2);
insert into tb_nvarchar2 values ('haha');
select nvarchartestfunc1(name) from tb_nvarchar2;
drop table tb_nvarchar2;

drop FUNCTION nvarchartestfunc1;
drop FUNCTION nvarchartestfunc11;
