/***************************************************************
 *
 * Character datatype functions.
 *
 ***************************************************************/

CREATE FUNCTION sys.asciistr(text)
RETURNS text
AS 'MODULE_PATHNAME','ora_asciistr'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.decompose(text, text DEFAULT 'canonical')
RETURNS text
AS $$
BEGIN
    IF LOWER($2) = 'canonical' THEN
        RETURN pg_catalog.normalize($1, 'NFD');
    ELSIF LOWER($2) = 'compatibility' THEN
        RETURN pg_catalog.normalize($1, 'NFKD');
    ELSE
        RAISE 'Invalid parameter string used in SQL function';
    END IF;
END;
$$
LANGUAGE plpgsql
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.compose(text)
RETURNS text
AS $$ SELECT pg_catalog.normalize($1, 'NFC');$$
LANGUAGE SQL
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_multi_byte(str text)
RETURNS text
AS 'MODULE_PATHNAME','ora_to_multi_byte'
LANGUAGE C 
STRICT
PARALLEL SAFE
IMMUTABLE; 
COMMENT ON FUNCTION sys.to_multi_byte(text) IS 'Convert all single-byte characters to their corresponding multibyte characters';

CREATE FUNCTION sys.to_single_byte(str text)
RETURNS text
AS 'MODULE_PATHNAME','ora_to_single_byte'
LANGUAGE C 
STRICT
PARALLEL SAFE
IMMUTABLE; 
COMMENT ON FUNCTION sys.to_single_byte(text) IS 'Convert characters to their corresponding single-byte characters if possible';

