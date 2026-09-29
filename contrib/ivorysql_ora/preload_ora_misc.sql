GRANT USAGE ON SCHEMA sys TO PUBLIC; 
SET search_path TO sys; 

CREATE table dual (DUMMY pg_catalog.bpchar(1));
insert into dual values('X');
GRANT SELECT ON dual TO PUBLIC;

--
-- Oracle-compatible ROWID and UROWID types
-- ROWID: Composite type containing row object ID and row number
-- UROWID: Universal ROWID, compatible with ROWID
--
CREATE TYPE sys.rowid AS(rowoid OID, rowno bigint);
CREATE TYPE sys.urowid AS(rowoid OID, rowno bigint);

-- A REF stores a logical object-table row identifier.  regclass text I/O
-- preserves the table identity across pg_dump/restore, unlike a bare OID.
CREATE TYPE sys.object_ref AS(table_id regclass, rowno bigint);

CREATE FUNCTION sys.make_object_ref(sys.rowid) RETURNS sys.object_ref
LANGUAGE SQL IMMUTABLE STRICT
AS $$ SELECT ROW(($1).rowoid::regclass, ($1).rowno)::sys.object_ref $$;

CREATE FUNCTION sys.object_ref_matches_domain(sys.object_ref, oid) RETURNS boolean
LANGUAGE SQL STABLE STRICT
AS $$ SELECT EXISTS (
    SELECT 1 FROM pg_catalog.pg_type t
    LEFT JOIN pg_catalog.pg_class c ON c.oid = ($1).table_id
    WHERE t.oid = $2 AND (c.oid IS NULL OR c.reloftype = t.typrefbase)
) $$;

CREATE CAST (sys.rowid AS sys.urowid) WITH INOUT AS IMPLICIT;
CREATE CAST (sys.urowid AS sys.rowid) WITH INOUT AS IMPLICIT;

--
-- Plugin uuid-ossp
--
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
