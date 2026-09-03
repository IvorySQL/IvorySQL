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
		  WHEN 'BG_JOB_ID' THEN SELECT NULL INTO res;
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
		  WHEN 'FG_JOB_ID' THEN SELECT NULL INTO res;
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
		  WHEN 'SCHEDULER_JOB' THEN SELECT NULL INTO res;
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
