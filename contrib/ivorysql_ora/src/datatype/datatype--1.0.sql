/***************************************************************
 *
 * sys.char(n char) type support
 *
 ***************************************************************/
/* Basic I/O functions for oracharchar */ 
CREATE FUNCTION sys.oracharcharin(cstring,oid,integer)
RETURNS sys.oracharchar
AS 'MODULE_PATHNAME','oracharcharin'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oracharcharout(sys.oracharchar)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oracharcharout'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oracharcharrecv(internal,oid,integer)
RETURNS sys.oracharchar
AS 'MODULE_PATHNAME','oracharcharrecv'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oracharcharsend(sys.oracharchar)
RETURNS bytea
AS 'MODULE_PATHNAME','oracharcharsend'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oracharchartypmodin(cstring[])
RETURNS integer
AS 'MODULE_PATHNAME','oracharchartypmodin'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oracharchartypmodout(integer)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oracharchartypmodout'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

/* The support routine required by B-trees */
CREATE FUNCTION sys.oracharcharcmp(sys.oracharchar, sys.oracharchar)
RETURNS integer
AS 'MODULE_PATHNAME','oracharcharcmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.orachar_bytecmp(sys.oracharchar, sys.oracharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','oracharcharcmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oracharchar_sortsupport(internal)
RETURNS void
AS 'MODULE_PATHNAME','oracharchar_sortsupport'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.btoravarstrequalimage(oid)
RETURNS boolean
AS 'btvarstrequalimage'
LANGUAGE internal
STRICT
IMMUTABLE;

/* Conversion Function */
-- Converts a oracharchar type to the specified size
CREATE FUNCTION sys.oracharchar(sys.oracharchar,integer,boolean)
RETURNS sys.oracharchar
AS 'MODULE_PATHNAME','oracharchar'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

-- Convert between text with orachar 
CREATE FUNCTION sys.text(sys.oracharchar)
RETURNS text
AS 'MODULE_PATHNAME','rtrim'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

-- Convert oracharchar to signal-byte "char"
CREATE FUNCTION sys.orachar_char(sys.oracharchar)
RETURNS pg_catalog.char
AS 'MODULE_PATHNAME','orachar_char'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

-- Convert signal-byte "char" to oracharchar and oracharbyte
CREATE FUNCTION sys.char_orachar(pg_catalog.char)
RETURNS sys.oracharchar
AS 'MODULE_PATHNAME','char_orachar'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

-- Convert oracharchar to name 
CREATE FUNCTION sys.orachar_name(sys.oracharchar)
RETURNS name
AS 'MODULE_PATHNAME','orachar_name'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

-- Convert name to oracharchar
CREATE FUNCTION sys.name_orachar(name)
RETURNS sys.oracharchar
AS 'MODULE_PATHNAME','name_orachar'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

-- Convert inet/cidr to oracharchar
CREATE FUNCTION sys.inet_orachar(inet)
RETURNS sys.oracharchar
AS 'network_show'
LANGUAGE internal
STRICT
STABLE;

-- Convert boolean to oracharchar
CREATE FUNCTION sys.bool_orachar(boolean)
RETURNS sys.oracharchar
AS 'MODULE_PATHNAME','bool_orachar'
LANGUAGE C
STRICT
IMMUTABLE;

-- Convert oracharchar to xml
CREATE FUNCTION sys.orachar_xml(sys.oracharchar)
RETURNS xml
AS 'texttoxml'
LANGUAGE internal
PARALLEL SAFE
STRICT
STABLE;

/* Aggregate Function */
CREATE FUNCTION sys.oracharchar_larger(sys.oracharchar, sys.oracharchar)
RETURNS sys.oracharchar
AS 'MODULE_PATHNAME','oracharchar_larger'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.oracharchar_smaller(sys.oracharchar, sys.oracharchar)
RETURNS sys.oracharchar
AS 'MODULE_PATHNAME','oracharchar_smaller'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

/* Operator function (oracharchar, oracharchar) */
CREATE FUNCTION sys.oracharchareq(sys.oracharchar, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharchareq'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.oracharcharne(sys.oracharchar, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharcharne'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.oracharcharle(sys.oracharchar, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharcharle'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;


CREATE FUNCTION sys.oracharchargt(sys.oracharchar, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharchargt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.oracharcharlt(sys.oracharchar, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharcharlt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.oracharcharge(sys.oracharchar, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharcharge'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

/* Operator function (oracharchar, oracharbyte) */
CREATE FUNCTION sys.orachar_byteeq(sys.oracharchar, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharchareq'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_bytene(sys.oracharchar, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharcharne'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_bytele(sys.oracharchar, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharcharle'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_bytegt(sys.oracharchar, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharchargt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_bytelt(sys.oracharchar, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharcharlt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_bytege(sys.oracharchar, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharcharge'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

-- Register the basic I/O for 'oracharchar' in pg_type.
UPDATE pg_type
SET typinput=(SELECT oid FROM pg_proc WHERE proname='oracharcharin')
WHERE oid = 9500;

UPDATE pg_type
SET typoutput=(SELECT oid FROM pg_proc WHERE proname='oracharcharout')
WHERE oid = 9500;

UPDATE pg_type
SET typreceive=(SELECT oid FROM pg_proc WHERE proname='oracharcharrecv')
WHERE oid = 9500;

UPDATE pg_type
SET typsend=(SELECT oid FROM pg_proc WHERE proname='oracharcharsend')
WHERE oid = 9500;

UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oracharchartypmodin')
WHERE oid = 9500;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oracharchartypmodout')
WHERE oid = 9500;

-- Register the typmod inout for 'oracharchar' array type in pg_type.
UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oracharchartypmodin')
WHERE oid = 9504;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oracharchartypmodout')
WHERE oid = 9504;

/* CREATE CAST */
---------- Compatible Postgresql Cast ----------
CREATE CAST (sys.oracharchar AS text)
WITH FUNCTION sys.text(sys.oracharchar)
AS IMPLICIT;

CREATE CAST (text AS sys.oracharchar)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (sys.oracharchar AS pg_catalog.bpchar)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (pg_catalog.bpchar AS sys.oracharchar)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (sys.oracharchar AS pg_catalog.varchar)
WITH FUNCTION sys.text(sys.oracharchar)
AS IMPLICIT;

CREATE CAST (pg_catalog.varchar AS sys.oracharchar)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (pg_catalog.char AS sys.oracharchar)
WITH FUNCTION sys.char_orachar(pg_catalog.char)
AS ASSIGNMENT;

CREATE CAST (sys.oracharchar AS pg_catalog.char)
WITH FUNCTION sys.orachar_char(sys.oracharchar)
AS ASSIGNMENT;

CREATE CAST (name AS sys.oracharchar)
WITH FUNCTION sys.name_orachar(name)
AS ASSIGNMENT;

CREATE CAST (sys.oracharchar AS name)
WITH FUNCTION sys.orachar_name(sys.oracharchar)
AS IMPLICIT;

CREATE CAST (cidr AS sys.oracharchar)
WITH FUNCTION sys.inet_orachar(inet)
AS ASSIGNMENT;

CREATE CAST (inet AS sys.oracharchar)
WITH FUNCTION sys.inet_orachar(inet)
AS ASSIGNMENT;

CREATE CAST (boolean AS sys.oracharchar)
WITH FUNCTION sys.bool_orachar(boolean)
AS ASSIGNMENT;

CREATE CAST (xml AS sys.oracharchar)
WITHOUT FUNCTION
AS ASSIGNMENT;

CREATE CAST (sys.oracharchar AS xml)
WITH FUNCTION sys.orachar_xml(sys.oracharchar);

---------- Compatible Oracle Cast ----------
CREATE CAST (sys.oracharchar AS numeric)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharchar AS sys.oracharchar)
WITH FUNCTION sys.oracharchar(sys.oracharchar, integer, boolean)
AS IMPLICIT;

CREATE CAST (sys.oracharchar AS sys.oracharbyte)
WITHOUT FUNCTION
AS IMPLICIT;

-- Convert 'oracharchar' to 'oravarcharchar' 
CREATE FUNCTION sys.orachar_oravarchar(sys.oracharchar)
RETURNS sys.oravarcharchar
AS 'MODULE_PATHNAME','rtrim'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE CAST (sys.oracharchar AS sys.oravarcharchar)
WITH FUNCTION sys.orachar_oravarchar(sys.oracharchar)
AS IMPLICIT;

-- Convert 'oracharchar' to 'oravarcharbyte' 
CREATE FUNCTION sys.orachar_oravarcharbyte(sys.oracharchar)
RETURNS sys.oravarcharbyte
AS 'MODULE_PATHNAME','rtrim'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE CAST (sys.oracharchar AS sys.oravarcharbyte)
WITH FUNCTION sys.orachar_oravarcharbyte(sys.oracharchar)
AS IMPLICIT;

CREATE CAST (sys.oracharchar AS sys.oradate)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharchar AS sys.oratimestamp)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharchar AS sys.oratimestamptz)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharchar AS sys.oratimestampltz)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharchar AS sys.yminterval)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharchar AS sys.dsinterval)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharchar AS sys.number)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharchar AS sys.binary_float)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharchar AS sys.binary_double)
WITH INOUT
AS IMPLICIT;

/***************************************************************
 *
 * sys.char(n byte) type support
 *
 ****************************************************************/
/* Basic I/O functions for oracharbyte */
CREATE FUNCTION sys.oracharbytein(cstring,oid,integer)
RETURNS sys.oracharbyte
AS 'MODULE_PATHNAME','oracharbytein'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oracharbyteout(sys.oracharbyte)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oracharbyteout'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oracharbyterecv(internal,oid,integer)
RETURNS sys.oracharbyte
AS 'MODULE_PATHNAME','oracharbyterecv'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oracharbytesend(sys.oracharbyte)
RETURNS bytea
AS 'MODULE_PATHNAME','oracharbytesend'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oracharbytetypmodin(cstring[])
RETURNS integer
AS 'MODULE_PATHNAME','oracharbytetypmodin'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oracharbytetypmodout(integer)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oracharbytetypmodout'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

/* The support routine required by B-trees */
CREATE FUNCTION sys.oracharbytecmp(sys.oracharbyte, sys.oracharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','oracharbytecmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.orabyte_charcmp(sys.oracharbyte, sys.oracharchar)
RETURNS integer
AS 'MODULE_PATHNAME','oracharbytecmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oracharbyte_sortsupport(internal)
RETURNS void
AS 'MODULE_PATHNAME','oracharbyte_sortsupport'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

/* Conversion function */
-- Converts a oracharbyte type to the specified size
CREATE FUNCTION sys.oracharbyte(sys.oracharbyte,integer,boolean)
RETURNS sys.oracharbyte
AS 'MODULE_PATHNAME','oracharbyte'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

-- Convert between text with oracharbyte
CREATE FUNCTION sys.text(sys.oracharbyte)
RETURNS text
AS 'MODULE_PATHNAME','rtrim'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

-- Convert oracharbyte to signal-byte "char"
CREATE FUNCTION sys.orachar_char(sys.oracharbyte)
RETURNS pg_catalog.char
AS 'MODULE_PATHNAME','orachar_char'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

-- Convert oracharbyte to name 
CREATE FUNCTION sys.orachar_name(sys.oracharbyte)
RETURNS name
AS 'MODULE_PATHNAME','orachar_name'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

-- Convert oracharbyte to xml 
CREATE FUNCTION sys.orachar_xml(sys.oracharbyte)
RETURNS xml
AS 'texttoxml'
LANGUAGE internal
PARALLEL SAFE
STRICT
STABLE;

/* Aggregate Function */
CREATE FUNCTION sys.oracharbyte_larger(sys.oracharbyte, sys.oracharbyte)
RETURNS sys.oracharbyte
AS 'MODULE_PATHNAME','oracharbyte_larger'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.oracharbyte_smaller(sys.oracharbyte, sys.oracharbyte)
RETURNS sys.oracharbyte
AS 'MODULE_PATHNAME','oracharbyte_smaller'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

/* Operator function for (oracharbyte, oracharbyte) */
CREATE FUNCTION sys.oracharbyteeq(sys.oracharbyte, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharbyteeq'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.oracharbytene(sys.oracharbyte, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharbytene'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.oracharbytele(sys.oracharbyte, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharbytele'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.oracharbytegt(sys.oracharbyte, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharbytegt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.oracharbytelt(sys.oracharbyte, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharbytelt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.oracharbytege(sys.oracharbyte, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharbytege'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

/* Operator function for (oracharbyte, oracharchar) */
CREATE FUNCTION sys.orabyte_chareq(sys.oracharbyte, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharbyteeq'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orabyte_charne(sys.oracharbyte, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharbytene'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orabyte_charle(sys.oracharbyte, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharbytele'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orabyte_chargt(sys.oracharbyte, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharbytegt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orabyte_charlt(sys.oracharbyte, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharbytelt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orabyte_charge(sys.oracharbyte, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oracharbytege'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

-- Register the basic I/O for 'oracharbyte' in pg_type.
UPDATE pg_type
SET typinput=(SELECT oid FROM pg_proc WHERE proname='oracharbytein')
WHERE oid = 9501;

UPDATE pg_type
SET typoutput=(SELECT oid FROM pg_proc WHERE proname='oracharbyteout')
WHERE oid = 9501;

UPDATE pg_type
SET typreceive=(SELECT oid FROM pg_proc WHERE proname='oracharbyterecv')
WHERE oid = 9501;

UPDATE pg_type
SET typsend=(SELECT oid FROM pg_proc WHERE proname='oracharbytesend')
WHERE oid = 9501;

UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oracharbytetypmodin')
WHERE oid = 9501;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oracharbytetypmodout')
WHERE oid = 9501;

-- Register the typmod inout for 'oracharbyte' array type in pg_type.
UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oracharbytetypmodin')
WHERE oid = 9505;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oracharbytetypmodout')
WHERE oid = 9505;

/* CREATE CAST */
----------- Compatible Postgresql cast -----------
CREATE CAST (sys.oracharbyte AS text)
WITH FUNCTION sys.text(sys.oracharbyte)
AS IMPLICIT;

CREATE CAST (text AS sys.oracharbyte)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (sys.oracharbyte AS bpchar)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (bpchar AS sys.oracharbyte)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (sys.oracharbyte AS pg_catalog.varchar)
WITH FUNCTION sys.text(sys.oracharbyte)
AS IMPLICIT;

CREATE CAST (pg_catalog.varchar AS sys.oracharbyte)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (pg_catalog.char AS sys.oracharbyte)
WITH FUNCTION sys.char_orachar(pg_catalog.char)
AS ASSIGNMENT;

CREATE CAST (sys.oracharbyte AS pg_catalog.char)
WITH FUNCTION sys.orachar_char(sys.oracharbyte)
AS ASSIGNMENT;

CREATE CAST (name AS sys.oracharbyte)
WITH FUNCTION sys.name_orachar(name)
AS ASSIGNMENT;

CREATE CAST (sys.oracharbyte AS name)
WITH FUNCTION sys.orachar_name(sys.oracharbyte)
AS IMPLICIT;

CREATE CAST (cidr AS sys.oracharbyte)
WITH FUNCTION sys.inet_orachar(inet)
AS ASSIGNMENT;

CREATE CAST (inet AS sys.oracharbyte)
WITH FUNCTION sys.inet_orachar(inet)
AS ASSIGNMENT;

CREATE CAST (boolean AS sys.oracharbyte)
WITH FUNCTION sys.bool_orachar(boolean)
AS ASSIGNMENT;

CREATE CAST (xml AS sys.oracharbyte)
WITHOUT FUNCTION
AS ASSIGNMENT;

CREATE CAST (sys.oracharbyte AS xml)
WITH FUNCTION sys.orachar_xml(sys.oracharbyte);

----------- Compatible Oracle Cast -----------
CREATE CAST (sys.oracharbyte AS numeric)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharbyte AS sys.oracharbyte)
WITH FUNCTION sys.oracharbyte(sys.oracharbyte, integer, boolean)
AS IMPLICIT;

CREATE CAST (sys.oracharbyte AS sys.oracharchar)
WITHOUT FUNCTION
AS IMPLICIT;

-- Convert 'oracharbyte' to 'oravarcharchar' 
CREATE FUNCTION sys.orachar_oravarchar(sys.oracharbyte)
RETURNS sys.oravarcharchar
AS 'MODULE_PATHNAME','rtrim'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE CAST (sys.oracharbyte AS sys.oravarcharchar)
WITH FUNCTION sys.orachar_oravarchar(sys.oracharbyte)
AS IMPLICIT;

-- Convert 'oracharbyte' to 'oravarcharbyte' 
CREATE FUNCTION sys.orachar_oravarcharbyte(sys.oracharbyte)
RETURNS sys.oravarcharbyte
AS 'MODULE_PATHNAME','rtrim'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE CAST (sys.oracharbyte AS sys.oravarcharbyte)
WITH FUNCTION sys.orachar_oravarcharbyte(sys.oracharbyte)
AS IMPLICIT;

CREATE CAST (sys.oracharbyte AS sys.oradate)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharbyte AS sys.oratimestamp)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharbyte AS sys.oratimestamptz)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharbyte AS sys.oratimestampltz)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharbyte AS sys.yminterval)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharbyte AS sys.dsinterval)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharbyte AS sys.number)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharbyte AS sys.binary_float)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oracharbyte AS sys.binary_double)
WITH INOUT
AS IMPLICIT;

/************************************************************************
 *
 * CREATE OPERATOR FAMILY and OPERATOR CLASS for CHAR(n char/byte)
 *
 **************************************************************************/
/* CREATE OPERATOR for (oracharchar, oracharchar) */
CREATE OPERATOR = (
	procedure = sys.oracharchareq,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharchar,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);

