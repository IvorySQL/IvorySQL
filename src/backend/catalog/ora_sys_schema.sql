/*
 * ora_sys_schema.sql
 *
 * Oracle Compatibility "sys" schema
 *
 * Copyright (c) 2022, IvorySQL-2.0
 *
 * src/backend/catalog/ora_sys_schema.sql
 *
 * IDENTIFICATION
 *	  src/backend/catalog/ora_sys_schema.sql
 *
 * add the file for requirement "SQL PARSER"
 *
 */
GRANT USAGE ON SCHEMA sys TO PUBLIC;
SET search_path TO sys;

CREATE table dual (DUMMY CHAR(1));
insert into dual values('X');
GRANT SELECT ON dual TO PUBLIC;