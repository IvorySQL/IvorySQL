--
-- Test Ivorysql compatible oracle XML functions
--

create table inaf(a int, b xmltype);
insert into inaf values(1,xmltype('<a><b>100</b></a>'));
insert into inaf values(2, '');

select * from inaf;

create table xmltest(id int, data XMLType);
insert into xmltest values(1, '<value>one</value>');
insert into xmltest values(2, '<value>two</value>');

select * from xmltest;

create table xmlnstest(id int, data xmltype);
INSERT INTO xmlnstest VALUES(1, xmltype('<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.def.com" xmlns:web="http://www.abc.com"><soapenv:Body><web:BBB><typ:EEE>41</typ:EEE><typ:FFF>42</typ:FFF></web:BBB></soapenv:Body></soapenv:Envelope>'));


--
-- extrct(XML)
--
SELECT extract(XMLType('<AA><ID>1</ID></AA>'), '/AA/ID') from dual;

SELECT extract(XMLType('<AA><ID>1</ID></AA>'), '/AA') from dual;

SELECT extract(XMLType('<Co Attr ="Test Attr"><ID>1</ID></Co>'), '/Co') from dual;

SELECT extract(XMLType('<Co Attr ="Test Attr"><ID>1</ID></Co>'), '/Co/@ Attr') from dual;

SELECT extract(XMLType('<a><b>b1</b><b>b2</b></a>'),'/a/b[2]') from dual;

SELECT extract(XMLType('<a><b>b1</b><b>b2</b></a>'),'/a/b[3]') from dual;

SELECT extract(b, '/a/b') from inaf where a = 2;

SELECT extract(XMLType('<a><b>b1</b><b>b2</b></a>'),'') from dual;

SELECT extract(XMLType('<a><b>b1</b><b>b2</b></a>'),null) from dual;

SELECT extract(data, 'soapenv:Envelope/soapenv:Body/web:BBB/typ:EEE', 'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.def.com" xmlns:web="http://www.abc.com"') from xmlnstest where id = 1;

--
-- extractvalue
--
SELECT extractvalue(XMLType('<a><b>100</b></a>'),'/a/b') from dual;

SELECT extractvalue(XMLType('<a><b>100</b></a>'),'/a') from dual;

SELECT extractvalue(b, '/a/b') from inaf where a = 2;

SELECT extractvalue(XMLType('<a><b>b</b></a>'), '') from dual;

SELECT extractvalue(XMLType('<a><b>b</b></a>'), null) from dual;

SELECT extractvalue(XMLType('<a><b>b1</b><b>b2</b></a>'),'/a/b[1]') from dual;

SELECT extractvalue(XMLType('<a><b>b1</b><b>b2</b></a>'),'/a/b[2]') from dual;

SELECT extractvalue(XMLType('<a><b>b1</b><b>b2</b></a>'),'/a/b') from dual;

SELECT extractvalue(data, 'soapenv:Envelope/soapenv:Body/web:BBB/typ:EEE', 'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.def.com" xmlns:web="http://www.abc.com"') from xmlnstest where id = 1;

--
-- existsnode
--
SELECT existsnode(XMLType('<a><b>d</b></a>'), '/a') from dual;

SELECT existsnode(XMLType('<a><b>d</b></a>'), '/a/b') from dual;

SELECT existsnode(XMLType('<a><b>d</b></a>'), '/a/b/c') from dual;

SELECT existsnode(b, '/a/b') from inaf where a = 2;

SELECT existsnode(XMLType('<a><b>d</b></a>'), '') from dual;

SELECT existsnode(XMLType('<a><b>d</b></a>'), null) from dual;

SELECT existsnode(data, 'soapenv:Envelope/soapenv:Body/web:BBB/typ:EEE', 'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.def.com" xmlns:web="http://www.abc.com"') from xmlnstest where id = 1;

--
-- deletexml
--
SELECT deletexml(XMLType('<test><value>oldnode</value><value>oldnode</value></test>'),
  '/test/value') from dual;

SELECT deletexml(XMLType('<test><value>111</value><value>222</value></test>'),
  '/test/value[1]') from dual;

SELECT deletexml(XMLType('<test><value>111</value><value>222</value></test>'),
  '/test/value[2]') from dual;

SELECT deletexml(XMLType('<a><b></b><b></b></a>'), '//b') from dual;

SELECT deletexml(XMLType('<a><b></b><b></b></a>'), '/a') from dual;

SELECT deletexml(b, '/a/b') from inaf where a = 2;

SELECT deletexml(XMLType('<test><value></value><value><t>11</t></value></test>'),
  '/test/value/t') from dual;

SELECT deletexml(XMLType('<test><value>12</value><value><t>12</t><b>12</b></value></test>'),
  '/test/value/t') from dual;

SELECT deletexml(XMLType('<a><b></b><b></b></a>'), '') from dual;

SELECT deletexml(XMLType('<a><b></b><b></b></a>'), null) from dual;

