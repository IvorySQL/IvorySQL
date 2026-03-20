-- create databases
create database gb18030_copy encoding='gb18030' LC_COLLATE='C' LC_CTYPE ='C' TEMPLATE=template0;

----------------------------------------------
-- GB18030 Copy Test
\c gb18030_copy
load 'gb18030_2022';
show server_encoding;
set client_encoding to utf8;
show client_encoding;
-- 1. copy from text
create table copy_18030_test(x text);
copy copy_18030_test from STDIN;
狜狝狟狢狣狤狥狦狧狪狫狵狶狹狽狾
狿猀猂猄猅猆猇猈猉猋猌猍猏猐猑猒
猔猘猙猚猟猠猣猤猦猧猨猭猯猰猲猳
猵猶猺猻猼猽獀獁獂獃獄獅獆獇獈
獉獊獋獌獎獏獑獓獔獕獖獘獙獚獛獜
獝獞獟獡獢獣獤獥獦獧獨獩獪獫獮獰
獱
\.

select * from copy_18030_test;
drop table copy_18030_test;

-- 2. copy from csv
create table copy_csv_18030(x text,y text);
copy copy_csv_18030 from STDIN CSV DELIMITER '@' ESCAPE 'g' QUOTE '/';
狜狝狟狢gdasgds/狣㐴㐵㐶㐷㐸㐹㐺㐻㐼狤狥狦/@/狧狪狫狵㒰㒱㒲㒳㒴狶狹狽狾/
狿猀猂猄猅㓢㓣㓤/㓥㓦猆gdsgdsag猇/猈@猉猋/猌猍gfsaf㓿㔀/㔁㔂㔃sa猏猐猑猒
猔猘猙猚gdsgr/ds猟gfdsagds/猠gdsgds猣猤@猦/猧猨gds猭猯猰猲猳/
猵猶猺猻猼/猽獀/獁@獂獃/獄獅獆/獇獈　
獉獊獋獌/獎獏/獑獓@gd/sgr/as
獝獞獟獡獢/獣gda獤/獥@獦獧/獨獩gdsgds獪獫獮獰/
gdagg/ds獱/@1f/asfs/
\.

select * from copy_csv_18030;
drop table copy_csv_18030;

\c postgres
drop database gb18030_copy;
