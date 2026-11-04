/* Copyright 2026 IvorySQL Global Development Team
 * Licensed under the Apache License, Version 2.0. See LICENSE.
 */
\echo Use "CREATE EXTENSION ivorysql_http" to load this file. \quit

-- No default network access, including for the extension installer.
CREATE TABLE sys.utl_http_host_acl (
  role_oid oid NOT NULL, host text COLLATE "C" NOT NULL,
  port integer NOT NULL CHECK(port BETWEEN 1 AND 65535), ca_file text,
  PRIMARY KEY(role_oid,host,port),
  CHECK(host=lower(host) AND host<>''),
  CHECK(ca_file IS NULL OR ca_file<>'')
);
REVOKE ALL ON sys.utl_http_host_acl FROM PUBLIC;

-- NULL denies access; empty string selects the system certificate store.
-- The C caller always supplies its actual current role, never an application
-- argument. This function exposes no file contents or executable SQL.
CREATE FUNCTION sys.ora_utl_http_policy(target_host text,target_port integer,invoker oid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER
SET ivorysql.compatible_mode=pg SET ivorysql.identifier_case_switch=normal
SET search_path=pg_catalog,pg_temp AS $$
  SELECT coalesce(a.ca_file,'') FROM sys.utl_http_host_acl a
    JOIN pg_catalog.pg_roles r ON r.oid=a.role_oid
  WHERE a.host=lower($1) AND a.port=$2 AND pg_catalog.pg_has_role($3,r.oid,'USAGE')
  ORDER BY (a.role_oid=$3) DESC,a.role_oid LIMIT 1;
$$;

CREATE FUNCTION sys.ora_utl_http_begin(url text,method text,http_version text) RETURNS integer
AS 'MODULE_PATHNAME','ora_http_begin' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_utl_http_set_header(id integer,name text,value text) RETURNS void
AS 'MODULE_PATHNAME','ora_http_header' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_utl_http_write(id integer,data text) RETURNS void
AS 'MODULE_PATHNAME','ora_http_write' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_utl_http_response(id integer) RETURNS void
AS 'MODULE_PATHNAME','ora_http_response' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_utl_http_info(id integer) RETURNS text[]
AS 'MODULE_PATHNAME','ora_http_info' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_utl_http_header_count(id integer) RETURNS integer
AS 'MODULE_PATHNAME','ora_http_header_count' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_utl_http_get_header(id integer,header_position integer) RETURNS text[]
AS 'MODULE_PATHNAME','ora_http_get_header' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_utl_http_read(id integer,len integer) RETURNS text
AS 'MODULE_PATHNAME','ora_http_read' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_utl_http_close(id integer) RETURNS void
AS 'MODULE_PATHNAME','ora_http_close' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_utl_http_timeout(seconds integer) RETURNS integer
AS 'MODULE_PATHNAME','ora_http_timeout' LANGUAGE C VOLATILE PARALLEL UNSAFE;

CREATE OR REPLACE PACKAGE utl_http AUTHID CURRENT_USER IS
  TYPE req IS RECORD(url VARCHAR2(32767),method VARCHAR2(64),http_version VARCHAR2(64),private_id INTEGER);
  TYPE resp IS RECORD(status_code INTEGER,reason_phrase VARCHAR2(256),http_version VARCHAR2(64),private_id INTEGER);
  end_of_body EXCEPTION;
  PRAGMA EXCEPTION_INIT(end_of_body,-29266);
  FUNCTION begin_request(url VARCHAR2,method VARCHAR2 DEFAULT 'GET',http_version VARCHAR2 DEFAULT 'HTTP/1.1') RETURN req;
  PROCEDURE set_header(r IN OUT req,name VARCHAR2,value VARCHAR2);
  PROCEDURE write_text(r IN OUT req,data VARCHAR2);
  FUNCTION get_response(r IN OUT req) RETURN resp;
  FUNCTION get_header_count(r resp) RETURN INTEGER;
  PROCEDURE get_header(r resp,n INTEGER,name OUT VARCHAR2,value OUT VARCHAR2);
  PROCEDURE read_text(r IN OUT resp,data OUT VARCHAR2,len INTEGER DEFAULT 32767);
  PROCEDURE end_response(r IN OUT resp);
  PROCEDURE end_request(r IN OUT req);
  PROCEDURE set_transfer_timeout(timeout INTEGER);
  FUNCTION get_transfer_timeout RETURN INTEGER;
  FUNCTION request(url VARCHAR2,proxy VARCHAR2 DEFAULT NULL,wallet_path VARCHAR2 DEFAULT NULL,
    wallet_password VARCHAR2 DEFAULT NULL,https_host VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;
END utl_http;

CREATE OR REPLACE PACKAGE BODY utl_http IS
  FUNCTION begin_request(url VARCHAR2,method VARCHAR2 DEFAULT 'GET',http_version VARCHAR2 DEFAULT 'HTTP/1.1') RETURN req IS
    result req;
  BEGIN
    result.url:=url; result.method:=method; result.http_version:=http_version;
    result.private_id:=sys.ora_utl_http_begin(url,method,http_version);
    RETURN result;
  END;
  PROCEDURE set_header(r IN OUT req,name VARCHAR2,value VARCHAR2) IS
  BEGIN PERFORM sys.ora_utl_http_set_header(r.private_id,name,value); END;
  PROCEDURE write_text(r IN OUT req,data VARCHAR2) IS
  BEGIN PERFORM sys.ora_utl_http_write(r.private_id,data); END;
  FUNCTION get_response(r IN OUT req) RETURN resp IS
    result resp; info TEXT[];
  BEGIN
    PERFORM sys.ora_utl_http_response(r.private_id);
    info:=sys.ora_utl_http_info(r.private_id);
    result.status_code:=CAST(info[1] AS INTEGER);
    result.reason_phrase:=info[2]; result.http_version:=info[3]; result.private_id:=r.private_id;
    RETURN result;
  END;
  FUNCTION get_header_count(r resp) RETURN INTEGER IS
  BEGIN RETURN sys.ora_utl_http_header_count(r.private_id); END;
  PROCEDURE get_header(r resp,n INTEGER,name OUT VARCHAR2,value OUT VARCHAR2) IS
    info TEXT[];
  BEGIN
    info:=sys.ora_utl_http_get_header(r.private_id,n); name:=info[1]; value:=info[2];
  END;
  PROCEDURE read_text(r IN OUT resp,data OUT VARCHAR2,len INTEGER DEFAULT 32767) IS
  BEGIN
    data:=sys.ora_utl_http_read(r.private_id,len);
    IF data IS NULL THEN RAISE end_of_body; END IF;
  END;
  PROCEDURE end_response(r IN OUT resp) IS
  BEGIN PERFORM sys.ora_utl_http_close(r.private_id); r.private_id:=NULL; END;
  PROCEDURE end_request(r IN OUT req) IS
  BEGIN PERFORM sys.ora_utl_http_close(r.private_id); r.private_id:=NULL; END;
  PROCEDURE set_transfer_timeout(timeout INTEGER) IS
  BEGIN
    IF timeout IS NULL THEN RAISE EXCEPTION 'HTTP timeout must not be null'; END IF;
    PERFORM sys.ora_utl_http_timeout(timeout);
  END;
  FUNCTION get_transfer_timeout RETURN INTEGER IS
  BEGIN RETURN sys.ora_utl_http_timeout(NULL); END;
  FUNCTION request(url VARCHAR2,proxy VARCHAR2 DEFAULT NULL,wallet_path VARCHAR2 DEFAULT NULL,
    wallet_password VARCHAR2 DEFAULT NULL,https_host VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    rq req; rs resp; result VARCHAR2;
  BEGIN
    IF proxy IS NOT NULL OR wallet_path IS NOT NULL OR wallet_password IS NOT NULL OR https_host IS NOT NULL THEN
      RAISE EXCEPTION 'proxy, wallet and https_host overrides are not supported';
    END IF;
    rq:=begin_request(url); rs:=get_response(rq);
    BEGIN
      read_text(rs,result,2000);
    EXCEPTION WHEN end_of_body THEN result:='';
    END;
    end_response(rs); RETURN result;
  EXCEPTION WHEN OTHERS THEN end_request(rq); RAISE;
  END;
END utl_http;