SELECT deletexml(data, 'soapenv:Envelope/soapenv:Body/web:BBB/typ:EEE', 'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.def.com" xmlns:web="http://www.abc.com"') from xmlnstest where id = 1;

--
-- appendchildxml
--
SELECT appendchildxml(XMLType('<test><value></value><value></value></test>'),
  '/test/value', XMLTYPE('<name>newnode</name>')) from dual;

SELECT appendchildxml(XMLType('<test><a></a><b></b></test>'),
  '/test/a', XMLTYPE('<name>aaa</name>')) from dual;

SELECT appendchildxml(XMLType('<a><b></b><b></b></a>'), '/a/b', XMLtype('<name>1000</name>')) from dual;

SELECT appendchildxml(XMLType('<a><b></b></a>'), '/a', XMLtype('<name>1000</name>')) from dual;

SELECT appendchildxml(b, '/a/b', XMLtype('<name>1000</name>')) from inaf where a = 2;

SELECT appendchildxml(XMLType('<a><b>666</b></a>'), '/a/b', XMLtype('<name>1000<mm>66</mm></name>')) from dual;

SELECT appendchildxml(XMLType('<ers:OPS xmlns:ers="http://www.test.com/schema/ers/v3"></ers:OPS>'), '/ers:OPS', XMLType('<ers:LOG xmlns:ers="http://www.test.com/schema/ers/v3" IVY="666"></ers:LOG>'),'xmlns:ers="http://www.test.com/schema/ers/v3"') from dual;

--
-- updatexml
--
SELECT updatexml(xmltype('<value>one</value>'), '/value', xmltype('<newvalue>1111</newvalue>')) FROM dual;

SELECT updatexml(b, '/a/b', xmltype('<b>1111</b>')) from inaf where a = 2;

SELECT updatexml(data, '/value', xmltype('<newvalue>newnode</newvalue>')) FROM xmltest;

SELECT updatexml(data, '/value/text()', '1000') FROM xmltest;

SELECT updatexml(XMLTYPE('<a><b>b1</b><b>b2</b></a>'), '/b', '1000') FROM dual;

SELECT updatexml(XMLTYPE('<a><b>b1</b><b>b2</b></a>'), '/b[1]/text()', '1000') FROM dual;

SELECT updatexml(data, 'soapenv:Envelope/soapenv:Body/web:BBB/typ:EEE/text()',123, 'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.def.com" xmlns:web="http://www.abc.com"') from xmlnstest where id = 1;

--
-- insertxmlbefore
--
SELECT insertxmlbefore(XMLType('<a>a</a>'),'/a', XMLType('<b>b</b>')) from dual;

SELECT insertxmlbefore(XMLType('<a><b>b</b></a>'),'/a/b', XMLType('<c>c</c>')) from dual;

SELECT insertxmlbefore(XMLType('<a><b></b></a>'),'/a/b', XMLType('<c></c>')) from dual;

SELECT insertxmlbefore(XMLType('<a>222<b>100</b></a>'), '/a/b', XMLTYPE('<c>88</c>')) from dual;

SELECT insertxmlbefore(XMLType('<a>222<b>100</b><b>200</b></a>'), '/a/b', XMLTYPE('<c>88</c>')) from dual;

SELECT insertxmlbefore(XMLType('<a>222<b>100</b><b>200</b></a>'), '/a/b[1]', XMLTYPE('<c>88</c>')) from dual;

SELECT insertxmlbefore(XMLType('<a>222<b>100</b><b>200</b></a>'), '/a/b[2]', XMLTYPE('<c>88</c>')) from dual;

SELECT insertxmlbefore(XMLType('<a>222<b>100</b><b>200</b></a>'), '/b', XMLTYPE('<c>88</c>')) from dual;

SELECT insertxmlbefore(b,'/a/b', XMLType('<c>200</c>')) from inaf where a = 2;

SELECT insertxmlbefore(data, 'soapenv:Envelope/soapenv:Body/web:BBB/typ:EEE', XMLType('<typ:IVY xmlns:typ="http://www.def.com">Ivory</typ:IVY>'), 'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.def.com" xmlns:web="http://www.abc.com"') from xmlnstest where id = 1;

--
-- insertxmlafter
--
SELECT insertxmlafter(XMLType('<a><b>100</b></a>'),'/a/b',XMLType('<c>88</c>')) from dual;

SELECT insertxmlafter(XMLType('<a>200<b>100</b><b>300</b></a>'),'/a/b',XMLType('<c>88</c>')) from dual;

SELECT insertxmlafter(XMLType('<a>200<b>100</b><b>300</b></a>'),'/a/b[1]',XMLType('<c>88</c>')) from dual;

SELECT insertxmlafter(XMLType('<a>200<b>100</b><b>300</b></a>'),'/a/b[2]',XMLType('<c>88</c>')) from dual;

SELECT insertxmlafter(XMLType('<a>200<b>100</b><b>300</b></a>'),'/b',XMLType('<c>88</c>')) from dual;

