--
-- Test INSERT alias.col in Oracle mode
--
set ivorysql.compatible_mode to oracle;
show ivorysql.compatible_mode;

CREATE TABLE alitb1 (a1 int, a2 int);

INSERT INTO alitb1(a1, a2) VALUES(1, 100);
INSERT INTO alitb1 AS al(al.a1, al.a2) VALUES(2, 200);

show ivorysql.insert_enable_alias;
set ivorysql.insert_enable_alias to on;
show ivorysql.insert_enable_alias;

INSERT INTO alitb1 AS al(al.a1, al.a2) VALUES(2, 200);

SELECT * FROM alitb1 ORDER BY a1;

reset ivorysql.insert_enable_alias;
show ivorysql.insert_enable_alias;

-- cleanup
DROP TABLE alitb1;

CREATE TYPE dtp AS (b1 int, b2 int);
CREATE TABLE alitb2(a1 int, a2 dtp);

INSERT INTO alitb2(a1, a2) VALUES(100, (1,1));
INSERT INTO alitb2(a1, a2.b1) VALUES(200, 2);
INSERT INTO alitb2(a1, a2.b2) VALUES(300, 3);
INSERT INTO alitb2 AS al(al.a1, al.a2) VALUES(400, (4,4));

show ivorysql.insert_enable_alias;
set ivorysql.insert_enable_alias to on;
show ivorysql.insert_enable_alias;

INSERT INTO alitb2 AS al(al.a1, al.a2) VALUES(400, (4,4));
INSERT INTO alitb2 AS al(al.a1, a2.b1) VALUES(500, 5);
INSERT INTO alitb2 AS al(al.a1, a2) VALUES(600, (6,6));
INSERT INTO alitb2 AS al(al.a1, al.a2.b1) VALUES(700, 7);

SELECT * FROM alitb2 ORDER BY a1;

--cleanup
DROP TABLE alitb2;
DROP TYPE dtp;
reset ivorysql.insert_enable_alias;

--
-- Test INSERT alias.col in pg mode
--
set ivorysql.compatible_mode to pg;
show ivorysql.compatible_mode;

CREATE TABLE alitb1 (a1 int, a2 int);

INSERT INTO alitb1(a1, a2) VALUES(1, 100);
INSERT INTO alitb1 AS al(al.a1, al.a2) VALUES(2, 200);

show ivorysql.insert_enable_alias;
set ivorysql.insert_enable_alias to on;
show ivorysql.insert_enable_alias;

INSERT INTO alitb1 AS al(al.a1, al.a2) VALUES(2, 200);

SELECT * FROM alitb1 ORDER BY a1;

reset ivorysql.insert_enable_alias;

-- cleanup
DROP TABLE alitb1;

CREATE TYPE dtp AS (b1 int, b2 int);
CREATE TABLE alitb2(a1 int, a2 dtp);

INSERT INTO alitb2(a1, a2) VALUES(100, (1,1));
INSERT INTO alitb2(a1, a2.b1) VALUES(200, 2);
INSERT INTO alitb2(a1, a2.b2) VALUES(300, 3);
INSERT INTO alitb2 AS al(al.a1, al.a2) VALUES(400, (4,4));

show ivorysql.insert_enable_alias;
set ivorysql.insert_enable_alias to on;
show ivorysql.insert_enable_alias;

INSERT INTO alitb2 AS al(al.a1, al.a2) VALUES(400, (4,4));
INSERT INTO alitb2 AS al(al.a1, a2.b1) VALUES(500, 5);
INSERT INTO alitb2 AS al(al.a1, a2) VALUES(600, (6,6));
INSERT INTO alitb2 AS al(al.a1, al.a2.b1) VALUES(700, 7);

SELECT * FROM alitb2 ORDER BY a1;

--cleanup
DROP TABLE alitb2;
DROP TYPE dtp;
reset ivorysql.insert_enable_alias;
reset ivorysql.compatible_mode;