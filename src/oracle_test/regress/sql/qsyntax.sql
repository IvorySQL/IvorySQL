select q'''s is good'';
select q'['s is good]';
select q'{'s is good}';
select q'\'s is good\';
select q'<'s is good>';
select q'a's is gooda';
select q'2's is good2';
select q'='s is good=';
select q'-'s is good-';
select q'*'s is good*';
select q'&'s is good&';
select q'%'s is good%';
select q'#'s is good#';
select q'^'s is good^';
select q'|'s is good|';
select q','s is good,';
select q';'s is good;';
select q'!'s is good!';

select Q'''s is good'';
select Q'['s is good]';
select Q'\'s is good\';
select Q'<'s is good>';
select Q'a's is gooda';
select Q'2's is good2';
select Q'='s is good=';
select Q'-'s is good-';
select Q'*'s is good*';
select Q'&'s is good&';
select Q'%'s is good%';
select Q'#'s is good#';
select Q'!'s is good!';

select 'bequq' || chr(10) || 'baz';
select 'bequq' || 'baz';
select 'ddq'||'dc'||q'fdgdgf'||'qddq'||q'qsfsq';
select 'ddq'||'dc'||'qddq'||q'dsfsd';
select  q'qsfsq'||'ddq'||'dc'||'qddq'||'fhsq';
select 'baq'||'adq';
select 'abq'||q'|'|adc|';
select q'aa';
select q'a'a'a;
select q'a'sfsdf a'a;
select q'a'b'a'dda;
select q'>ada>';
select q')ada)';
select q'}ada}';
select q']ada]';
select q'Ab'cA';
select q'……a……d…………';
select q'【abc【';
select q'，ddd ，' ;
select q'。abc。';
select q'；abc；';
select q'(a(q'adda') a)' || q'改改 as 改';
select q'abbc is a' || q'啊 奥利给 啊';
select q'改add改';
select q'('改'改'变'自'己'改')';
select q'ａ a ａ';
select q'ａａaａ ａ';
select q'ａq'aabca'ａ';
select q'改改变自己改';
select q'a'b'a';
select q'' ''||'adc';
select q''||'adc'';
select 'q';
select q'qqqq';
select q'adda';
select q'|---|';
select 'ddq'||'dc';
select 'ddq' || 'dc' || 'qddq' || q'dsfsd';
select 'ddq'||'dc'||'qddq'||q'qsfsq';

select q'('a'b'c'd'e'f')';
select q'('a'b'c'd'e')'||q'qqddq';
select q'('a'b'c'd'e'f')'||q'qqddq';
select q'('a'b'c'd'e'f')'||'qq';
select q'('a'b'c'd'e'f')'||q'qqq';
select q'aq'bab'a';
select q'a'a a';
select q'(a()a)';
select q'(a(q'adda')a)';
select q'<daddd'''sf>';
select 'baq','adq';
select q'aaa
aa';

create table test(id int,name varchar(20));
insert into test values(1,'K'||q'aima');
insert into test values(2,'T'||q'aima');
select * from test;

update test set name = 'B'||q'[ob]' where id = 1 ;
select * from test order by id;
update test set name = 'J'||q'<im>' where id =2 ;
select * from test order by id;

create or replace function test_q() returns text as 
$$
	declare
		a text := q'> It's good>';
	begin
		return a;
	end;
$$language plisql;
/
select test_q();
drop function test_q;

create or replace function getname(idd int) returns text as $$
declare
	names text default q'{name is}';
	rec_name record;
	cur_test cursor(idd int) for select name from test where id = idd;
begin
	open cur_test(idd);
	loop
		fetch cur_test into rec_name;
		exit when not found;
			names = names || ' '||rec_name;
	end loop;
	close cur_test;
	return names;
end;$$
language plisql;
/
select  getname(1);
drop function getname;

create or replace procedure test_q1(idd int) as $$
declare
	cur_test cursor for select * from test where id <= idd;
begin
	for rec_name in cur_test loop
		raise notice 'id = %,name=%',rec_name.id,rec_name.name||q'a'sa';
	end loop;
end;$$
language plisql;
/
call test_q1(2);
drop procedure test_q1;
