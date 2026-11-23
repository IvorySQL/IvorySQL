-- XMLTYPE forward declaration
CREATE TYPE sys.XMLTYPE;

--
-- XMLTYPE input/output functions
--
CREATE FUNCTION sys.xmltype_in(cstring)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_xmltype_in'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.xmltype_out(sys.xmltype)
RETURNS cstring
AS 'MODULE_PATHNAME','ivy_xmltype_out'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE TYPE sys.XMLTYPE (
	INPUT		   = sys.xmltype_in,
	OUTPUT		   = sys.xmltype_out,
	LIKE		   = xml
);


-------------------------------------------------------
-- Oracle 12c SQL/XML functions
-------------------------------------------------------

--
-- EXISTSNODE
--
CREATE FUNCTION sys.EXISTSNODE(sys.xmltype, text)
RETURNS int
AS 'MODULE_PATHNAME','ivy_existsnode'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- existsnode with namespace
CREATE FUNCTION sys.EXISTSNODE(sys.xmltype, text, text)
RETURNS int
AS 'MODULE_PATHNAME','ivy_existsnode2'
LANGUAGE C IMMUTABLE PARALLEL SAFE;


--
-- EXTRACTVALUE
--
CREATE FUNCTION sys.EXTRACTVALUE(sys.xmltype, text)
RETURNS text
AS 'MODULE_PATHNAME','ivy_extractvalue'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- extractvalue with namespace
CREATE FUNCTION sys.EXTRACTVALUE(sys.xmltype, text, text)
RETURNS text
AS 'MODULE_PATHNAME','ivy_extractvalue2'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

--
-- EXTRACT(XML)
--
CREATE FUNCTION sys.EXTRACT(sys.xmltype, text)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_extract'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- extract with namespace
CREATE FUNCTION sys.EXTRACT(sys.xmltype, text, text)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_extract2'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

--
-- DELETEXML
--
CREATE FUNCTION sys.DELETEXML(sys.xmltype, text)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_deletexml'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- deletexml with namespace
CREATE FUNCTION sys.DELETEXML(sys.xmltype, text, text)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_deletexml2'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

--
-- APPENDCHILDXML
--
CREATE FUNCTION sys.APPENDCHILDXML(sys.xmltype, text, sys.xmltype)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_appendchildxml'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- appendchildxml with namespace
CREATE FUNCTION sys.APPENDCHILDXML(sys.xmltype, text, sys.xmltype, text)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_appendchildxml2'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

--
-- INSERTXMLBEFORE
--
CREATE FUNCTION sys.INSERTXMLBEFORE(sys.xmltype, text, sys.xmltype)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_insertxmlbefore'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- insertxmlbefore with namespace
CREATE FUNCTION sys.INSERTXMLBEFORE(sys.xmltype, text, sys.xmltype, text)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_insertxmlbefore2'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

--
-- INSERTXMLAFTER
--
CREATE FUNCTION sys.INSERTXMLAFTER(sys.xmltype, text, sys.xmltype)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_insertxmlafter'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- insertxmlafter with namspace
CREATE FUNCTION sys.INSERTXMLAFTER(sys.xmltype, text, sys.xmltype, text)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_insertxmlafter2'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

--
-- INSERTCHILDXML
--
CREATE FUNCTION sys.INSERTCHILDXML(sys.xmltype, text, text, sys.xmltype)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_insertchildxml'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- insertchildxml with namespace
CREATE FUNCTION sys.INSERTCHILDXML(sys.xmltype, text, text, sys.xmltype, text)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_insertchildxml2'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

--
-- INSERTCHILDXMLBEFORE
--
CREATE FUNCTION sys.INSERTCHILDXMLBEFORE(sys.xmltype, text, text, sys.xmltype)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_insertchildxmlbefore'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- insertchildxmlbefore with namespace
CREATE FUNCTION sys.INSERTCHILDXMLBEFORE(sys.xmltype, text, text, sys.xmltype, text)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_insertchildxmlbefore2'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

--
-- INSERTCHILDXMLAFTER
--
CREATE FUNCTION sys.INSERTCHILDXMLAFTER(sys.xmltype, text, text, sys.xmltype)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_insertchildxmlafter'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- inseretchildxmlafter with namespace
CREATE FUNCTION sys.INSERTCHILDXMLAFTER(sys.xmltype, text, text, sys.xmltype, text)
RETURNS sys.xmltype
AS 'MODULE_PATHNAME','ivy_insertchildxmlafter2'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

--
-- XMLISVALID
--
CREATE OR REPLACE FUNCTION sys.XMLISVALID(sys.xmltype)
RETURNS INTEGER
AS 'MODULE_PATHNAME','ivy_xmlisvalid'
LANGUAGE C IMMUTABLE PARALLEL SAFE;