CREATE OPERATOR > (
	procedure = sys.oracharchargt,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharchar,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR < (
	procedure = sys.oracharcharlt,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharchar,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR <> (
	procedure = sys.oracharcharne,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharchar,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);

CREATE OPERATOR >= (
	procedure = sys.oracharcharge,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharchar,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR <= (
	procedure = sys.oracharcharle,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharchar,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
 
/* CREATE OPERATOR for (oracharbyte, oracharbyte) */
CREATE OPERATOR = (
	procedure = sys.oracharbyteeq,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharbyte,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);

CREATE OPERATOR > (
	procedure = sys.oracharbytegt,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharbyte,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR < (
	procedure = sys.oracharbytelt,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharbyte,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR <> (
	procedure = sys.oracharbytene,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharbyte,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);

CREATE OPERATOR >= (
	procedure = sys.oracharbytege,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharbyte,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR <= (
	procedure = sys.oracharbytele,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharbyte,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* CREATE OPERATOR for (oracharchar, oracharbyte) */
CREATE OPERATOR = (
	procedure = sys.orachar_byteeq,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharbyte,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);

CREATE OPERATOR > (
	procedure = sys.orachar_bytegt,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharbyte,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR < (
	procedure = sys.orachar_bytelt,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharbyte,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR <> (
	procedure = sys.orachar_bytene,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharbyte,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);

CREATE OPERATOR >= (
	procedure = sys.orachar_bytege,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharbyte,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR <= (
	procedure = sys.orachar_bytele,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharbyte,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* CREATE OPERATOR for (oracharbyte, oracharchar) */
CREATE OPERATOR = (
	procedure = sys.orabyte_chareq,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharchar,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);

CREATE OPERATOR > (
	procedure = sys.orabyte_chargt,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharchar,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR < (
	procedure = sys.orabyte_charlt,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharchar,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR <> (
	procedure = sys.orabyte_charne,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharchar,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);

CREATE OPERATOR >= (
	procedure = sys.orabyte_charge,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharchar,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR <= (
	procedure = sys.orabyte_charle,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharchar,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

--
-- B-tree index support
--
/* CREATE OPERATOR FAMILY */
CREATE OPERATOR FAMILY sys.orachar_ops USING btree;

/* CREATE OPERATOR CLASS for 'oracharchar' */
CREATE OPERATOR CLASS sys.oracharchar_ops
    DEFAULT FOR TYPE sys.oracharchar USING btree FAMILY sys.orachar_ops AS
        OPERATOR        1       < (sys.oracharchar, sys.oracharchar),
        OPERATOR        2       <= (sys.oracharchar, sys.oracharchar),
        OPERATOR        3       = (sys.oracharchar, sys.oracharchar),
        OPERATOR        4       >= (sys.oracharchar, sys.oracharchar),
        OPERATOR        5       > (sys.oracharchar, sys.oracharchar),
        FUNCTION        1       sys.oracharcharcmp(sys.oracharchar, sys.oracharchar),
		FUNCTION        2 (sys.oracharchar, sys.oracharchar)       sys.oracharchar_sortsupport(internal),
		FUNCTION        4 (sys.oracharchar, sys.oracharchar)       sys.btoravarstrequalimage(oid);
		
/* CREATE OPERATOR CLASS for 'oracharbyte' */
CREATE OPERATOR CLASS sys.oracharbyte_ops
    DEFAULT FOR TYPE sys.oracharbyte USING btree FAMILY sys.orachar_ops AS
        OPERATOR        1       < (sys.oracharbyte, sys.oracharbyte),
        OPERATOR        2       <= (sys.oracharbyte, sys.oracharbyte),
        OPERATOR        3       = (sys.oracharbyte, sys.oracharbyte),
        OPERATOR        4       >= (sys.oracharbyte, sys.oracharbyte),
        OPERATOR        5       > (sys.oracharbyte, sys.oracharbyte),
        FUNCTION        1       sys.oracharbytecmp(sys.oracharbyte, sys.oracharbyte),
		FUNCTION        2 (sys.oracharbyte, sys.oracharbyte)       sys.oracharbyte_sortsupport(internal),
		FUNCTION        4 (sys.oracharbyte, sys.oracharbyte)       sys.btoravarstrequalimage(oid);		

ALTER OPERATOR FAMILY sys.orachar_ops USING btree ADD
	-- Cross data type comparison
	OPERATOR        1       < (sys.oracharchar, sys.oracharbyte),
	OPERATOR        2       <= (sys.oracharchar, sys.oracharbyte),
	OPERATOR        3       = (sys.oracharchar, sys.oracharbyte),
	OPERATOR        4       >= (sys.oracharchar, sys.oracharbyte),
	OPERATOR        5       > (sys.oracharchar, sys.oracharbyte),
	FUNCTION        1       sys.orachar_bytecmp(sys.oracharchar, sys.oracharbyte),
	FUNCTION        2 (sys.oracharchar, sys.oracharbyte)       sys.oracharchar_sortsupport(internal),
	
	-- Cross data type comparison
	OPERATOR        1       < (sys.oracharbyte, sys.oracharchar),
	OPERATOR        2       <= (sys.oracharbyte, sys.oracharchar),
	OPERATOR        3       = (sys.oracharbyte, sys.oracharchar),
	OPERATOR        4       >= (sys.oracharbyte, sys.oracharchar),
	OPERATOR        5       > (sys.oracharbyte, sys.oracharchar),
	FUNCTION        1       sys.orabyte_charcmp(sys.oracharbyte, sys.oracharchar),
	FUNCTION        2 (sys.oracharbyte, sys.oracharchar)       sys.oracharbyte_sortsupport(internal);

/*
 * Character-by-Character comparison operators.
 */
/* args type is (sys.oracharchar, sys.oracharchar) */
CREATE FUNCTION sys.orachar_pattern_lt(sys.oracharchar, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_lt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_pattern_le(sys.oracharchar, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_le'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_pattern_ge(sys.oracharchar, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_ge'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_pattern_gt(sys.oracharchar, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_gt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

/* args type is (sys.oracharbyte, sys.oracharbyte) */
CREATE FUNCTION sys.orachar_pattern_lt(sys.oracharbyte, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_lt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_pattern_le(sys.oracharbyte, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_le'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_pattern_ge(sys.oracharbyte, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_ge'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_pattern_gt(sys.oracharbyte, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_gt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

/* args type is (sys.oracharchar, sys.oracharbyte) */
CREATE FUNCTION sys.orachar_pattern_lt(sys.oracharchar, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_lt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_pattern_le(sys.oracharchar, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_le'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_pattern_ge(sys.oracharchar, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_ge'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_pattern_gt(sys.oracharchar, sys.oracharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_gt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

/* args type is (sys.oracharbyte, sys.oracharchar) */
CREATE FUNCTION sys.orachar_pattern_lt(sys.oracharbyte, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_lt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_pattern_le(sys.oracharbyte, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_le'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_pattern_ge(sys.oracharbyte, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_ge'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.orachar_pattern_gt(sys.oracharbyte, sys.oracharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','orachar_pattern_gt'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

/* Index Method Support Routines */
CREATE FUNCTION sys.btorachar_pattern_cmp(sys.oracharchar, sys.oracharchar)
RETURNS INTEGER
AS 'MODULE_PATHNAME','btorachar_pattern_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.btorachar_pattern_cmp(sys.oracharbyte, sys.oracharbyte)
RETURNS INTEGER
AS 'MODULE_PATHNAME','btorachar_pattern_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.btorachar_pattern_cmp(sys.oracharchar, sys.oracharbyte)
RETURNS INTEGER
AS 'MODULE_PATHNAME','btorachar_pattern_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.btorachar_pattern_cmp(sys.oracharbyte, sys.oracharchar)
RETURNS INTEGER
AS 'MODULE_PATHNAME','btorachar_pattern_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE FUNCTION sys.btoracharchar_pattern_sortsupport(internal)
RETURNS void
AS 'MODULE_PATHNAME','btoracharchar_pattern_sortsupport'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.btoracharbyte_pattern_sortsupport(internal)
RETURNS void
AS 'MODULE_PATHNAME','btoracharbyte_pattern_sortsupport'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;


CREATE FUNCTION sys.btoraequalimage(oid)
RETURNS boolean
AS 'btequalimage'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;


/* CREATE OPERATOR */
-- Argument type: (oracharchar, oracharchar)
CREATE OPERATOR ~>~ (
	procedure = sys.orachar_pattern_gt,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharchar,
	commutator = ~<~,
	negator = ~<=~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<~ (
	procedure = sys.orachar_pattern_lt,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharchar,
	commutator = ~>~,
	negator = ~>=~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR ~>=~ (
	procedure = sys.orachar_pattern_ge,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharchar,
	commutator = ~<=~,
	negator = ~<~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<=~ (
	procedure = sys.orachar_pattern_le,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharchar,
	commutator = ~>=~,
	negator = ~>~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

-- Argument type: (oracharbyte, oracharbyte)
CREATE OPERATOR ~>~ (
	procedure = sys.orachar_pattern_gt,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharbyte,
	commutator = ~<~,
	negator = ~<=~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<~ (
	procedure = sys.orachar_pattern_lt,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharbyte,
	commutator = ~>~,
	negator = ~>=~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR ~>=~ (
	procedure = sys.orachar_pattern_ge,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharbyte,
	commutator = ~<=~,
	negator = ~<~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<=~ (
	procedure = sys.orachar_pattern_le,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharbyte,
	commutator = ~>=~,
	negator = ~>~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

-- Argument type: (oracharchar, oracharbyte)
CREATE OPERATOR ~>~ (
	procedure = sys.orachar_pattern_gt,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharbyte,
	commutator = ~<~,
	negator = ~<=~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<~ (
	procedure = sys.orachar_pattern_lt,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharbyte,
	commutator = ~>~,
	negator = ~>=~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR ~>=~ (
	procedure = sys.orachar_pattern_ge,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharbyte,
	commutator = ~<=~,
	negator = ~<~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<=~ (
	procedure = sys.orachar_pattern_le,
	leftarg = sys.oracharchar,
	rightarg = sys.oracharbyte,
	commutator = ~>=~,
	negator = ~>~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

-- Argument type: (oracharbyte, oracharchar)
CREATE OPERATOR ~>~ (
	procedure = sys.orachar_pattern_gt,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharchar,
	commutator = ~<~,
	negator = ~<=~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<~ (
	procedure = sys.orachar_pattern_lt,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharchar,
	commutator = ~>~,
	negator = ~>=~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR ~>=~ (
	procedure = sys.orachar_pattern_ge,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharchar,
	commutator = ~<=~,
	negator = ~<~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<=~ (
	procedure = sys.orachar_pattern_le,
	leftarg = sys.oracharbyte,
	rightarg = sys.oracharchar,
	commutator = ~>=~,
	negator = ~>~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* CREATE OPERATOR FAMILY */
CREATE OPERATOR FAMILY sys.orachar_pattern_ops USING btree;

/* CREATE OPERATOR CLASS for 'oracharchar' */
CREATE OPERATOR CLASS sys.oracharchar_pattern_ops
	FOR TYPE sys.oracharchar USING btree FAMILY sys.orachar_pattern_ops AS
        OPERATOR        1       ~<~ (sys.oracharchar, sys.oracharchar),
        OPERATOR        2       ~<=~ (sys.oracharchar, sys.oracharchar),
        OPERATOR        3       = (sys.oracharchar, sys.oracharchar),
        OPERATOR        4       ~>=~ (sys.oracharchar, sys.oracharchar),
        OPERATOR        5       ~>~ (sys.oracharchar, sys.oracharchar),
        FUNCTION        1       sys.btorachar_pattern_cmp(sys.oracharchar, sys.oracharchar),
		FUNCTION        2 (sys.oracharchar, sys.oracharchar)       sys.btoracharchar_pattern_sortsupport(internal),
		FUNCTION        4 (sys.oracharchar, sys.oracharchar)       sys.btoraequalimage(oid);
		
/* CREATE OPERATOR CLASS for 'oracharbyte' */
CREATE OPERATOR CLASS sys.oracharbyte_pattern_ops
    FOR TYPE sys.oracharbyte USING btree FAMILY sys.orachar_pattern_ops AS
        OPERATOR        1       ~<~ (sys.oracharbyte, sys.oracharbyte),
        OPERATOR        2       ~<=~ (sys.oracharbyte, sys.oracharbyte),
        OPERATOR        3       = (sys.oracharbyte, sys.oracharbyte),
        OPERATOR        4       ~>=~ (sys.oracharbyte, sys.oracharbyte),
        OPERATOR        5       ~>~ (sys.oracharbyte, sys.oracharbyte),
        FUNCTION        1       sys.btorachar_pattern_cmp(sys.oracharbyte, sys.oracharbyte),
		FUNCTION        2 (sys.oracharbyte, sys.oracharbyte)       sys.btoracharbyte_pattern_sortsupport(internal),
		FUNCTION        4 (sys.oracharbyte, sys.oracharbyte)       sys.btoraequalimage(oid);

ALTER OPERATOR FAMILY sys.orachar_pattern_ops USING btree ADD
	-- Cross data type comparison
	OPERATOR        1       ~<~ (sys.oracharchar, sys.oracharbyte),
	OPERATOR        2       ~<=~ (sys.oracharchar, sys.oracharbyte),
	OPERATOR        3       = (sys.oracharchar, sys.oracharbyte),
	OPERATOR        4       ~>=~ (sys.oracharchar, sys.oracharbyte),
	OPERATOR        5       ~>~ (sys.oracharchar, sys.oracharbyte),
	FUNCTION        1       sys.btorachar_pattern_cmp(sys.oracharchar, sys.oracharbyte),
	FUNCTION        2 (sys.oracharchar, sys.oracharbyte)       sys.btoracharchar_pattern_sortsupport(internal),
	-- Cross data type comparison
	OPERATOR        1       ~<~ (sys.oracharbyte, sys.oracharchar),
	OPERATOR        2       ~<=~ (sys.oracharbyte, sys.oracharchar),
	OPERATOR        3       = (sys.oracharbyte, sys.oracharchar),
	OPERATOR        4       ~>=~ (sys.oracharbyte, sys.oracharchar),
	OPERATOR        5       ~>~ (sys.oracharbyte, sys.oracharchar),
	FUNCTION        1       sys.btorachar_pattern_cmp(sys.oracharbyte, sys.oracharchar),
	FUNCTION        2 (sys.oracharbyte, sys.oracharchar)       sys.btoracharbyte_pattern_sortsupport(internal);

--
-- Hash index support
--
CREATE FUNCTION sys.oracharcharhash(sys.oracharchar)
RETURNS integer
AS 'MODULE_PATHNAME','oracharcharhash'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oracharbytehash(sys.oracharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','oracharbytehash'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.hashoracharcharextended(sys.oracharchar, bigint)
RETURNS bigint
AS 'hashbpcharextended'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.hashoracharbyteextended(sys.oracharbyte, bigint)
RETURNS bigint
AS 'hashbpcharextended'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

/* CREATE OPERATOR FAMILY */
CREATE OPERATOR FAMILY sys.orachar_ops USING hash;

/* CREATE OPERATOR CLASS for 'oracharchar' */
CREATE OPERATOR CLASS sys.oracharchar_ops
    DEFAULT FOR TYPE sys.oracharchar USING hash FAMILY sys.orachar_ops AS
		OPERATOR        1       = (sys.oracharchar, sys.oracharchar),
        FUNCTION        1       sys.oracharcharhash(sys.oracharchar),
		FUNCTION        2 (sys.oracharchar, sys.oracharchar)       sys.hashoracharcharextended(sys.oracharchar, bigint);

/* CREATE OPERATOR CLASS for 'oracharbyte' */
CREATE OPERATOR CLASS sys.oracharbyte_ops
    DEFAULT FOR TYPE sys.oracharbyte USING hash FAMILY sys.orachar_ops AS
		OPERATOR        1       = (sys.oracharbyte, sys.oracharbyte),
        FUNCTION        1       sys.oracharbytehash(sys.oracharbyte),
		FUNCTION        2 (sys.oracharbyte, sys.oracharbyte)       sys.hashoracharbyteextended(sys.oracharbyte, bigint);

ALTER OPERATOR FAMILY sys.orachar_ops USING hash ADD
	-- Cross data type comparison
	OPERATOR        1       = (sys.oracharchar, sys.oracharbyte),
	OPERATOR        1       = (sys.oracharbyte, sys.oracharchar);

	
/* CREATE OPERATOR FAMILY */
CREATE OPERATOR FAMILY sys.orachar_pattern_ops USING hash;

/* CREATE OPERATOR CLASS for 'oracharchar' */
CREATE OPERATOR CLASS sys.oracharchar_pattern_ops
    FOR TYPE sys.oracharchar USING hash FAMILY sys.orachar_pattern_ops AS
		OPERATOR        1       = (sys.oracharchar, sys.oracharchar),
        FUNCTION        1       sys.oracharcharhash(sys.oracharchar),
		FUNCTION        2 (sys.oracharchar, sys.oracharchar)       sys.hashoracharcharextended(sys.oracharchar, bigint);

/* CREATE OPERATOR CLASS for 'oracharbyte' */
CREATE OPERATOR CLASS sys.oracharbyte_pattern_ops
    FOR TYPE sys.oracharbyte USING hash FAMILY sys.orachar_pattern_ops AS
		OPERATOR        1       = (sys.oracharbyte, sys.oracharbyte),
        FUNCTION        1       sys.oracharbytehash(sys.oracharbyte),
		FUNCTION        2 (sys.oracharbyte, sys.oracharbyte)       sys.hashoracharbyteextended(sys.oracharbyte, bigint);

ALTER OPERATOR FAMILY sys.orachar_pattern_ops USING hash ADD
	-- Cross data type comparison
	OPERATOR        1       = (sys.oracharchar, sys.oracharbyte),
	OPERATOR        1       = (sys.oracharbyte, sys.oracharchar);


--
-- brin index support for all data type 
--
CREATE FUNCTION sys.brin_minmax_opcinfo(internal)
RETURNS internal
AS 'brin_minmax_opcinfo'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.brin_minmax_add_value(internal, internal, internal, internal)
RETURNS boolean
AS 'brin_minmax_add_value'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.brin_minmax_consistent(internal, internal, internal)
RETURNS boolean
AS 'brin_minmax_consistent'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.brin_minmax_union(internal, internal, internal)
RETURNS boolean
AS 'brin_minmax_union'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

/* CREATE OPERATOR FAMILY */
CREATE OPERATOR FAMILY sys.orachar_minmax_ops USING brin;

/* CREATE OPERATOR CLASS for 'oracharchar' */
CREATE OPERATOR CLASS sys.oracharchar_minmax_ops
    DEFAULT FOR TYPE sys.oracharchar USING brin FAMILY sys.orachar_minmax_ops AS
        OPERATOR        1       < (sys.oracharchar, sys.oracharchar),
        OPERATOR        2       <= (sys.oracharchar, sys.oracharchar),
        OPERATOR        3       = (sys.oracharchar, sys.oracharchar),
        OPERATOR        4       >= (sys.oracharchar, sys.oracharchar),
        OPERATOR        5       > (sys.oracharchar, sys.oracharchar),
        FUNCTION        1       sys.brin_minmax_opcinfo(internal),
		FUNCTION        2       sys.brin_minmax_add_value(internal, internal, internal, internal),
		FUNCTION        3       sys.brin_minmax_consistent(internal, internal, internal),
		FUNCTION        4       sys.brin_minmax_union(internal, internal, internal);
		
/* CREATE OPERATOR CLASS for 'oracharbyte' */
CREATE OPERATOR CLASS sys.oracharbyte_minmax_ops
    DEFAULT FOR TYPE sys.oracharbyte USING brin FAMILY sys.orachar_minmax_ops AS
        OPERATOR        1       < (sys.oracharbyte, sys.oracharbyte),
        OPERATOR        2       <= (sys.oracharbyte, sys.oracharbyte),
        OPERATOR        3       = (sys.oracharbyte, sys.oracharbyte),
        OPERATOR        4       >= (sys.oracharbyte, sys.oracharbyte),
        OPERATOR        5       > (sys.oracharbyte, sys.oracharbyte),
        FUNCTION        1       sys.brin_minmax_opcinfo(internal),
		FUNCTION        2       sys.brin_minmax_add_value(internal, internal, internal, internal),
		FUNCTION        3       sys.brin_minmax_consistent(internal, internal, internal),
		FUNCTION        4       sys.brin_minmax_union(internal, internal, internal);	

ALTER OPERATOR FAMILY sys.orachar_minmax_ops USING brin ADD
	-- Cross data type comparison
	OPERATOR        1       < (sys.oracharchar, sys.oracharbyte),
	OPERATOR        2       <= (sys.oracharchar, sys.oracharbyte),
	OPERATOR        3       = (sys.oracharchar, sys.oracharbyte),
	OPERATOR        4       >= (sys.oracharchar, sys.oracharbyte),
	OPERATOR        5       > (sys.oracharchar, sys.oracharbyte),
	-- Cross data type comparison
	OPERATOR        1       < (sys.oracharbyte, sys.oracharchar),
	OPERATOR        2       <= (sys.oracharbyte, sys.oracharchar),
	OPERATOR        3       = (sys.oracharbyte, sys.oracharchar),
	OPERATOR        4       >= (sys.oracharbyte, sys.oracharchar),
	OPERATOR        5       > (sys.oracharbyte, sys.oracharchar);

/*
 * CREATE AGGREGATE for CHAR(n char/byte).
 */
CREATE AGGREGATE sys.max(sys.oracharchar) (
  SFUNC=sys.oracharchar_larger,
  STYPE= sys.oracharchar,
  SORTOP= >
);
CREATE AGGREGATE sys.min(sys.oracharchar) (
  SFUNC=sys.oracharchar_smaller,
  STYPE= sys.oracharchar,
  SORTOP= <
);

CREATE AGGREGATE sys.max(sys.oracharbyte) (
  SFUNC=sys.oracharbyte_larger,
  STYPE= sys.oracharbyte,
  SORTOP= >
);
CREATE AGGREGATE sys.min(sys.oracharbyte) (
  SFUNC=sys.oracharbyte_smaller,
  STYPE= sys.oracharbyte,
  SORTOP= <
);

/***************************************************************
 *
 * sys.varchar2(n char) type support
 *
 ****************************************************************/
/* Basic I/O functions for oravarcharchar. */
CREATE FUNCTION sys.oravarcharcharin(cstring,oid,integer)
RETURNS sys.oravarcharchar
AS 'MODULE_PATHNAME','oravarcharcharin'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oravarcharcharout(sys.oravarcharchar)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oravarcharcharout'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oravarcharcharrecv(internal,oid,integer)
RETURNS sys.oravarcharchar
AS 'MODULE_PATHNAME','oravarcharcharrecv'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oravarcharcharsend(sys.oravarcharchar)
RETURNS bytea
AS 'MODULE_PATHNAME','oravarcharcharsend'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oravarcharchartypmodin(cstring[])
RETURNS integer
AS 'MODULE_PATHNAME','oravarcharchartypmodin'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oravarcharchartypmodout(integer)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oravarcharchartypmodout'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

/* Conversion Function */
-- Converts a oravarcharchar type to the specified size
CREATE FUNCTION sys.oravarcharchar(sys.oravarcharchar,integer,boolean)
RETURNS sys.oravarcharchar
AS 'MODULE_PATHNAME','oravarcharchar'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

-- relabel the typmod
CREATE FUNCTION sys.oravarcharchar_support(internal)
RETURNS internal
AS 'varchar_support'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

/* Operator function (oravarcharchar, oravarcharchar) */
CREATE FUNCTION sys.oravarcharchareq(sys.oravarcharchar, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchareq'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharcharne(sys.oravarcharchar, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharne'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharcharle(sys.oravarcharchar, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharle'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharchargt(sys.oravarcharchar, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchargt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharcharlt(sys.oravarcharchar, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharlt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharcharge(sys.oravarcharchar, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharge'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

/* Operator function (oravarcharchar, oravarcharbyte) */
CREATE FUNCTION sys.oravarcharchareq(sys.oravarcharchar, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchareq'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharcharne(sys.oravarcharchar, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharne'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharcharle(sys.oravarcharchar, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharle'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharchargt(sys.oravarcharchar, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchargt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharcharlt(sys.oravarcharchar, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharlt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharcharge(sys.oravarcharchar, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharge'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

-- Register the basic I/O for 'oravarcharchar' in pg_type.
UPDATE pg_type
SET typinput=(SELECT oid FROM pg_proc WHERE proname='oravarcharcharin')
WHERE oid = 9502;

UPDATE pg_type
SET typoutput=(SELECT oid FROM pg_proc WHERE proname='oravarcharcharout')
WHERE oid = 9502;

UPDATE pg_type
SET typreceive=(SELECT oid FROM pg_proc WHERE proname='oravarcharcharrecv')
WHERE oid = 9502;

UPDATE pg_type
SET typsend=(SELECT oid FROM pg_proc WHERE proname='oravarcharcharsend')
WHERE oid = 9502;

UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oravarcharchartypmodin')
WHERE oid = 9502;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oravarcharchartypmodout')
WHERE oid = 9502;

-- Register the typmod inout for 'oravarcharchar' array type in pg_type.
UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oravarcharchartypmodin')
WHERE oid = 9506;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oravarcharchartypmodout')
WHERE oid = 9506;

UPDATE pg_proc
SET prosupport=(SELECT oid FROM pg_proc WHERE proname='oravarcharchar_support')
WHERE proname='oravarcharchar';


/* CREATE CAST */
---------- Compatible Postgresql Cast ----------
CREATE FUNCTION sys.oravarchar_regclass(sys.oravarcharchar)
RETURNS OID 
AS 'MODULE_PATHNAME','oravarchar_regclass'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE CAST (sys.oravarcharchar AS pg_catalog.regclass)
WITH FUNCTION oravarchar_regclass(sys.oravarcharchar)
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS pg_catalog.text)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (pg_catalog.text AS sys.oravarcharchar)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS pg_catalog.bpchar)
WITHOUT FUNCTION
AS IMPLICIT;

-- Convert 'bpchar' to 'oravarcharchar' 
CREATE FUNCTION sys.bpchar_oravarchar(pg_catalog.bpchar)
RETURNS sys.oravarcharchar
AS 'MODULE_PATHNAME','rtrim'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (pg_catalog.bpchar AS sys.oravarcharchar)
WITH FUNCTION sys.bpchar_oravarchar(pg_catalog.bpchar)
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS pg_catalog.varchar)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (pg_catalog.varchar AS sys.oravarcharchar)
WITHOUT FUNCTION
AS IMPLICIT;

-- Convert '"char"' to 'oravarcharchar' 
CREATE FUNCTION sys.char_oravarchar(pg_catalog.char)
RETURNS sys.oravarcharchar
AS 'MODULE_PATHNAME','char_oravarchar'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (pg_catalog.char AS sys.oravarcharchar)
WITH FUNCTION sys.char_oravarchar(pg_catalog.char)
AS ASSIGNMENT;

-- Convert 'oravarcharchar' to '"char"'
CREATE FUNCTION sys.oravarchar_char(sys.oravarcharchar)
RETURNS pg_catalog.char
AS 'MODULE_PATHNAME','oravarchar_char'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.oravarcharchar AS pg_catalog.char)
WITH FUNCTION sys.oravarchar_char(sys.oravarcharchar)
AS ASSIGNMENT;

-- Convert 'name' to 'oravarcharchar' 
CREATE FUNCTION sys.name_oravarchar(pg_catalog.name)
RETURNS sys.oravarcharchar
AS 'MODULE_PATHNAME','name_oravarchar'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (pg_catalog.name AS sys.oravarcharchar)
WITH FUNCTION sys.name_oravarchar(pg_catalog.name)
AS ASSIGNMENT;

-- Convert 'oravarcharchar' to 'name'
CREATE FUNCTION sys.oravarchar_name(sys.oravarcharchar)
RETURNS pg_catalog.name
AS 'MODULE_PATHNAME','oravarchar_name'
LANGUAGE C
PARALLEL SAFE
STRICT
LEAKPROOF
IMMUTABLE;

CREATE CAST (sys.oravarcharchar AS pg_catalog.name)
WITH FUNCTION sys.oravarchar_name(sys.oravarcharchar)
AS ASSIGNMENT;

-- Convert cidr to oravarchar
CREATE FUNCTION sys.cidr_oravarchar(cidr)
RETURNS sys.oravarcharchar
AS 'network_show'
LANGUAGE internal
STRICT
STABLE;

CREATE CAST (cidr AS sys.oravarcharchar)
WITH FUNCTION sys.cidr_oravarchar(cidr)
AS ASSIGNMENT;

-- Convert inet to oravarchar
CREATE FUNCTION sys.inet_oravarchar(inet)
RETURNS sys.oravarcharchar
AS 'network_show'
LANGUAGE internal
PARALLEL SAFE
STRICT
STABLE;

CREATE CAST (inet AS sys.oravarcharchar)
WITH FUNCTION sys.inet_oravarchar(inet)
AS ASSIGNMENT;

-- Convert boolean to oravarchar
CREATE FUNCTION sys.bool_oravarchar(pg_catalog.bool)
RETURNS sys.oravarcharchar
AS 'MODULE_PATHNAME','bool_oravarchar'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (pg_catalog.bool AS sys.oravarcharchar)
WITH FUNCTION sys.bool_oravarchar(pg_catalog.bool)
AS ASSIGNMENT;

CREATE CAST (pg_catalog.xml AS sys.oravarcharchar)
WITHOUT FUNCTION
AS ASSIGNMENT;

-- Convert oravarchar to xml
CREATE FUNCTION sys.oravarchar_xml(sys.oravarcharchar)
RETURNS pg_catalog.xml
AS 'MODULE_PATHNAME','oravarchar_xml'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE CAST (sys.oravarcharchar AS pg_catalog.xml)
WITH FUNCTION sys.oravarchar_xml(sys.oravarcharchar);

---------- Compatible Oracle Cast -----------------------
CREATE CAST (sys.oravarcharchar AS sys.oravarcharchar)
WITH FUNCTION sys.oravarcharchar(sys.oravarcharchar, integer, boolean)
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS sys.oravarcharbyte)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS sys.oracharchar)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS sys.oracharbyte)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS sys.oradate)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS sys.oratimestamp)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS sys.oratimestamptz)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS sys.oratimestampltz)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS sys.yminterval)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS sys.dsinterval)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS sys.number)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS sys.binary_float)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS sys.binary_double)
WITH INOUT
AS IMPLICIT;

/***************************************************************
 *
 * sys.varchar2(n byte) type support
 *
 ****************************************************************/
/* Basic I/O functions for oravarcharbyte */
CREATE FUNCTION sys.oravarcharbytein(cstring,oid,integer)
RETURNS sys.oravarcharbyte
AS 'MODULE_PATHNAME','oravarcharbytein'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oravarcharbyteout(sys.oravarcharbyte)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oravarcharbyteout'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oravarcharbyterecv(internal,oid,integer)
RETURNS sys.oravarcharbyte
AS 'MODULE_PATHNAME','oravarcharbyterecv'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oravarcharbytesend(sys.oravarcharbyte)
RETURNS bytea
AS 'MODULE_PATHNAME','oravarcharbytesend'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oravarcharbytetypmodin(cstring[])
RETURNS integer
AS 'MODULE_PATHNAME','oravarcharbytetypmodin'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oravarcharbytetypmodout(integer)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oravarcharbytetypmodout'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

/* Conversion Function */
-- Converts a oracharchar type to the specified size
CREATE FUNCTION sys.oravarcharbyte(sys.oravarcharbyte,integer,boolean)
RETURNS sys.oravarcharbyte
AS 'MODULE_PATHNAME','oravarcharbyte'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

-- relabel the typmod
CREATE FUNCTION sys.oravarcharbyte_support(internal)
RETURNS internal
AS 'varchar_support'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

/* Operator function (oravarcharbyte, oravarcharbyte) */
CREATE FUNCTION sys.oravarcharbyteeq(sys.oravarcharbyte, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchareq'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharbytene(sys.oravarcharbyte, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharne'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharbytele(sys.oravarcharbyte, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharle'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharbytegt(sys.oravarcharbyte, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchargt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharbytelt(sys.oravarcharbyte, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharlt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharbytege(sys.oravarcharbyte, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharge'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

/* Operator function (oravarcharbyte, oravarcharchar) */
CREATE FUNCTION sys.oravarcharbyteeq(sys.oravarcharbyte, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchareq'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharbytene(sys.oravarcharbyte, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharne'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharbytele(sys.oravarcharbyte, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharle'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharbytegt(sys.oravarcharbyte, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchargt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharbytelt(sys.oravarcharbyte, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharlt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarcharbytege(sys.oravarcharbyte, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarcharge'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

-- Register the basic I/O for 'oravarcharbyte' in pg_type.
UPDATE pg_type
SET typinput=(SELECT oid FROM pg_proc WHERE proname='oravarcharbytein')
WHERE oid = 9503;

UPDATE pg_type
SET typoutput=(SELECT oid FROM pg_proc WHERE proname='oravarcharbyteout')
WHERE oid = 9503;

UPDATE pg_type
SET typreceive=(SELECT oid FROM pg_proc WHERE proname='oravarcharbyterecv')
WHERE oid = 9503;

UPDATE pg_type
SET typsend=(SELECT oid FROM pg_proc WHERE proname='oravarcharbytesend')
WHERE oid = 9503;

UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oravarcharbytetypmodin')
WHERE oid = 9503;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oravarcharbytetypmodout')
WHERE oid = 9503;

-- Register the typmod inout for 'oravarcharbyte' array type in pg_type.
UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oravarcharbytetypmodin')
WHERE oid = 9507;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oravarcharbytetypmodout')
WHERE oid = 9507;

UPDATE pg_proc
SET prosupport=(SELECT oid FROM pg_proc WHERE proname='oravarcharbyte_support')
WHERE proname='oravarcharbyte';

/* CREATE CAST */
---------- Compatible Oracle Cast ----------
CREATE CAST (sys.oravarcharbyte AS sys.oravarcharbyte)
WITH FUNCTION sys.oravarcharbyte(sys.oravarcharbyte, integer, boolean)
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS sys.oravarcharchar)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS sys.oracharchar)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS sys.oracharbyte)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS sys.oradate)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS sys.oratimestamp)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS sys.oratimestamptz)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS sys.oratimestampltz)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS sys.yminterval)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS sys.dsinterval)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS sys.number)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS sys.binary_float)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS sys.binary_double)
WITH INOUT
AS IMPLICIT;

---------- Compatible Postgresql Cast ----------
CREATE FUNCTION sys.oravarchar_regclass(sys.oravarcharbyte)
RETURNS OID 
AS 'MODULE_PATHNAME','oravarchar_regclass'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE CAST (sys.oravarcharbyte AS pg_catalog.regclass)
WITH FUNCTION oravarchar_regclass(sys.oravarcharbyte)
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS pg_catalog.text)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (pg_catalog.text AS sys.oravarcharbyte)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS pg_catalog.bpchar)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (pg_catalog.bpchar AS sys.oravarcharbyte)
WITH FUNCTION sys.bpchar_oravarchar(pg_catalog.bpchar)
AS IMPLICIT;


CREATE CAST (sys.oravarcharbyte AS pg_catalog.varchar)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (pg_catalog.varchar AS sys.oravarcharbyte)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (pg_catalog.char AS sys.oravarcharbyte)
WITH FUNCTION sys.char_oravarchar(pg_catalog.char)
AS ASSIGNMENT;

CREATE CAST (sys.oravarcharbyte AS pg_catalog.char)
WITH FUNCTION sys.oravarchar_char(sys.oravarcharchar)
AS ASSIGNMENT;

CREATE CAST (pg_catalog.name AS sys.oravarcharbyte)
WITH FUNCTION sys.name_oravarchar(pg_catalog.name)
AS ASSIGNMENT;

CREATE CAST (sys.oravarcharbyte AS pg_catalog.name)
WITH FUNCTION sys.oravarchar_name(sys.oravarcharchar)
AS ASSIGNMENT;

CREATE CAST (cidr AS sys.oravarcharbyte)
WITH FUNCTION sys.cidr_oravarchar(cidr)
AS ASSIGNMENT;

CREATE CAST (inet AS sys.oravarcharbyte)
WITH FUNCTION sys.inet_oravarchar(inet)
AS ASSIGNMENT;

CREATE CAST (pg_catalog.bool AS sys.oravarcharbyte)
WITH FUNCTION sys.bool_oravarchar(pg_catalog.bool)
AS ASSIGNMENT;

CREATE CAST (pg_catalog.xml AS sys.oravarcharbyte)
WITHOUT FUNCTION
AS ASSIGNMENT;

CREATE CAST (sys.oravarcharbyte AS pg_catalog.xml)
WITH FUNCTION sys.oravarchar_xml(sys.oravarcharchar);

/* CREATE OPERATOR for (oravarcharchar, oravarcharchar) */
CREATE OPERATOR = (
	procedure = sys.oravarcharchareq,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharchar,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);

CREATE OPERATOR > (
	procedure = sys.oravarcharchargt,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharchar,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR < (
	procedure = sys.oravarcharcharlt,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharchar,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR <> (
	procedure = sys.oravarcharcharne,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharchar,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);

CREATE OPERATOR >= (
	procedure = sys.oravarcharcharge,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharchar,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR <= (
	procedure = sys.oravarcharcharle,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharchar,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* CREATE OPERATOR for (oravarcharchar, oravarcharbyte) */
CREATE OPERATOR = (
	procedure = sys.oravarcharchareq,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharbyte,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);

CREATE OPERATOR > (
	procedure = sys.oravarcharchargt,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharbyte,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR < (
	procedure = sys.oravarcharcharlt,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharbyte,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR <> (
	procedure = sys.oravarcharcharne,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharbyte,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);

CREATE OPERATOR >= (
	procedure = sys.oravarcharcharge,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharbyte,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR <= (
	procedure = sys.oravarcharcharle,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharbyte,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* CREATE OPERATOR for (oravarcharbyte, oravarcharbyte) */
CREATE OPERATOR = (
	procedure = sys.oravarcharbyteeq,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharbyte,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);

CREATE OPERATOR > (
	procedure = sys.oravarcharbytegt,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharbyte,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR < (
	procedure = sys.oravarcharbytelt,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharbyte,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR <> (
	procedure = sys.oravarcharbytene,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharbyte,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);

CREATE OPERATOR >= (
	procedure = sys.oravarcharbytege,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharbyte,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR <= (
	procedure = sys.oravarcharbytele,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharbyte,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* CREATE OPERATOR for (oravarcharbyte, oravarcharchar) */
CREATE OPERATOR = (
	procedure = sys.oravarcharbyteeq,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharchar,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);

CREATE OPERATOR > (
	procedure = sys.oravarcharbytegt,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharchar,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR < (
	procedure = sys.oravarcharbytelt,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharchar,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR <> (
	procedure = sys.oravarcharbytene,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharchar,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);

CREATE OPERATOR >= (
	procedure = sys.oravarcharbytege,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharchar,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR <= (
	procedure = sys.oravarcharbytele,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharchar,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

--
-- B-tree index support
--
/* The support procedure required by B-trees */
CREATE FUNCTION sys.bt_oravarchar_cmp(sys.oravarcharchar, sys.oravarcharchar)
RETURNS integer
AS 'MODULE_PATHNAME','bt_oravarchar_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.bt_oravarchar_cmp(sys.oravarcharchar, sys.oravarcharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','bt_oravarchar_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.bt_oravarchar_cmp(sys.oravarcharbyte, sys.oravarcharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','bt_oravarchar_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.bt_oravarchar_cmp(sys.oravarcharbyte, sys.oravarcharchar)
RETURNS integer
AS 'MODULE_PATHNAME','bt_oravarchar_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

/* The sort support procedure required by B-trees */
CREATE FUNCTION sys.btoravarcharcharsortsupport(internal)
RETURNS void
AS 'MODULE_PATHNAME','btoravarcharcharsortsupport'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.btoravarcharbytesortsupport(internal)
RETURNS void
AS 'MODULE_PATHNAME','btoravarcharbytesortsupport'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

/* CREATE OPERATOR FAMILY */
CREATE OPERATOR FAMILY sys.oravarchar_ops USING btree;

/* CREATE OPERATOR CLASS for 'oravarcharchar' */
CREATE OPERATOR CLASS sys.oravarcharchar_ops
    DEFAULT FOR TYPE sys.oravarcharchar USING btree FAMILY sys.oravarchar_ops AS
        OPERATOR        1       < (sys.oravarcharchar, sys.oravarcharchar),
        OPERATOR        2       <= (sys.oravarcharchar, sys.oravarcharchar),
        OPERATOR        3       = (sys.oravarcharchar, sys.oravarcharchar),
        OPERATOR        4       >= (sys.oravarcharchar, sys.oravarcharchar),
        OPERATOR        5       > (sys.oravarcharchar, sys.oravarcharchar),
        FUNCTION        1       sys.bt_oravarchar_cmp(sys.oravarcharchar, sys.oravarcharchar),
        FUNCTION        2 (sys.oravarcharchar, sys.oravarcharchar)       sys.btoravarcharcharsortsupport(internal),
		FUNCTION        4 (sys.oravarcharchar, sys.oravarcharchar)       sys.btoravarstrequalimage(oid);
		
/* CREATE OPERATOR CLASS for 'oravarcharbyte' */
CREATE OPERATOR CLASS sys.oravarcharbyte_ops
    DEFAULT FOR TYPE sys.oravarcharbyte USING btree FAMILY sys.oravarchar_ops AS
        OPERATOR        1       < (sys.oravarcharbyte, sys.oravarcharbyte),
        OPERATOR        2       <= (sys.oravarcharbyte, sys.oravarcharbyte),
        OPERATOR        3       = (sys.oravarcharbyte, sys.oravarcharbyte),
        OPERATOR        4       >= (sys.oravarcharbyte, sys.oravarcharbyte),
        OPERATOR        5       > (sys.oravarcharbyte, sys.oravarcharbyte),
        FUNCTION        1       sys.bt_oravarchar_cmp(sys.oravarcharbyte, sys.oravarcharbyte),	
        FUNCTION        2 (sys.oravarcharbyte, sys.oravarcharbyte)       sys.btoravarcharbytesortsupport(internal),
		FUNCTION        4 (sys.oravarcharbyte, sys.oravarcharbyte)       sys.btoravarstrequalimage(oid);

ALTER OPERATOR FAMILY sys.oravarchar_ops USING btree ADD
	-- Cross data type comparison
	OPERATOR        1       < (sys.oravarcharchar, sys.oravarcharbyte),
	OPERATOR        2       <= (sys.oravarcharchar, sys.oravarcharbyte),
	OPERATOR        3       = (sys.oravarcharchar, sys.oravarcharbyte),
	OPERATOR        4       >= (sys.oravarcharchar, sys.oravarcharbyte),
	OPERATOR        5       > (sys.oravarcharchar, sys.oravarcharbyte),
	FUNCTION        1       sys.bt_oravarchar_cmp(sys.oravarcharchar, sys.oravarcharbyte),
	FUNCTION        2 (sys.oravarcharchar, sys.oravarcharbyte)       sys.btoravarcharcharsortsupport(internal),
	
	-- Cross data type comparison
	OPERATOR        1       < (sys.oravarcharbyte, sys.oravarcharchar),
	OPERATOR        2       <= (sys.oravarcharbyte, sys.oravarcharchar),
	OPERATOR        3       = (sys.oravarcharbyte, sys.oravarcharchar),
	OPERATOR        4       >= (sys.oravarcharbyte, sys.oravarcharchar),
	OPERATOR        5       > (sys.oravarcharbyte, sys.oravarcharchar),
	FUNCTION        1       sys.bt_oravarchar_cmp(sys.oravarcharbyte, sys.oravarcharchar),
	FUNCTION        2 (sys.oravarcharbyte, sys.oravarcharchar)       sys.btoravarcharbytesortsupport(internal);

--
-- Hash index support (oravarchar)
--
CREATE FUNCTION sys.hashoravarchar(sys.oravarcharchar)
RETURNS integer
AS 'MODULE_PATHNAME','hashoravarchar'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.hashoravarchar(sys.oravarcharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','hashoravarchar'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.hashoravarcharcharextended(sys.oravarcharchar, bigint)
RETURNS bigint
AS 'hashtextextended'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.hashoravarcharbyteextended(sys.oravarcharbyte, bigint)
RETURNS bigint
AS 'hashtextextended'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

/* CREATE OPERATOR FAMILY */
CREATE OPERATOR FAMILY sys.oravarchar_ops USING hash;

/* CREATE OPERATOR CLASS for 'oravarcharchar' */
CREATE OPERATOR CLASS sys.oravarcharchar_ops
    DEFAULT FOR TYPE sys.oravarcharchar USING hash FAMILY sys.oravarchar_ops AS
		OPERATOR        1       = (sys.oravarcharchar, sys.oravarcharchar),
        FUNCTION        1       sys.hashoravarchar(sys.oravarcharchar),
		FUNCTION        2       sys.hashoravarcharcharextended(sys.oravarcharchar, bigint);

/* CREATE OPERATOR CLASS for 'oravarcharbyte' */
CREATE OPERATOR CLASS sys.oravarcharbyte_ops
    DEFAULT FOR TYPE sys.oravarcharbyte USING hash FAMILY sys.oravarchar_ops AS
		OPERATOR        1       = (sys.oravarcharbyte, sys.oravarcharbyte),
        FUNCTION        1       sys.hashoravarchar(sys.oravarcharbyte),
		FUNCTION        2       sys.hashoravarcharbyteextended(sys.oravarcharbyte, bigint);

ALTER OPERATOR FAMILY sys.oravarchar_ops USING hash ADD
	-- Cross data type comparison
	OPERATOR        1       = (sys.oravarcharchar, sys.oravarcharbyte),
	OPERATOR        1       = (sys.oravarcharbyte, sys.oravarcharchar);
	
/* 
 * VARCHAR2(n char/byte) pattern comparison. 
 */

/* args type is (sys.oravarcharchar, sys.oravarcharchar) */
CREATE FUNCTION sys.oravarchar_pattern_lt(sys.oravarcharchar, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_lt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarchar_pattern_le(sys.oravarcharchar, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_le'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarchar_pattern_ge(sys.oravarcharchar, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_ge'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarchar_pattern_gt(sys.oravarcharchar, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_gt'
LANGUAGE C
STRICT
IMMUTABLE
LEAKPROOF;

/* args type is (sys.oravarcharbyte, sys.oravarcharbyte) */
CREATE FUNCTION sys.oravarchar_pattern_lt(sys.oravarcharbyte, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_lt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarchar_pattern_le(sys.oravarcharbyte, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_le'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarchar_pattern_ge(sys.oravarcharbyte, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_ge'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarchar_pattern_gt(sys.oravarcharbyte, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_gt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

/* args type is (sys.oravarcharchar, sys.oravarcharbyte) */

CREATE FUNCTION sys.oravarchar_pattern_lt(sys.oravarcharchar, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_lt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarchar_pattern_le(sys.oravarcharchar, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_le'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarchar_pattern_ge(sys.oravarcharchar, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_ge'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarchar_pattern_gt(sys.oravarcharchar, sys.oravarcharbyte)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_gt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

/* args type is (sys.oravarcharbyte, sys.oravarcharchar) */
CREATE FUNCTION sys.oravarchar_pattern_lt(sys.oravarcharbyte, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_lt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarchar_pattern_le(sys.oravarcharbyte, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_le'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarchar_pattern_ge(sys.oravarcharbyte, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_ge'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarchar_pattern_gt(sys.oravarcharbyte, sys.oravarcharchar)
RETURNS boolean
AS 'MODULE_PATHNAME','oravarchar_pattern_gt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

/* Index Method Support Routines */
CREATE FUNCTION sys.btoravarchar_pattern_cmp(sys.oravarcharchar, sys.oravarcharchar)
RETURNS INTEGER
AS 'MODULE_PATHNAME','btoravarchar_pattern_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.btoravarchar_pattern_cmp(sys.oravarcharbyte, sys.oravarcharbyte)
RETURNS INTEGER
AS 'MODULE_PATHNAME','btoravarchar_pattern_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.btoravarchar_pattern_cmp(sys.oravarcharchar, sys.oravarcharbyte)
RETURNS INTEGER
AS 'MODULE_PATHNAME','btoravarchar_pattern_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.btoravarchar_pattern_cmp(sys.oravarcharbyte, sys.oravarcharchar)
RETURNS INTEGER
AS 'MODULE_PATHNAME','btoravarchar_pattern_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.btoravarcharchar_pattern_sortsupport(internal)
RETURNS void
AS 'MODULE_PATHNAME','btoravarcharchar_pattern_sortsupport'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.btoravarcharbyte_pattern_sortsupport(internal)
RETURNS void
AS 'MODULE_PATHNAME','btoravarcharbyte_pattern_sortsupport'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;


/* CREATE OPERATOR */
-- Argument type: (oravarcharchar, oravarcharchar)
CREATE OPERATOR ~>~ (
	procedure = sys.oravarchar_pattern_gt,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharchar,
	commutator = ~<~,
	negator = ~<=~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<~ (
	procedure = sys.oravarchar_pattern_lt,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharchar,
	commutator = ~>~,
	negator = ~>=~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR ~>=~ (
	procedure = sys.oravarchar_pattern_ge,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharchar,
	commutator = ~<=~,
	negator = ~<~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<=~ (
	procedure = sys.oravarchar_pattern_le,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharchar,
	commutator = ~>=~,
	negator = ~>~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

-- Argument type: (oravarcharchar, oravarcharbyte)
CREATE OPERATOR ~>~ (
	procedure = sys.oravarchar_pattern_gt,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharbyte,
	commutator = ~<~,
	negator = ~<=~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<~ (
	procedure = sys.oravarchar_pattern_lt,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharbyte,
	commutator = ~>~,
	negator = ~>=~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR ~>=~ (
	procedure = sys.oravarchar_pattern_ge,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharbyte,
	commutator = ~<=~,
	negator = ~<~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<=~ (
	procedure = sys.oravarchar_pattern_le,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharbyte,
	commutator = ~>=~,
	negator = ~>~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

-- Argument type: (oravarcharbyte, oravarcharbyte)
CREATE OPERATOR ~>~ (
	procedure = sys.oravarchar_pattern_gt,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharbyte,
	commutator = ~<~,
	negator = ~<=~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<~ (
	procedure = sys.oravarchar_pattern_lt,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharbyte,
	commutator = ~>~,
	negator = ~>=~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR ~>=~ (
	procedure = sys.oravarchar_pattern_ge,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharbyte,
	commutator = ~<=~,
	negator = ~<~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<=~ (
	procedure = sys.oravarchar_pattern_le,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharbyte,
	commutator = ~>=~,
	negator = ~>~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

-- Argument type: (oravarcharbyte, oravarcharchar)
CREATE OPERATOR ~>~ (
	procedure = sys.oravarchar_pattern_gt,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharchar,
	commutator = ~<~,
	negator = ~<=~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<~ (
	procedure = sys.oravarchar_pattern_lt,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharchar,
	commutator = ~>~,
	negator = ~>=~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR ~>=~ (
	procedure = sys.oravarchar_pattern_ge,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharchar,
	commutator = ~<=~,
	negator = ~<~,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR ~<=~ (
	procedure = sys.oravarchar_pattern_le,
	leftarg = sys.oravarcharbyte,
	rightarg = sys.oravarcharchar,
	commutator = ~>=~,
	negator = ~>~,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* CREATE OPERATOR FAMILY */
CREATE OPERATOR FAMILY sys.oravarchar_pattern_ops USING btree;

/* CREATE OPERATOR CLASS for 'oravarcharchar' */
CREATE OPERATOR CLASS sys.oravarcharchar_pattern_ops
	FOR TYPE sys.oravarcharchar USING btree FAMILY sys.oravarchar_pattern_ops AS
        OPERATOR        1       ~<~ (sys.oravarcharchar, sys.oravarcharchar),
        OPERATOR        2       ~<=~ (sys.oravarcharchar, sys.oravarcharchar),
        OPERATOR        3       = (sys.oravarcharchar, sys.oravarcharchar),
        OPERATOR        4       ~>=~ (sys.oravarcharchar, sys.oravarcharchar),
        OPERATOR        5       ~>~ (sys.oravarcharchar, sys.oravarcharchar),
        FUNCTION        1       sys.btoravarchar_pattern_cmp(sys.oravarcharchar, sys.oravarcharchar),
		FUNCTION        2 (sys.oravarcharchar, sys.oravarcharchar)       sys.btoravarcharchar_pattern_sortsupport(internal),
		FUNCTION        4 (sys.oravarcharchar, sys.oravarcharchar)       sys.btoraequalimage(oid);
		
/* CREATE OPERATOR CLASS for 'oravarcharbyte' */
CREATE OPERATOR CLASS sys.oravarcharbyte_pattern_ops
    FOR TYPE sys.oravarcharbyte USING btree FAMILY sys.oravarchar_pattern_ops AS
        OPERATOR        1       ~<~ (sys.oravarcharbyte, sys.oravarcharbyte),
        OPERATOR        2       ~<=~ (sys.oravarcharbyte, sys.oravarcharbyte),
        OPERATOR        3       = (sys.oravarcharbyte, sys.oravarcharbyte),
        OPERATOR        4       ~>=~ (sys.oravarcharbyte, sys.oravarcharbyte),
        OPERATOR        5       ~>~ (sys.oravarcharbyte, sys.oravarcharbyte),
        FUNCTION        1       sys.btoravarchar_pattern_cmp(sys.oravarcharbyte, sys.oravarcharbyte),
		FUNCTION        2 (sys.oravarcharbyte, sys.oravarcharbyte)       sys.btoravarcharbyte_pattern_sortsupport(internal),
		FUNCTION        4 (sys.oravarcharbyte, sys.oravarcharbyte)       sys.btoraequalimage(oid);

ALTER OPERATOR FAMILY sys.oravarchar_pattern_ops USING btree ADD
	-- Cross data type comparison
	OPERATOR        1       ~<~ (sys.oravarcharchar, sys.oravarcharbyte),
	OPERATOR        2       ~<=~ (sys.oravarcharchar, sys.oravarcharbyte),
	OPERATOR        3       = (sys.oravarcharchar, sys.oravarcharbyte),
	OPERATOR        4       ~>=~ (sys.oravarcharchar, sys.oravarcharbyte),
	OPERATOR        5       ~>~ (sys.oravarcharchar, sys.oravarcharbyte),
	FUNCTION        1       sys.btoravarchar_pattern_cmp(sys.oravarcharchar, sys.oravarcharbyte),
	FUNCTION        2 (sys.oravarcharchar, sys.oravarcharbyte)       sys.btoravarcharchar_pattern_sortsupport(internal),
	-- Cross data type comparison
	OPERATOR        1       ~<~ (sys.oravarcharbyte, sys.oravarcharchar),
	OPERATOR        2       ~<=~ (sys.oravarcharbyte, sys.oravarcharchar),
	OPERATOR        3       = (sys.oravarcharbyte, sys.oravarcharchar),
	OPERATOR        4       ~>=~ (sys.oravarcharbyte, sys.oravarcharchar),
	OPERATOR        5       ~>~ (sys.oravarcharbyte, sys.oravarcharchar),
	FUNCTION        1       sys.btoravarchar_pattern_cmp(sys.oravarcharbyte, sys.oravarcharchar),
	FUNCTION        2 (sys.oravarcharbyte, sys.oravarcharchar)       sys.btoravarcharbyte_pattern_sortsupport(internal);

/* CREATE OPERATOR FAMILY */
CREATE OPERATOR FAMILY sys.oravarchar_pattern_ops USING hash;

/* CREATE OPERATOR CLASS for 'oravarcharchar' */
CREATE OPERATOR CLASS sys.oravarcharchar_pattern_ops
    FOR TYPE sys.oravarcharchar USING hash FAMILY sys.oravarchar_pattern_ops AS
		OPERATOR        1       = (sys.oravarcharchar, sys.oravarcharchar),
        FUNCTION        1       sys.hashoravarchar(sys.oravarcharchar),
		FUNCTION        2       sys.hashoravarcharcharextended(sys.oravarcharchar, bigint);

/* CREATE OPERATOR CLASS for 'oravarcharbyte' */
CREATE OPERATOR CLASS sys.oravarcharbyte_pattern_ops
    FOR TYPE sys.oravarcharbyte USING hash FAMILY sys.oravarchar_pattern_ops AS
		OPERATOR        1       = (sys.oravarcharbyte, sys.oravarcharbyte),
        FUNCTION        1       sys.hashoravarchar(sys.oravarcharbyte),
		FUNCTION        2       sys.hashoravarcharbyteextended(sys.oravarcharbyte, bigint);

ALTER OPERATOR FAMILY sys.oravarchar_pattern_ops USING hash ADD
	-- Cross data type comparison
	OPERATOR        1       = (sys.oravarcharchar, sys.oravarcharbyte),
	OPERATOR        1       = (sys.oravarcharbyte, sys.oravarcharchar);

	
/* 
 * CREATE AGGREGATE
 */	
/* Aggregate Function for 'oravarcharchar'*/
CREATE FUNCTION sys.oravarchar_larger(sys.oravarcharchar, sys.oravarcharchar)
RETURNS sys.oravarcharchar
AS 'MODULE_PATHNAME','oravarchar_larger'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarchar_smaller(sys.oravarcharchar, sys.oravarcharchar)
RETURNS sys.oravarcharchar
AS 'MODULE_PATHNAME','oravarchar_smaller'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

/* Aggregate Function for 'oravarcharbyte'*/
CREATE FUNCTION sys.oravarchar_larger(sys.oravarcharbyte, sys.oravarcharbyte)
RETURNS sys.oravarcharbyte
AS 'MODULE_PATHNAME','oravarchar_larger'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oravarchar_smaller(sys.oravarcharbyte, sys.oravarcharbyte)
RETURNS sys.oravarcharbyte
AS 'MODULE_PATHNAME','oravarchar_smaller'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE AGGREGATE sys.max(sys.oravarcharchar) (
  SFUNC=sys.oravarchar_larger,
  STYPE= sys.oravarcharchar,
  SORTOP= >
);
CREATE AGGREGATE sys.min(sys.oravarcharchar) (
  SFUNC=sys.oravarchar_smaller,
  STYPE= sys.oravarcharchar,
  SORTOP= <
);

CREATE AGGREGATE sys.max(sys.oravarcharbyte) (
  SFUNC=sys.oravarchar_larger,
  STYPE= sys.oravarcharbyte,
  SORTOP= >
);
CREATE AGGREGATE sys.min(sys.oravarcharbyte) (
  SFUNC=sys.oravarchar_smaller,
  STYPE= sys.oravarcharbyte,
  SORTOP= <
);

-- Operator function of "||"
CREATE FUNCTION sys.oravarcharcat(sys.oravarcharchar, sys.oravarcharchar)
RETURNS sys.oravarcharchar
AS 'MODULE_PATHNAME','oravarcharcat'
LANGUAGE C
IMMUTABLE;

CREATE OPERATOR ||  (
	procedure = sys.oravarcharcat,
	leftarg = sys.oravarcharchar,
	rightarg = sys.oravarcharchar
);

CREATE FUNCTION sys.concat(sys.oravarcharchar, sys.oravarcharchar)
RETURNS sys.oravarcharchar
AS 'MODULE_PATHNAME','oravarcharcat'
LANGUAGE C
IMMUTABLE;
/***************************************************************
 *
 * oracle date type support
 *
 ****************************************************************/
CREATE FUNCTION sys.oradate_in(cstring)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oradate_in'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oradate_out(sys.oradate)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oradate_out'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oradate_recv(internal)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oradate_recv'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oradate_send(sys.oradate)
RETURNS bytea
AS 'MODULE_PATHNAME','oradate_send'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

-- Register the basic I/O for 'oradate' in pg_type.
UPDATE pg_type
SET typinput=(SELECT oid FROM pg_proc WHERE proname='oradate_in')
WHERE oid = 9508;

UPDATE pg_type
SET typoutput=(SELECT oid FROM pg_proc WHERE proname='oradate_out')
WHERE oid = 9508;

UPDATE pg_type
SET typreceive=(SELECT oid FROM pg_proc WHERE proname='oradate_recv')
WHERE oid = 9508;

UPDATE pg_type
SET typsend=(SELECT oid FROM pg_proc WHERE proname='oradate_send')
WHERE oid = 9508;
 
/* CREATE CAST */
---------- Compatible Postgresql Cast ----------
CREATE FUNCTION sys.oradate_date(sys.oradate)
RETURNS pg_catalog.date
AS 'MODULE_PATHNAME','oradate_date'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE CAST (sys.oradate AS pg_catalog.date)
WITH FUNCTION sys.oradate_date(sys.oradate)
AS IMPLICIT;

CREATE FUNCTION sys.date_oradate(pg_catalog.date)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','date_oradate'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE CAST (pg_catalog.date AS sys.oradate)
WITH FUNCTION sys.date_oradate(pg_catalog.date)
AS IMPLICIT;

---------- Compatible Oracle Cast ----------
CREATE CAST (sys.oradate AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oradate AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oradate AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oradate AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

CREATE FUNCTION sys.oradate_oratimestamptz(sys.oradate)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','oradate_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oradate_oratimestampltz(sys.oradate)
RETURNS sys.oratimestampltz
AS 'MODULE_PATHNAME','oradate_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE CAST (sys.oradate AS sys.oratimestamp)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (sys.oradate AS sys.oratimestamptz)
WITH FUNCTION sys.oradate_oratimestamptz(sys.oradate)
AS IMPLICIT;

CREATE CAST (sys.oradate AS sys.oratimestampltz)
WITH FUNCTION sys.oradate_oratimestampltz(sys.oradate)
AS IMPLICIT;

/* CREATE OPERATOR */
/* oradate vs oradate */
CREATE FUNCTION sys.oradate_eq(sys.oradate, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_eq'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;
 
CREATE FUNCTION sys.oradate_ne(sys.oradate, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_ne'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;
 
CREATE FUNCTION sys.oradate_lt(sys.oradate, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_lt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;
 
CREATE FUNCTION sys.oradate_gt(sys.oradate, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_gt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;
 
CREATE FUNCTION sys.oradate_le(sys.oradate, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_le'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;
 
CREATE FUNCTION sys.oradate_ge(sys.oradate, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_ge'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE OPERATOR = (
	procedure = sys.oradate_eq,
	leftarg = sys.oradate,
	rightarg = sys.oradate,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oradate_ne,
	leftarg = sys.oradate,
	rightarg = sys.oradate,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oradate_lt,
	leftarg = sys.oradate,
	rightarg = sys.oradate,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oradate_gt,
	leftarg = sys.oradate,
	rightarg = sys.oradate,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oradate_ge,
	leftarg = sys.oradate,
	rightarg = sys.oradate,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oradate_le,
	leftarg = sys.oradate,
	rightarg = sys.oradate,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* oradate vs oratimestamp */
CREATE FUNCTION sys.oradate_eq_oratimestamp(sys.oradate, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_eq_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;
 
CREATE FUNCTION sys.oradate_ne_oratimestamp(sys.oradate, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_ne_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;
 
CREATE FUNCTION sys.oradate_lt_oratimestamp(sys.oradate, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_lt_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;
 
CREATE FUNCTION sys.oradate_gt_oratimestamp(sys.oradate, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_gt_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;
 
CREATE FUNCTION sys.oradate_le_oratimestamp(sys.oradate, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_le_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;
 
CREATE FUNCTION sys.oradate_ge_oratimestamp(sys.oradate, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_ge_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE OPERATOR = (
	procedure = sys.oradate_eq_oratimestamp,
	leftarg = sys.oradate,
	rightarg = sys.oratimestamp,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oradate_ne_oratimestamp,
	leftarg = sys.oradate,
	rightarg = sys.oratimestamp,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oradate_lt_oratimestamp,
	leftarg = sys.oradate,
	rightarg = sys.oratimestamp,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oradate_gt_oratimestamp,
	leftarg = sys.oradate,
	rightarg = sys.oratimestamp,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oradate_ge_oratimestamp,
	leftarg = sys.oradate,
	rightarg = sys.oratimestamp,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oradate_le_oratimestamp,
	leftarg = sys.oradate,
	rightarg = sys.oratimestamp,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* oradate vs oratimestamptz */
CREATE FUNCTION sys.oradate_eq_oratimestamptz(sys.oradate, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_eq_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;
 
CREATE FUNCTION sys.oradate_ne_oratimestamptz(sys.oradate, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_ne_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;
 
CREATE FUNCTION sys.oradate_lt_oratimestamptz(sys.oradate, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_lt_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;
 
CREATE FUNCTION sys.oradate_gt_oratimestamptz(sys.oradate, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_gt_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;
 
CREATE FUNCTION sys.oradate_le_oratimestamptz(sys.oradate, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_le_oratimestamptz'
LANGUAGE C
STRICT
STABLE;
 
CREATE FUNCTION sys.oradate_ge_oratimestamptz(sys.oradate, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_ge_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE OPERATOR = (
	procedure = sys.oradate_eq_oratimestamptz,
	leftarg = sys.oradate,
	rightarg = sys.oratimestamptz,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oradate_ne_oratimestamptz,
	leftarg = sys.oradate,
	rightarg = sys.oratimestamptz,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oradate_lt_oratimestamptz,
	leftarg = sys.oradate,
	rightarg = sys.oratimestamptz,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oradate_gt_oratimestamptz,
	leftarg = sys.oradate,
	rightarg = sys.oratimestamptz,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oradate_ge_oratimestamptz,
	leftarg = sys.oradate,
	rightarg = sys.oratimestamptz,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oradate_le_oratimestamptz,
	leftarg = sys.oradate,
	rightarg = sys.oratimestamptz,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* oradate vs oratimestampltz */
CREATE FUNCTION sys.oradate_eq_oratimestampltz(sys.oradate, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_eq_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;
 
CREATE FUNCTION sys.oradate_ne_oratimestampltz(sys.oradate, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_ne_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;
 
CREATE FUNCTION sys.oradate_lt_oratimestampltz(sys.oradate, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_lt_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;
 
CREATE FUNCTION sys.oradate_gt_oratimestampltz(sys.oradate, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_gt_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;
 
CREATE FUNCTION sys.oradate_le_oratimestampltz(sys.oradate, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_le_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;
 
CREATE FUNCTION sys.oradate_ge_oratimestampltz(sys.oradate, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oradate_ge_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE OPERATOR = (
	procedure = sys.oradate_eq_oratimestampltz,
	leftarg = sys.oradate,
	rightarg = sys.oratimestampltz,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oradate_ne_oratimestampltz,
	leftarg = sys.oradate,
	rightarg = sys.oratimestampltz,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oradate_lt_oratimestampltz,
	leftarg = sys.oradate,
	rightarg = sys.oratimestampltz,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oradate_gt_oratimestampltz,
	leftarg = sys.oradate,
	rightarg = sys.oratimestampltz,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oradate_ge_oratimestampltz,
	leftarg = sys.oradate,
	rightarg = sys.oratimestampltz,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oradate_le_oratimestampltz,
	leftarg = sys.oradate,
	rightarg = sys.oratimestampltz,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/*
 * B-tree Index Support
 * Create Operator family 'oradatetime_ops' for type 'oradate/oratimestamp/oratimestamptz/oratimestampltz.
 */
/* B-tree index support procedure */
CREATE FUNCTION sys.oradate_cmp(sys.oradate, sys.oradate)
RETURNS integer
AS 'MODULE_PATHNAME','oradate_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oradate_cmp_oratimestamp(sys.oradate, sys.oratimestamp)
RETURNS integer
AS 'MODULE_PATHNAME','oradate_cmp_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oradate_cmp_oratimestamptz(sys.oradate, sys.oratimestamptz)
RETURNS integer
AS 'MODULE_PATHNAME','oradate_cmp_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oradate_cmp_oratimestampltz(sys.oradate, sys.oratimestampltz)
RETURNS integer
AS 'MODULE_PATHNAME','oradate_cmp_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oradate_sortsupport(internal)
RETURNS void
AS 'timestamp_sortsupport'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

/* Create Operator family 'oradatetime_ops' */
CREATE OPERATOR FAMILY sys.oradatetime_ops USING btree;

/* CREATE OPERATOR CLASS for 'oradate' */
CREATE OPERATOR CLASS sys.oradate_ops
    DEFAULT FOR TYPE sys.oradate USING btree FAMILY sys.oradatetime_ops AS
        OPERATOR        1       < (sys.oradate, sys.oradate),
        OPERATOR        2       <= (sys.oradate, sys.oradate),
        OPERATOR        3       = (sys.oradate, sys.oradate),
        OPERATOR        4       >= (sys.oradate, sys.oradate),
        OPERATOR        5       > (sys.oradate, sys.oradate),
        FUNCTION        1       sys.oradate_cmp(sys.oradate, sys.oradate),
		FUNCTION		2		sys.oradate_sortsupport(internal),
		FUNCTION		4		(sys.oradate, sys.oradate) sys.btoraequalimage(oid);

ALTER OPERATOR FAMILY sys.oradatetime_ops USING btree ADD
	-- Cross data type comparison
	OPERATOR        1       < (sys.oradate, sys.oratimestamp),
	OPERATOR        2       <= (sys.oradate, sys.oratimestamp),
	OPERATOR        3       = (sys.oradate, sys.oratimestamp),
	OPERATOR        4       >= (sys.oradate, sys.oratimestamp),
	OPERATOR        5       > (sys.oradate, sys.oratimestamp),
	FUNCTION        1       sys.oradate_cmp_oratimestamp(sys.oradate, sys.oratimestamp),

	OPERATOR        1       < (sys.oradate, sys.oratimestamptz),
	OPERATOR        2       <= (sys.oradate, sys.oratimestamptz),
	OPERATOR        3       = (sys.oradate, sys.oratimestamptz),
	OPERATOR        4       >= (sys.oradate, sys.oratimestamptz),
	OPERATOR        5       > (sys.oradate, sys.oratimestamptz),
	FUNCTION        1       sys.oradate_cmp_oratimestamptz(sys.oradate, sys.oratimestamptz),
	
	OPERATOR        1       < (sys.oradate, sys.oratimestampltz),
	OPERATOR        2       <= (sys.oradate, sys.oratimestampltz),
	OPERATOR        3       = (sys.oradate, sys.oratimestampltz),
	OPERATOR        4       >= (sys.oradate, sys.oratimestampltz),
	OPERATOR        5       > (sys.oradate, sys.oratimestampltz),
	FUNCTION        1       sys.oradate_cmp_oratimestampltz(sys.oradate, sys.oratimestampltz);
		
/* HASH index support */
CREATE FUNCTION sys.oradate_hash(sys.oradate)
RETURNS integer
AS 'MODULE_PATHNAME','oradate_hash'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oradate_hash_extended(sys.oradate, int8)
RETURNS bigint
AS 'MODULE_PATHNAME','oradate_hash_extended'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR CLASS sys.oradate_ops
    DEFAULT FOR TYPE sys.oradate USING hash AS
		OPERATOR        1       = (sys.oradate, sys.oradate),
		FUNCTION        1       sys.oradate_hash(sys.oradate),
		FUNCTION        2       sys.oradate_hash_extended(sys.oradate, int8);

/*
 * Brin index support
 * Create Operator family 'oradatetime_minmax_ops' for type 'oradate/oratimestamp/oratimestamptz/oratimestampltz.
 */
CREATE OPERATOR FAMILY sys.oradatetime_minmax_ops USING brin;

/* CREATE OPERATOR CLASS for 'oradate' */
CREATE OPERATOR CLASS sys.oradate_minmax_ops
    DEFAULT FOR TYPE sys.oradate USING brin FAMILY sys.oradatetime_minmax_ops AS
        OPERATOR        1       < (sys.oradate, sys.oradate),
        OPERATOR        2       <= (sys.oradate, sys.oradate),
        OPERATOR        3       = (sys.oradate, sys.oradate),
        OPERATOR        4       >= (sys.oradate, sys.oradate),
        OPERATOR        5       > (sys.oradate, sys.oradate),
        FUNCTION        1       sys.brin_minmax_opcinfo(internal),
		FUNCTION        2       sys.brin_minmax_add_value(internal, internal, internal, internal),
		FUNCTION        3       sys.brin_minmax_consistent(internal, internal, internal),
		FUNCTION        4       sys.brin_minmax_union(internal, internal, internal);

ALTER OPERATOR FAMILY sys.oradatetime_minmax_ops USING brin ADD
	OPERATOR        1       < (sys.oradate, sys.oratimestamp),
	OPERATOR        2       <= (sys.oradate, sys.oratimestamp),
	OPERATOR        3       = (sys.oradate, sys.oratimestamp),
	OPERATOR        4       >= (sys.oradate, sys.oratimestamp),
	OPERATOR        5       > (sys.oradate, sys.oratimestamp),
	
	OPERATOR        1       < (sys.oradate, sys.oratimestamptz),
	OPERATOR        2       <= (sys.oradate, sys.oratimestamptz),
	OPERATOR        3       = (sys.oradate, sys.oratimestamptz),
	OPERATOR        4       >= (sys.oradate, sys.oratimestamptz),
	OPERATOR        5       > (sys.oradate, sys.oratimestamptz),

	OPERATOR        1       < (sys.oradate, sys.oratimestampltz),
	OPERATOR        2       <= (sys.oradate, sys.oratimestampltz),
	OPERATOR        3       = (sys.oradate, sys.oratimestampltz),
	OPERATOR        4       >= (sys.oradate, sys.oratimestampltz),
	OPERATOR        5       > (sys.oradate, sys.oratimestampltz);

/* Create aggregate for type 'oradate' */
/* Aggregate Function */
CREATE FUNCTION sys.oradate_larger(sys.oradate, sys.oradate)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oradate_larger'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oradate_smaller(sys.oradate, sys.oradate)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oradate_smaller'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE AGGREGATE sys.max(sys.oradate) (
  SFUNC=sys.oradate_larger,
  STYPE= sys.oradate,
  SORTOP= >
);
CREATE AGGREGATE sys.min(sys.oradate) (
  SFUNC=sys.oradate_smaller,
  STYPE= sys.oradate,
  SORTOP= <
);

/***************************************************************
 *
 * oracle timestamp type support
 *
 ****************************************************************/
CREATE FUNCTION sys.oratimestamp_in(cstring, oid, integer)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','oratimestamp_in'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_out(sys.oratimestamp)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oratimestamp_out'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_recv(internal, oid, integer)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','oratimestamp_recv'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oratimestamp_send(sys.oratimestamp)
RETURNS bytea
AS 'MODULE_PATHNAME','oratimestamp_send'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oratimestamptypmodin(cstring[])
RETURNS integer
AS 'MODULE_PATHNAME','oratimestamptypmodin'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oratimestamptypmodout(integer)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oratimestamptypmodout'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

-- Register the basic I/O for 'oratimestamp' in pg_type.
UPDATE pg_type
SET typinput=(SELECT oid FROM pg_proc WHERE proname='oratimestamp_in')
WHERE oid = 9510;

UPDATE pg_type
SET typoutput=(SELECT oid FROM pg_proc WHERE proname='oratimestamp_out')
WHERE oid = 9510;

UPDATE pg_type
SET typreceive=(SELECT oid FROM pg_proc WHERE proname='oratimestamp_recv')
WHERE oid = 9510;

UPDATE pg_type
SET typsend=(SELECT oid FROM pg_proc WHERE proname='oratimestamp_send')
WHERE oid = 9510;

UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oratimestamptypmodin')
WHERE oid = 9510;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oratimestamptypmodout')
WHERE oid = 9510;

-- Register the typmod inout for 'oratimestamp' array type in pg_type.
UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oratimestamptypmodin')
WHERE oid = 9511;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oratimestamptypmodout')
WHERE oid = 9511;

/* CREATE CAST */
---------- Compatible Postgresql Cast ----------
CREATE CAST (sys.oratimestamp AS pg_catalog.timestamp)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (pg_catalog.timestamp AS sys.oratimestamp)
WITHOUT FUNCTION
AS IMPLICIT;

---------- Compatible Oracle Cast ----------
CREATE CAST (sys.oratimestamp AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oratimestamp AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oratimestamp AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oratimestamp AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

-- Converts a timestamp(n) type to the specified typmod
CREATE FUNCTION sys.oratimestamp(sys.oratimestamp,integer)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.oratimestamp AS sys.oratimestamp)
WITH FUNCTION sys.oratimestamp(sys.oratimestamp, integer)
AS IMPLICIT;

CREATE FUNCTION sys.oratimestamp_oradate(sys.oratimestamp)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oratimestamp_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.oratimestamp AS sys.oradate)
WITH FUNCTION sys.oratimestamp_oradate(sys.oratimestamp)
AS IMPLICIT;

CREATE FUNCTION sys.oratimestamp_oratimestamptz(sys.oratimestamp)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','oratimestamp_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE CAST (sys.oratimestamp AS sys.oratimestamptz)
WITH FUNCTION sys.oratimestamp_oratimestamptz(sys.oratimestamp)
AS IMPLICIT;

CREATE FUNCTION sys.oratimestamp_oratimestampltz(sys.oratimestamp)
RETURNS sys.oratimestampltz
AS 'MODULE_PATHNAME','oratimestamp_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE CAST (sys.oratimestamp AS sys.oratimestampltz)
WITH FUNCTION sys.oratimestamp_oratimestampltz(sys.oratimestamp)
AS IMPLICIT;

/* CREATE OPERATOR */
CREATE FUNCTION sys.oratimestamp_eq(sys.oratimestamp, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_eq'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;
 
CREATE FUNCTION sys.oratimestamp_ne(sys.oratimestamp, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_ne'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;
 
CREATE FUNCTION sys.oratimestamp_lt(sys.oratimestamp, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_lt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestamp_gt(sys.oratimestamp, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_gt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestamp_le(sys.oratimestamp, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_le'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestamp_ge(sys.oratimestamp, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_ge'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE OPERATOR = (
	procedure = sys.oratimestamp_eq,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestamp,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oratimestamp_ne,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestamp,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oratimestamp_lt,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestamp,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oratimestamp_gt,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestamp,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oratimestamp_ge,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestamp,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oratimestamp_le,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestamp,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* oratimestamp vs oradate */
CREATE FUNCTION sys.oratimestamp_eq_oradate(sys.oratimestamp, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_eq_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_ne_oradate(sys.oratimestamp, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_ne_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_lt_oradate(sys.oratimestamp, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_lt_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_gt_oradate(sys.oratimestamp, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_gt_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_le_oradate(sys.oratimestamp, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_le_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_ge_oradate(sys.oratimestamp, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_ge_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE OPERATOR = (
	procedure = sys.oratimestamp_eq_oradate,
	leftarg = sys.oratimestamp,
	rightarg = sys.oradate,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oratimestamp_ne_oradate,
	leftarg = sys.oratimestamp,
	rightarg = sys.oradate,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oratimestamp_lt_oradate,
	leftarg = sys.oratimestamp,
	rightarg = sys.oradate,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oratimestamp_gt_oradate,
	leftarg = sys.oratimestamp,
	rightarg = sys.oradate,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oratimestamp_ge_oradate,
	leftarg = sys.oratimestamp,
	rightarg = sys.oradate,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oratimestamp_le_oradate,
	leftarg = sys.oratimestamp,
	rightarg = sys.oradate,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* oratimestamp vs oratimestamptz */
CREATE FUNCTION sys.oratimestamp_eq_oratimestamptz(sys.oratimestamp, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_eq_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_ne_oratimestamptz(sys.oratimestamp, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_ne_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_lt_oratimestamptz(sys.oratimestamp, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_lt_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_gt_oratimestamptz(sys.oratimestamp, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_gt_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_le_oratimestamptz(sys.oratimestamp, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_le_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_ge_oratimestamptz(sys.oratimestamp, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_ge_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE OPERATOR = (
	procedure = sys.oratimestamp_eq_oratimestamptz,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestamptz,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oratimestamp_ne_oratimestamptz,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestamptz,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oratimestamp_lt_oratimestamptz,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestamptz,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oratimestamp_gt_oratimestamptz,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestamptz,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oratimestamp_ge_oratimestamptz,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestamptz,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oratimestamp_le_oratimestamptz,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestamptz,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* oratimestamp vs oratimestampltz */
CREATE FUNCTION sys.oratimestamp_eq_oratimestampltz(sys.oratimestamp, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_eq_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_ne_oratimestampltz(sys.oratimestamp, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_ne_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_lt_oratimestampltz(sys.oratimestamp, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_lt_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_gt_oratimestampltz(sys.oratimestamp, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_gt_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_le_oratimestampltz(sys.oratimestamp, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_le_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_ge_oratimestampltz(sys.oratimestamp, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamp_ge_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE OPERATOR = (
	procedure = sys.oratimestamp_eq_oratimestampltz,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestampltz,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oratimestamp_ne_oratimestampltz,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestampltz,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oratimestamp_lt_oratimestampltz,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestampltz,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oratimestamp_gt_oratimestampltz,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestampltz,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oratimestamp_ge_oratimestampltz,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestampltz,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oratimestamp_le_oratimestampltz,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestampltz,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/*
 * B-tree Index Support
 */
/* B-tree index support procedure */
CREATE FUNCTION sys.oratimestamp_cmp(sys.oratimestamp, sys.oratimestamp)
RETURNS integer
AS 'MODULE_PATHNAME','oratimestamp_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestamp_cmp_oradate(sys.oratimestamp, sys.oradate)
RETURNS integer
AS 'MODULE_PATHNAME','oratimestamp_cmp_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_cmp_oratimestamptz(sys.oratimestamp, sys.oratimestamptz)
RETURNS integer
AS 'MODULE_PATHNAME','oratimestamp_cmp_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_cmp_oratimestampltz(sys.oratimestamp, sys.oratimestampltz)
RETURNS integer
AS 'MODULE_PATHNAME','oratimestamp_cmp_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamp_sortsupport(internal)
RETURNS void
AS 'timestamp_sortsupport'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

/* CREATE OPERATOR CLASS for 'oratimestamp' */
CREATE OPERATOR CLASS sys.oratimestamp_ops
    DEFAULT FOR TYPE sys.oratimestamp USING btree FAMILY sys.oradatetime_ops AS
        OPERATOR        1       < (sys.oratimestamp, sys.oratimestamp),
        OPERATOR        2       <= (sys.oratimestamp, sys.oratimestamp),
        OPERATOR        3       = (sys.oratimestamp, sys.oratimestamp),
        OPERATOR        4       >= (sys.oratimestamp, sys.oratimestamp),
        OPERATOR        5       > (sys.oratimestamp, sys.oratimestamp),
        FUNCTION        1       sys.oratimestamp_cmp(sys.oratimestamp, sys.oratimestamp),
		FUNCTION		2		sys.oratimestamp_sortsupport(internal),
		FUNCTION		4		(sys.oratimestamp, sys.oratimestamp) sys.btoraequalimage(oid);

ALTER OPERATOR FAMILY sys.oradatetime_ops USING btree ADD
	-- Cross data type comparison
	OPERATOR        1       < (sys.oratimestamp, sys.oradate),
	OPERATOR        2       <= (sys.oratimestamp, sys.oradate),
	OPERATOR        3       = (sys.oratimestamp, sys.oradate),
	OPERATOR        4       >= (sys.oratimestamp, sys.oradate),
	OPERATOR        5       > (sys.oratimestamp, sys.oradate),
	FUNCTION        1       sys.oratimestamp_cmp_oradate(sys.oratimestamp, sys.oradate),
	
	OPERATOR        1       < (sys.oratimestamp, sys.oratimestamptz),
	OPERATOR        2       <= (sys.oratimestamp, sys.oratimestamptz),
	OPERATOR        3       = (sys.oratimestamp, sys.oratimestamptz),
	OPERATOR        4       >= (sys.oratimestamp, sys.oratimestamptz),
	OPERATOR        5       > (sys.oratimestamp, sys.oratimestamptz),
	FUNCTION        1       sys.oratimestamp_cmp_oratimestamptz(sys.oratimestamp, sys.oratimestamptz),
	
	OPERATOR        1       < (sys.oratimestamp, sys.oratimestampltz),
	OPERATOR        2       <= (sys.oratimestamp, sys.oratimestampltz),
	OPERATOR        3       = (sys.oratimestamp, sys.oratimestampltz),
	OPERATOR        4       >= (sys.oratimestamp, sys.oratimestampltz),
	OPERATOR        5       > (sys.oratimestamp, sys.oratimestampltz),
	FUNCTION        1       sys.oratimestamp_cmp_oratimestampltz(sys.oratimestamp, sys.oratimestampltz);
	
/* HASH index support */
CREATE FUNCTION sys.oratimestamp_hash(sys.oratimestamp)
RETURNS integer
AS 'MODULE_PATHNAME','oratimestamp_hash'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oratimestamp_hash_extended(sys.oratimestamp, int8)
RETURNS bigint
AS 'MODULE_PATHNAME','oratimestamp_hash_extended'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR CLASS sys.oratimestamp_ops
    DEFAULT FOR TYPE sys.oratimestamp USING hash AS
		OPERATOR        1       = (sys.oratimestamp, sys.oratimestamp),
		FUNCTION        1       sys.oratimestamp_hash(sys.oratimestamp),
		FUNCTION        2       sys.oratimestamp_hash_extended(sys.oratimestamp, int8);

/*
 * Brin index support
 */
/* CREATE OPERATOR CLASS for 'oratimestamp' */
CREATE OPERATOR CLASS sys.oratimestamp_minmax_ops
    DEFAULT FOR TYPE sys.oratimestamp USING brin FAMILY sys.oradatetime_minmax_ops AS
        OPERATOR        1       < (sys.oratimestamp, sys.oratimestamp),
        OPERATOR        2       <= (sys.oratimestamp, sys.oratimestamp),
        OPERATOR        3       = (sys.oratimestamp, sys.oratimestamp),
        OPERATOR        4       >= (sys.oratimestamp, sys.oratimestamp),
        OPERATOR        5       > (sys.oratimestamp, sys.oratimestamp),
        FUNCTION        1       sys.brin_minmax_opcinfo(internal),
		FUNCTION        2       sys.brin_minmax_add_value(internal, internal, internal, internal),
		FUNCTION        3       sys.brin_minmax_consistent(internal, internal, internal),
		FUNCTION        4       sys.brin_minmax_union(internal, internal, internal);
		
ALTER OPERATOR FAMILY sys.oradatetime_minmax_ops USING brin ADD
	OPERATOR        1       < (sys.oratimestamp, sys.oradate),
	OPERATOR        2       <= (sys.oratimestamp, sys.oradate),
	OPERATOR        3       = (sys.oratimestamp, sys.oradate),
	OPERATOR        4       >= (sys.oratimestamp, sys.oradate),
	OPERATOR        5       > (sys.oratimestamp, sys.oradate),
	
	OPERATOR        1       < (sys.oratimestamp, sys.oratimestamptz),
	OPERATOR        2       <= (sys.oratimestamp, sys.oratimestamptz),
	OPERATOR        3       = (sys.oratimestamp, sys.oratimestamptz),
	OPERATOR        4       >= (sys.oratimestamp, sys.oratimestamptz),
	OPERATOR        5       > (sys.oratimestamp, sys.oratimestamptz),
	
	OPERATOR        1       < (sys.oratimestamp, sys.oratimestampltz),
	OPERATOR        2       <= (sys.oratimestamp, sys.oratimestampltz),
	OPERATOR        3       = (sys.oratimestamp, sys.oratimestampltz),
	OPERATOR        4       >= (sys.oratimestamp, sys.oratimestampltz),
	OPERATOR        5       > (sys.oratimestamp, sys.oratimestampltz);	

/* Create aggregate for type 'oratimestamp' */
/* Aggregate Function */
CREATE FUNCTION sys.oratimestamp_larger(sys.oratimestamp, sys.oratimestamp)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','oratimestamp_larger'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oratimestamp_smaller(sys.oratimestamp, sys.oratimestamp)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','oratimestamp_smaller'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE AGGREGATE sys.max(sys.oratimestamp) (
  SFUNC=sys.oratimestamp_larger,
  STYPE= sys.oratimestamp,
  SORTOP= >
);
CREATE AGGREGATE sys.min(sys.oratimestamp) (
  SFUNC=sys.oratimestamp_smaller,
  STYPE= sys.oratimestamp,
  SORTOP= <
);		
		
/***************************************************************
 *
 * oracle timestamp with time zone type support
 *
 ****************************************************************/
CREATE FUNCTION sys.oratimestamptz_in(cstring, oid, integer)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','oratimestamptz_in'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_out(sys.oratimestamptz)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oratimestamptz_out'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_recv(internal, oid, integer)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','oratimestamptz_recv'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oratimestamptz_send(sys.oratimestamptz)
RETURNS bytea
AS 'MODULE_PATHNAME','oratimestamptz_send'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oratimestamptztypmodin(cstring[])
RETURNS integer
AS 'MODULE_PATHNAME','oratimestamptztypmodin'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oratimestamptztypmodout(integer)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oratimestamptztypmodout'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

UPDATE pg_type
SET typinput=(SELECT oid FROM pg_proc WHERE proname='oratimestamptz_in')
WHERE oid = 9512;

UPDATE pg_type
SET typoutput=(SELECT oid FROM pg_proc WHERE proname='oratimestamptz_out')
WHERE oid = 9512;

UPDATE pg_type
SET typreceive=(SELECT oid FROM pg_proc WHERE proname='oratimestamptz_recv')
WHERE oid = 9512;

UPDATE pg_type
SET typsend=(SELECT oid FROM pg_proc WHERE proname='oratimestamptz_send')
WHERE oid = 9512;

UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oratimestamptztypmodin')
WHERE oid = 9512;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oratimestamptztypmodout')
WHERE oid = 9512;

UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oratimestamptztypmodin')
WHERE oid = 9513;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oratimestamptztypmodout')
WHERE oid = 9513;

/* CREATE CAST */
----------- Compatible Postgresql Cast -----------
CREATE CAST (sys.oratimestamptz AS pg_catalog.timestamptz)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (pg_catalog.timestamptz AS sys.oratimestamptz)
WITHOUT FUNCTION
AS IMPLICIT;

----------- Compatible Oracle Cast -----------
CREATE CAST (sys.oratimestamptz AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oratimestamptz AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oratimestamptz AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oratimestamptz AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

-- Converts a oratimestamptz(n) type to the specified typmod
CREATE FUNCTION sys.oratimestamptz(sys.oratimestamptz,integer)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.oratimestamptz AS sys.oratimestamptz)
WITH FUNCTION sys.oratimestamptz(sys.oratimestamptz, integer)
AS IMPLICIT;

CREATE FUNCTION sys.oratimestamptz_oradate(sys.oratimestamptz)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oratimestamptz_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE CAST (sys.oratimestamptz AS sys.oradate)
WITH FUNCTION sys.oratimestamptz_oradate(sys.oratimestamptz)
AS IMPLICIT;

CREATE FUNCTION sys.oratimestamptz_oratimestamp(sys.oratimestamptz)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','oratimestamptz_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE CAST (sys.oratimestamptz AS sys.oratimestamp)
WITH FUNCTION sys.oratimestamptz_oratimestamp(sys.oratimestamptz)
AS IMPLICIT;

CREATE CAST (sys.oratimestamptz AS sys.oratimestampltz)
WITHOUT FUNCTION 
AS IMPLICIT;

/* CREATE OPERATOR */
CREATE FUNCTION sys.oratimestamptz_eq(sys.oratimestamptz, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_eq'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestamptz_ne(sys.oratimestamptz, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_ne'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestamptz_lt(sys.oratimestamptz, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_lt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestamptz_gt(sys.oratimestamptz, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_gt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestamptz_le(sys.oratimestamptz, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_le'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestamptz_ge(sys.oratimestamptz, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_ge'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE OPERATOR = (
	procedure = sys.oratimestamptz_eq,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestamptz,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oratimestamptz_ne,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestamptz,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oratimestamptz_lt,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestamptz,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oratimestamptz_gt,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestamptz,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oratimestamptz_ge,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestamptz,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oratimestamptz_le,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestamptz,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* oratimestamptz vs oradate */
CREATE FUNCTION sys.oratimestamptz_eq_oradate(sys.oratimestamptz, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_eq_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_ne_oradate(sys.oratimestamptz, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_ne_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_lt_oradate(sys.oratimestamptz, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_lt_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_gt_oradate(sys.oratimestamptz, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_gt_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_le_oradate(sys.oratimestamptz, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_le_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_ge_oradate(sys.oratimestamptz, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_ge_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE OPERATOR = (
	procedure = sys.oratimestamptz_eq_oradate,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oradate,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oratimestamptz_ne_oradate,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oradate,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oratimestamptz_lt_oradate,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oradate,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oratimestamptz_gt_oradate,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oradate,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oratimestamptz_ge_oradate,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oradate,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oratimestamptz_le_oradate,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oradate,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* oratimestamptz vs oratimestamp */
CREATE FUNCTION sys.oratimestamptz_eq_oratimestamp(sys.oratimestamptz, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_eq_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_ne_oratimestamp(sys.oratimestamptz, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_ne_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_lt_oratimestamp(sys.oratimestamptz, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_lt_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_gt_oratimestamp(sys.oratimestamptz, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_gt_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_le_oratimestamp(sys.oratimestamptz, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_le_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_ge_oratimestamp(sys.oratimestamptz, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_ge_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE OPERATOR = (
	procedure = sys.oratimestamptz_eq_oratimestamp,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestamp,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oratimestamptz_ne_oratimestamp,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestamp,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oratimestamptz_lt_oratimestamp,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestamp,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oratimestamptz_gt_oratimestamp,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestamp,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oratimestamptz_ge_oratimestamp,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestamp,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oratimestamptz_le_oratimestamp,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestamp,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* oratimestamptz vs oratimestampltz */
CREATE FUNCTION sys.oratimestamptz_eq_oratimestampltz(sys.oratimestamptz, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_eq_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_ne_oratimestampltz(sys.oratimestamptz, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_ne_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_lt_oratimestampltz(sys.oratimestamptz, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_lt_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_gt_oratimestampltz(sys.oratimestamptz, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_gt_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_le_oratimestampltz(sys.oratimestamptz, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_le_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_ge_oratimestampltz(sys.oratimestamptz, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestamptz_ge_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE OPERATOR = (
	procedure = sys.oratimestamptz_eq_oratimestampltz,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestampltz,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oratimestamptz_ne_oratimestampltz,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestampltz,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oratimestamptz_lt_oratimestampltz,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestampltz,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oratimestamptz_gt_oratimestampltz,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestampltz,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oratimestamptz_ge_oratimestampltz,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestampltz,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oratimestamptz_le_oratimestampltz,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestampltz,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/*
 * B-tree Index Support
 */
/* B-tree index support procedure */
CREATE FUNCTION sys.oratimestamptz_cmp(sys.oratimestamptz, sys.oratimestamptz)
RETURNS integer
AS 'MODULE_PATHNAME','oratimestamptz_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestamptz_cmp_oradate(sys.oratimestamptz, sys.oradate)
RETURNS integer
AS 'MODULE_PATHNAME','oratimestamptz_cmp_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_cmp_oratimestamp(sys.oratimestamptz, sys.oratimestamp)
RETURNS integer
AS 'MODULE_PATHNAME','oratimestamptz_cmp_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_cmp_oratimestampltz(sys.oratimestamptz, sys.oratimestampltz)
RETURNS integer
AS 'MODULE_PATHNAME','oratimestamptz_cmp_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestamptz_sortsupport(internal)
RETURNS void
AS 'timestamp_sortsupport'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

/* CREATE OPERATOR CLASS for 'oratimestamptz' */
CREATE OPERATOR CLASS sys.oratimestamptz_ops
    DEFAULT FOR TYPE sys.oratimestamptz USING btree FAMILY sys.oradatetime_ops AS
        OPERATOR        1       < (sys.oratimestamptz, sys.oratimestamptz),
        OPERATOR        2       <= (sys.oratimestamptz, sys.oratimestamptz),
        OPERATOR        3       = (sys.oratimestamptz, sys.oratimestamptz),
        OPERATOR        4       >= (sys.oratimestamptz, sys.oratimestamptz),
        OPERATOR        5       > (sys.oratimestamptz, sys.oratimestamptz),
        FUNCTION        1       sys.oratimestamptz_cmp(sys.oratimestamptz, sys.oratimestamptz),
		FUNCTION		2		sys.oratimestamptz_sortsupport(internal);

ALTER OPERATOR FAMILY sys.oradatetime_ops USING btree ADD
	-- Cross data type comparison
	OPERATOR        1       < (sys.oratimestamptz, sys.oradate),
	OPERATOR        2       <= (sys.oratimestamptz, sys.oradate),
	OPERATOR        3       = (sys.oratimestamptz, sys.oradate),
	OPERATOR        4       >= (sys.oratimestamptz, sys.oradate),
	OPERATOR        5       > (sys.oratimestamptz, sys.oradate),
	FUNCTION        1       sys.oratimestamptz_cmp_oradate(sys.oratimestamptz, sys.oradate),
	
	OPERATOR        1       < (sys.oratimestamptz, sys.oratimestamp),
	OPERATOR        2       <= (sys.oratimestamptz, sys.oratimestamp),
	OPERATOR        3       = (sys.oratimestamptz, sys.oratimestamp),
	OPERATOR        4       >= (sys.oratimestamptz, sys.oratimestamp),
	OPERATOR        5       > (sys.oratimestamptz, sys.oratimestamp),
	FUNCTION        1       sys.oratimestamptz_cmp_oratimestamp(sys.oratimestamptz, sys.oratimestamp),
	
	OPERATOR        1       < (sys.oratimestamptz, sys.oratimestampltz),
	OPERATOR        2       <= (sys.oratimestamptz, sys.oratimestampltz),
	OPERATOR        3       = (sys.oratimestamptz, sys.oratimestampltz),
	OPERATOR        4       >= (sys.oratimestamptz, sys.oratimestampltz),
	OPERATOR        5       > (sys.oratimestamptz, sys.oratimestampltz),
	FUNCTION        1       sys.oratimestamptz_cmp_oratimestampltz(sys.oratimestamptz, sys.oratimestampltz);
		
/* HASH index support */
CREATE FUNCTION sys.oratimestamptz_hash(sys.oratimestamptz)
RETURNS integer
AS 'MODULE_PATHNAME','oratimestamptz_hash'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR CLASS sys.oratimestamptz_ops
    DEFAULT FOR TYPE sys.oratimestamptz USING hash AS
		OPERATOR        1       = (sys.oratimestamptz, sys.oratimestamptz),
        FUNCTION        1       sys.oratimestamptz_hash(sys.oratimestamptz);		

/*
 * Brin index support
 */
/* CREATE OPERATOR CLASS for 'oratimestamptz' */
CREATE OPERATOR CLASS sys.oratimestamptz_minmax_ops
    DEFAULT FOR TYPE sys.oratimestamptz USING brin FAMILY sys.oradatetime_minmax_ops AS
        OPERATOR        1       < (sys.oratimestamptz, sys.oratimestamptz),
        OPERATOR        2       <= (sys.oratimestamptz, sys.oratimestamptz),
        OPERATOR        3       = (sys.oratimestamptz, sys.oratimestamptz),
        OPERATOR        4       >= (sys.oratimestamptz, sys.oratimestamptz),
        OPERATOR        5       > (sys.oratimestamptz, sys.oratimestamptz),
        FUNCTION        1       sys.brin_minmax_opcinfo(internal),
		FUNCTION        2       sys.brin_minmax_add_value(internal, internal, internal, internal),
		FUNCTION        3       sys.brin_minmax_consistent(internal, internal, internal),
		FUNCTION        4       sys.brin_minmax_union(internal, internal, internal);
		
ALTER OPERATOR FAMILY sys.oradatetime_minmax_ops USING brin ADD
	OPERATOR        1       < (sys.oratimestamptz, sys.oradate),
	OPERATOR        2       <= (sys.oratimestamptz, sys.oradate),
	OPERATOR        3       = (sys.oratimestamptz, sys.oradate),
	OPERATOR        4       >= (sys.oratimestamptz, sys.oradate),
	OPERATOR        5       > (sys.oratimestamptz, sys.oradate),
	
	OPERATOR        1       < (sys.oratimestamptz, sys.oratimestamp),
	OPERATOR        2       <= (sys.oratimestamptz, sys.oratimestamp),
	OPERATOR        3       = (sys.oratimestamptz, sys.oratimestamp),
	OPERATOR        4       >= (sys.oratimestamptz, sys.oratimestamp),
	OPERATOR        5       > (sys.oratimestamptz, sys.oratimestamp),
	
	OPERATOR        1       < (sys.oratimestamptz, sys.oratimestampltz),
	OPERATOR        2       <= (sys.oratimestamptz, sys.oratimestampltz),
	OPERATOR        3       = (sys.oratimestamptz, sys.oratimestampltz),
	OPERATOR        4       >= (sys.oratimestamptz, sys.oratimestampltz),
	OPERATOR        5       > (sys.oratimestamptz, sys.oratimestampltz);


/* Create aggregate for type 'oratimestamptz' */
/* Aggregate Function */
CREATE FUNCTION sys.oratimestamptz_larger(sys.oratimestamptz, sys.oratimestamptz)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','oratimestamptz_larger'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oratimestamptz_smaller(sys.oratimestamptz, sys.oratimestamptz)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','oratimestamptz_smaller'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE AGGREGATE sys.max(sys.oratimestamptz) (
  SFUNC=sys.oratimestamptz_larger,
  STYPE= sys.oratimestamptz,
  SORTOP= >
);
CREATE AGGREGATE sys.min(sys.oratimestamptz) (
  SFUNC=sys.oratimestamptz_smaller,
  STYPE= sys.oratimestamptz,
  SORTOP= <
);		

/***************************************************************
 *
 * oracle timestamp with local time zone type support
 *
 ****************************************************************/
CREATE FUNCTION sys.oratimestampltz_in(cstring, oid, integer)
RETURNS sys.oratimestampltz
AS 'MODULE_PATHNAME','oratimestampltz_in'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_out(sys.oratimestampltz)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oratimestampltz_out'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_recv(internal, oid, integer)
RETURNS sys.oratimestampltz
AS 'MODULE_PATHNAME','oratimestampltz_recv'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oratimestampltz_send(sys.oratimestampltz)
RETURNS bytea
AS 'MODULE_PATHNAME','oratimestampltz_send'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oratimestampltztypmodin(cstring[])
RETURNS integer
AS 'MODULE_PATHNAME','oratimestampltztypmodin'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oratimestampltztypmodout(integer)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oratimestampltztypmodout'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

-- Register the basic I/O for 'oratimestampltz' in pg_type.
UPDATE pg_type
SET typinput=(SELECT oid FROM pg_proc WHERE proname='oratimestampltz_in')
WHERE oid = 9514;

UPDATE pg_type
SET typoutput=(SELECT oid FROM pg_proc WHERE proname='oratimestampltz_out')
WHERE oid = 9514;

UPDATE pg_type
SET typreceive=(SELECT oid FROM pg_proc WHERE proname='oratimestampltz_recv')
WHERE oid = 9514;

UPDATE pg_type
SET typsend=(SELECT oid FROM pg_proc WHERE proname='oratimestampltz_send')
WHERE oid = 9514;

UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oratimestampltztypmodin')
WHERE oid = 9514;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oratimestampltztypmodout')
WHERE oid = 9514;

-- Register the typmod inout for 'oratimestampltz' array type in pg_type.
UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oratimestampltztypmodin')
WHERE oid = 9515;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oratimestampltztypmodout')
WHERE oid = 9515;

/* CREATE CAST */
---------- Compatible Oracle Cast ----------
CREATE CAST (sys.oratimestampltz AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oratimestampltz AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oratimestampltz AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oratimestampltz AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

CREATE FUNCTION sys.oratimestampltz(sys.oratimestampltz,integer)
RETURNS sys.oratimestampltz
AS 'MODULE_PATHNAME','oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.oratimestampltz AS sys.oratimestampltz)
WITH FUNCTION sys.oratimestampltz(sys.oratimestampltz, integer)
AS IMPLICIT;

CREATE FUNCTION sys.oratimestampltz_oradate(sys.oratimestampltz)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oratimestampltz_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE CAST (sys.oratimestampltz AS sys.oradate)
WITH FUNCTION sys.oratimestampltz_oradate(sys.oratimestampltz)
AS IMPLICIT;

CREATE FUNCTION sys.oratimestampltz_oratimestamp(sys.oratimestampltz)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','oratimestampltz_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE CAST (sys.oratimestampltz AS sys.oratimestamp)
WITH FUNCTION sys.oratimestampltz_oratimestamp(sys.oratimestampltz)
AS IMPLICIT;

CREATE CAST (sys.oratimestampltz AS sys.oratimestamptz)
WITHOUT FUNCTION 
AS IMPLICIT;

/* CREATE OPERATOR */
CREATE FUNCTION sys.oratimestampltz_eq(sys.oratimestampltz, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_eq'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestampltz_ne(sys.oratimestampltz, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_ne'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestampltz_lt(sys.oratimestampltz, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_lt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestampltz_gt(sys.oratimestampltz, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_gt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestampltz_le(sys.oratimestampltz, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_le'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestampltz_ge(sys.oratimestampltz, sys.oratimestampltz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_ge'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE OPERATOR = (
	procedure = sys.oratimestampltz_eq,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestampltz,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oratimestampltz_ne,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestampltz,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oratimestampltz_lt,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestampltz,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oratimestampltz_gt,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestampltz,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oratimestampltz_ge,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestampltz,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oratimestampltz_le,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestampltz,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* oratimestampltz vs oradate */
CREATE FUNCTION sys.oratimestampltz_eq_oradate(sys.oratimestampltz, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_eq_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_ne_oradate(sys.oratimestampltz, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_ne_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_lt_oradate(sys.oratimestampltz, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_lt_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_gt_oradate(sys.oratimestampltz, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_gt_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_le_oradate(sys.oratimestampltz, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_le_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_ge_oradate(sys.oratimestampltz, sys.oradate)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_ge_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE OPERATOR = (
	procedure = sys.oratimestampltz_eq_oradate,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oradate,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oratimestampltz_ne_oradate,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oradate,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oratimestampltz_lt_oradate,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oradate,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oratimestampltz_gt_oradate,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oradate,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oratimestampltz_ge_oradate,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oradate,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oratimestampltz_le_oradate,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oradate,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* oratimestampltz vs oratimestamp */
CREATE FUNCTION sys.oratimestampltz_eq_oratimestamp(sys.oratimestampltz, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_eq_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_ne_oratimestamp(sys.oratimestampltz, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_ne_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_lt_oratimestamp(sys.oratimestampltz, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_lt_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_gt_oratimestamp(sys.oratimestampltz, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_gt_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_le_oratimestamp(sys.oratimestampltz, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_le_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_ge_oratimestamp(sys.oratimestampltz, sys.oratimestamp)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_ge_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE OPERATOR = (
	procedure = sys.oratimestampltz_eq_oratimestamp,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestamp,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oratimestampltz_ne_oratimestamp,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestamp,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oratimestampltz_lt_oratimestamp,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestamp,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oratimestampltz_gt_oratimestamp,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestamp,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oratimestampltz_ge_oratimestamp,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestamp,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oratimestampltz_le_oratimestamp,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestamp,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* oratimestampltz vs oratimestamptz */
CREATE FUNCTION sys.oratimestampltz_eq_oratimestamptz(sys.oratimestampltz, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_eq_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_ne_oratimestamptz(sys.oratimestampltz, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_ne_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_lt_oratimestamptz(sys.oratimestampltz, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_lt_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_gt_oratimestamptz(sys.oratimestampltz, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_gt_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_le_oratimestamptz(sys.oratimestampltz, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_le_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_ge_oratimestamptz(sys.oratimestampltz, sys.oratimestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME','oratimestampltz_ge_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE OPERATOR = (
	procedure = sys.oratimestampltz_eq_oratimestamptz,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestamptz,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.oratimestampltz_ne_oratimestamptz,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestamptz,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.oratimestampltz_lt_oratimestamptz,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestamptz,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.oratimestampltz_gt_oratimestamptz,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestamptz,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.oratimestampltz_ge_oratimestamptz,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestamptz,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.oratimestampltz_le_oratimestamptz,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestamptz,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/*
 * B-tree Index Support
 */
/* B-tree index support procedure */
CREATE FUNCTION sys.oratimestampltz_cmp(sys.oratimestampltz, sys.oratimestampltz)
RETURNS integer
AS 'MODULE_PATHNAME','oratimestampltz_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.oratimestampltz_cmp_oradate(sys.oratimestampltz, sys.oradate)
RETURNS integer
AS 'MODULE_PATHNAME','oratimestampltz_cmp_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_cmp_oratimestamp(sys.oratimestampltz, sys.oratimestamp)
RETURNS integer
AS 'MODULE_PATHNAME','oratimestampltz_cmp_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_cmp_oratimestamptz(sys.oratimestampltz, sys.oratimestamptz)
RETURNS integer
AS 'MODULE_PATHNAME','oratimestampltz_cmp_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.oratimestampltz_sortsupport(internal)
RETURNS void
AS 'timestamp_sortsupport'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

/* CREATE OPERATOR CLASS for 'oratimestampltz' */
CREATE OPERATOR CLASS sys.oratimestampltz_ops
    DEFAULT FOR TYPE sys.oratimestampltz USING btree FAMILY sys.oradatetime_ops AS
        OPERATOR        1       < (sys.oratimestampltz, sys.oratimestampltz),
        OPERATOR        2       <= (sys.oratimestampltz, sys.oratimestampltz),
        OPERATOR        3       = (sys.oratimestampltz, sys.oratimestampltz),
        OPERATOR        4       >= (sys.oratimestampltz, sys.oratimestampltz),
        OPERATOR        5       > (sys.oratimestampltz, sys.oratimestampltz),
        FUNCTION        1       sys.oratimestampltz_cmp(sys.oratimestampltz, sys.oratimestampltz),
		FUNCTION		2		sys.oratimestampltz_sortsupport(internal),
		FUNCTION		4		(sys.oratimestampltz, sys.oratimestampltz) sys.btoraequalimage(oid);

ALTER OPERATOR FAMILY sys.oradatetime_ops USING btree ADD
	-- Cross data type comparison
	OPERATOR        1       < (sys.oratimestampltz, sys.oradate),
	OPERATOR        2       <= (sys.oratimestampltz, sys.oradate),
	OPERATOR        3       = (sys.oratimestampltz, sys.oradate),
	OPERATOR        4       >= (sys.oratimestampltz, sys.oradate),
	OPERATOR        5       > (sys.oratimestampltz, sys.oradate),
	FUNCTION        1       sys.oratimestampltz_cmp_oradate(sys.oratimestampltz, sys.oradate),
	
	OPERATOR        1       < (sys.oratimestampltz, sys.oratimestamp),
	OPERATOR        2       <= (sys.oratimestampltz, sys.oratimestamp),
	OPERATOR        3       = (sys.oratimestampltz, sys.oratimestamp),
	OPERATOR        4       >= (sys.oratimestampltz, sys.oratimestamp),
	OPERATOR        5       > (sys.oratimestampltz, sys.oratimestamp),
	FUNCTION        1       sys.oratimestampltz_cmp_oratimestamp(sys.oratimestampltz, sys.oratimestamp),
	
	OPERATOR        1       < (sys.oratimestampltz, sys.oratimestamptz),
	OPERATOR        2       <= (sys.oratimestampltz, sys.oratimestamptz),
	OPERATOR        3       = (sys.oratimestampltz, sys.oratimestamptz),
	OPERATOR        4       >= (sys.oratimestampltz, sys.oratimestamptz),
	OPERATOR        5       > (sys.oratimestampltz, sys.oratimestamptz),
	FUNCTION        1       sys.oratimestampltz_cmp_oratimestamptz(sys.oratimestampltz, sys.oratimestamptz);

		
/* HASH index support */
CREATE FUNCTION sys.oratimestampltz_hash(sys.oratimestampltz)
RETURNS integer
AS 'MODULE_PATHNAME','oratimestampltz_hash'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oratimestampltz_hash_extended(sys.oratimestampltz, int8)
RETURNS bigint
AS 'MODULE_PATHNAME','oratimestamp_hash_extended'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR CLASS sys.oratimestampltz_ops
    DEFAULT FOR TYPE sys.oratimestampltz USING hash AS
		OPERATOR        1       = (sys.oratimestampltz, sys.oratimestampltz),
		FUNCTION        1       sys.oratimestampltz_hash(sys.oratimestampltz),
		FUNCTION        2       sys.oratimestampltz_hash_extended(sys.oratimestampltz, int8);

/*
 * Brin index support
 */
/* CREATE OPERATOR CLASS for 'oratimestampltz' */
CREATE OPERATOR CLASS sys.oratimestampltz_minmax_ops
    DEFAULT FOR TYPE sys.oratimestampltz USING brin FAMILY sys.oradatetime_minmax_ops AS
        OPERATOR        1       < (sys.oratimestampltz, sys.oratimestampltz),
        OPERATOR        2       <= (sys.oratimestampltz, sys.oratimestampltz),
        OPERATOR        3       = (sys.oratimestampltz, sys.oratimestampltz),
        OPERATOR        4       >= (sys.oratimestampltz, sys.oratimestampltz),
        OPERATOR        5       > (sys.oratimestampltz, sys.oratimestampltz),
        FUNCTION        1       sys.brin_minmax_opcinfo(internal),
		FUNCTION        2       sys.brin_minmax_add_value(internal, internal, internal, internal),
		FUNCTION        3       sys.brin_minmax_consistent(internal, internal, internal),
		FUNCTION        4       sys.brin_minmax_union(internal, internal, internal);
		
ALTER OPERATOR FAMILY sys.oradatetime_minmax_ops USING brin ADD
	OPERATOR        1       < (sys.oratimestampltz, sys.oradate),
	OPERATOR        2       <= (sys.oratimestampltz, sys.oradate),
	OPERATOR        3       = (sys.oratimestampltz, sys.oradate),
	OPERATOR        4       >= (sys.oratimestampltz, sys.oradate),
	OPERATOR        5       > (sys.oratimestampltz, sys.oradate),
	
	OPERATOR        1       < (sys.oratimestampltz, sys.oratimestamp),
	OPERATOR        2       <= (sys.oratimestampltz, sys.oratimestamp),
	OPERATOR        3       = (sys.oratimestampltz, sys.oratimestamp),
	OPERATOR        4       >= (sys.oratimestampltz, sys.oratimestamp),
	OPERATOR        5       > (sys.oratimestampltz, sys.oratimestamp),
	
	OPERATOR        1       < (sys.oratimestampltz, sys.oratimestamptz),
	OPERATOR        2       <= (sys.oratimestampltz, sys.oratimestamptz),
	OPERATOR        3       = (sys.oratimestampltz, sys.oratimestamptz),
	OPERATOR        4       >= (sys.oratimestampltz, sys.oratimestamptz),
	OPERATOR        5       > (sys.oratimestampltz, sys.oratimestamptz);

/* Create aggregate for type 'oratimestampltz' */
/* Aggregate Function */
CREATE FUNCTION sys.oratimestampltz_larger(sys.oratimestampltz, sys.oratimestampltz)
RETURNS sys.oratimestampltz
AS 'MODULE_PATHNAME','oratimestampltz_larger'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oratimestampltz_smaller(sys.oratimestampltz, sys.oratimestampltz)
RETURNS sys.oratimestampltz
AS 'MODULE_PATHNAME','oratimestampltz_smaller'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE AGGREGATE sys.max(sys.oratimestampltz) (
  SFUNC=sys.oratimestampltz_larger,
  STYPE= sys.oratimestampltz,
  SORTOP= >
);
CREATE AGGREGATE sys.min(sys.oratimestampltz) (
  SFUNC=sys.oratimestampltz_smaller,
  STYPE= sys.oratimestampltz,
  SORTOP= <
);

/***************************************************************
 *
 * oracle INTERVAL YEAR TO MONTH type support
 *
 ****************************************************************/
CREATE FUNCTION sys.yminterval_in(cstring, oid, integer)
RETURNS sys.yminterval
AS 'MODULE_PATHNAME','yminterval_in'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.yminterval_out(sys.yminterval)
RETURNS CSTRING
AS 'MODULE_PATHNAME','yminterval_out'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.yminterval_recv(internal, oid, integer)
RETURNS sys.yminterval
AS 'MODULE_PATHNAME','yminterval_recv'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.yminterval_send(sys.yminterval)
RETURNS bytea
AS 'MODULE_PATHNAME','yminterval_send'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.ymintervaltypmodin(cstring[])
RETURNS integer
AS 'MODULE_PATHNAME','ymintervaltypmodin'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.ymintervaltypmodout(integer)
RETURNS CSTRING
AS 'MODULE_PATHNAME','ymintervaltypmodout'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

UPDATE pg_type
SET typinput=(SELECT oid FROM pg_proc WHERE proname='yminterval_in')
WHERE oid = 9516;

UPDATE pg_type
SET typoutput=(SELECT oid FROM pg_proc WHERE proname='yminterval_out')
WHERE oid = 9516;

UPDATE pg_type
SET typreceive=(SELECT oid FROM pg_proc WHERE proname='yminterval_recv')
WHERE oid = 9516;

UPDATE pg_type
SET typsend=(SELECT oid FROM pg_proc WHERE proname='yminterval_send')
WHERE oid = 9516;

UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='ymintervaltypmodin')
WHERE oid = 9516;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='ymintervaltypmodout')
WHERE oid = 9516;


UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='ymintervaltypmodin')
WHERE oid = 9517;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='ymintervaltypmodout')
WHERE oid = 9517;

/* CREATE CAST */
--------- Compatible Oracle Cast ---------
-- Converts a yminterval type to the specified typmod
CREATE FUNCTION sys.yminterval(sys.yminterval, integer)
RETURNS sys.yminterval
AS 'MODULE_PATHNAME','yminterval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.yminterval AS sys.yminterval)
WITH FUNCTION sys.yminterval(sys.yminterval, integer)
AS IMPLICIT;

/* implicit conversion (varchar2 & yminterval) */
CREATE CAST (sys.yminterval AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.yminterval AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

/* implicit conversion (char & yminterval) */
CREATE CAST (sys.yminterval AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.yminterval AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

/* CREATE OPERATOR */
CREATE FUNCTION sys.yminterval_eq(sys.yminterval, sys.yminterval)
RETURNS boolean
AS 'MODULE_PATHNAME','yminterval_eq'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.yminterval_ne(sys.yminterval, sys.yminterval)
RETURNS boolean
AS 'MODULE_PATHNAME','yminterval_ne'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.yminterval_lt(sys.yminterval, sys.yminterval)
RETURNS boolean
AS 'MODULE_PATHNAME','yminterval_lt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.yminterval_gt(sys.yminterval, sys.yminterval)
RETURNS boolean
AS 'MODULE_PATHNAME','yminterval_gt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.yminterval_le(sys.yminterval, sys.yminterval)
RETURNS boolean
AS 'MODULE_PATHNAME','yminterval_le'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.yminterval_ge(sys.yminterval, sys.yminterval)
RETURNS boolean
AS 'MODULE_PATHNAME','yminterval_ge'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

/* Arithmetic operation */
CREATE FUNCTION sys.yminterval_mi(sys.yminterval, sys.yminterval)
RETURNS sys.yminterval
AS 'MODULE_PATHNAME','yminterval_mi'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.yminterval_pl(sys.yminterval, sys.yminterval)
RETURNS sys.yminterval
AS 'MODULE_PATHNAME','yminterval_pl'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.yminterval_pl,
	leftarg = sys.yminterval,
	rightarg = sys.yminterval,
	commutator = +
);

CREATE OPERATOR - (
	procedure = sys.yminterval_mi,
	leftarg = sys.yminterval,
	rightarg = sys.yminterval
);

CREATE OPERATOR = (
	procedure = sys.yminterval_eq,
	leftarg = sys.yminterval,
	rightarg = sys.yminterval,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);

CREATE OPERATOR <> (
	procedure = sys.yminterval_ne,
	leftarg = sys.yminterval,
	rightarg = sys.yminterval,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);

CREATE OPERATOR < (
	procedure = sys.yminterval_lt,
	leftarg = sys.yminterval,
	rightarg = sys.yminterval,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR > (
	procedure = sys.yminterval_gt,
	leftarg = sys.yminterval,
	rightarg = sys.yminterval,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR >= (
	procedure = sys.yminterval_ge,
	leftarg = sys.yminterval,
	rightarg = sys.yminterval,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR <= (
	procedure = sys.yminterval_le,
	leftarg = sys.yminterval,
	rightarg = sys.yminterval,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

--
-- B-tree index support
--
CREATE FUNCTION sys.yminterval_cmp(sys.yminterval, sys.yminterval)
RETURNS INTEGER
AS 'MODULE_PATHNAME','yminterval_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.ymin_range(sys.yminterval, sys.yminterval, sys.yminterval, bool, bool)
RETURNS boolean
AS 'MODULE_PATHNAME','in_range_yminterval_yminterval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR CLASS sys.yminterval_ops
    DEFAULT FOR TYPE sys.yminterval USING btree AS
        OPERATOR        1       < (sys.yminterval, sys.yminterval),
        OPERATOR        2       <= (sys.yminterval, sys.yminterval),
        OPERATOR        3       = (sys.yminterval, sys.yminterval),
        OPERATOR        4       >= (sys.yminterval, sys.yminterval),
        OPERATOR        5       > (sys.yminterval, sys.yminterval),
        FUNCTION        1       sys.yminterval_cmp(sys.yminterval, sys.yminterval),
        FUNCTION        3       sys.ymin_range(sys.yminterval, sys.yminterval, sys.yminterval, bool, bool),
        FUNCTION        4       (sys.yminterval, sys.yminterval) sys.btoraequalimage(oid);

--
-- HASH index support
--		
CREATE FUNCTION sys.yminterval_hash(sys.yminterval)
RETURNS INTEGER
AS 'MODULE_PATHNAME','yminterval_hash'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.yminterval_hash_extended(sys.yminterval, int8)
RETURNS bigint
AS 'MODULE_PATHNAME','yminterval_hash_extended'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR CLASS sys.yminterval_ops
    DEFAULT FOR TYPE sys.yminterval USING hash AS
		OPERATOR        1       = (sys.yminterval, sys.yminterval),
        FUNCTION        1       sys.yminterval_hash(sys.yminterval),
        FUNCTION        2       sys.yminterval_hash_extended(sys.yminterval, int8);

--
-- BRIN index support
--			
CREATE OPERATOR CLASS sys.yminterval_minmax_ops
    DEFAULT FOR TYPE sys.yminterval USING brin AS
        OPERATOR        1       < (sys.yminterval, sys.yminterval),
        OPERATOR        2       <= (sys.yminterval, sys.yminterval),
        OPERATOR        3       = (sys.yminterval, sys.yminterval),
        OPERATOR        4       >= (sys.yminterval, sys.yminterval),
        OPERATOR        5       > (sys.yminterval, sys.yminterval),
        FUNCTION        1       sys.brin_minmax_opcinfo(internal),
		FUNCTION        2       sys.brin_minmax_add_value(internal, internal, internal, internal),
		FUNCTION        3       sys.brin_minmax_consistent(internal, internal, internal),
		FUNCTION        4       sys.brin_minmax_union(internal, internal, internal);	

/* CREATE AGGREGATE */	
CREATE FUNCTION sys.yminterval_larger(sys.yminterval, sys.yminterval)
RETURNS sys.yminterval
AS 'MODULE_PATHNAME','yminterval_larger'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.yminterval_smaller(sys.yminterval, sys.yminterval)
RETURNS sys.yminterval
AS 'MODULE_PATHNAME','yminterval_smaller'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE AGGREGATE sys.max(sys.yminterval) (
  SFUNC=sys.yminterval_larger,
  STYPE= sys.yminterval,
  SORTOP= >
);
CREATE AGGREGATE sys.min(sys.yminterval) (
  SFUNC=sys.yminterval_smaller,
  STYPE= sys.yminterval,
  SORTOP= <
);

/***************************************************************
 *
 * oracle INTERVAL DAY TO SECOND type support
 *
 ****************************************************************/
CREATE FUNCTION sys.dsinterval_in(cstring, oid, integer)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','dsinterval_in'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.dsinterval_out(sys.dsinterval)
RETURNS CSTRING
AS 'MODULE_PATHNAME','dsinterval_out'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.dsinterval_recv(internal, oid, integer)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','dsinterval_recv'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.dsinterval_send(sys.dsinterval)
RETURNS bytea
AS 'MODULE_PATHNAME','dsinterval_send'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.dsintervaltypmodin(cstring[])
RETURNS integer
AS 'MODULE_PATHNAME','dsintervaltypmodin'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.dsintervaltypmodout(integer)
RETURNS CSTRING
AS 'MODULE_PATHNAME','dsintervaltypmodout'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

UPDATE pg_type
SET typinput=(SELECT oid FROM pg_proc WHERE proname='dsinterval_in')
WHERE oid = 9518;

UPDATE pg_type
SET typoutput=(SELECT oid FROM pg_proc WHERE proname='dsinterval_out')
WHERE oid = 9518;

UPDATE pg_type
SET typreceive=(SELECT oid FROM pg_proc WHERE proname='dsinterval_recv')
WHERE oid = 9518;

UPDATE pg_type
SET typsend=(SELECT oid FROM pg_proc WHERE proname='dsinterval_send')
WHERE oid = 9518;

UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='dsintervaltypmodin')
WHERE oid = 9518;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='dsintervaltypmodout')
WHERE oid = 9518;


UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='dsintervaltypmodin')
WHERE oid = 9519;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='dsintervaltypmodout')
WHERE oid = 9519;

/* CREATE CAST */
CREATE FUNCTION sys.dsinterval(sys.dsinterval, integer)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','dsinterval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.dsinterval AS sys.dsinterval)
WITH FUNCTION sys.dsinterval(sys.dsinterval, integer)
AS IMPLICIT;

/* implicit conversion (varchar2 & dsinterval) */
CREATE CAST (sys.dsinterval AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.dsinterval AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

/* implicit conversion (char & dsinterval) */
CREATE CAST (sys.dsinterval AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.dsinterval AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

/* CREATE OPERATOR */
CREATE FUNCTION sys.dsinterval_eq(sys.dsinterval, sys.dsinterval)
RETURNS boolean
AS 'MODULE_PATHNAME','dsinterval_eq'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.dsinterval_ne(sys.dsinterval, sys.dsinterval)
RETURNS boolean
AS 'MODULE_PATHNAME','dsinterval_ne'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.dsinterval_lt(sys.dsinterval, sys.dsinterval)
RETURNS boolean
AS 'MODULE_PATHNAME','dsinterval_lt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.dsinterval_gt(sys.dsinterval, sys.dsinterval)
RETURNS boolean
AS 'MODULE_PATHNAME','dsinterval_gt'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.dsinterval_le(sys.dsinterval, sys.dsinterval)
RETURNS boolean
AS 'MODULE_PATHNAME','dsinterval_le'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.dsinterval_ge(sys.dsinterval, sys.dsinterval)
RETURNS boolean
AS 'MODULE_PATHNAME','dsinterval_ge'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE OPERATOR = (
	procedure = sys.dsinterval_eq,
	leftarg = sys.dsinterval,
	rightarg = sys.dsinterval,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);
CREATE OPERATOR <> (
	procedure = sys.dsinterval_ne,
	leftarg = sys.dsinterval,
	rightarg = sys.dsinterval,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.dsinterval_lt,
	leftarg = sys.dsinterval,
	rightarg = sys.dsinterval,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.dsinterval_gt,
	leftarg = sys.dsinterval,
	rightarg = sys.dsinterval,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.dsinterval_ge,
	leftarg = sys.dsinterval,
	rightarg = sys.dsinterval,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.dsinterval_le,
	leftarg = sys.dsinterval,
	rightarg = sys.dsinterval,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

/* Arithmetic operation */
CREATE FUNCTION sys.dsinterval_pl(sys.dsinterval, sys.dsinterval)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','dsinterval_pl'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.dsinterval_mi(sys.dsinterval, sys.dsinterval)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','dsinterval_mi'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.dsinterval_pl,
	leftarg = sys.dsinterval,
	rightarg = sys.dsinterval,
	commutator = +
);

CREATE OPERATOR - (
	procedure = sys.dsinterval_mi,
	leftarg = sys.dsinterval,
	rightarg = sys.dsinterval
);

--
-- B-tree index support
--
CREATE FUNCTION sys.dsinterval_cmp(sys.dsinterval, sys.dsinterval)
RETURNS INTEGER
AS 'MODULE_PATHNAME','dsinterval_cmp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.dsin_range(sys.dsinterval, sys.dsinterval, sys.dsinterval, bool, bool)
RETURNS boolean
AS 'MODULE_PATHNAME','in_range_dsinterval_dsinterval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE OPERATOR CLASS sys.dsinterval_ops
    DEFAULT FOR TYPE sys.dsinterval USING btree AS
        OPERATOR        1       < (sys.dsinterval, sys.dsinterval),
        OPERATOR        2       <= (sys.dsinterval, sys.dsinterval),
        OPERATOR        3       = (sys.dsinterval, sys.dsinterval),
        OPERATOR        4       >= (sys.dsinterval, sys.dsinterval),
        OPERATOR        5       > (sys.dsinterval, sys.dsinterval),
        FUNCTION        1       sys.dsinterval_cmp(sys.dsinterval, sys.dsinterval),
        FUNCTION        3       sys.dsin_range(sys.dsinterval, sys.dsinterval, sys.dsinterval, bool, bool),
        FUNCTION        4       (sys.dsinterval, sys.dsinterval) sys.btoraequalimage(oid);

--
-- HASH index support
--		
CREATE FUNCTION sys.dsinterval_hash(sys.dsinterval)
RETURNS INTEGER
AS 'MODULE_PATHNAME','dsinterval_hash'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.dsinterval_hash_extended(sys.dsinterval, int8)
RETURNS bigint
AS 'MODULE_PATHNAME','dsinterval_hash_extended'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR CLASS sys.dsinterval_ops
    DEFAULT FOR TYPE sys.dsinterval USING hash AS
		OPERATOR        1       = (sys.dsinterval, sys.dsinterval),
        FUNCTION        1       sys.dsinterval_hash(sys.dsinterval),
        FUNCTION        2       sys.dsinterval_hash_extended(sys.dsinterval, int8);

--
-- BRIN index support
--			
CREATE OPERATOR CLASS sys.dsinterval_minmax_ops
    DEFAULT FOR TYPE sys.dsinterval USING brin AS
        OPERATOR        1       < (sys.dsinterval, sys.dsinterval),
        OPERATOR        2       <= (sys.dsinterval, sys.dsinterval),
        OPERATOR        3       = (sys.dsinterval, sys.dsinterval),
        OPERATOR        4       >= (sys.dsinterval, sys.dsinterval),
        OPERATOR        5       > (sys.dsinterval, sys.dsinterval),
        FUNCTION        1       sys.brin_minmax_opcinfo(internal),
		FUNCTION        2       sys.brin_minmax_add_value(internal, internal, internal, internal),
		FUNCTION        3       sys.brin_minmax_consistent(internal, internal, internal),
		FUNCTION        4       sys.brin_minmax_union(internal, internal, internal);	


/* CREATE AGGREGATE */
CREATE FUNCTION sys.dsinterval_larger(sys.dsinterval, sys.dsinterval)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','dsinterval_larger'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.dsinterval_smaller(sys.dsinterval, sys.dsinterval)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','dsinterval_smaller'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE AGGREGATE sys.max(sys.dsinterval) (
  SFUNC=sys.dsinterval_larger,
  STYPE= sys.dsinterval,
  SORTOP= >
);
CREATE AGGREGATE sys.min(sys.dsinterval) (
  SFUNC=sys.dsinterval_smaller,
  STYPE= sys.dsinterval,
  SORTOP= <
);
		
/*****************************************************************************
 * 
 * Datetime/Interval Arithmetic
 * 
 ******************************************************************************/
--
-- oradate - other 
--
/* oradate - oradate */
CREATE FUNCTION sys.oradate_mi(sys.oradate, sys.oradate)
RETURNS sys.number
AS 'MODULE_PATHNAME','oradate_mi'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oradate_mi,
	leftarg = sys.oradate,
	rightarg = sys.oradate
);

/* oradate - oratimestamp */
CREATE FUNCTION sys.oratimestamp_mi(sys.oradate, sys.oratimestamp)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','oratimestamp_mi'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestamp_mi,
	leftarg = sys.oradate,
	rightarg = sys.oratimestamp
);

/* oradate - oratimestamptz */
CREATE FUNCTION sys.oradate_mi_oratimestampltz(sys.oradate, sys.oratimestamptz)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','oradate_mi_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oradate_mi_oratimestampltz,
	leftarg = sys.oradate,
	rightarg = sys.oratimestamptz
);

/* oradate - oratimestampltz */
CREATE FUNCTION sys.oradate_mi_oratimestampltz(sys.oradate, sys.oratimestampltz)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','oradate_mi_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oradate_mi_oratimestampltz,
	leftarg = sys.oradate,
	rightarg = sys.oratimestampltz
);

/* oradate - interval year to month */
CREATE FUNCTION sys.oradate_mi_yminterval(sys.oradate, sys.yminterval)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oradate_mi_interval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oradate_mi_yminterval,
	leftarg = sys.oradate,
	rightarg = sys.yminterval
);

/* oradate - interval day to second */
CREATE FUNCTION sys.oradate_mi_dsinterval(sys.oradate, sys.dsinterval)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oradate_mi_interval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oradate_mi_dsinterval,
	leftarg = sys.oradate,
	rightarg = sys.dsinterval
);

/* oradate - number */
CREATE FUNCTION sys.oradate_mi_number(sys.oradate, sys.number)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oradate_mi_number'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oradate_mi_number,
	leftarg = sys.oradate,
	rightarg = sys.number
);

--
-- oradate + other 
--
/* oradate + interval year to month */
CREATE FUNCTION sys.oradate_pl_yminterval(sys.oradate, sys.yminterval)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oradate_pl_interval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.oradate_pl_yminterval,
	leftarg = sys.oradate,
	rightarg = sys.yminterval,
	commutator = +
);

/* oradate + interval day to second */
CREATE FUNCTION sys.oradate_pl_dsinterval(sys.oradate, sys.dsinterval)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oradate_pl_interval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.oradate_pl_dsinterval,
	leftarg = sys.oradate,
	rightarg = sys.dsinterval,
	commutator = +
);

/* oradate + number */
CREATE FUNCTION sys.oradate_pl_number(sys.oradate, sys.number)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oradate_pl_number'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.oradate_pl_number,
	leftarg = sys.oradate,
	rightarg = sys.number,
	commutator = +
);

--
-- oratimestamp - other
--
/* oratimestamp - oratimestamp */
CREATE FUNCTION sys.oratimestamp_mi(sys.oratimestamp, sys.oratimestamp)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','oratimestamp_mi'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestamp_mi,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestamp
);

/* oratimestamp - oradate */
CREATE FUNCTION sys.oratimestamp_mi(sys.oratimestamp, sys.oradate)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','oratimestamp_mi'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestamp_mi,
	leftarg = sys.oratimestamp,
	rightarg = sys.oradate
);

/* oratimestamp - oratimestamptz */
CREATE FUNCTION sys.oradate_mi_oratimestampltz(sys.oratimestamp, sys.oratimestamptz)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','oradate_mi_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oradate_mi_oratimestampltz,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestamptz
);

/* oratimestamp - oratimestampltz */
CREATE FUNCTION sys.oradate_mi_oratimestampltz(sys.oratimestamp, sys.oratimestampltz)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','oradate_mi_oratimestampltz'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oradate_mi_oratimestampltz,
	leftarg = sys.oratimestamp,
	rightarg = sys.oratimestampltz
);

/* oratimestamp - interval year to month */
CREATE FUNCTION sys.oratimestamp_mi_yminterval(sys.oratimestamp, sys.yminterval)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','oratimestamp_mi_interval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestamp_mi_yminterval,
	leftarg = sys.oratimestamp,
	rightarg = sys.yminterval
);


/* oratimestamp - interval day to second */
CREATE FUNCTION sys.oratimestamp_mi_dsinterval(sys.oratimestamp, sys.dsinterval)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','oratimestamp_mi_interval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestamp_mi_dsinterval,
	leftarg = sys.oratimestamp,
	rightarg = sys.dsinterval
);


/* oratimestamp - number */
CREATE FUNCTION sys.oratimestamp_mi_number(sys.oratimestamp, sys.number)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oratimestamp_mi_number'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestamp_mi_number,
	leftarg = sys.oratimestamp,
	rightarg = sys.number
);

--
-- oratimestamp + other
--
/* oratimestamp + interval year to month */
CREATE FUNCTION sys.oratimestamp_pl_yminterval(sys.oratimestamp, sys.yminterval)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','oratimestamp_pl_interval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.oratimestamp_pl_yminterval,
	leftarg = sys.oratimestamp,
	rightarg = sys.yminterval,
	commutator = +
);

/* oratimestamp + interval day to second */
CREATE FUNCTION sys.oratimestamp_pl_dsinterval(sys.oratimestamp, sys.dsinterval)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','oratimestamp_pl_interval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.oratimestamp_pl_dsinterval,
	leftarg = sys.oratimestamp,
	rightarg = sys.dsinterval,
	commutator = +
);

/* oratimestamp + number */
CREATE FUNCTION sys.oratimestamp_pl_number(sys.oratimestamp, sys.number)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oratimestamp_pl_number'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.oratimestamp_pl_number,
	leftarg = sys.oratimestamp,
	rightarg = sys.number,
	commutator = +
);

--
-- oratimestamptz - other 
--
/* oratimestamptz - oratimestamptz */
CREATE FUNCTION sys.oratimestamp_mi(sys.oratimestamptz, sys.oratimestamptz)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','oratimestamp_mi'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestamp_mi,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestamptz
);

/* oratimestamptz - oradate */
CREATE FUNCTION sys.oratimestampltz_mi_oradate(sys.oratimestamptz, sys.oradate)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','oratimestampltz_mi_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestampltz_mi_oradate,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oradate
);

/* oratimestamptz - oratimestamp */
CREATE FUNCTION sys.oratimestampltz_mi_oradate(sys.oratimestamptz, sys.oratimestamp)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','oratimestampltz_mi_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestampltz_mi_oradate,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestamp
);

/* oratimestamptz - oratimestampltz */
CREATE FUNCTION sys.oratimestamp_mi(sys.oratimestamptz, sys.oratimestampltz)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','oratimestamp_mi'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestamp_mi,
	leftarg = sys.oratimestamptz,
	rightarg = sys.oratimestampltz
);

/* oratimestamptz - interval year to month */
CREATE FUNCTION sys.oratimestamptz_mi_yminterval(sys.oratimestamptz, sys.yminterval)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','oratimestamptz_mi_interval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestamptz_mi_yminterval,
	leftarg = sys.oratimestamptz,
	rightarg = sys.yminterval
);

/* oratimestamptz - interval day to second */
CREATE FUNCTION sys.oratimestamptz_mi_dsinterval(sys.oratimestamptz, sys.dsinterval)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','oratimestamptz_mi_interval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestamptz_mi_dsinterval,
	leftarg = sys.oratimestamptz,
	rightarg = sys.dsinterval
);

/* oratimestamptz - number */
CREATE FUNCTION sys.oratimestamptz_mi_number(sys.oratimestamptz, sys.number)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oratimestamptz_mi_number'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestamptz_mi_number,
	leftarg = sys.oratimestamptz,
	rightarg = sys.number
);

--
-- oratimestamptz + other 
--
/* oratimestamptz + interval year to month */
CREATE FUNCTION sys.oratimestamptz_pl_yminterval(sys.oratimestamptz, sys.yminterval)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','oratimestamptz_pl_interval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.oratimestamptz_pl_yminterval,
	leftarg = sys.oratimestamptz,
	rightarg = sys.yminterval,
	commutator = +
);

/* oratimestamptz + interval day to second */
CREATE FUNCTION sys.oratimestamptz_pl_dsinterval(sys.oratimestamptz, sys.dsinterval)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','oratimestamptz_pl_interval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.oratimestamptz_pl_dsinterval,
	leftarg = sys.oratimestamptz,
	rightarg = sys.dsinterval,
	commutator = +
);

/* oratimestamptz + number */
CREATE FUNCTION sys.oratimestamptz_pl_number(sys.oratimestamptz, sys.number)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oratimestamptz_pl_number'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.oratimestamptz_pl_number,
	leftarg = sys.oratimestamptz,
	rightarg = sys.number,
	commutator = +
);

--
-- oratimestampltz - other 
--
/* oratimestampltz - oratimestampltz */
CREATE FUNCTION sys.oratimestamp_mi(sys.oratimestampltz, sys.oratimestampltz)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','oratimestamp_mi'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestamp_mi,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestampltz
);

/* oratimestampltz - oradate */
CREATE FUNCTION sys.oratimestampltz_mi_oradate(sys.oratimestampltz, sys.oradate)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','oratimestampltz_mi_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestampltz_mi_oradate,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oradate
);

/* oratimestampltz - oratimestamp */
CREATE FUNCTION sys.oratimestampltz_mi_oradate(sys.oratimestampltz, sys.oratimestamp)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','oratimestampltz_mi_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestampltz_mi_oradate,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestamp
);

/* oratimestampltz - oratimestamptz */
CREATE FUNCTION sys.oratimestamp_mi(sys.oratimestampltz, sys.oratimestamptz)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','oratimestamp_mi'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestamp_mi,
	leftarg = sys.oratimestampltz,
	rightarg = sys.oratimestamptz
);

/* oratimestampltz - interval year to month */
CREATE FUNCTION sys.oratimestampltz_mi_yminterval(sys.oratimestampltz, sys.yminterval)
RETURNS sys.oratimestampltz
AS 'MODULE_PATHNAME','oratimestamptz_mi_interval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestampltz_mi_yminterval,
	leftarg = sys.oratimestampltz,
	rightarg = sys.yminterval
);

/* oratimestampltz - interval day to second */
CREATE FUNCTION sys.oratimestampltz_mi_dsinterval(sys.oratimestampltz, sys.dsinterval)
RETURNS sys.oratimestampltz
AS 'MODULE_PATHNAME','oratimestamptz_mi_interval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestampltz_mi_dsinterval,
	leftarg = sys.oratimestampltz,
	rightarg = sys.dsinterval
);

/* oratimestampltz - number */
CREATE FUNCTION sys.oratimestampltz_mi_number(sys.oratimestampltz, sys.number)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oratimestamptz_mi_number'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.oratimestampltz_mi_number,
	leftarg = sys.oratimestampltz,
	rightarg = sys.number
);

--
-- oratimestampltz + other 
--
/* oratimestampltz + interval year to month */
CREATE FUNCTION sys.oratimestampltz_pl_yminterval(sys.oratimestampltz, sys.yminterval)
RETURNS sys.oratimestampltz
AS 'MODULE_PATHNAME','oratimestamptz_pl_interval'
PARALLEL SAFE
LANGUAGE C
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.oratimestampltz_pl_yminterval,
	leftarg = sys.oratimestampltz,
	rightarg = sys.yminterval,
	commutator = +
);

/* oratimestampltz + interval day to second */
CREATE FUNCTION sys.oratimestampltz_pl_dsinterval(sys.oratimestampltz, sys.dsinterval)
RETURNS sys.oratimestampltz
AS 'MODULE_PATHNAME','oratimestamptz_pl_interval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.oratimestampltz_pl_dsinterval,
	leftarg = sys.oratimestampltz,
	rightarg = sys.dsinterval,
	commutator = +
);

/* oratimestampltz + number */
CREATE FUNCTION sys.oratimestampltz_pl_number(sys.oratimestampltz, sys.number)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','oratimestamptz_pl_number'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.oratimestampltz_pl_number,
	leftarg = sys.oratimestampltz,
	rightarg = sys.number,
	commutator = +
);

--
-- Interval + other 
--
/* interval year to month + oradate */
CREATE FUNCTION sys.yminterval_pl_oradate(sys.yminterval, sys.oradate)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','interval_pl_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.yminterval_pl_oradate,
	leftarg = sys.yminterval,
	rightarg = sys.oradate,
	commutator = +
);

/* interval day to second + oradate */
CREATE FUNCTION sys.dsinterval_pl_oradate(sys.dsinterval, sys.oradate)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','interval_pl_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.dsinterval_pl_oradate,
	leftarg = sys.dsinterval,
	rightarg = sys.oradate,
	commutator = +
);

/* interval year to month + oratimestamp */
CREATE FUNCTION sys.yminterval_pl_oratimestamp(sys.yminterval, sys.oratimestamp)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','interval_pl_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.yminterval_pl_oratimestamp,
	leftarg = sys.yminterval,
	rightarg = sys.oratimestamp,
	commutator = +
);

/* interval day to second + oratimestamp */
CREATE FUNCTION sys.dsinterval_pl_oratimestamp(sys.dsinterval, sys.oratimestamp)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','interval_pl_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.dsinterval_pl_oratimestamp,
	leftarg = sys.dsinterval,
	rightarg = sys.oratimestamp,
	commutator = +
);

/* interval year to month + oratimestamptz */
CREATE FUNCTION sys.yminterval_pl_oratimestamptz(sys.yminterval, sys.oratimestamptz)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','interval_pl_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.yminterval_pl_oratimestamptz,
	leftarg = sys.yminterval,
	rightarg = sys.oratimestamptz,
	commutator = +
);

/* interval day to second + oratimestamptz */
CREATE FUNCTION sys.dsinterval_pl_oratimestamptz(sys.dsinterval, sys.oratimestamptz)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','interval_pl_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.dsinterval_pl_oratimestamptz,
	leftarg = sys.dsinterval,
	rightarg = sys.oratimestamptz,
	commutator = +
);

/* interval year to month + oratimestampltz */
CREATE FUNCTION sys.yminterval_pl_oratimestampltz(sys.yminterval, sys.oratimestampltz)
RETURNS sys.oratimestampltz
AS 'MODULE_PATHNAME','interval_pl_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.yminterval_pl_oratimestampltz,
	leftarg = sys.yminterval,
	rightarg = sys.oratimestampltz,
	commutator = +
);

/* interval day to second + oratimestampltz */
CREATE FUNCTION sys.dsinterval_pl_oratimestampltz(sys.dsinterval, sys.oratimestampltz)
RETURNS sys.oratimestampltz
AS 'MODULE_PATHNAME','interval_pl_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.dsinterval_pl_oratimestampltz,
	leftarg = sys.dsinterval,
	rightarg = sys.oratimestampltz,
	commutator = +
);

--
-- Interval * other
--
/* interval year to month * number */
CREATE FUNCTION sys.yminterval_mul(sys.yminterval, sys.number)
RETURNS sys.yminterval
AS 'MODULE_PATHNAME','yminterval_mul'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR * (
	procedure = sys.yminterval_mul,
	leftarg = sys.yminterval,
	rightarg = sys.number,
	commutator = *
);

/* interval day to second * number */
CREATE FUNCTION sys.dsinterval_mul(sys.dsinterval, sys.number)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','dsinterval_mul'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR * (
	procedure = sys.dsinterval_mul,
	leftarg = sys.dsinterval,
	rightarg = sys.number,
	commutator = *
);

--
-- Interval / other
--
/* interval year to month / number */
CREATE FUNCTION sys.yminterval_div(sys.yminterval, sys.number)
RETURNS sys.yminterval
AS 'MODULE_PATHNAME','yminterval_div'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR / (
	procedure = sys.yminterval_div,
	leftarg = sys.yminterval,
	rightarg = sys.number
);

/* interval day to second / number */
CREATE FUNCTION sys.dsinterval_div(sys.dsinterval, sys.number)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','dsinterval_div'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR / (
	procedure = sys.dsinterval_div,
	leftarg = sys.dsinterval,
	rightarg = sys.number
);

--
-- number + other
--
/* number + oradate */
CREATE FUNCTION sys.number_pl_oradate(sys.number, sys.oradate)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','number_pl_oradate'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.number_pl_oradate,
	leftarg = sys.number,
	rightarg = sys.oradate,
	commutator = +
);

/* number + oratimestamp */
CREATE FUNCTION sys.number_pl_oratimestamp(sys.number, sys.oratimestamp)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','number_pl_oratimestamp'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.number_pl_oratimestamp,
	leftarg = sys.number,
	rightarg = sys.oratimestamp,
	commutator = +
);

/* number + oratimestamptz */
CREATE FUNCTION sys.number_pl_oratimestamptz(sys.number, sys.oratimestamptz)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','number_pl_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.number_pl_oratimestamptz,
	leftarg = sys.number,
	rightarg = sys.oratimestamptz,
	commutator = +
);

/* number + oratimestampltz */
CREATE FUNCTION sys.number_pl_oratimestampltz(sys.number, sys.oratimestampltz)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','number_pl_oratimestamptz'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.number_pl_oratimestampltz,
	leftarg = sys.number,
	rightarg = sys.oratimestampltz,
	commutator = +
);

--
-- number * other
--
/* number * interval year to month */
CREATE FUNCTION sys.mul_d_yminterval(sys.number, sys.yminterval)
RETURNS sys.yminterval
AS 'MODULE_PATHNAME','mul_d_yminterval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR * (
	procedure = sys.mul_d_yminterval,
	leftarg = sys.number,
	rightarg = sys.yminterval,
	commutator = *
);

/* number * interval day to second */
CREATE FUNCTION sys.mul_d_dsinterval(sys.number, sys.dsinterval)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','mul_d_dsinterval'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR * (
	procedure = sys.mul_d_dsinterval,
	leftarg = sys.number,
	rightarg = sys.dsinterval,
	commutator = *
);

/***************************************************************
 *
 * oracle NUMBER support
 *
 ****************************************************************/

CREATE FUNCTION sys.number_in(cstring, oid, integer)
RETURNS sys.number
AS 'numeric_in'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.number_out(sys.number)
RETURNS CSTRING
AS 'numeric_out'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.number_recv(internal, oid, integer)
RETURNS sys.number
AS 'numeric_recv'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.number_send(sys.number)
RETURNS bytea
AS 'numeric_send'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.numbertypmodin(cstring[])
RETURNS integer
AS 'numerictypmodin'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.numbertypmodout(integer)
RETURNS CSTRING
AS 'numerictypmodout'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

UPDATE pg_type
SET typinput=(SELECT oid FROM pg_proc WHERE proname='number_in')
WHERE oid = 9520;

UPDATE pg_type
SET typoutput=(SELECT oid FROM pg_proc WHERE proname='number_out')
WHERE oid = 9520;

UPDATE pg_type
SET typreceive=(SELECT oid FROM pg_proc WHERE proname='number_recv')
WHERE oid = 9520;

UPDATE pg_type
SET typsend=(SELECT oid FROM pg_proc WHERE proname='number_send')
WHERE oid = 9520;

UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='numbertypmodin')
WHERE oid = 9520;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='numbertypmodout')
WHERE oid = 9520;


UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='numbertypmodin')
WHERE oid = 9521;

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='numbertypmodout')
WHERE oid = 9521;

/* CREATE CAST */
---------- Compatible Postgresql Cast ----------
--NUMERIC & NUMBER 
CREATE CAST (sys.number AS pg_catalog.numeric)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (pg_catalog.numeric AS sys.number)
WITHOUT FUNCTION
AS IMPLICIT;

-- Converts a number type to int8 type
CREATE FUNCTION sys.number_int8(sys.number)
RETURNS int8
AS 'numeric_int8'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.number AS int8)
WITH FUNCTION sys.number_int8(sys.number)
AS ASSIGNMENT;

-- Converts a int8 type to number type
CREATE FUNCTION sys.int8_number(int8)
RETURNS sys.number
AS 'int8_numeric'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE CAST (int8 AS sys.number)
WITH FUNCTION sys.int8_number(int8)
AS IMPLICIT;

-- Converts a number type to int2 type
CREATE FUNCTION sys.number_int2(sys.number)
RETURNS int2
AS 'numeric_int2'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.number AS int2)
WITH FUNCTION sys.number_int2(sys.number)
AS ASSIGNMENT;

-- Converts a int2 type to number type
CREATE FUNCTION sys.int2_number(int2)
RETURNS sys.number
AS 'int2_numeric'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE CAST (int2 AS sys.number)
WITH FUNCTION sys.int2_number(int2)
AS IMPLICIT;

-- Converts a number type to int4 type
CREATE FUNCTION sys.number_int4(sys.number)
RETURNS int4
AS 'numeric_int4'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;
--bug#797 --bug#973 recorver assignment
CREATE CAST (sys.number AS int4)
WITH FUNCTION sys.number_int4(sys.number)
AS ASSIGNMENT;

-- Converts a int4 type to number type
CREATE FUNCTION sys.int4_number(int4)
RETURNS sys.number
AS 'int4_numeric'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE CAST (int4 AS sys.number)
WITH FUNCTION sys.int4_number(int4)
AS IMPLICIT;

-- Converts a number type to float4 type
CREATE FUNCTION sys.number_float4(sys.number)
RETURNS float4
AS 'numeric_float4'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.number AS float4)
WITH FUNCTION sys.number_float4(sys.number)
AS IMPLICIT;

-- Converts a float4 type to number type
CREATE FUNCTION sys.float4_number(float4)
RETURNS sys.number
AS 'float4_numeric'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE CAST (float4 AS sys.number)
WITH FUNCTION sys.float4_number(float4)
AS IMPLICIT;

-- Converts a number type to float8 type
CREATE FUNCTION sys.number_float8(sys.number)
RETURNS float8
AS 'numeric_float8'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.number AS float8)
WITH FUNCTION sys.number_float8(sys.number)
AS IMPLICIT;

-- Converts a float8 type to number type
CREATE FUNCTION sys.float8_number(float8)
RETURNS sys.number
AS 'float8_numeric'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE CAST (float8 AS sys.number)
WITH FUNCTION sys.float8_number(float8)
AS IMPLICIT;

-- Converts a number type to money type
CREATE FUNCTION sys.number_cash(sys.number)
RETURNS money
AS 'numeric_cash'
LANGUAGE internal
PARALLEL SAFE
STRICT
STABLE;

CREATE CAST (sys.number AS money)
WITH FUNCTION sys.number_cash(sys.number)
AS ASSIGNMENT;

-- Converts a money type to number type
CREATE FUNCTION sys.cash_number(money)
RETURNS sys.number
AS 'cash_numeric'
LANGUAGE internal
PARALLEL SAFE
STRICT
STABLE;

CREATE CAST (money AS sys.number)
WITH FUNCTION sys.cash_number(money)
AS ASSIGNMENT;

--------- Compatible Oracle Cast ---------
-- Converts a number type to the specified typmod
CREATE FUNCTION sys.number(sys.number, integer)
RETURNS sys.number
AS 'numeric'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.number AS sys.number)
WITH FUNCTION sys.number(sys.number, integer)
AS IMPLICIT;

CREATE CAST (sys.number AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.number AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.number AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.number AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

-- Converts a number type to binary_float type
CREATE FUNCTION sys.number_binary_float(sys.number)
RETURNS sys.binary_float
AS 'MODULE_PATHNAME','number_binary_float'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.number AS sys.binary_float)
WITH FUNCTION sys.number_binary_float(sys.number)
AS IMPLICIT;

-- Converts a number type to binary_double type
CREATE FUNCTION sys.number_binary_double(sys.number)
RETURNS sys.binary_double
AS 'MODULE_PATHNAME','number_binary_double'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.number AS sys.binary_double)
WITH FUNCTION sys.number_binary_double(sys.number)
AS IMPLICIT;

/* CREATE OPERATOR */
CREATE FUNCTION sys.number_eq(sys.number, sys.number)
RETURNS boolean
AS 'numeric_eq'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.number_ne(sys.number, sys.number)
RETURNS boolean
AS 'numeric_ne'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.number_lt(sys.number, sys.number)
RETURNS boolean
AS 'numeric_lt'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.number_le(sys.number, sys.number)
RETURNS boolean
AS 'numeric_le'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.number_gt(sys.number, sys.number)
RETURNS boolean
AS 'numeric_gt'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.number_ge(sys.number, sys.number)
RETURNS boolean
AS 'numeric_ge'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR = (
	procedure = sys.number_eq,
	leftarg = sys.number,
	rightarg = sys.number,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);

CREATE OPERATOR <> (
	procedure = sys.number_ne,
	leftarg = sys.number,
	rightarg = sys.number,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);

CREATE OPERATOR < (
	procedure = sys.number_lt,
	leftarg = sys.number,
	rightarg = sys.number,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR > (
	procedure = sys.number_gt,
	leftarg = sys.number,
	rightarg = sys.number,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR >= (
	procedure = sys.number_ge,
	leftarg = sys.number,
	rightarg = sys.number,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR <= (
	procedure = sys.number_le,
	leftarg = sys.number,
	rightarg = sys.number,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE FUNCTION sys.number_add(sys.number, sys.number)
RETURNS sys.number
AS 'numeric_add'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.number_add,
	leftarg = sys.number,
	rightarg = sys.number,
	commutator =  +
);

CREATE FUNCTION sys.number_sub(sys.number, sys.number)
RETURNS sys.number
AS 'numeric_sub'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.number_sub,
	leftarg = sys.number,
	rightarg = sys.number
);

CREATE FUNCTION sys.number_mul(sys.number, sys.number)
RETURNS sys.number
AS 'numeric_mul'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR * (
	procedure = sys.number_mul,
	leftarg = sys.number,
	rightarg = sys.number,
	commutator = *
);

CREATE FUNCTION sys.number_div(sys.number, sys.number)
RETURNS sys.number
AS 'numeric_div'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR / (
	procedure = sys.number_div,
	leftarg = sys.number,
	rightarg = sys.number
);

CREATE FUNCTION sys.number_mod(sys.number, sys.number)
RETURNS sys.number
AS 'numeric_mod'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR % (
	procedure = sys.number_mod,
	leftarg = sys.number,
	rightarg = sys.number
);

CREATE FUNCTION sys.number_power(sys.number, sys.number)
RETURNS sys.number
AS 'numeric_power'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR ^ (
	procedure = sys.number_power,
	leftarg = sys.number,
	rightarg = sys.number
);

CREATE FUNCTION sys.number_abs(sys.number)
RETURNS sys.number
AS 'numeric_abs'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR @ (
	procedure = sys.number_abs,
	rightarg = sys.number
);

CREATE FUNCTION sys.number_uplus(sys.number)
RETURNS sys.number
AS 'numeric_uplus'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.number_uplus,
	rightarg = sys.number
);

-- uminus
CREATE FUNCTION sys.number_uminus(sys.number)
RETURNS sys.number
AS 'numeric_uminus'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.number_uminus,
	rightarg = sys.number
);

--
-- B-tree index support
--
CREATE FUNCTION sys.number_cmp(sys.number, sys.number)
RETURNS integer
AS 'numeric_cmp'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.number_sortsupport(internal)
RETURNS void
AS 'numeric_sortsupport'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.number_in_range(sys.number, sys.number, sys.number, bool, bool)
RETURNS boolean
AS 'in_range_numeric_numeric'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

/* CREATE OPERATOR CLASS for 'NUMBER' */
CREATE OPERATOR CLASS sys.number_ops
    DEFAULT FOR TYPE sys.number USING btree AS
        OPERATOR        1       < (sys.number, sys.number),
        OPERATOR        2       <= (sys.number, sys.number),
        OPERATOR        3       = (sys.number, sys.number),
        OPERATOR        4       >= (sys.number, sys.number),
        OPERATOR        5       > (sys.number, sys.number),
        FUNCTION        1       sys.number_cmp(sys.number, sys.number),
		FUNCTION		2		sys.number_sortsupport(internal),
		FUNCTION        3       sys.number_in_range(sys.number, sys.number, sys.number, bool, bool);

--
-- HASH index support
--		
CREATE FUNCTION sys.hash_number(sys.number)
RETURNS INTEGER
AS 'hash_numeric'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.hash_number_extended(sys.number, int8)
RETURNS int8
AS 'hash_numeric_extended'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR CLASS sys.number_ops
    DEFAULT FOR TYPE sys.number USING hash AS
		OPERATOR        1       = (sys.number, sys.number),
        FUNCTION        1       sys.hash_number(sys.number),
        FUNCTION        2       sys.hash_number_extended(sys.number, int8);

--
-- BRIN index support
--			
CREATE OPERATOR CLASS sys.number_minmax_ops
    DEFAULT FOR TYPE sys.number USING brin AS
        OPERATOR        1       < (sys.number, sys.number),
        OPERATOR        2       <= (sys.number, sys.number),
        OPERATOR        3       = (sys.number, sys.number),
        OPERATOR        4       >= (sys.number, sys.number),
        OPERATOR        5       > (sys.number, sys.number),
        FUNCTION        1       sys.brin_minmax_opcinfo(internal),
		FUNCTION        2       sys.brin_minmax_add_value(internal, internal, internal, internal),
		FUNCTION        3       sys.brin_minmax_consistent(internal, internal, internal),
		FUNCTION        4       sys.brin_minmax_union(internal, internal, internal);

--
-- CREATE AGGREGATE 
--
/* max */
CREATE FUNCTION sys.number_larger(sys.number, sys.number)
RETURNS sys.number
AS 'numeric_larger'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE AGGREGATE sys.max(sys.number) (
  SFUNC=sys.number_larger,
  STYPE= sys.number,
  SORTOP= >
);

/* min */
CREATE FUNCTION sys.number_smaller(sys.number, sys.number)
RETURNS sys.number
AS 'numeric_smaller'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE AGGREGATE sys.min(sys.number) (
  SFUNC=sys.number_smaller,
  STYPE= sys.number,
  SORTOP= <
);		

/* AVG */
CREATE FUNCTION sys.number_avg_accum(internal, sys.number)
RETURNS internal
AS 'numeric_avg_accum'
LANGUAGE internal
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.number_avg(internal)
RETURNS sys.number
AS 'numeric_avg'
LANGUAGE internal
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.number_accum_inv(internal, sys.number)
RETURNS internal
AS 'numeric_accum_inv'
LANGUAGE internal
PARALLEL SAFE
IMMUTABLE;

CREATE AGGREGATE sys.avg(sys.number) (
  SFUNC = sys.number_avg_accum,
  FINALFUNC = number_avg,
  MSFUNC = number_avg_accum,
  MINVFUNC = number_accum_inv,
  MFINALFUNC = number_avg,
  STYPE = internal,
  SSPACE = 128,
  MSTYPE = internal,
  MSSPACE =128
);	

/* sum */
CREATE FUNCTION sys.number_sum(internal)
RETURNS sys.number
AS 'numeric_sum'
LANGUAGE internal
PARALLEL SAFE
IMMUTABLE;

CREATE AGGREGATE sys.sum(sys.number) (
  SFUNC = sys.number_avg_accum,
  FINALFUNC = number_sum,
  MSFUNC = number_avg_accum,
  MINVFUNC = number_accum_inv,
  MFINALFUNC = number_sum,
  STYPE = internal,
  SSPACE = 128,
  MSTYPE = internal,
  MSSPACE =128
);

/* var_pop */
CREATE FUNCTION sys.number_accum(internal, sys.number)
RETURNS internal
AS 'numeric_accum'
LANGUAGE internal
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.number_var_pop(internal)
RETURNS sys.number
AS 'numeric_var_pop'
LANGUAGE internal
PARALLEL SAFE
IMMUTABLE;

CREATE AGGREGATE sys.var_pop(sys.number) (
  SFUNC = sys.number_accum,
  FINALFUNC = number_var_pop,
  MSFUNC = number_accum,
  MINVFUNC = number_accum_inv,
  MFINALFUNC = number_var_pop,
  STYPE = internal,
  SSPACE = 128,
  MSTYPE = internal,
  MSSPACE =128
);

/* var_samp */
CREATE FUNCTION sys.number_var_samp(internal)
RETURNS sys.number
AS 'numeric_var_samp'
LANGUAGE internal
PARALLEL SAFE
IMMUTABLE;

CREATE AGGREGATE sys.var_samp(sys.number) (
  SFUNC = sys.number_accum,
  FINALFUNC = number_var_samp,
  MSFUNC = number_accum,
  MINVFUNC = number_accum_inv,
  MFINALFUNC = number_var_samp,
  STYPE = internal,
  SSPACE = 128,
  MSTYPE = internal,
  MSSPACE =128
);

/* variance: historical Postgres syntax for var_samp */
CREATE AGGREGATE sys.variance(sys.number) (
  SFUNC = sys.number_accum,
  FINALFUNC = number_var_samp,
  MSFUNC = number_accum,
  MINVFUNC = number_accum_inv,
  MFINALFUNC = number_var_samp,
  STYPE = internal,
  SSPACE = 128,
  MSTYPE = internal,
  MSSPACE =128
);

/* stddev_pop */
CREATE FUNCTION sys.number_stddev_pop(internal)
RETURNS sys.number
AS 'numeric_stddev_pop'
LANGUAGE internal
PARALLEL SAFE
IMMUTABLE;

CREATE AGGREGATE sys.stddev_pop(sys.number) (
  SFUNC = sys.number_accum,
  FINALFUNC = number_stddev_pop,
  MSFUNC = number_accum,
  MINVFUNC = number_accum_inv,
  MFINALFUNC = number_stddev_pop,
  STYPE = internal,
  SSPACE = 128,
  MSTYPE = internal,
  MSSPACE =128
);

/* stddev_samp */
CREATE FUNCTION sys.number_stddev_samp(internal)
RETURNS sys.number
AS 'numeric_stddev_samp'
LANGUAGE internal
PARALLEL SAFE
IMMUTABLE;

CREATE AGGREGATE sys.stddev_samp(sys.number) (
  SFUNC = sys.number_accum,
  FINALFUNC = number_stddev_samp,
  MSFUNC = number_accum,
  MINVFUNC = number_accum_inv,
  MFINALFUNC = number_stddev_samp,
  STYPE = internal,
  SSPACE = 128,
  MSTYPE = internal,
  MSSPACE =128
);

/* stddev: historical Postgres syntax for stddev_samp */
CREATE AGGREGATE sys.stddev(sys.number) (
  SFUNC = sys.number_accum,
  FINALFUNC = number_stddev_samp,
  MSFUNC = number_accum,
  MINVFUNC = number_accum_inv,
  MFINALFUNC = number_stddev_samp,
  STYPE = internal,
  SSPACE = 128,
  MSTYPE = internal,
  MSSPACE =128
);


/***************************************************************
 *
 * Oracle BINARY_FLOAT data type  
 *
 ****************************************************************/
CREATE FUNCTION sys.binary_float_in(cstring)
RETURNS sys.binary_float
AS 'MODULE_PATHNAME','binary_float_in'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.binary_float_out(sys.binary_float)
RETURNS CSTRING
AS 'MODULE_PATHNAME','binary_float_out'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.binary_float_recv(internal)
RETURNS sys.binary_float
AS 'MODULE_PATHNAME','binary_float_recv'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.binary_float_send(sys.binary_float)
RETURNS bytea
AS 'MODULE_PATHNAME','binary_float_send'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

UPDATE pg_type
SET typinput=(SELECT oid FROM pg_proc WHERE proname='binary_float_in')
WHERE oid = 9522;

UPDATE pg_type
SET typoutput=(SELECT oid FROM pg_proc WHERE proname='binary_float_out')
WHERE oid = 9522;

UPDATE pg_type
SET typreceive=(SELECT oid FROM pg_proc WHERE proname='binary_float_recv')
WHERE oid = 9522;

UPDATE pg_type
SET typsend=(SELECT oid FROM pg_proc WHERE proname='binary_float_send')
WHERE oid = 9522;

/* CREATE CAST */
--------- Compatible Postgresql Cast ---------
-- Converts a binary_float type to real type
CREATE CAST (sys.binary_float AS real)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (real AS sys.binary_float)
WITHOUT FUNCTION
AS IMPLICIT;

-- Converts a binary_float type to int8 type
CREATE FUNCTION sys.binary_float_int8(sys.binary_float)
RETURNS int8
AS 'ftoi8'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.binary_float AS int8)
WITH FUNCTION sys.binary_float_int8(sys.binary_float)
AS ASSIGNMENT;

-- Converts a int8 type to binary_float type
CREATE FUNCTION sys.int8_binary_float(int8)
RETURNS sys.binary_float
AS 'i8tof'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (int8 AS sys.binary_float)
WITH FUNCTION sys.int8_binary_float(int8)
AS IMPLICIT;

-- Converts a binary_float type to int2 type
CREATE FUNCTION sys.binary_float_int2(sys.binary_float)
RETURNS int2
AS 'ftoi2'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.binary_float AS int2)
WITH FUNCTION sys.binary_float_int2(sys.binary_float)
AS ASSIGNMENT;

-- Converts a int2 type to binary_float type
CREATE FUNCTION sys.int2_binary_float(int2)
RETURNS sys.binary_float
AS 'i2tof'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (int2 AS sys.binary_float)
WITH FUNCTION sys.int2_binary_float(int2)
AS IMPLICIT;

-- Converts a binary_float type to int4 type
CREATE FUNCTION sys.binary_float_int4(sys.binary_float)
RETURNS int4
AS 'ftoi4'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.binary_float AS int4)
WITH FUNCTION sys.binary_float_int4(sys.binary_float)
AS ASSIGNMENT;

-- Converts a int4 type to binary_float type
CREATE FUNCTION sys.int4_binary_float(int4)
RETURNS sys.binary_float
AS 'i4tof'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (int4 AS sys.binary_float)
WITH FUNCTION sys.int4_binary_float(int4)
AS IMPLICIT;

-- Converts a binary_float type to double precision type
CREATE FUNCTION sys.binary_float_float8(sys.binary_float)
RETURNS float8
AS 'ftod'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.binary_float AS float8)
WITH FUNCTION sys.binary_float_float8(sys.binary_float)
AS IMPLICIT;

-- Converts a float8 type to binary_float type
CREATE FUNCTION sys.float8_binary_float(float8)
RETURNS sys.binary_float
AS 'dtof'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (float8 AS sys.binary_float)
WITH FUNCTION sys.float8_binary_float(float8)
AS ASSIGNMENT;

-- Converts a binary_float type to numeric type
CREATE FUNCTION sys.binary_float_numeric(sys.binary_float)
RETURNS numeric
AS 'float4_numeric'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE CAST (sys.binary_float AS numeric)
WITH FUNCTION sys.binary_float_numeric(sys.binary_float)
AS ASSIGNMENT;

-- Converts a numeric type to binary_float type
CREATE FUNCTION sys.numeric_binary_float(numeric)
RETURNS sys.binary_float
AS 'MODULE_PATHNAME','number_binary_float'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (numeric AS sys.binary_float)
WITH FUNCTION sys.numeric_binary_float(numeric)
AS IMPLICIT;

--------- Compatible Oracle Cast ---------
CREATE CAST (sys.binary_float AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.binary_float AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.binary_float AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.binary_float AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

-- Converts a binary_float type to number type
CREATE FUNCTION sys.binary_float_number(sys.binary_float)
RETURNS sys.number
AS 'float4_numeric'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE CAST (sys.binary_float AS sys.number)
WITH FUNCTION sys.binary_float_number(sys.binary_float)
AS IMPLICIT;

-- Converts a binary_float type to binary_double type
CREATE FUNCTION sys.binary_float_binary_double(sys.binary_float)
RETURNS sys.binary_double
AS 'ftod'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE CAST (sys.binary_float AS sys.binary_double)
WITH FUNCTION sys.binary_float_binary_double(sys.binary_float)
AS IMPLICIT;

/* CREATE OPERATOR */
CREATE FUNCTION sys.binary_float_eq(sys.binary_float, sys.binary_float)
RETURNS boolean
AS 'float4eq'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_float_ne(sys.binary_float, sys.binary_float)
RETURNS boolean
AS 'float4ne'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_float_lt(sys.binary_float, sys.binary_float)
RETURNS boolean
AS 'float4lt'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_float_le(sys.binary_float, sys.binary_float)
RETURNS boolean
AS 'float4le'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_float_gt(sys.binary_float, sys.binary_float)
RETURNS boolean
AS 'float4gt'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_float_ge(sys.binary_float, sys.binary_float)
RETURNS boolean
AS 'float4ge'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE OPERATOR = (
	procedure = sys.binary_float_eq,
	leftarg = sys.binary_float,
	rightarg = sys.binary_float,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);

CREATE OPERATOR <> (
	procedure = sys.binary_float_ne,
	leftarg = sys.binary_float,
	rightarg = sys.binary_float,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.binary_float_lt,
	leftarg = sys.binary_float,
	rightarg = sys.binary_float,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.binary_float_gt,
	leftarg = sys.binary_float,
	rightarg = sys.binary_float,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.binary_float_ge,
	leftarg = sys.binary_float,
	rightarg = sys.binary_float,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.binary_float_le,
	leftarg = sys.binary_float,
	rightarg = sys.binary_float,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE FUNCTION sys.binary_float_pl(sys.binary_float, sys.binary_float)
RETURNS sys.binary_float
AS 'float4pl'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.binary_float_pl,
	leftarg = sys.binary_float,
	rightarg = sys.binary_float,
	commutator = +
);

CREATE FUNCTION sys.binary_float_mi(sys.binary_float, sys.binary_float)
RETURNS sys.binary_float
AS 'float4mi'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.binary_float_mi,
	leftarg = sys.binary_float,
	rightarg = sys.binary_float
);

CREATE FUNCTION sys.binary_float_mul(sys.binary_float, sys.binary_float)
RETURNS sys.binary_float
AS 'float4mul'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR * (
	procedure = sys.binary_float_mul,
	leftarg = sys.binary_float,
	rightarg = sys.binary_float,
	commutator = *
);

CREATE FUNCTION sys.binary_float_div(sys.binary_float, sys.binary_float)
RETURNS sys.binary_float
AS 'float4div'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR / (
	procedure = sys.binary_float_div,
	leftarg = sys.binary_float,
	rightarg = sys.binary_float
);

/***************************************************************
 *
 * Oracle BINARY_DOUBLE data type  
 *
 ****************************************************************/
CREATE FUNCTION sys.binary_double_in(cstring)
RETURNS sys.binary_double
AS 'MODULE_PATHNAME','binary_double_in'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.binary_double_out(sys.binary_double)
RETURNS CSTRING
AS 'MODULE_PATHNAME','binary_double_out'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.binary_double_recv(internal)
RETURNS sys.binary_double
AS 'MODULE_PATHNAME','binary_double_recv'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.binary_double_send(sys.binary_double)
RETURNS bytea
AS 'MODULE_PATHNAME','binary_double_send'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

UPDATE pg_type
SET typinput=(SELECT oid FROM pg_proc WHERE proname='binary_double_in')
WHERE oid = 9524;

UPDATE pg_type
SET typoutput=(SELECT oid FROM pg_proc WHERE proname='binary_double_out')
WHERE oid = 9524;

UPDATE pg_type
SET typreceive=(SELECT oid FROM pg_proc WHERE proname='binary_double_recv')
WHERE oid = 9524;

UPDATE pg_type
SET typsend=(SELECT oid FROM pg_proc WHERE proname='binary_double_send')
WHERE oid = 9524;

/* CREATE CAST */
--------- Compatible Postgresql Cast ---------
-- Converts a binary_double type to double precision type
CREATE CAST (sys.binary_double AS double precision)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (double precision AS sys.binary_double)
WITHOUT FUNCTION
AS IMPLICIT;

-- Converts a binary_double type to int8 type
CREATE FUNCTION sys.binary_double_int8(sys.binary_double)
RETURNS int8
AS 'dtoi8'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.binary_double AS int8)
WITH FUNCTION sys.binary_double_int8(sys.binary_double)
AS ASSIGNMENT;

-- Converts a int8 type to binary_double type
CREATE FUNCTION sys.int8_binary_double(int8)
RETURNS sys.binary_double
AS 'i8tod'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE CAST (int8 AS sys.binary_double)
WITH FUNCTION sys.int8_binary_double(int8)
AS IMPLICIT;

-- Converts a binary_double type to int2 type
CREATE FUNCTION sys.binary_double_int2(sys.binary_double)
RETURNS int2
AS 'dtoi2'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.binary_double AS int2)
WITH FUNCTION sys.binary_double_int2(sys.binary_double)
AS ASSIGNMENT;

-- Converts a int2 type to binary_double type
CREATE FUNCTION sys.int2_binary_double(int2)
RETURNS sys.binary_double
AS 'i2tod'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE CAST (int2 AS sys.binary_double)
WITH FUNCTION sys.int2_binary_double(int2)
AS IMPLICIT;

-- Converts a binary_double type to int4 type
CREATE FUNCTION sys.binary_double_int4(sys.binary_double)
RETURNS int4
AS 'dtoi4'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.binary_double AS int4)
WITH FUNCTION sys.binary_double_int4(sys.binary_double)
AS ASSIGNMENT;

-- Converts a int4 type to binary_double type
CREATE FUNCTION sys.int4_binary_double(int4)
RETURNS sys.binary_double
AS 'i4tod'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE CAST (int4 AS sys.binary_double)
WITH FUNCTION sys.int4_binary_double(int4)
AS IMPLICIT;

-- Converts a binary_double type to real type
CREATE FUNCTION sys.binary_double_to_real(sys.binary_double)
RETURNS float4
AS 'dtof'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.binary_double AS real)
WITH FUNCTION sys.binary_double_to_real(sys.binary_double)
AS ASSIGNMENT;

-- Converts a real type to binary_double type
CREATE FUNCTION sys.real_to_binary_double(float4)
RETURNS sys.binary_double
AS 'ftod'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE CAST (real AS sys.binary_double)
WITH FUNCTION sys.real_to_binary_double(float4)
AS IMPLICIT;

-- Converts a binary_double type to numeric type
CREATE FUNCTION sys.binary_double_numeric(sys.binary_double)
RETURNS numeric
AS 'float8_numeric'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.binary_double AS numeric)
WITH FUNCTION sys.binary_double_numeric(sys.binary_double)
AS ASSIGNMENT;

-- Converts a numeric type to binary_double type
CREATE FUNCTION sys.numeric_binary_double(numeric)
RETURNS sys.binary_double
AS 'MODULE_PATHNAME','number_binary_double'
LANGUAGE C
STRICT
IMMUTABLE
LEAKPROOF;

CREATE CAST (numeric AS sys.binary_double)
WITH FUNCTION sys.numeric_binary_double(numeric)
AS IMPLICIT;

--------- Compatible Oracle Cast ---------
CREATE CAST (sys.binary_double AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.binary_double AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.binary_double AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.binary_double AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

-- Converts a binary_double type to number type
CREATE FUNCTION sys.binary_double_number(sys.binary_double)
RETURNS sys.number
AS 'float8_numeric'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.binary_double AS sys.number)
WITH FUNCTION sys.binary_double_number(sys.binary_double)
AS IMPLICIT;

-- Converts a binary_double type to binary_float type
CREATE FUNCTION sys.binary_double_to_binary_float(sys.binary_double)
RETURNS sys.binary_float
AS 'dtof'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (sys.binary_double AS sys.binary_float)
WITH FUNCTION sys.binary_double_to_binary_float(sys.binary_double)
AS IMPLICIT;

/* CREATE OPERATOR */
CREATE FUNCTION sys.binary_double_eq(sys.binary_double, sys.binary_double)
RETURNS boolean
AS 'float8eq'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_double_ne(sys.binary_double, sys.binary_double)
RETURNS boolean
AS 'float8ne'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_double_lt(sys.binary_double, sys.binary_double)
RETURNS boolean
AS 'float8lt'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_double_le(sys.binary_double, sys.binary_double)
RETURNS boolean
AS 'float8le'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_double_gt(sys.binary_double, sys.binary_double)
RETURNS boolean
AS 'float8gt'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_double_ge(sys.binary_double, sys.binary_double)
RETURNS boolean
AS 'float8ge'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE OPERATOR = (
	procedure = sys.binary_double_eq,
	leftarg = sys.binary_double,
	rightarg = sys.binary_double,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);

CREATE OPERATOR <> (
	procedure = sys.binary_double_ne,
	leftarg = sys.binary_double,
	rightarg = sys.binary_double,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);

CREATE OPERATOR < (
	procedure = sys.binary_double_lt,
	leftarg = sys.binary_double,
	rightarg = sys.binary_double,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE OPERATOR > (
	procedure = sys.binary_double_gt,
	leftarg = sys.binary_double,
	rightarg = sys.binary_double,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR >= (
	procedure = sys.binary_double_ge,
	leftarg = sys.binary_double,
	rightarg = sys.binary_double,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);

CREATE OPERATOR <= (
	procedure = sys.binary_double_le,
	leftarg = sys.binary_double,
	rightarg = sys.binary_double,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE FUNCTION sys.binary_double_pl(sys.binary_double, sys.binary_double)
RETURNS sys.binary_double
AS 'float8pl'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.binary_double_pl,
	leftarg = sys.binary_double,
	rightarg = sys.binary_double,
	commutator = +
);

CREATE FUNCTION sys.binary_double_mi(sys.binary_double, sys.binary_double)
RETURNS sys.binary_double
AS 'float8mi'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.binary_double_mi,
	leftarg = sys.binary_double,
	rightarg = sys.binary_double
);

CREATE FUNCTION sys.binary_double_mul(sys.binary_double, sys.binary_double)
RETURNS sys.binary_double
AS 'float8mul'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR * (
	procedure = sys.binary_double_mul,
	leftarg = sys.binary_double,
	rightarg = sys.binary_double,
	commutator = *
);

CREATE FUNCTION sys.binary_double_div(sys.binary_double, sys.binary_double)
RETURNS sys.binary_double
AS 'float8div'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR / (
	procedure = sys.binary_double_div,
	leftarg = sys.binary_double,
	rightarg = sys.binary_double
);

CREATE FUNCTION sys.binary_double_pow(sys.binary_double, sys.binary_double)
RETURNS sys.binary_double
AS 'dpow'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR ^ (
	procedure = sys.binary_double_pow,
	leftarg = sys.binary_double,
	rightarg = sys.binary_double
);

-- CREATE OPERATOR for (BINARY_FLOAT, BINARY_DOUBLE)
CREATE FUNCTION sys.binary_float_eq_binary_double(sys.binary_float, sys.binary_double)
RETURNS boolean
AS 'float48eq'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_float_ne_binary_double(sys.binary_float, sys.binary_double)
RETURNS boolean
AS 'float48ne'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_float_lt_binary_double(sys.binary_float, sys.binary_double)
RETURNS boolean
AS 'float48lt'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_float_le_binary_double(sys.binary_float, sys.binary_double)
RETURNS boolean
AS 'float48le'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_float_gt_binary_double(sys.binary_float, sys.binary_double)
RETURNS boolean
AS 'float48gt'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_float_ge_binary_double(sys.binary_float, sys.binary_double)
RETURNS boolean
AS 'float48ge'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE OPERATOR = (
	procedure = sys.binary_float_eq_binary_double,
	leftarg = sys.binary_float,
	rightarg = sys.binary_double,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);

CREATE OPERATOR <> (
	procedure = sys.binary_float_ne_binary_double,
	leftarg = sys.binary_float,
	rightarg = sys.binary_double,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.binary_float_lt_binary_double,
	leftarg = sys.binary_float,
	rightarg = sys.binary_double,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.binary_float_gt_binary_double,
	leftarg = sys.binary_float,
	rightarg = sys.binary_double,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.binary_float_ge_binary_double,
	leftarg = sys.binary_float,
	rightarg = sys.binary_double,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.binary_float_le_binary_double,
	leftarg = sys.binary_float,
	rightarg = sys.binary_double,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE FUNCTION sys.binary_float_pl_binary_double(sys.binary_float, sys.binary_double)
RETURNS sys.binary_double
AS 'float48pl'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.binary_float_pl_binary_double,
	leftarg = sys.binary_float,
	rightarg = sys.binary_double,
	commutator = +
);

CREATE FUNCTION sys.binary_float_mi_binary_double(sys.binary_float, sys.binary_double)
RETURNS sys.binary_double
AS 'float48mi'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.binary_float_mi_binary_double,
	leftarg = sys.binary_float,
	rightarg = sys.binary_double
);

CREATE FUNCTION sys.binary_float_mul_binary_double(sys.binary_float, sys.binary_double)
RETURNS sys.binary_double
AS 'float48mul'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR * (
	procedure = sys.binary_float_mul_binary_double,
	leftarg = sys.binary_float,
	rightarg = sys.binary_double,
	commutator = *
);

CREATE FUNCTION sys.binary_float_div_binary_double(sys.binary_float, sys.binary_double)
RETURNS sys.binary_double
AS 'float48div'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR / (
	procedure = sys.binary_float_div_binary_double,
	leftarg = sys.binary_float,
	rightarg = sys.binary_double
);


-- CREATE OPERATOR for (BINARY_DOUBLE, BINARY_FLOAT)
CREATE FUNCTION sys.binary_double_eq_binary_float(sys.binary_double, sys.binary_float)
RETURNS boolean
AS 'float84eq'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_double_ne_binary_float(sys.binary_double, sys.binary_float)
RETURNS boolean
AS 'float84ne'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_double_lt_binary_float(sys.binary_double, sys.binary_float)
RETURNS boolean
AS 'float84lt'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_double_le_binary_float(sys.binary_double, sys.binary_float)
RETURNS boolean
AS 'float84le'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_double_gt_binary_float(sys.binary_double, sys.binary_float)
RETURNS boolean
AS 'float84gt'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.binary_double_ge_binary_float(sys.binary_double, sys.binary_float)
RETURNS boolean
AS 'float84ge'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE OPERATOR = (
	procedure = sys.binary_double_eq_binary_float,
	leftarg = sys.binary_double,
	rightarg = sys.binary_float,
	commutator = =,
	negator = <>,
	restrict = eqsel,
	join = eqjoinsel,
	hashes,
	merges
);

CREATE OPERATOR <> (
	procedure = sys.binary_double_ne_binary_float,
	leftarg = sys.binary_double,
	rightarg = sys.binary_float,
	commutator = <>,
	negator = =,
	restrict = neqsel,
	join = neqjoinsel
);
CREATE OPERATOR < (
	procedure = sys.binary_double_lt_binary_float,
	leftarg = sys.binary_double,
	rightarg = sys.binary_float,
	commutator = >,
	negator = >=,
	restrict = scalarltsel,
	join = scalarltjoinsel
);
CREATE OPERATOR > (
	procedure = sys.binary_double_gt_binary_float,
	leftarg = sys.binary_double,
	rightarg = sys.binary_float,
	commutator = <,
	negator = <=,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR >= (
	procedure = sys.binary_double_ge_binary_float,
	leftarg = sys.binary_double,
	rightarg = sys.binary_float,
	commutator = <=,
	negator = <,
	restrict = scalargtsel,
	join = scalargtjoinsel
);
CREATE OPERATOR <= (
	procedure = sys.binary_double_le_binary_float,
	leftarg = sys.binary_double,
	rightarg = sys.binary_float,
	commutator = >=,
	negator = >,
	restrict = scalarltsel,
	join = scalarltjoinsel
);

CREATE FUNCTION sys.binary_double_pl_binary_float(sys.binary_double, sys.binary_float)
RETURNS sys.binary_double
AS 'float84pl'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR + (
	procedure = sys.binary_double_pl_binary_float,
	leftarg = sys.binary_double,
	rightarg = sys.binary_float,
	commutator = +
);

CREATE FUNCTION sys.binary_double_mi_binary_float(sys.binary_double, sys.binary_float)
RETURNS sys.binary_double
AS 'float84mi'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR - (
	procedure = sys.binary_double_mi_binary_float,
	leftarg = sys.binary_double,
	rightarg = sys.binary_float
);

CREATE FUNCTION sys.binary_double_mul_binary_float(sys.binary_double, sys.binary_float)
RETURNS sys.binary_double
AS 'float84mul'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR * (
	procedure = sys.binary_double_mul_binary_float,
	leftarg = sys.binary_double,
	rightarg = sys.binary_float,
	commutator = *
);

CREATE FUNCTION sys.binary_double_div_binary_float(sys.binary_double, sys.binary_float)
RETURNS sys.binary_double
AS 'float84div'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OPERATOR / (
	procedure = sys.binary_double_div_binary_float,
	leftarg = sys.binary_double,
	rightarg = sys.binary_float
);

--
-- B-tree index support
--
-- The support procedure for b-tree index of binary_float 
CREATE FUNCTION sys.bt_binary_float_cmp(sys.binary_float, sys.binary_float)
RETURNS int4
AS 'btfloat4cmp'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.bt_binary_float_sortsupport(internal)
RETURNS void
AS 'btfloat4sortsupport'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

-- The support procedure for b-tree index of binary_double 
CREATE FUNCTION sys.bt_binary_double_cmp(sys.binary_double, sys.binary_double)
RETURNS int4
AS 'btfloat8cmp'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.bt_binary_double_sortsupport(internal)
RETURNS void
AS 'btfloat8sortsupport'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

-- Cross data type comparison function 
CREATE FUNCTION sys.bt_binary_float_double_cmp(sys.binary_float, sys.binary_double)
RETURNS int4
AS 'btfloat48cmp'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;

CREATE FUNCTION sys.bt_binary_double_float_cmp(sys.binary_double, sys.binary_float)
RETURNS int4
AS 'btfloat84cmp'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE
LEAKPROOF;


/* CREATE OPERATOR FAMILY */
CREATE OPERATOR FAMILY sys.binary_ops USING btree;

/* CREATE OPERATOR CLASS for 'binary_float' */
CREATE OPERATOR CLASS sys.binary_float_ops
    DEFAULT FOR TYPE sys.binary_float USING btree FAMILY sys.binary_ops AS
        OPERATOR        1       < (sys.binary_float, sys.binary_float),
        OPERATOR        2       <= (sys.binary_float, sys.binary_float),
        OPERATOR        3       = (sys.binary_float, sys.binary_float),
        OPERATOR        4       >= (sys.binary_float, sys.binary_float),
        OPERATOR        5       > (sys.binary_float, sys.binary_float),
        FUNCTION        1       sys.bt_binary_float_cmp(sys.binary_float, sys.binary_float),
		FUNCTION        2       sys.bt_binary_float_sortsupport(internal);
		
/* CREATE OPERATOR CLASS for 'binary_double' */
CREATE OPERATOR CLASS sys.binary_double_ops
    DEFAULT FOR TYPE sys.binary_double USING btree FAMILY sys.binary_ops AS
        OPERATOR        1       < (sys.binary_double, sys.binary_double),
        OPERATOR        2       <= (sys.binary_double, sys.binary_double),
        OPERATOR        3       = (sys.binary_double, sys.binary_double),
        OPERATOR        4       >= (sys.binary_double, sys.binary_double),
        OPERATOR        5       > (sys.binary_double, sys.binary_double),
        FUNCTION        1       sys.bt_binary_double_cmp(sys.binary_double, sys.binary_double),
		FUNCTION        2       sys.bt_binary_double_sortsupport(internal);		

ALTER OPERATOR FAMILY sys.binary_ops USING btree ADD
	-- Cross data type comparison
	OPERATOR        1       < (sys.binary_float, sys.binary_double),
	OPERATOR        2       <= (sys.binary_float, sys.binary_double),
	OPERATOR        3       = (sys.binary_float, sys.binary_double),
	OPERATOR        4       >= (sys.binary_float, sys.binary_double),
	OPERATOR        5       > (sys.binary_float, sys.binary_double),
	FUNCTION        1       sys.bt_binary_float_double_cmp(sys.binary_float, sys.binary_double),
	
	-- Cross data type comparison
	OPERATOR        1       < (sys.binary_double, sys.binary_float),
	OPERATOR        2       <= (sys.binary_double, sys.binary_float),
	OPERATOR        3       = (sys.binary_double, sys.binary_float),
	OPERATOR        4       >= (sys.binary_double, sys.binary_float),
	OPERATOR        5       > (sys.binary_double, sys.binary_float),
	FUNCTION        1       sys.bt_binary_double_float_cmp(sys.binary_double, sys.binary_float);

--
-- Hash index support
--
CREATE FUNCTION sys.hash_binary_float(sys.binary_float)
RETURNS int4
AS 'hashfloat4'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.hash_binary_float_extended(sys.binary_float, int8)
RETURNS int8
AS 'hashfloat4extended'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.hash_binary_double(sys.binary_double)
RETURNS int4
AS 'hashfloat8'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.hash_binary_double_extended(sys.binary_double, int8)
RETURNS int8
AS 'hashfloat8extended'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

/* CREATE OPERATOR FAMILY */
CREATE OPERATOR FAMILY sys.binary_ops USING hash;

/* CREATE OPERATOR CLASS for 'binary_float' */
CREATE OPERATOR CLASS sys.binary_float_ops
    DEFAULT FOR TYPE sys.binary_float USING hash FAMILY sys.binary_ops AS
		OPERATOR        1       = (sys.binary_float, sys.binary_float),
        FUNCTION        1       sys.hash_binary_float(sys.binary_float),
        FUNCTION        2       sys.hash_binary_float_extended(sys.binary_float, int8);

/* CREATE OPERATOR CLASS for 'binary_double' */
CREATE OPERATOR CLASS sys.binary_double_ops
    DEFAULT FOR TYPE sys.binary_double USING hash FAMILY sys.binary_ops AS
		OPERATOR        1       = (sys.binary_double, sys.binary_double),
        FUNCTION        1       sys.hash_binary_double(sys.binary_double),
        FUNCTION        2       sys.hash_binary_double_extended(sys.binary_double, int8);

ALTER OPERATOR FAMILY sys.binary_ops USING hash ADD
	-- Cross data type comparison
	OPERATOR        1       = (sys.binary_float, sys.binary_double),
	OPERATOR        1       = (sys.binary_double, sys.binary_float);

--
-- brin index support
--
/* CREATE OPERATOR FAMILY */
CREATE OPERATOR FAMILY sys.binary_minmax_ops USING brin;

/* CREATE OPERATOR CLASS for 'binary_float' */
CREATE OPERATOR CLASS sys.binary_float_minmax_ops
    DEFAULT FOR TYPE sys.binary_float USING brin FAMILY sys.binary_minmax_ops AS
        OPERATOR        1       < (sys.binary_float, sys.binary_float),
        OPERATOR        2       <= (sys.binary_float, sys.binary_float),
        OPERATOR        3       = (sys.binary_float, sys.binary_float),
        OPERATOR        4       >= (sys.binary_float, sys.binary_float),
        OPERATOR        5       > (sys.binary_float, sys.binary_float),
        FUNCTION        1       sys.brin_minmax_opcinfo(internal),
		FUNCTION        2       sys.brin_minmax_add_value(internal, internal, internal, internal),
		FUNCTION        3       sys.brin_minmax_consistent(internal, internal, internal),
		FUNCTION        4       sys.brin_minmax_union(internal, internal, internal);
		
/* CREATE OPERATOR CLASS for 'binary_double' */
CREATE OPERATOR CLASS sys.binary_double_minmax_ops
    DEFAULT FOR TYPE sys.binary_double USING brin FAMILY sys.binary_minmax_ops AS
        OPERATOR        1       < (sys.binary_double, sys.binary_double),
        OPERATOR        2       <= (sys.binary_double, sys.binary_double),
        OPERATOR        3       = (sys.binary_double, sys.binary_double),
        OPERATOR        4       >= (sys.binary_double, sys.binary_double),
        OPERATOR        5       > (sys.binary_double, sys.binary_double),
        FUNCTION        1       sys.brin_minmax_opcinfo(internal),
		FUNCTION        2       sys.brin_minmax_add_value(internal, internal, internal, internal),
		FUNCTION        3       sys.brin_minmax_consistent(internal, internal, internal),
		FUNCTION        4       sys.brin_minmax_union(internal, internal, internal);	

ALTER OPERATOR FAMILY sys.binary_minmax_ops USING brin ADD
	-- Cross data type comparison
	OPERATOR        1       < (sys.binary_float, sys.binary_double),
	OPERATOR        2       <= (sys.binary_float, sys.binary_double),
	OPERATOR        3       = (sys.binary_float, sys.binary_double),
	OPERATOR        4       >= (sys.binary_float, sys.binary_double),
	OPERATOR        5       > (sys.binary_float, sys.binary_double),
	-- Cross data type comparison
	OPERATOR        1       < (sys.binary_double, sys.binary_float),
	OPERATOR        2       <= (sys.binary_double, sys.binary_float),
	OPERATOR        3       = (sys.binary_double, sys.binary_float),
	OPERATOR        4       >= (sys.binary_double, sys.binary_float),
	OPERATOR        5       > (sys.binary_double, sys.binary_float);

--
-- CREATE AGGREGATE FOR BINARY_FLOAT AND BINARY_DOUBLE TYPE 
-- Most depend on implicit conversion 
/* max */
CREATE FUNCTION sys.binary_float_larger(sys.binary_float, sys.binary_float)
RETURNS sys.binary_float
AS 'float4larger'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE AGGREGATE sys.max(sys.binary_float) (
  SFUNC = sys.binary_float_larger,
  STYPE = sys.binary_float,
  SORTOP = >
);

/* min */
CREATE FUNCTION sys.binary_float_smaller(sys.binary_float, sys.binary_float)
RETURNS sys.binary_float
AS 'float4smaller'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE AGGREGATE sys.min(sys.binary_float) (
  SFUNC=sys.binary_float_smaller,
  STYPE= sys.binary_float,
  SORTOP= <
);

-- ----------------------------------------
-- REDO LATER
-- ----------------------------------------
create or replace function sys.text_text(text,text) returns numeric as $$
  select $1::varchar2-$2::varchar2;
$$ language sql strict immutable;

CREATE OPERATOR sys.- (
	procedure = sys.text_text,
	leftarg = pg_catalog.text,
	rightarg = pg_catalog.text
);


CREATE CAST (pg_catalog.int2 AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.int4 AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.int8 AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.int2 AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.int4 AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.int8 AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;


CREATE CAST (pg_catalog.int2 AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.int4 AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.int8 AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.int2 AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.int4 AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.int8 AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;




CREATE CAST (pg_catalog.float4 AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.float8 AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.float4 AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.float8 AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;


CREATE CAST (pg_catalog.float4 AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.float8 AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.float4 AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.float8 AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;




CREATE CAST (pg_catalog.numeric AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.numeric AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.numeric AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.numeric AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.money AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.money AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.money AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.money AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;


CREATE CAST (pg_catalog.time AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.time AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.time AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.time AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.timetz AS sys.oravarcharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.timetz AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.timetz AS sys.oracharbyte)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.timetz AS sys.oracharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.bytea AS sys.oravarcharbyte)
WITH INOUT
AS ASSIGNMENT;

CREATE CAST (pg_catalog.bytea AS sys.oravarcharchar)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharchar AS pg_catalog.int8)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS pg_catalog.int8)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.varchar AS pg_catalog.int8)
WITH INOUT
AS IMPLICIT;



--create function for sgrdb
-- add immutable
create or replace function sys.to_char(text) RETURNS text AS $$ SELECT $1 $$ LANGUAGE SQL IMMUTABLE;

-- generate_series support int2,int4,int8 but number has more choices will result error
CREATE FUNCTION sys.generate_series(number, number) returns setof numeric AS $$
SELECT PG_CATALOG.generate_series($1::numeric,$2::numeric)
$$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION sys.generate_series(number, number, number) returns setof numeric AS $$
SELECT PG_CATALOG.generate_series($1::numeric,$2::numeric, $3::numeric)
$$ LANGUAGE SQL IMMUTABLE;

CREATE CAST (sys.oravarcharchar AS pg_catalog.int4)
WITH INOUT
AS IMPLICIT;

/* will move to oracharchar partion */
create or replace function sys.oid_cc_eq(oid_l pg_catalog.oid, cc_r sys.oracharchar) RETURNS BOOLEAN AS $$ SELECT $1::sys.oracharchar=trim(leading '0' from $2) $$ LANGUAGE SQL;
create or replace function sys.cc_oid_eq(cc_l sys.oracharchar, oid_r pg_catalog.oid) RETURNS BOOLEAN AS $$ SELECT trim(leading '0' from $1)=$2::sys.oracharchar $$ LANGUAGE SQL;
create or replace function sys.oid_cc_ne(oid_l pg_catalog.oid, cc_r sys.oracharchar) RETURNS BOOLEAN AS $$ SELECT not sys.oid_cc_eq(oid_l, cc_r) $$ LANGUAGE SQL;
create or replace function sys.cc_oid_ne(cc_l sys.oracharchar, oid_r pg_catalog.oid) RETURNS BOOLEAN AS $$ SELECT not sys.cc_oid_eq(cc_l, oid_r) $$ LANGUAGE SQL;
create operator = (procedure=sys.oid_cc_eq, LEFTARG=pg_catalog.oid, RIGHTARG=sys.oracharchar);
create operator = (procedure=sys.cc_oid_eq, LEFTARG=sys.oracharchar, RIGHTARG=pg_catalog.oid);
create operator <> (procedure=sys.oid_cc_ne, LEFTARG=pg_catalog.oid, RIGHTARG=sys.oracharchar);
create operator <> (procedure=sys.cc_oid_ne, LEFTARG=sys.oracharchar, RIGHTARG=pg_catalog.oid);


CREATE FUNCTION sys.round(number, integer)
RETURNS numeric
AS $$SELECT pg_catalog.round($1,$2);$$
LANGUAGE SQL
STRICT
IMMUTABLE;

CREATE CAST (sys.oravarcharchar AS float8)
WITH INOUT
AS IMPLICIT;

CREATE CAST (sys.oravarcharbyte AS float8)
WITH INOUT
AS IMPLICIT;

/* AT TIME ZONE */
CREATE FUNCTION sys.timezone(text, sys.oratimestamp)
RETURNS sys.oratimestamptz
AS 'timestamp_zone'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.timezone(text, sys.oratimestamptz)
RETURNS sys.oratimestamp
AS 'timestamptz_zone'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.timezone(pg_catalog.interval, sys.oratimestamp)
RETURNS sys.oratimestamptz
AS 'timestamp_izone'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.timezone(pg_catalog.interval, sys.oratimestamptz)
RETURNS sys.oratimestamp
AS 'timestamptz_izone'
LANGUAGE internal
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE  OR REPLACE FUNCTION sys.varchar2like(varchar2, varchar2)
RETURNS bool AS $$
SELECT $1::text like $2::text;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR ~~ (
PROCEDURE = sys.varchar2like,
LEFTARG   = varchar2,
RIGHTARG  = varchar2
);

/***************************************************************
 *
 * raw and long type support
 *
 ***************************************************************/
CREATE FUNCTION sys.oralongtypmodin(cstring[])
RETURNS integer
AS 'MODULE_PATHNAME','oralongtypmodin'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.oralongtypmodout(integer)
RETURNS CSTRING
AS 'MODULE_PATHNAME','oralongtypmodout'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oralongtypmodin')
WHERE typname = 'long';

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oralongtypmodout')
WHERE typname = 'long';

UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='oralongtypmodin')
WHERE typname = '_long';

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='oralongtypmodout')
WHERE typname = '_long';


CREATE FUNCTION sys.orarawtypmodin(cstring[])
RETURNS integer
AS 'MODULE_PATHNAME','orarawtypmodin'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.orarawtypmodout(integer)
RETURNS CSTRING
AS 'MODULE_PATHNAME','orarawtypmodout'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='orarawtypmodin')
WHERE typname = 'raw';

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='orarawtypmodout')
WHERE typname = 'raw';

UPDATE pg_type
SET typmodin=(SELECT oid FROM pg_proc WHERE proname='orarawtypmodin')
WHERE typname = '_raw';

UPDATE pg_type
SET typmodout=(SELECT oid FROM pg_proc WHERE proname='orarawtypmodout')
WHERE typname = '_raw';


CREATE FUNCTION sys.orabytea_to_raw_with_typmod(bytea, integer, boolean)
RETURNS bytea
AS 'MODULE_PATHNAME','orabytea_to_raw_with_typmod'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.orachar_to_long_with_typmod(text, integer, boolean)
RETURNS text
AS 'MODULE_PATHNAME','orachar_to_long_with_typmod'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE CAST (bytea AS bytea)
WITH FUNCTION sys.orabytea_to_raw_with_typmod(bytea, integer, boolean)
AS IMPLICIT;

CREATE CAST (text AS text)
WITH FUNCTION sys.orachar_to_long_with_typmod(text, integer, boolean)
AS IMPLICIT;