/* length/lengthb for CHAR(n char/byte) */
CREATE FUNCTION sys.length(text)
RETURNS integer
AS 'MODULE_PATHNAME','oracharlen'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.length(sys.oracharchar)
RETURNS integer
AS 'MODULE_PATHNAME','oracharlen'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.length(sys.oracharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','oracharlen'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.lengthb(sys.oracharchar)
RETURNS integer
AS 'MODULE_PATHNAME','oracharoctetlen'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.lengthb(sys.oracharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','oracharoctetlen'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

/* length/lengthb for VARCHAR2(n char/byte) */
CREATE FUNCTION sys.length(sys.oravarcharchar)
RETURNS integer
AS 'MODULE_PATHNAME','oravarcharlen'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.length(sys.oravarcharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','oravarcharlen'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.lengthb(sys.oravarcharchar)
RETURNS integer
AS 'MODULE_PATHNAME','oravarcharoctetlen'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.lengthb(sys.oravarcharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','oravarcharoctetlen'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

/*
 * lengthc --- Oracle's LENGTHC: the number of complete Unicode characters,
 * that is, the number of code points left after NFC normalization.
 *
 * All five character types bind the C symbol directly and none of them go
 * through a cast: sys.oracharchar -> text and sys.oracharchar ->
 * sys.oravarcharchar are both implemented by rtrim(), so routing CHAR through
 * either of them would silently drop the blank padding that Oracle counts.
 *
 * The overload set deliberately mirrors sys.length(): with more than one
 * candidate in the same namespace, func_select_candidate() cannot break the
 * tie by search path position and fails with "function ... is not unique".
 * Dropping the text overload would therefore break lengthc('abc'), and
 * dropping the numeric/date wrappers would break lengthc(192).  Conversely
 * sys.binary_float and sys.oratimestampltz are intentionally absent: they
 * resolve via the preferred types sys.binary_double and sys.oratimestamptz.
 * sys.long is a domain over text and folds onto lengthc(text).
 *
 * The numeric and datetime wrappers are not a liberty we take: Oracle does
 * not list DATE/TIMESTAMP/NUMBER as LENGTHC inputs either, but it reaches
 * them through the generic implicit argument conversion and answers
 * normally -- LENGTHC(SYSDATE) is 19, LENGTHC(SYSTIMESTAMP) 35,
 * LENGTHC(192.922) 7 -- exactly as sys.length() already does here.
 *
 * The LOB types are the real exception.  Oracle's LENGTH entry says
 * LENGTHC/LENGTH2/LENGTH4 "do not allow char to be a CLOB or NCLOB", and an
 * instance rejects BLOB the same way, so sys.clob, sys.nclob and sys.blob
 * get exact-match overloads bound to ora_lengthc_unsupported() below.
 * Without them nothing would be rejected: the first two are domains over
 * text and the third one over bytea, which has an implicit cast to
 * sys.oravarcharchar.
 *
 * RAW stays accepted, because Oracle accepts it -- LENGTHC(HEXTORAW(
 * '616263')) is 6, the length of the hex text.  We agree on the mechanism
 * but not on the number: PG's bytea output carries a "\x" prefix, so our
 * answers are Oracle's plus two.  That belongs to the extension-wide
 * bytea -> sys.oravarcharchar cast, not to lengthc.
 */

CREATE FUNCTION sys.lengthc(text)
RETURNS integer
AS 'MODULE_PATHNAME','ora_lengthc'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.lengthc(sys.oracharchar)
RETURNS integer
AS 'MODULE_PATHNAME','ora_lengthc'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.lengthc(sys.oracharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','ora_lengthc'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.lengthc(sys.oravarcharchar)
RETURNS integer
AS 'MODULE_PATHNAME','ora_lengthc'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.lengthc(sys.oravarcharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','ora_lengthc'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

COMMENT ON FUNCTION sys.lengthc(text) IS 'Return the number of complete Unicode characters (code points after NFC normalization)';

CREATE FUNCTION sys.lengthc(integer)
RETURNS integer
AS 'select sys.lengthc($1::sys.oravarcharchar)'
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.lengthc(numeric)
RETURNS integer
AS 'select sys.lengthc($1::sys.oravarcharchar)'
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.lengthc(sys.number)
RETURNS integer
AS 'select sys.lengthc($1::sys.oravarcharchar)'
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.lengthc(sys.binary_double)
RETURNS integer
AS 'select sys.lengthc($1::sys.oravarcharchar)'
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE STRICT;

/*
 * The datetime overloads are STABLE, not IMMUTABLE: the cast to
 * oravarcharchar goes through sys.oradate_out() and friends, which are
 * themselves STABLE because they read nls_date_format / nls_timestamp_format
 * -- the same reason pg_catalog.date_out() and timestamp_out() are STABLE.
 * Declaring these IMMUTABLE would launder that dependency past
 * contain_mutable_functions(), which does not look inside a SQL function
 * body, and let CREATE INDEX ... (lengthc(date_col)) store lengths that go
 * stale the moment the format changes.
 */
CREATE FUNCTION sys.lengthc(sys.oradate)
RETURNS integer
AS 'select sys.lengthc($1::sys.oravarcharchar)'
LANGUAGE SQL
STABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.lengthc(sys.oratimestamp)
RETURNS integer
AS 'select sys.lengthc($1::sys.oravarcharchar)'
LANGUAGE SQL
STABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.lengthc(sys.oratimestamptz)
RETURNS integer
AS 'select sys.lengthc($1::sys.oravarcharchar)'
LANGUAGE SQL
STABLE PARALLEL SAFE STRICT;

/*
 * bytea and the two non-LOB domains over it.  These only restate the
 * coercion that used to happen on its own, and they have to be spelled out
 * because sys.lengthc(sys.blob) below made bytea ambiguous: a bytea reaches
 * both the blob overload (domain relabel) and the oravarcharchar one
 * (implicit cast), and category U has no preferred type to break the tie.
 * The text side needs no such help -- sys.clob/nclob/long all lose to
 * lengthc(text), text being the preferred type of category S.
 */
CREATE FUNCTION sys.lengthc(pg_catalog.bytea)
RETURNS integer
AS 'select sys.lengthc($1::sys.oravarcharchar)'
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.lengthc(sys.raw)
RETURNS integer
AS 'select sys.lengthc($1::sys.oravarcharchar)'
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.lengthc(sys.long_raw)
RETURNS integer
AS 'select sys.lengthc($1::sys.oravarcharchar)'
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE STRICT;

/*
 * The three LOB types Oracle's LENGTHC refuses; see
 * ora_lengthc_unsupported().  NOT STRICT on purpose -- Oracle rejects the
 * type while parsing, so a NULL CLOB has to be a type error here too.
 */
CREATE FUNCTION sys.lengthc(sys.clob)
RETURNS integer
AS 'MODULE_PATHNAME','ora_lengthc_unsupported'
LANGUAGE C
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.lengthc(sys.nclob)
RETURNS integer
AS 'MODULE_PATHNAME','ora_lengthc_unsupported'
LANGUAGE C
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.lengthc(sys.blob)
RETURNS integer
AS 'MODULE_PATHNAME','ora_lengthc_unsupported'
LANGUAGE C
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.length(integer)
RETURNS integer
AS $$SELECT sys.length(cast($1 as sys.oravarcharchar));$$
LANGUAGE SQL
PARALLEL SAFE
VOLATILE;

create function sys.lengthb(bytea) returns int as
$$
begin
  return octet_length($1);
end;
$$
language plpgsql
PARALLEL SAFE;


/* trim/ltrim/rtrim functions */
CREATE FUNCTION sys.rtrim(sys.oravarcharchar)
RETURNS oravarcharchar
AS 'MODULE_PATHNAME','rtrim1'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.rtrim(sys.oravarcharchar, sys.oravarcharchar)
RETURNS oravarcharchar
AS 'MODULE_PATHNAME','rtrim2'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.ltrim(sys.oravarcharchar)
RETURNS oravarcharchar
AS 'MODULE_PATHNAME','ltrim1'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.ltrim(sys.oravarcharchar, sys.oravarcharchar)
RETURNS oravarcharchar
AS 'MODULE_PATHNAME','ltrim2'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE FUNCTION sys.trim(sys.oravarcharchar)
RETURNS oravarcharchar
AS 'MODULE_PATHNAME','trim1'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.trim(sys.oravarcharchar, sys.oravarcharchar)
RETURNS oravarcharchar
AS 'MODULE_PATHNAME','trim2'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

--bytea use pg_catalog
CREATE FUNCTION sys.trim(bytea, bytea)
RETURNS bytea
AS $$ SELECT pg_catalog.btrim($1, $2);$$
LANGUAGE SQL
STRICT
PARALLEL SAFE
IMMUTABLE;

/* regexp_replace */
CREATE FUNCTION sys.regexp_replace(varchar2, varchar2, varchar2, integer,integer,varchar2)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_replace'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_replace(varchar2, varchar2, varchar2, integer,integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_replace'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_replace(varchar2, varchar2, varchar2, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_replace'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_replace(text, text, text, integer,integer,text)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_replace'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_replace(text, text, text, integer,integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_replace'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_replace(text, text, text, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_replace'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_replace(varchar2, varchar2, varchar2)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_replace'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_replace(text, text, text)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_replace'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_replace(varchar2, varchar2)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_replace'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_replace(varchar2)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_replace'
LANGUAGE C
PARALLEL SAFE
STABLE;

/*regexp_substr*/
CREATE FUNCTION sys.regexp_substr(varchar2, varchar2, integer, integer, varchar2, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_substr'
LANGUAGE C
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.regexp_substr(varchar2, varchar2, integer, integer, varchar2)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_substr'
LANGUAGE C
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.regexp_substr(varchar2, varchar2, integer, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_substr'
LANGUAGE C
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.regexp_substr(varchar2, varchar2, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_substr'
LANGUAGE C
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.regexp_substr(text, text, integer, integer, text, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_substr'
LANGUAGE C
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.regexp_substr(text, text, integer, integer, text)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_substr'
LANGUAGE C
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.regexp_substr(text, text, integer, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_substr'
LANGUAGE C
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.regexp_substr(text, text, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_substr'
LANGUAGE C
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.regexp_substr(varchar2, varchar2)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_substr'
LANGUAGE C
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.regexp_substr(varchar2)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_substr'
LANGUAGE C
PARALLEL SAFE
IMMUTABLE;

/*regexp_instr*/
CREATE FUNCTION sys.regexp_instr(varchar2, varchar2, integer, integer, integer, varchar2, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_instr'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_instr(varchar2, varchar2, integer, integer, integer, varchar2)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_instr'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_instr(varchar2, varchar2, integer, integer, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_instr'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_instr(varchar2, varchar2, integer, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_instr'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_instr(varchar2, varchar2, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_instr'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_instr(text, text, integer, integer, integer, text, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_instr'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_instr(text, text, integer, integer, integer, text)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_instr'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_instr(text, text, integer, integer, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_instr'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_instr(text, text, integer, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_instr'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_instr(text, text, integer)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_instr'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_instr(varchar2, varchar2)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_instr'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_instr(varchar2)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_instr'
LANGUAGE C
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_instr(text)
RETURNS varchar2
AS 'MODULE_PATHNAME','ora_regexp_instr'
LANGUAGE C
PARALLEL SAFE
STABLE;

/* regexp_like */
CREATE FUNCTION sys.regexp_like(varchar2, varchar2)
RETURNS bool
AS 'MODULE_PATHNAME','ora_regexp_like_no_flags'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.regexp_like(varchar2, varchar2, varchar2)
RETURNS bool
AS 'MODULE_PATHNAME','ora_regexp_like'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;
CREATE FUNCTION sys.regexp_count(text, text, integer)
RETURNS int AS $$
	SELECT sys.regexp_count($1::varchar2, $2::varchar2, $3::number);
$$ LANGUAGE SQL
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_count(text, text, integer, text)
RETURNS int AS $$
	SELECT sys.regexp_count($1::varchar2, $2::varchar2, $3::number, $4::varchar2);
$$ LANGUAGE SQL
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.regexp_count(varchar2, varchar2, number default 1, varchar2 default 'g')
RETURNS int
AS 'MODULE_PATHNAME','ora_regexp_count'
LANGUAGE C
PARALLEL SAFE
STABLE;

/* SUBSTR uses character positions; SUBSTRB below uses byte positions. */
CREATE FUNCTION sys.substr(text, pg_catalog.int4)
RETURNS text
AS 'MODULE_PATHNAME','ora_substr_no_length'
LANGUAGE C
STRICT
IMMUTABLE
PARALLEL SAFE;

CREATE FUNCTION sys.substr(text, pg_catalog.int4, pg_catalog.int4)
RETURNS text
AS 'MODULE_PATHNAME','ora_substr'
LANGUAGE C
STRICT
IMMUTABLE
PARALLEL SAFE;

/* SR */
CREATE FUNCTION sys.substrb(varchar, number)
RETURNS text
AS 'MODULE_PATHNAME','ora_substrb_no_length'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.substrb(varchar, number, number)
RETURNS text
AS 'MODULE_PATHNAME','ora_substrb'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.replace(varchar, varchar, varchar default NULL)
RETURNS text
AS 'MODULE_PATHNAME','ora_replace'
LANGUAGE C
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.instrb(varchar2, varchar2, number default 1, number default 1)
RETURNS int
AS 'MODULE_PATHNAME','ora_instrb'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

--lpad
CREATE FUNCTION sys.lpad(varchar2, number) returns varchar2 AS
$$ select pg_catalog.lpad($1::text, $2::integer); $$
LANGUAGE SQL
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.lpad(varchar2, number, varchar2) returns varchar2 AS
$$ select pg_catalog.lpad($1::text, $2::integer, $3::text); $$
LANGUAGE SQL
STRICT
PARALLEL SAFE
IMMUTABLE;

--rpad
CREATE FUNCTION sys.rpad(varchar2, number) returns varchar2 AS
$$ select pg_catalog.rpad($1::text, $2::integer); $$
LANGUAGE SQL
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.rpad(varchar2, number, varchar2) returns varchar2 AS
$$ select pg_catalog.rpad($1::text, $2::integer, $3::text); $$
LANGUAGE SQL
STRICT
PARALLEL SAFE
IMMUTABLE;

/***************************************************************
 *
 * Datetime datatype functions. 
 *
 ***************************************************************/
CREATE FUNCTION sys.sysdate()
RETURNS sys.oradate
AS 'MODULE_PATHNAME','sysdate'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.current_date()
RETURNS sys.oradate
AS 'MODULE_PATHNAME','ora_current_date'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.systimestamp()
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','ora_current_timestamp'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.current_timestamp()
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','ora_current_timestamp'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.current_timestamp(integer)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','ora_current_timestamp'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.localtimestamp()
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','ora_local_timestamp'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.localtimestamp(integer)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','ora_local_timestamp'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.last_day(sys.oradate)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','last_day'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.add_months(sys.oradate,sys.number)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','add_months'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.round(sys.oradate,text)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','ora_round'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.round(sys.oradate)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','ora_round'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.trunc(sys.oradate,text)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','ora_trunc'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.trunc(sys.oradate)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','ora_trunc'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.next_day(sys.oradate,integer)
RETURNS sys.oradate
AS 'MODULE_PATHNAME', 'next_day_by_index'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.next_day(sys.oradate,text)
RETURNS sys.oradate
AS 'MODULE_PATHNAME', 'next_day'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.new_time(sys.oradate,text,text)
RETURNS sys.oradate
AS 'MODULE_PATHNAME', 'ora_new_time'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.tz_offset(text)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_tz_offset'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.months_between(sys.oradate, sys.oradate)
RETURNS double precision
AS 'MODULE_PATHNAME', 'months_between'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.from_tz(sys.oratimestamp,text)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','ora_from_tz'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.sys_extract_utc(sys.oratimestamptz)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','ora_sys_extract_utc'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.sessiontimezone()
RETURNS text
AS 'MODULE_PATHNAME','ora_sessiontimezone'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.dbtimezone()
RETURNS text
AS 'MODULE_PATHNAME','ora_dbtimezone'
LANGUAGE C
STRICT
STABLE;

CREATE FUNCTION sys.to_date(text)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','to_oradate1'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.to_date(text,text)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','to_oradate2'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;
 
CREATE FUNCTION sys.to_date(text, text, text)
RETURNS sys.oradate
AS 'MODULE_PATHNAME','to_oradate3'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.to_timestamp(text)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','to_oratimestamp1'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.to_timestamp(text, text)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','to_oratimestamp2'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.to_timestamp(text, text, text)
RETURNS sys.oratimestamp
AS 'MODULE_PATHNAME','to_oratimestamp3'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.to_timestamp_tz(text)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','to_oratimestamptz1'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.to_timestamp_tz(text, text)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','to_oratimestamptz2'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.to_timestamp_tz(text, text, text)
RETURNS sys.oratimestamptz
AS 'MODULE_PATHNAME','to_oratimestamptz3'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.to_char(sys.oradate)
RETURNS varchar2
AS 'MODULE_PATHNAME','oradate_to_char1'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;


CREATE FUNCTION sys.to_char(sys.oradate, text)
RETURNS varchar2
AS 'MODULE_PATHNAME','oradate_to_char2'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.oradate, text, text)
RETURNS varchar2
AS 'MODULE_PATHNAME','oradate_to_char3'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.oratimestamp)
RETURNS varchar2
AS 'MODULE_PATHNAME','oratimestamp_to_char1'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.oratimestamp, text)
RETURNS varchar2
AS 'MODULE_PATHNAME','oratimestamp_to_char2'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.oratimestamp, text, text)
RETURNS varchar2
AS 'MODULE_PATHNAME','oratimestamp_to_char3'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.oratimestamptz)
RETURNS varchar2
AS 'MODULE_PATHNAME','oratimestamptz_to_char1'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.oratimestamptz, text)
RETURNS varchar2
AS 'MODULE_PATHNAME','oratimestamptz_to_char2'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.oratimestamptz, text, text)
RETURNS varchar2
AS 'MODULE_PATHNAME','oratimestamptz_to_char3'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.oratimestampltz)
RETURNS varchar2
AS 'MODULE_PATHNAME','oratimestampltz_to_char1'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.oratimestampltz, text)
RETURNS varchar2
AS 'MODULE_PATHNAME','oratimestampltz_to_char2'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.oratimestampltz, text, text)
RETURNS varchar2
AS 'MODULE_PATHNAME','oratimestampltz_to_char3'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.dsinterval)
RETURNS varchar2
AS 'MODULE_PATHNAME','oradsinterval_to_char1'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.dsinterval, text)
RETURNS varchar2
AS 'MODULE_PATHNAME','oradsinterval_to_char1'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.dsinterval, text, text)
RETURNS varchar2
AS 'MODULE_PATHNAME','oradsinterval_to_char1'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.yminterval)
RETURNS varchar2
AS 'MODULE_PATHNAME','orayminterval_to_char1'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.yminterval, text)
RETURNS varchar2
AS 'MODULE_PATHNAME','orayminterval_to_char1'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.yminterval, text, text)
RETURNS varchar2
AS 'MODULE_PATHNAME','orayminterval_to_char1'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_yminterval(text)
RETURNS sys.yminterval
AS 'MODULE_PATHNAME','to_yminterval'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.numtoyminterval(float8, text)
RETURNS sys.yminterval
AS 'MODULE_PATHNAME','numtoyminterval'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_dsinterval(text)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','to_dsinterval'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.numtodsinterval(float8, text)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME','numtodsinterval'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;


/***************************************************************
 *
 * Number datatype functions.
 *
 ***************************************************************/
CREATE FUNCTION sys.bitand(number,number)
RETURNS number
AS 'MODULE_PATHNAME','number_bitand'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.bitand(text, text)
RETURNS number
AS
$$
declare
  v1 number = cast($1 as number);
  v2 number = cast($2 as number);
begin
	return sys.bitand(v1, v2);
end;
$$
LANGUAGE plpgsql
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.nanvl(number, number)
RETURNS number
AS 'MODULE_PATHNAME','number_nanvl'
LANGUAGE C
IMMUTABLE
PARALLEL SAFE;

CREATE FUNCTION sys.nanvl(sys.binary_float, sys.binary_float)
RETURNS sys.binary_float
AS 'MODULE_PATHNAME','binary_float_nanvl'
LANGUAGE C
IMMUTABLE
PARALLEL SAFE;

CREATE FUNCTION sys.nanvl(sys.binary_double, sys.binary_double)
RETURNS sys.binary_double
AS 'MODULE_PATHNAME','binary_double_nanvl'
LANGUAGE C
IMMUTABLE
PARALLEL SAFE;

CREATE FUNCTION sys.to_number(text,text)
RETURNS sys.number
AS 'MODULE_PATHNAME','ora_to_number'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.to_number(text)
RETURNS sys.number
AS 'MODULE_PATHNAME','ora_to_number'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

-- to_binary_float
CREATE FUNCTION sys.to_binary_float(text,text)
RETURNS sys.binary_float
AS 'MODULE_PATHNAME','ora_to_binary_float'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE FUNCTION sys.to_binary_float(text)
RETURNS sys.binary_float
AS 'MODULE_PATHNAME','ora_to_binary_float'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE OR REPLACE FUNCTION sys.to_binary_float(number)
RETURNS sys.binary_float
AS 'select $1::sys.binary_float'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.to_binary_float(binary_float)
RETURNS sys.binary_float
AS 'select $1'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.to_binary_float(binary_double)
RETURNS sys.binary_float
AS 'select $1::sys.binary_float'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

-- to_binary_double
CREATE FUNCTION sys.to_binary_double(text,text)
RETURNS sys.binary_double
AS 'MODULE_PATHNAME','ora_to_binary_double'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE FUNCTION sys.to_binary_double(text)
RETURNS sys.binary_double
AS 'MODULE_PATHNAME','ora_to_binary_double'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE OR REPLACE FUNCTION sys.to_binary_double(number)
RETURNS sys.binary_double
AS 'select $1::sys.binary_double'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.to_binary_double(binary_double)
RETURNS sys.binary_double
AS 'select $1'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.to_binary_double(binary_float)
RETURNS sys.binary_double
AS 'select $1::sys.binary_double'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

/***************************************************************
 *
 * RAW BLOB CLOB datatype functions.
 *
 ***************************************************************/
CREATE OR REPLACE FUNCTION sys.to_clob(varchar2)
RETURNS clob
AS $$ SELECT $1::clob;$$
LANGUAGE SQL
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE OR REPLACE FUNCTION sys.to_blob(varchar2)
RETURNS blob
AS $$ SELECT $1::blob;$$
LANGUAGE SQL
STRICT
PARALLEL SAFE
IMMUTABLE;

/* support hextoraw function for oracle compatibility */
CREATE or REPLACE FUNCTION sys.hextoraw(text)
RETURNS bytea
AS $$ SELECT pg_catalog.decode($1, 'hex'); $$
LANGUAGE SQL
PARALLEL SAFE
STRICT
IMMUTABLE;

/* support rawtohex function for oracle compatibility */
CREATE OR REPLACE FUNCTION sys.rawtohex(bytea)
RETURNS varchar2
AS $$ SELECT CASE WHEN pg_catalog.octet_length($1) > 0 THEN upper(pg_catalog.encode($1, 'hex'))::varchar2 END; $$ 
LANGUAGE SQL
PARALLEL SAFE
STRICT
IMMUTABLE;

CREATE OR REPLACE FUNCTION sys.rawtohex(text)
RETURNS varchar2
AS $$ SELECT CASE WHEN pg_catalog.octet_length($1) > 0 THEN upper(pg_catalog.encode($1::bytea, 'hex'))::varchar2 END; $$ 
LANGUAGE SQL
PARALLEL SAFE
STRICT
IMMUTABLE;


/***************************************************************
 *
 * Misc functions.
 *
 ***************************************************************/
CREATE FUNCTION sys.uid()
RETURNS int4
AS 'MODULE_PATHNAME','uid'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

/*
 * Oracle USERENV support
 */
/* SESSIONID */
CREATE SEQUENCE sys.userenv_sessionid_sequence;
GRANT SELECT, USAGE ON SEQUENCE sys.userenv_sessionid_sequence TO public;

CREATE OR REPLACE FUNCTION sys.get_sessionid() RETURNS number AS $$
DECLARE
	res int8;
BEGIN
	SELECT currval('sys.userenv_sessionid_sequence') into res;
RETURN res;
EXCEPTION
	WHEN sqlstate '55000' THEN
		SELECT nextval('sys.userenv_sessionid_sequence') into res;
		RETURN res;
	WHEN sqlstate '42P01' THEN
		CREATE SEQUENCE sys.userenv_sessionid_sequence;
		SELECT nextval('sys.userenv_sessionid_sequence') into res;
		RETURN res;
END;
$$ LANGUAGE plpgsql STRICT SET client_min_messages to error;

/* LANG */
CREATE OR REPLACE FUNCTION sys.get_lang() RETURNS varchar2 AS $$
	SELECT (regexp_split_to_array(current_setting('lc_messages'), '\.'))[1];
$$ LANGUAGE sql STRICT;

/* LANGUAGE */
CREATE OR REPLACE FUNCTION sys.get_language() RETURNS varchar2 AS $$
	SELECT (regexp_split_to_array(current_setting('lc_monetary'), '\.'))[1]||'.'||pg_client_encoding();
$$ LANGUAGE sql STRICT;

/* CLIENT_INFO */
CREATE OR REPLACE FUNCTION sys.get_client_info() RETURNS varchar2 AS $$
DECLARE
BEGIN
	RETURN NULL;
END;
$$ LANGUAGE plpgsql STRICT SET client_min_messages to error;


/* ENTRYID */
CREATE OR REPLACE FUNCTION sys.get_entryid() RETURNS number AS $$
DECLARE
BEGIN
	RETURN NULL;
END;
$$ LANGUAGE plpgsql STRICT SET client_min_messages to error;

/* TERMINAL */
CREATE OR REPLACE FUNCTION sys.get_terminal() RETURNS number AS $$
DECLARE
BEGIN
	RETURN NULL;
END;
$$ LANGUAGE plpgsql STRICT SET client_min_messages to error;

/* SID */
CREATE OR REPLACE FUNCTION sys.get_sid() RETURNS number AS $$
DECLARE
	res int;
BEGIN
	SELECT pg_backend_pid() into res;
	RETURN res;
END;
$$ LANGUAGE plpgsql STRICT SET client_min_messages to error;

/* ISDBA */
CREATE OR REPLACE FUNCTION sys.get_isdba() RETURNS VARCHAR2 AS $$
DECLARE
	res boolean;
BEGIN
	SELECT rolsuper into res FROM pg_roles WHERE rolname=current_user;
	IF res = true THEN
		RETURN 'TRUE';
	ELSIF res = false THEN
		RETURN 'FALSE';
	ELSE
		RAISE 'Failed to obtain user attributes.';
	END IF;
END;
$$ LANGUAGE plpgsql STRICT SET client_min_messages to error;

/* using numeric because float point number
 * and big number, them can't recognized by number type
 */
CREATE OR REPLACE FUNCTION sys.length(numeric)
RETURNS integer
AS 'select sys.length($1::sys.oravarcharchar)'
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.length(sys.number)
RETURNS integer
AS 'select sys.length($1::sys.oravarcharchar)'
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.length(sys.binary_double)
RETURNS integer
AS 'select sys.length($1::sys.oravarcharchar)'
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.length(sys.oradate)
RETURNS integer
AS 'select sys.length($1::sys.oravarcharchar)'
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.length(sys.oradate)
RETURNS integer
AS 'select sys.length($1::sys.oravarcharchar)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.length(sys.oratimestamp)
RETURNS integer
AS 'select sys.length($1::sys.oravarcharchar)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.length(sys.oratimestamptz)
RETURNS integer
AS 'select sys.length($1::sys.oravarcharchar)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;


--lengthb
CREATE OR REPLACE FUNCTION sys.lengthb(integer)
RETURNS integer
AS 'select sys.lengthb($1::sys.oravarcharchar)'
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.lengthb(numeric)
RETURNS integer
AS 'select sys.lengthb($1::sys.oravarcharchar)'
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.lengthb(sys.number)
RETURNS integer
AS 'select sys.lengthb($1::sys.oravarcharchar)'
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.lengthb(sys.oradate)
RETURNS integer
AS 'select sys.lengthb($1::sys.oravarcharchar)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.lengthb(sys.oratimestamp)
RETURNS integer
AS 'select sys.lengthb($1::sys.oravarcharchar)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.lengthb(sys.oratimestamptz)
RETURNS integer
AS 'select sys.lengthb($1::sys.oravarcharchar)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.lengthb(text)
RETURNS integer
AS 'MODULE_PATHNAME','oravarcharoctetlen'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

--round
CREATE OR REPLACE FUNCTION sys.round(text)
RETURNS sys.number
AS 'select pg_catalog.round($1::pg_catalog.numeric)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.round(text, integer)
RETURNS sys.number
AS 'select pg_catalog.round($1::pg_catalog.numeric, $2)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.round(double precision, integer)
RETURNS numeric
AS $$SELECT pg_catalog.round($1::numeric,$2);$$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

--trunc
CREATE OR REPLACE FUNCTION sys.trunc(text)
RETURNS sys.number
AS 'select pg_catalog.trunc($1::pg_catalog.numeric)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.trunc(text, integer)
RETURNS sys.number
AS 'select pg_catalog.trunc($1::pg_catalog.numeric, $2)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.trunc(double precision, integer)
RETURNS sys.number
AS 'select pg_catalog.trunc($1::pg_catalog.numeric, $2)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

--to_date
CREATE OR REPLACE FUNCTION sys.to_date(bigint)
RETURNS sys.oradate
AS 'select sys.to_date($1::text)'
LANGUAGE SQL STABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.to_date(bigint, text)
RETURNS sys.oradate
AS 'select sys.to_date($1::text, $2)'
LANGUAGE SQL STABLE PARALLEL SAFE STRICT;

--to_char
CREATE OR REPLACE FUNCTION sys.to_char(number)
RETURNS sys.oravarcharchar
AS 'select sys.to_char($1::text)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

--to_number
CREATE OR REPLACE FUNCTION sys.to_number(number)
RETURNS sys.number
AS 'select sys.to_number($1::text)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sys.to_number(number, number)
RETURNS sys.number
AS 'select sys.to_number($1::text, $2::text)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.instr(str text, patt text, sta int, nth int)
RETURNS int
AS 'MODULE_PATHNAME','oracle_instr_4'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.instr(str text, patt text, sta int)
RETURNS int
AS 'MODULE_PATHNAME','oracle_instr_3'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.instr(str text, patt text)
RETURNS int
AS 'MODULE_PATHNAME','oracle_instr_2'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.instr(str varchar2, patt varchar2, sta number, nth number)
RETURNS int
AS $$
  select sys.instr(str::text, patt::text, sta::integer, nth::integer);
$$ LANGUAGE SQL
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.instr(str varchar2, patt varchar2, sta number)
RETURNS int
AS $$
  select sys.instr(str::text, patt::text, sta::integer);
$$ LANGUAGE SQL
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.instr(str varchar2, patt varchar2)
RETURNS int
AS $$
  select sys.instr(str::text, patt::text);
$$ LANGUAGE SQL
STRICT
PARALLEL SAFE
IMMUTABLE;

/* Begin - SYS_CONTEXT */
CREATE OR REPLACE FUNCTION sys.sys_context(a varchar2, b varchar2)
RETURNS varchar2 AS $$
DECLARE
	res varchar2;
BEGIN
	IF upper(a) = 'USERENV' THEN
	  CASE upper(b)
		  WHEN 'CURRENT_SCHEMA' THEN
			SELECT current_schema() INTO res;
		  WHEN 'CURRENT_SCHEMAID' THEN
			SELECT current_schema()::regnamespace::oid INTO res;
		  WHEN 'SESSION_USER' THEN
			SELECT session_user INTO res;
		  WHEN 'SESSION_USERID' THEN
			SELECT session_user::regrole::oid INTO res;
		  WHEN 'PROXY_USER' THEN
			SELECT session_user INTO res;
		  WHEN 'PROXY_USERID' THEN
			SELECT session_user::regrole::oid INTO res;
		  WHEN 'CURRENT_USER' THEN
		    SELECT current_user INTO res;
		  WHEN 'CURRENT_USERID' THEN
			SELECT current_user::regrole::oid INTO res;
		  WHEN 'CURRENT_EDITION_NAME' THEN
			SELECT version() INTO res;
		  WHEN 'CLIENT_PROGRAM_NAME' THEN
			SELECT application_name INTO res FROM pg_stat_activity WHERE pid = pg_backend_pid();
		  WHEN 'IP_ADDRESS' THEN
		    SELECT client_addr INTO res FROM pg_stat_activity WHERE pid = pg_backend_pid();
		  WHEN 'HOST' THEN
			SELECT client_hostname INTO res FROM pg_stat_activity WHERE pid = pg_backend_pid();
		  WHEN 'ISDBA' THEN
			SELECT sys.get_isdba() INTO res;
		  WHEN 'LANGUAGE' THEN
			SELECT sys.get_language() INTO res;
		  WHEN 'LANG' THEN
			SELECT sys.get_lang() INTO res;
		  WHEN 'NLS_CURRENCY' THEN
			SELECT null INTO res;
		  WHEN 'NLS_DATE_FORMAT' THEN
			SELECT current_setting('nls_date_format') INTO res;
		  WHEN 'NLS_DATE_LANGUAGE' THEN
			SELECT null INTO res;
		  WHEN 'NLS_SORT' THEN
			SELECT null INTO res;
		  WHEN 'NLS_TERRITORY' THEN
			SELECT null INTO res;
		  WHEN 'ORACLE_HOME' THEN
			SELECT current_setting('data_directory') INTO res;
		  WHEN 'PLATFORM_SLASH' THEN
			SELECT
				CASE
					WHEN substring((SELECT setting FROM pg_settings WHERE name = 'data_directory') FROM 1 for 1) = '/' THEN 'LINUX'
					ELSE 'WINDOWS'
				END INTO res;
		  WHEN 'DB_NAME' THEN
			SELECT current_database() INTO res;
		  WHEN 'SESSION_DEFAULT_COLLATION' THEN
			SELECT null INTO res;
		  WHEN 'SID' THEN
			SELECT sys.get_sid() INTO res;
		  WHEN 'ACTION' THEN SELECT NULL INTO res;
		  WHEN 'IS_APPLICATION_ROOT' THEN SELECT NULL INTO res;
		  WHEN 'IS_APPLICATION_PDB' THEN SELECT NULL INTO res;
		  WHEN 'AUDITED_CURSORID' THEN SELECT NULL INTO res;
		  WHEN 'AUTHENTICATED_IDENTITY' THEN SELECT NULL INTO res;
		  WHEN 'AUTHENTICATION_DATA' THEN SELECT NULL INTO res;
		  WHEN 'AUTHENTICATION_METHOD' THEN SELECT NULL INTO res;
		  WHEN 'BG_JOB_ID' THEN
			SELECT sys.get_bg_job_id() INTO res;
		  WHEN 'CDB_DOMAIN' THEN SELECT NULL INTO res;
		  WHEN 'CDB_NAME' THEN SELECT NULL INTO res;
		  WHEN 'CLIENT_IDENTIFIER' THEN SELECT NULL INTO res;
		  WHEN 'CLIENT_INFO' THEN
			SELECT sys.get_client_info() INTO res;
		  WHEN 'CON_ID' THEN SELECT NULL INTO res;
		  WHEN 'CON_NAME' THEN SELECT NULL INTO res;
		  WHEN 'CURRENT_BIND' THEN SELECT NULL INTO res;
		  WHEN 'CURRENT_EDITION_ID' THEN SELECT NULL INTO res;
		  WHEN 'CURRENT_SQL' THEN SELECT NULL INTO res;
		  WHEN 'CURRENT_SQL1' THEN SELECT NULL INTO res;
		  WHEN 'CURRENT_SQL2' THEN SELECT NULL INTO res;
		  WHEN 'CURRENT_SQL3' THEN SELECT NULL INTO res;
		  WHEN 'CURRENT_SQL4' THEN SELECT NULL INTO res;
		  WHEN 'CURRENT_SQL5' THEN SELECT NULL INTO res;
		  WHEN 'CURRENT_SQL6' THEN SELECT NULL INTO res;
		  WHEN 'CURRENT_SQL7' THEN SELECT NULL INTO res;
		  WHEN 'CURRENT_SQL_LENGTH' THEN SELECT NULL INTO res;
		  WHEN 'DATABASE_ROLE' THEN SELECT NULL INTO res;
		  WHEN 'DB_DOMAIN' THEN SELECT NULL INTO res;
		  WHEN 'DB_SUPPLEMENTAL_LOG_LEVEL' THEN SELECT NULL INTO res;
		  WHEN 'DB_UNIQUE_NAME' THEN SELECT NULL INTO res;
		  WHEN 'DBLINK_INFO' THEN SELECT NULL INTO res;
		  WHEN 'DRAIN_STATUS' THEN SELECT NULL INTO res;
		  WHEN 'ENTRYID' THEN
			SELECT sys.get_entryid() INTO res;
		  WHEN 'ENTERPRISE_IDENTITY' THEN SELECT NULL INTO res;
		  WHEN 'FG_JOB_ID' THEN
			SELECT sys.get_fg_job_id() INTO res;
		  WHEN 'GLOBAL_CONTEXT_MEMORY' THEN SELECT NULL INTO res;
		  WHEN 'GLOBAL_UID' THEN SELECT NULL INTO res;
		  WHEN 'IDENTIFICATION_TYPE' THEN SELECT NULL INTO res;
		  WHEN 'INSTANCE' THEN SELECT NULL INTO res;
		  WHEN 'INSTANCE_NAME' THEN SELECT NULL INTO res;
		  WHEN 'IS_APPLY_SERVER' THEN SELECT 'FALSE' INTO res;
		  WHEN 'IS_DG_ROLLING_UPGRADE' THEN SELECT 'FALSE' INTO res;
		  WHEN 'LDAP_SERVER_TYPE' THEN SELECT NULL INTO res;
		  WHEN 'MODULE' THEN SELECT NULL INTO res;
		  WHEN 'NETWORK_PROTOCOL' THEN SELECT NULL INTO res;
		  WHEN 'NLS_CALENDAR' THEN SELECT NULL INTO res;
		  WHEN 'OS_USER' THEN SELECT NULL INTO res;
		  WHEN 'POLICY_INVOKER' THEN SELECT NULL INTO res;
		  WHEN 'PROXY_ENTERPRISE_IDENTITY' THEN SELECT NULL INTO res;
		  WHEN 'SCHEDULER_JOB' THEN
			SELECT sys.get_scheduler_job() INTO res;
		  WHEN 'SERVER_HOST' THEN SELECT NULL INTO res;
		  WHEN 'SERVICE_NAME' THEN SELECT NULL INTO res;
		  WHEN 'SESSION_EDITION_ID' THEN SELECT NULL INTO res;
		  WHEN 'SESSION_EDITION_NAME' THEN SELECT NULL INTO res;
		  WHEN 'SESSIONID' THEN
			SELECT sys.get_sessionid() INTO res;
		  WHEN 'STATEMENTID' THEN SELECT NULL INTO res;
		  WHEN 'TERMINAL' THEN
			SELECT sys.get_terminal() INTO res;
		  WHEN 'UNIFIED_AUDIT_SESSIONID' THEN SELECT NULL INTO res;
		  ELSE
			RAISE EXCEPTION 'invalid USERENV parameter: %', b;
	  END CASE;
	ELSIF upper(a) = 'SYS_SESSION_ROLES' THEN
		CASE upper(b)
			WHEN 'DBA' THEN
				SELECT sys.get_isdba() INTO res;
			WHEN 'LOGIN' THEN
				SELECT CASE WHEN rolcanlogin = 't' THEN 'TRUE' ELSE 'FALSE' END INTO res FROM pg_roles WHERE oid = current_user::regrole::oid;
			WHEN 'CREATEROLE' THEN
				SELECT CASE WHEN rolcreaterole = 't' THEN 'TRUE' ELSE 'FALSE' END INTO res FROM pg_roles WHERE oid = current_user::regrole::oid;
			WHEN 'CREATEDB' THEN
				SELECT CASE WHEN rolcreatedb = 't' THEN 'TRUE' ELSE 'FALSE' END INTO res FROM pg_roles WHERE oid = current_user::regrole::oid;
			ELSE
				RAISE EXCEPTION 'invalid SYS_SESSION_ROLES parameter: %', b;
		END CASE;
	ELSE
	  /* Custom namespace: read DBMS_SESSION application context first,
	   * then fall back to a GUC named <namespace>.<attribute>. */
	  SELECT sys.ora_dbms_session_get_context(a, b) INTO res;
	  IF res IS NULL THEN
	    SELECT current_setting(a||'.'||b, true) INTO res;
	  END IF;
	END IF;
	RETURN res;
END;
$$ LANGUAGE plisql SECURITY INVOKER;


CREATE or REPLACE FUNCTION sys.sys_context(a varchar2, b varchar2, c number)
RETURNS varchar2 AS $$
DECLARE
	res varchar2;
BEGIN
	SELECT left(sys.sys_context(a, b), c::integer) INTO res;
	RETURN res;
END;
$$ LANGUAGE plisql SECURITY INVOKER;
/* End - SYS_CONTEXT */

/* Begin - ASCII */
CREATE FUNCTION sys.ascii(sys.number)
RETURNS INT
AS 'MODULE_PATHNAME','ora_ascii'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.ascii(sys.binary_float)
RETURNS INT
AS 'MODULE_PATHNAME','ora_ascii'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.ascii(sys.binary_double)
RETURNS INT
AS 'MODULE_PATHNAME','ora_ascii'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.ascii(sys.oravarcharchar)
RETURNS INT
AS 'MODULE_PATHNAME','ora_ascii'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.ascii(sys.oradate)
RETURNS INT
AS 'MODULE_PATHNAME','ora_ascii'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.ascii(sys.oratimestamp)
RETURNS INT
AS 'MODULE_PATHNAME','ora_ascii'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;

CREATE FUNCTION sys.ascii(sys.oratimestamptz)
RETURNS INT
AS 'MODULE_PATHNAME','ora_ascii'
LANGUAGE C
STRICT
PARALLEL SAFE
STABLE;
/* End - ASCII */

/*
 * LISTAGG support
 *
 * sys.ora_listagg_check(text) enforces Oracle's VARCHAR2 maximum length (4000 bytes)
 * on the LISTAGG result.  It is automatically injected by the Oracle-mode parser
 * as a wrapper around string_agg() when LISTAGG(...) WITHIN GROUP (ORDER BY ...)
 * is parsed, so users never call it directly.
 */
CREATE FUNCTION sys.ora_listagg_check(text)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_listagg_check'
LANGUAGE C
CALLED ON NULL INPUT
PARALLEL SAFE
IMMUTABLE;

/* STRAGG */
/*
 * STRAGG: Oracle-compatible string aggregation.
 * Concatenates non-null values with ',' separator (no ORDER BY guarantee).
 * Shares state layout with string_agg so string_agg_finalfn / string_agg_combine
 * can be reused, giving correct parallel-safe behavior.
 */
CREATE FUNCTION sys.stragg_transfn(internal, text)
RETURNS internal
AS 'MODULE_PATHNAME', 'stragg_transfn'
LANGUAGE C
CALLED ON NULL INPUT
PARALLEL SAFE;

CREATE AGGREGATE sys.stragg(text) (
    SFUNC     = sys.stragg_transfn,
    STYPE     = internal,
    FINALFUNC = string_agg_finalfn,
    COMBINEFUNC = string_agg_combine,
    SERIALFUNC  = string_agg_serialize,
    DESERIALFUNC = string_agg_deserialize,
    PARALLEL  = SAFE
);
/* End - STRAGG */

/* LNNVL */
/*
 * LNNVL: Oracle-compatible condition negation.
 * Returns true when the condition is false or unknown, and false when it is
 * true, so a WHERE clause keeps the rows whose condition is unknown, which a
 * plain NOT silently drops.
 *
 * The truth table is exactly that of the SQL standard "IS NOT TRUE" predicate,
 * so the body needs nothing more than that.  Written in SQL rather than C so
 * that inline_function() folds it into the caller and the resulting plan is the
 * same as writing IS NOT TRUE by hand.
 *
 * Must NOT be declared STRICT: LNNVL(NULL) has to return true, which is the
 * whole reason the function exists.  CALLED ON NULL INPUT is the default and is
 * spelled out here so it does not get "tidied" into STRICT like its neighbours.
 */
CREATE FUNCTION sys.lnnvl(pg_catalog.bool)
RETURNS pg_catalog.bool
AS $$SELECT $1 IS NOT TRUE$$
LANGUAGE sql
CALLED ON NULL INPUT
PARALLEL SAFE
IMMUTABLE;
/* End - LNNVL */

/* VSIZE */
/*
 * VSIZE: Oracle-compatible function returning the number of bytes in the
 * internal representation of the argument.  Returns NULL for NULL input.
 * For varlena types the logical (decompressed) data size, excluding the
 * varlena header, is returned; for fixed-width types the storage width is
 * returned.
 *
 * The anycompatible pseudo-type accepts a value of any data type, and an
 * untyped string literal is resolved to text, so VSIZE('abc') works just
 * like in Oracle.
 */
CREATE FUNCTION sys.vsize(anycompatible)
RETURNS int4
AS 'MODULE_PATHNAME', 'ora_vsize'
LANGUAGE C
STRICT
IMMUTABLE;
/* End - VSIZE */


/* RAISE_APPLICATION_ERROR */
/*
 * RAISE_APPLICATION_ERROR: Oracle's way for application code to raise a
 * user-defined error.  Oracle code calls it as a statement, so this has to be
 * a procedure rather than a function.
 *
 * Oracle documents the error number as a negative integer in the range
 * -20999 .. -20000 and prefixes the message with "ORA-<number>: "; anything
 * outside that range is itself an ORA-21000 error.  The third argument,
 * keep_errors, only matters for Oracle's error stack, which PostgreSQL does
 * not have, so it is accepted and ignored.
 */
CREATE OR REPLACE PROCEDURE sys.raise_application_error(
    error_number sys.number,
    message pg_catalog.text,
    keep_errors pg_catalog.bool DEFAULT false)
AS $$
BEGIN
    IF error_number IS NULL OR message IS NULL THEN
        RAISE EXCEPTION 'ORA-06531: null argument to raise_application_error';
    END IF;
    IF error_number > -20000 OR error_number < -20999 THEN
        RAISE EXCEPTION 'ORA-21000: error number argument to raise_application_error of % is out of range',
            error_number;
    END IF;
    RAISE EXCEPTION 'ORA-%: %', -error_number, message;
END;
$$ LANGUAGE plisql;
/* End - RAISE_APPLICATION_ERROR */

/* Oracle-compatible ORA_INVOKING_USER: the database user whose privileges the
 * current statement runs with, which is CURRENT_USER in PostgreSQL. */
CREATE OR REPLACE FUNCTION sys.ora_invoking_user()
RETURNS varchar2
AS $$ SELECT pg_catalog.current_user::varchar2; $$
LANGUAGE SQL
STABLE;

/* Oracle-compatible NLS_INITCAP: INITCAP performed under the given collation.
 * IvorySQL has one database collation, so the locale argument is accepted for
 * compatibility and the result is INITCAP, which is what Oracle returns when
 * the session collation already matches the requested one. */
CREATE OR REPLACE FUNCTION sys.nls_initcap(text)
RETURNS text
AS $$ SELECT pg_catalog.initcap($1); $$
LANGUAGE SQL
IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION sys.nls_initcap(text, text)
RETURNS text
AS $$ SELECT pg_catalog.initcap($1); $$
LANGUAGE SQL
IMMUTABLE STRICT PARALLEL SAFE;

/* Oracle-compatible VALIDATE_CONVERSION(expr, type, fmt): 1 when expr can be
 * converted to type, 0 when it cannot.  The type name is matched against a
 * fixed list and never interpolated into SQL, so the function cannot be used
 * to run arbitrary type names; an unknown type answers 0.  A NULL expr is
 * convertible, as in Oracle.  DATE/TIMESTAMP use the NLS formats (or fmt when
 * given), which is what makes the check match what TO_DATE/TO_TIMESTAMP would
 * do in the same session. */
CREATE OR REPLACE FUNCTION sys.validate_conversion(text, text, text DEFAULT NULL)
RETURNS number
AS $$
DECLARE
    t text := pg_catalog.upper(pg_catalog.btrim($2));
BEGIN
    IF $1 IS NULL OR $2 IS NULL THEN
        RETURN 1;
    END IF;
    BEGIN
        IF t = 'NUMBER' THEN
            PERFORM $1::sys.number;
        ELSIF t = 'INTEGER' THEN
            PERFORM $1::pg_catalog.int4;
        ELSIF t = 'BINARY_FLOAT' THEN
            PERFORM $1::sys.binary_float;
        ELSIF t = 'BINARY_DOUBLE' THEN
            PERFORM $1::sys.binary_double;
        ELSIF t = 'DATE' THEN
            PERFORM sys.to_date($1, COALESCE($3, pg_catalog.current_setting('nls_date_format')));
        ELSIF t = 'TIMESTAMP' THEN
            PERFORM sys.to_timestamp($1, COALESCE($3, pg_catalog.current_setting('nls_timestamp_format')));
        ELSIF t = 'TIMESTAMP WITH TIME ZONE' THEN
            PERFORM sys.to_timestamp_tz($1, COALESCE($3, pg_catalog.current_setting('nls_timestamp_tz_format')));
        ELSIF t IN ('VARCHAR2', 'CHAR', 'VARCHAR') THEN
            PERFORM $1;
        ELSE
            RETURN 0;
        END IF;
        RETURN 1;
    EXCEPTION WHEN others THEN
        RETURN 0;
    END;
END;
$$
LANGUAGE plpgsql
STABLE;

GRANT EXECUTE ON FUNCTION sys.validate_conversion(text, text, text) TO PUBLIC;

/* Oracle-compatible SUBSTR2: substring by USC2 code units.  A character
 * outside the BMP occupies two units, so counting (and slicing) differs from
 * SUBSTR for supplementary characters.  PostgreSQL cannot represent half of a
 * surrogate pair in UTF-8, so a range boundary that falls inside one keeps
 * that whole character rather than returning an invalid string; positions
 * after it are still counted in units, which is the part callers rely on. */
CREATE OR REPLACE FUNCTION sys.substr2(text, integer, integer DEFAULT NULL)
RETURNS text
AS $$
DECLARE
    src     text := $1;
    pos     int  := $2;
    slen    int  := $3;
    n       int  := pg_catalog.length($1);
    i       int  := 1;
    units   int  := 0;
    total   int  := 0;
    ustart  int;
    start_u int;
    end_u   int;
    ch      text;
    cp      int;
    res     text := '';
BEGIN
    IF n IS NULL OR pos IS NULL THEN
        RETURN NULL;
    END IF;
    IF slen IS NOT NULL AND slen < 1 THEN
        RETURN NULL;
    END IF;

    FOR i IN 1..n LOOP
        cp := pg_catalog.ascii(pg_catalog.substr(src, i, 1));
        total := total + CASE WHEN cp >= 65536 THEN 2 ELSE 1 END;
    END LOOP;

    IF pos > 0 THEN
        start_u := CASE WHEN pos <= total THEN pos ELSE total + 1 END;
    ELSIF pos < 0 THEN
        start_u := total + pos + 1;
    ELSE
        start_u := 1;
    END IF;
    IF start_u < 1 THEN
        start_u := 1;
    END IF;
    end_u := CASE WHEN slen IS NULL THEN total ELSE start_u + slen - 1 END;

    FOR i IN 1..n LOOP
        ch := pg_catalog.substr(src, i, 1);
        cp := pg_catalog.ascii(ch);
        ustart := units + 1;
        units := units + CASE WHEN cp >= 65536 THEN 2 ELSE 1 END;
        IF units >= start_u AND ustart <= end_u THEN
            res := res || ch;
        END IF;
    END LOOP;
    RETURN res;
END;
$$
LANGUAGE plpgsql
IMMUTABLE STRICT PARALLEL SAFE;

/* Oracle-compatible INSTR2: the position is counted in USC2 code units.  The
 * search itself is delegated to sys.instr, so position/occurrence semantics
 * stay identical; only the character index is translated to a unit index, and
 * a negative position is mapped back to the equivalent negative character
 * position so that sys.instr still searches backwards. */
CREATE OR REPLACE FUNCTION sys.instr2(text, text, integer DEFAULT 1, integer DEFAULT 1)
RETURNS integer
AS $$
DECLARE
    src        text := $1;
    sub        text := $2;
    pos        int  := $3;
    occ        int  := $4;
    n          int  := pg_catalog.length($1);
    i          int  := 1;
    units      int  := 0;
    total      int  := 0;
    start_u    int;
    start_char int  := 1;
    res_char   int;
    cp         int;
BEGIN
    IF n IS NULL OR sub IS NULL OR pos IS NULL OR occ IS NULL THEN
        RETURN NULL;
    END IF;

    FOR i IN 1..n LOOP
        cp := pg_catalog.ascii(pg_catalog.substr(src, i, 1));
        total := total + CASE WHEN cp >= 65536 THEN 2 ELSE 1 END;
    END LOOP;

    IF pos > 0 THEN
        start_u := pos;
    ELSIF pos < 0 THEN
        start_u := total + pos + 1;
    ELSE
        start_u := 1;
    END IF;

    FOR i IN 1..n LOOP
        cp := pg_catalog.ascii(pg_catalog.substr(src, i, 1));
        units := units + CASE WHEN cp >= 65536 THEN 2 ELSE 1 END;
        IF units >= start_u THEN
            start_char := i;
            EXIT;
        END IF;
    END LOOP;

    IF pos < 0 THEN
        /* keep the backward-searching semantics of sys.instr */
        res_char := sys.instr(src, sub, -(n - start_char + 1), occ);
    ELSE
        res_char := sys.instr(src, sub, start_char, occ);
    END IF;
    IF res_char IS NULL OR res_char = 0 THEN
        RETURN 0;
    END IF;

    units := 0;
    FOR i IN 1..(res_char - 1) LOOP
        cp := pg_catalog.ascii(pg_catalog.substr(src, i, 1));
        units := units + CASE WHEN cp >= 65536 THEN 2 ELSE 1 END;
    END LOOP;
    RETURN units + 1;
END;
$$
LANGUAGE plpgsql
IMMUTABLE STRICT PARALLEL SAFE;

GRANT EXECUTE ON FUNCTION sys.substr2(text, integer, integer) TO PUBLIC;
GRANT EXECUTE ON FUNCTION sys.instr2(text, text, integer, integer) TO PUBLIC;

/* Oracle-compatible ROWIDTOCHAR: the external (character) form of a ROWID.
 * The rowid type already prints its external form through its output
 * function, so the conversion is the type's text representation. */
CREATE OR REPLACE FUNCTION sys.rowidtochar(sys.rowid)
RETURNS varchar2
AS $$ SELECT $1::pg_catalog.text::varchar2; $$
LANGUAGE SQL
IMMUTABLE STRICT PARALLEL SAFE;

/* Oracle-compatible CHARTOROWID: parse an external ROWID string back into the
 * rowid type, using the type's own input function so that exactly the strings
 * the output function produces round-trip. */
CREATE OR REPLACE FUNCTION sys.chartorowid(text)
RETURNS sys.rowid
AS $$ SELECT $1::pg_catalog.text::sys.rowid; $$
LANGUAGE SQL
IMMUTABLE STRICT PARALLEL SAFE;

GRANT EXECUTE ON FUNCTION sys.rowidtochar(sys.rowid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION sys.chartorowid(text) TO PUBLIC;

/* Oracle-compatible TO_NCHAR.  IvorySQL has one database character set, so
 * the national character set is the database character set and TO_NCHAR is
 * the identity for text; for the other types it produces the same text that
 * TO_CHAR produces, which is what Oracle does for an explicit conversion. */
CREATE OR REPLACE FUNCTION sys.to_nchar(text)
RETURNS text
AS $$ SELECT $1; $$
LANGUAGE SQL
IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION sys.to_nchar(number)
RETURNS text
AS $$ SELECT sys.to_char($1); $$
LANGUAGE SQL
STABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION sys.to_nchar(sys.oradate)
RETURNS text
AS $$ SELECT sys.to_char($1); $$
LANGUAGE SQL
STABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION sys.to_nchar(sys.oratimestamp)
RETURNS text
AS $$ SELECT sys.to_char($1); $$
LANGUAGE SQL
STABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION sys.to_nchar(sys.oratimestamptz)
RETURNS text
AS $$ SELECT sys.to_char($1); $$
LANGUAGE SQL
STABLE STRICT PARALLEL SAFE;

GRANT EXECUTE ON FUNCTION sys.to_nchar(text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION sys.to_nchar(number) TO PUBLIC;
GRANT EXECUTE ON FUNCTION sys.to_nchar(sys.oradate) TO PUBLIC;
GRANT EXECUTE ON FUNCTION sys.to_nchar(sys.oratimestamp) TO PUBLIC;
GRANT EXECUTE ON FUNCTION sys.to_nchar(sys.oratimestamptz) TO PUBLIC;

/* Oracle-compatible UNISTR: interprets \XXXX escapes as Unicode code
 * points, including a surrogate pair written as two escapes.  A backslash
 * that is not followed by four hex digits is kept literally, which is how
 * Oracle treats it. */
CREATE OR REPLACE FUNCTION sys.unistr(text)
RETURNS text
AS $$
DECLARE
    src  text := $1;
    res  text := '';
    i    int  := 1;
    n    int  := pg_catalog.length($1);
    ch   text;
    hex4 text;
    code int;
    low  int;
BEGIN
    WHILE i <= n LOOP
        ch := pg_catalog.substr(src, i, 1);
        IF ch = '\' THEN
            hex4 := pg_catalog.substr(src, i + 1, 4);
            IF hex4 ~ '^[0-9A-Fa-f]{4}$' THEN
                code := ('x' || hex4)::bit(16)::int;
                i := i + 5;
                IF code BETWEEN 55296 AND 56319 THEN
                    IF pg_catalog.substr(src, i, 1) = '\' AND
                       pg_catalog.substr(src, i + 1, 4) ~ '^[0-9A-Fa-f]{4}$' THEN
                        low := ('x' || pg_catalog.substr(src, i + 1, 4))::bit(16)::int;
                        IF low BETWEEN 56320 AND 57343 THEN
                            code := 65536 + ((code - 55296) << 10) + (low - 56320);
                            i := i + 5;
                        END IF;
                    END IF;
                END IF;
                res := res || pg_catalog.chr(code);
                CONTINUE;
            END IF;
        END IF;
        res := res || ch;
        i := i + 1;
    END LOOP;
    RETURN res;
END;
$$
LANGUAGE plpgsql
IMMUTABLE STRICT PARALLEL SAFE;

GRANT EXECUTE ON FUNCTION sys.unistr(text) TO PUBLIC;

/* Oracle-compatible SYS_GUID: a 16-byte RAW value that is unique per call.
 * gen_random_uuid() is already a version 4 UUID, so stripping the dashes and
 * decoding the hex gives Oracle's RAW(16) shape. */
CREATE OR REPLACE FUNCTION sys.sys_guid()
RETURNS bytea
AS $$ SELECT pg_catalog.decode(pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', ''), 'hex'); $$
LANGUAGE SQL
VOLATILE
PARALLEL SAFE;
GRANT EXECUTE ON FUNCTION sys.sys_guid() TO PUBLIC;


/* Start - INSTR4 */
/*
 * Oracle's INSTR4 counts positions in UCS4 code points, which is the
 * character semantics PostgreSQL's substr() and strpos() already use; the
 * function exists so that the code that spells out the variant keeps
 * working, next to INSTR, INSTRB and the family.
 *
 * Oracle's rules are followed: a position below one counts from the end of
 * the string and the search then runs backwards, occurrence selects which
 * match to report (counting from the end in the backwards case), a string
 * or substring that is NULL returns NULL and no match returns 0.
 */
CREATE FUNCTION sys.instr4(text, text, integer DEFAULT 1, integer DEFAULT 1)
RETURNS integer
AS
$$
declare
	src text := $1;
	sub text := $2;
	pos integer := $3;
	occ integer := $4;
	len integer;
	region text;
	start integer;
	idx integer;
	p integer;
	total integer := 0;
	want integer;
	i integer := 0;
begin
	if src is null or sub is null then
		return null;
	end if;

	if occ is null or occ < 1 then
		return 0;
	end if;
	if pos is null then
		pos := 1;
	end if;

	len := pg_catalog.length(src);

	if pos >= 0 then
		start := greatest(pos, 1);
		while start <= len loop
			idx := pg_catalog.strpos(pg_catalog.substr(src, start), sub);
			if idx = 0 then
				return 0;
			end if;
			i := i + 1;
			if i = occ then
				return start + idx - 1;
			end if;
			start := start + idx - 1 + greatest(pg_catalog.length(sub), 1);
		end loop;
		return 0;
	end if;

	/* backwards from the given position, counted from the end */
	region := pg_catalog.substr(src, 1, greatest(len + pos + 1, 1));
	p := 1;
	while p <= pg_catalog.length(region) loop
		idx := pg_catalog.strpos(pg_catalog.substr(region, p), sub);
		exit when idx = 0;
		total := total + 1;
		p := p + idx - 1 + greatest(pg_catalog.length(sub), 1);
	end loop;

	if total < occ then
		return 0;
	end if;

	want := total - occ + 1;
	p := 1;
	while p <= pg_catalog.length(region) loop
		idx := pg_catalog.strpos(pg_catalog.substr(region, p), sub);
		if idx = 0 then
			return 0;
		end if;
		i := i + 1;
		if i = want then
			return p + idx - 1;
		end if;
		p := p + idx - 1 + greatest(pg_catalog.length(sub), 1);
	end loop;

	return 0;
end;
$$
LANGUAGE plpgsql
IMMUTABLE;
/* End - INSTR4 */


/* Start - SUBSTR4 */
/*
 * Oracle's SUBSTR4 counts positions and lengths in UCS4 code points, which
 * is what PostgreSQL's character based substr() does as well; the function
 * exists so that the code that spells out the variant keeps working, and
 * SUBSTR2 (UCS2 code units) can follow on top of the same definition.
 *
 * Like Oracle, a length below one returns NULL, while a position below one
 * counts from the end of the string, and a valid position with no length
 * returns the rest of the string.
 */
CREATE FUNCTION sys.substr4(text, integer, integer DEFAULT NULL)
RETURNS text
AS
$$
begin
	if $3 is null then
		return pg_catalog.substr($1, $2);
	end if;
	if $3 <= 0 then
		return null;
	end if;
	return pg_catalog.substr($1, $2, $3);
end;
$$
LANGUAGE plpgsql
IMMUTABLE;
/* End - SUBSTR4 */


/* Start - WM_CONCAT */
/*
 * WM_CONCAT is Oracle's legacy aggregate for concatenating a column into a
 * comma separated list, the job LISTAGG(t, ',') does today.  Like in
 * Oracle, NULL values are skipped and the function returns NULL when no
 * value was aggregated; the order of the values is not defined, exactly as
 * in Oracle (WM_CONCAT has no WITHIN GROUP clause there either).
 */
CREATE FUNCTION sys.wm_concat_trans(state text, value text)
RETURNS text
AS
$$
begin
	if value is null then
		return state;
	end if;
	if state is null then
		return value;
	end if;
	return state || ',' || value;
end;
$$
LANGUAGE plpgsql
IMMUTABLE;

CREATE FUNCTION sys.wm_concat_final(state text)
RETURNS text
AS
$$
begin
	return state;
end;
$$
LANGUAGE plpgsql
IMMUTABLE;

CREATE AGGREGATE sys.wm_concat(text) (
	SFUNC = sys.wm_concat_trans,
	STYPE = text,
	FINALFUNC = sys.wm_concat_final,
	PARALLEL = SAFE
);

/* numbers are converted to their text form, like Oracle does implicitly */
CREATE FUNCTION sys.wm_concat_trans(state text, value number)
RETURNS text
AS
$$
begin
	return sys.wm_concat_trans(state, value::text);
end;
$$
LANGUAGE plpgsql
IMMUTABLE;

CREATE AGGREGATE sys.wm_concat(number) (
	SFUNC = sys.wm_concat_trans,
	STYPE = text,
	FINALFUNC = sys.wm_concat_final,
	PARALLEL = SAFE
);
/* End - WM_CONCAT */

/* Start - LENGTH2 / LENGTH4 */
/*
 * Oracle's LENGTH4 counts UCS4 code points and LENGTH2 counts UCS2 code
 * units, so a supplementary character counts twice for LENGTH2 but once
 * for LENGTH4.  The argument types mirror sys.lengthc().
 */

CREATE FUNCTION sys.length2(text)
RETURNS integer
AS 'MODULE_PATHNAME','ora_length2'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.length2(sys.oracharchar)
RETURNS integer
AS 'MODULE_PATHNAME','ora_length2'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.length2(sys.oracharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','ora_length2'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.length2(sys.oravarcharchar)
RETURNS integer
AS 'MODULE_PATHNAME','ora_length2'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.length2(sys.oravarcharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','ora_length2'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.length4(text)
RETURNS integer
AS 'MODULE_PATHNAME','ora_length4'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.length4(sys.oracharchar)
RETURNS integer
AS 'MODULE_PATHNAME','ora_length4'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.length4(sys.oracharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','ora_length4'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.length4(sys.oravarcharchar)
RETURNS integer
AS 'MODULE_PATHNAME','ora_length4'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

CREATE FUNCTION sys.length4(sys.oravarcharbyte)
RETURNS integer
AS 'MODULE_PATHNAME','ora_length4'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;
/* End - LENGTH2 / LENGTH4 */


/* Start - ORA_HASH */
/*
 * ORA_HASH(expr [, max_bucket [, seed]]) returns a hash value for expr in
 * the range 0 .. max_bucket (4294967295 by default), like Oracle.
 *
 * As in Oracle, the hash values themselves are implementation-defined; the
 * contract of the function is that the same expression, max_bucket and seed
 * produce the same value, inside the requested range.
 */
CREATE FUNCTION sys.ora_hash(value anycompatible,
                             max_bucket int8 DEFAULT 4294967295,
                             seed int8 DEFAULT 0)
RETURNS number
AS
$$
begin
	if max_bucket is null or max_bucket < 0 then
		raise exception 'ORA_HASH: max_bucket must be a non-negative integer';
	end if;

	if value is null then
		return null;
	end if;

	return (abs(pg_catalog.hashtextextended(value::text, seed)::numeric)
		% (max_bucket + 1));
end;
$$
LANGUAGE plpgsql
IMMUTABLE;
/* End - ORA_HASH */


/* Start - BIN_TO_NUM */
/*
 * BIN_TO_NUM(bit, bit, ...) converts a list of bits into the number they
 * spell; the first argument is the most significant bit:
 *
 *     SELECT BIN_TO_NUM(1, 0, 1, 0) FROM DUAL;   -- 10
 *
 * Like Oracle, every argument must be 0 or 1, otherwise an error is raised.
 */
CREATE FUNCTION sys.bin_to_num(VARIADIC bits number[])
RETURNS number
AS
$$
declare
	result number := 0;
	bit_value number;
begin
	if array_length(bits, 1) is null then
		raise exception 'BIN_TO_NUM: at least one bit is required';
	end if;

	foreach bit_value in array bits loop
		if bit_value is null or bit_value not in (0, 1) then
			raise exception 'BIN_TO_NUM: each bit must be 0 or 1';
		end if;
		result := result * 2 + bit_value;
	end loop;

	return result;
end;
$$
LANGUAGE plpgsql
IMMUTABLE;
/* End - BIN_TO_NUM */