SELECT insertxmlafter(b,'/a/b', XMLType('<c>200</c>')) from inaf where a = 2;

SELECT insertxmlafter(data, 'soapenv:Envelope/soapenv:Body/web:BBB/typ:EEE', XMLType('<typ:IVY xmlns:typ="http://www.def.com">Ivory</typ:IVY>'), 'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.def.com" xmlns:web="http://www.abc.com"') from xmlnstest where id = 1;

--
-- insertchildxml
--
SELECT insertchildxml(XMLType('<a>one<b></b>three<b></b></a>'), '//b', 'name', XMLTYPE('<name>newnode</name>')) from dual;

SELECT insertchildxml(XMLType('<a><b>100</b></a>'), '/a/b', 'c', XMLType('<c>88</c>')) from dual;

SELECT insertchildxml(XMLType('<a><b>100</b></a>'), '/a/b', 'c', XMLType('<m>88</m>')) from dual;

SELECT insertchildxml(b, '/a/b', 'c', XMLType('<c>200</c>')) from inaf where a = 2;

SELECT insertchildxml(XMLType('<a><b>100</b><b>200</b></a>'), '/a/b', 'c', XMLType('<c>88</c>')) from dual;

SELECT insertchildxml(XMLType('<a><b>100</b><b>200</b></a>'), '/a/b[1]', 'c', XMLType('<c>88</c>')) from dual;

SELECT insertchildxml(XMLType('<a><b>100</b><b>200</b></a>'), '/a/b[2]', 'c', XMLType('<c>88</c>')) from dual;

SELECT insertchildxml(data, 'soapenv:Envelope/soapenv:Body/web:BBB/typ:EEE','typ:IVY', XMLType('<typ:IVY xmlns:typ="http://www.def.com">Ivory</typ:IVY>'), 'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.def.com" xmlns:web="http://www.abc.com"') from xmlnstest where id = 1;

--
-- insertchildxmlbefore
--
SELECT insertchildxmlbefore(XMLType('<a><b>100</b></a>'), '/a/b', 'b', XMLType('<c>88</c>')) from dual;

SELECT insertchildxmlbefore(XMLType('<a><b>100</b></a>'), '/a', 'b', XMLType('<c>88</c>')) from dual;

SELECT insertchildxmlbefore(XMLType('<a><b>100</b><b>200</b></a>'), '/a', 'b', XMLType('<c>88</c>')) from dual;

SELECT insertchildxmlbefore(XMLType('<a><b>100</b><b>200</b></a>'), '/a', 'b[1]', XMLType('<c>88</c>')) from dual;

SELECT insertchildxmlbefore(XMLType('<a><b>100</b><b>200</b></a>'), '/a', 'b[2]', XMLType('<c>88</c>')) from dual;

SELECT insertchildxmlbefore(b, '/a', 'b', XMLType('<c>200</c>')) from inaf where a = 2;

SELECT insertchildxmlbefore(XMLType('<a><b>100</b><b>200</b></a>'), '/a/b[1]', 'b', XMLType('<c>88</c>')) from dual;

SELECT insertchildxmlbefore(data, 'soapenv:Envelope/soapenv:Body/web:BBB','typ:FFF', XMLType('<typ:IVY xmlns:typ="http://www.def.com">Ivory</typ:IVY>'), 'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.def.com" xmlns:web="http://www.abc.com"') from xmlnstest where id = 1;

--
-- insertchildxmlafter
--
SELECT insertchildxmlafter(XMLType('<a><b>100</b></a>'), '/a/b', 'b', XMLType('<c>88</c>')) from dual;

SELECT insertchildxmlafter(XMLType('<a><b>100</b></a>'), '/a', 'b', XMLType('<c>88</c>')) from dual;

SELECT insertchildxmlafter(XMLType('<a><b>100</b><b>200</b></a>'), '/a', 'b', XMLType('<c>88</c>')) from dual;

SELECT insertchildxmlafter(XMLType('<a><b>100</b><b>200</b></a>'), '/a', 'b[1]', XMLType('<c>88</c>')) from dual;

SELECT insertchildxmlafter(XMLType('<a><b>100</b><b>200</b></a>'), '/a', 'b[2]', XMLType('<c>88</c>')) from dual;

SELECT insertchildxmlafter(b, '/a', 'b', XMLType('<c>200</c>')) from inaf where a = 2;

SELECT insertchildxmlafter(XMLType('<a><b>100</b><b>200</b></a>'), '/a/b[1]', 'b', XMLType('<c>88</c>')) from dual;

SELECT insertchildxmlafter(data, 'soapenv:Envelope/soapenv:Body/web:BBB','typ:FFF', XMLType('<typ:IVY xmlns:typ="http://www.def.com">Ivory</typ:IVY>'), 'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="http://www.def.com" xmlns:web="http://www.abc.com"') from xmlnstest where id = 1;

drop table inaf;
drop table xmltest;
drop table xmlnstest;
