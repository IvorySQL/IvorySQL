/***************************************************************
 *
 * UTL_ENCODE Package
 *
 * Oracle-compatible encoding/decoding utilities.
 *
 ***************************************************************
*/

/*
 * Register the C implementation in the sys schema.
 * Input/output use bytea (RAW maps to bytea in IvorySQL).
 * STRICT: returns NULL automatically when input is NULL.
 */
CREATE FUNCTION sys.utl_encode_base64_encode(bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ivorysql_utl_encode_base64_encode'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_encode_base64_decode(bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ivorysql_utl_encode_base64_decode'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

-- PL/iSQL package declaration
CREATE PACKAGE utl_encode AS

    /*
     * BASE64_ENCODE
     * Encodes binary RAW data to base64 format.
     * Each output line is 64 characters followed by a newline (RFC 1521).
     *
     * Parameters:
     *   r  IN RAW  - binary data to encode
     * Returns:
     *   RAW  - base64-encoded data as ASCII bytes with embedded newlines
     */
    FUNCTION base64_encode(r IN RAW) RETURN RAW;

    /*
     * BASE64_DECODE
     * Decodes base64-encoded RAW data back to binary.
     * Embedded whitespace (LF, CRLF, tab, space) is stripped before decoding.
     *
     * Parameters:
     *   r  IN RAW  - base64-encoded data to decode
     * Returns:
     *   RAW  - decoded binary data
     */
    FUNCTION base64_decode(r IN RAW) RETURN RAW;

    FUNCTION uuencode(r IN RAW, enc_type IN NUMBER DEFAULT 1,
                      filename IN VARCHAR2 DEFAULT NULL) RETURN RAW;
    FUNCTION uudecode(r IN RAW) RETURN RAW;
    FUNCTION quoted_printable_encode(r IN RAW) RETURN RAW;
    FUNCTION quoted_printable_decode(r IN RAW) RETURN RAW;
    FUNCTION mime_header_encode(r IN RAW, charset IN VARCHAR2 DEFAULT 'UTF-8',
                                encoding IN VARCHAR2 DEFAULT 'B') RETURN RAW;
    FUNCTION mime_header_decode(r IN RAW) RETURN RAW;
    FUNCTION text_encode(r IN RAW, charset IN VARCHAR2 DEFAULT 'UTF8',
                         encoding IN NUMBER DEFAULT 1) RETURN RAW;
    FUNCTION text_decode(r IN RAW, charset IN VARCHAR2 DEFAULT 'UTF8',
                         encoding IN NUMBER DEFAULT 1) RETURN RAW;

END utl_encode;

CREATE PACKAGE BODY utl_encode AS

    FUNCTION base64_encode(r IN RAW) RETURN RAW IS
    BEGIN
        RETURN utl_encode_base64_encode(r);
    END;

    FUNCTION base64_decode(r IN RAW) RETURN RAW IS
    BEGIN
        RETURN utl_encode_base64_decode(r);
    END;

    /* UUENCODE: 6-bit groups, 45 bytes per line, length prefix, header/footer */
    FUNCTION uuencode(r IN RAW, enc_type IN NUMBER DEFAULT 1,
                      filename IN VARCHAR2 DEFAULT NULL) RETURN RAW IS
        n INT;
        i INT;
        chunk INT;
        j INT;
        b1 INT;
        b2 INT;
        b3 INT;
        c INT;
        line TEXT;
        out_txt TEXT;
        fn TEXT;

        FUNCTION enc_char(v INT) RETURN TEXT IS
        BEGIN
            IF v = 0 THEN
                RETURN pg_catalog.chr(96);
            END IF;
            RETURN pg_catalog.chr(32 + v);
        END;
    BEGIN
        IF r IS NULL THEN
            RETURN NULL;
        END IF;
        fn := COALESCE(filename::TEXT, 'untitled');
        out_txt := 'begin 644 ' || fn || pg_catalog.chr(10);
        n := pg_catalog.length(r);
        i := 0;
        WHILE i < n LOOP
            chunk := least(45, n - i);
            line := pg_catalog.chr(32 + chunk);
            j := 0;
            WHILE j < chunk LOOP
                b1 := pg_catalog.get_byte(r, i + j);
                b2 := CASE WHEN j + 1 < chunk
                           THEN pg_catalog.get_byte(r, i + j + 1) ELSE 0 END;
                b3 := CASE WHEN j + 2 < chunk
                           THEN pg_catalog.get_byte(r, i + j + 2) ELSE 0 END;
                line := line
                     || enc_char((b1 >> 2) & 63)
                     || enc_char(((b1 & 3) << 4) | (b2 >> 4))
                     || enc_char(((b2 & 15) << 2) | (b3 >> 6))
                     || enc_char(b3 & 63);
                j := j + 3;
            END LOOP;
            out_txt := out_txt || line || pg_catalog.chr(10);
            i := i + chunk;
        END LOOP;
        out_txt := out_txt || '`' || pg_catalog.chr(10) || 'end'
                   || pg_catalog.chr(10);
        RETURN pg_catalog.convert_to(out_txt, 'UTF8');
    END;

    /* UUDECODE: ignore the begin/end lines, rebuild bytes from 6-bit groups */
    FUNCTION uudecode(r IN RAW) RETURN RAW IS
        txt TEXT;
        lines TEXT[];
        ln TEXT;
        k INT;
        pos INT;
        len INT;
        taken INT;
        idx INT;
        c1 INT;
        c2 INT;
        c3 INT;
        c4 INT;
        b1 INT;
        b2 INT;
        b3 INT;
        hex TEXT;

        FUNCTION dec_char(p TEXT) RETURN INT IS
            v INT;
        BEGIN
            IF p IS NULL OR p = '' THEN
                RETURN 0;
            END IF;
            v := pg_catalog.ascii(p) - 32;
            IF v = 64 THEN
                v := 0;
            END IF;
            RETURN v;
        END;
    BEGIN
        IF r IS NULL THEN
            RETURN NULL;
        END IF;
        txt := pg_catalog.convert_from(r, 'UTF8');
        hex := '';
        FOR k IN 1 .. pg_catalog.array_length(
                        pg_catalog.string_to_array(txt, pg_catalog.chr(10)), 1)
        LOOP
            ln := pg_catalog.split_part(txt, pg_catalog.chr(10), k);
            CONTINUE WHEN ln IS NULL OR ln = ''
                OR ln LIKE 'begin %' OR ln = 'end' OR ln LIKE '`%';
            len := pg_catalog.ascii(ln) - 32;
            IF len = 64 THEN
                len := 0;
            END IF;
            pos := 2;
            taken := 0;
            WHILE taken < len AND pos + 3 <= pg_catalog.length(ln) LOOP
                c1 := dec_char(pg_catalog.substr(ln, pos, 1));
                c2 := dec_char(pg_catalog.substr(ln, pos + 1, 1));
                c3 := dec_char(pg_catalog.substr(ln, pos + 2, 1));
                c4 := dec_char(pg_catalog.substr(ln, pos + 3, 1));
                b1 := (c1 << 2) | (c2 >> 4);
                b2 := ((c2 & 15) << 4) | (c3 >> 2);
                b3 := ((c3 & 3) << 6) | c4;
                hex := hex || pg_catalog.lpad(
                           pg_catalog.to_hex(b1), 2, '0');
                IF taken + 1 < len THEN
                    hex := hex || pg_catalog.lpad(
                               pg_catalog.to_hex(b2), 2, '0');
                END IF;
                IF taken + 2 < len THEN
                    hex := hex || pg_catalog.lpad(
                               pg_catalog.to_hex(b3), 2, '0');
                END IF;
                taken := taken + 3;
                pos := pos + 4;
            END LOOP;
        END LOOP;
        RETURN pg_catalog.decode(hex, 'hex');
    END;

    /* QUOTED_PRINTABLE_ENCODE: RFC 1521, space and every non-printable escaped */
    FUNCTION quoted_printable_encode(r IN RAW) RETURN RAW IS
        n INT;
        i INT;
        b INT;
        out_txt TEXT;
    BEGIN
        IF r IS NULL THEN
            RETURN NULL;
        END IF;
        n := pg_catalog.length(r);
        out_txt := '';
        i := 0;
        WHILE i < n LOOP
            b := pg_catalog.get_byte(r, i);
            IF b = 10 THEN
                out_txt := out_txt || pg_catalog.chr(10);
            ELSIF b = 32 THEN
                out_txt := out_txt || '=20';
            ELSIF b = 9 OR b = 13 OR (b >= 33 AND b <= 60) OR (b >= 62 AND b <= 126)
            THEN
                out_txt := out_txt || pg_catalog.chr(b);
            ELSE
                out_txt := out_txt || '=' || pg_catalog.upper(
                               pg_catalog.lpad(pg_catalog.to_hex(b), 2, '0'));
            END IF;
            i := i + 1;
        END LOOP;
        RETURN pg_catalog.convert_to(out_txt, 'UTF8');
    END;

    /* QUOTED_PRINTABLE_DECODE: =XX back to a byte, everything else literal */
    FUNCTION quoted_printable_decode(r IN RAW) RETURN RAW IS
        txt TEXT;
        n INT;
        i INT;
        ch TEXT;
        pair TEXT;
        hex TEXT;
    BEGIN
        IF r IS NULL THEN
            RETURN NULL;
        END IF;
        txt := pg_catalog.convert_from(r, 'UTF8');
        n := pg_catalog.length(txt);
        hex := '';
        i := 1;
        WHILE i <= n LOOP
            ch := pg_catalog.substr(txt, i, 1);
            IF ch = '=' AND i + 2 <= n THEN
                pair := pg_catalog.substr(txt, i + 1, 2);
                IF pair ~ '^[0-9A-Fa-f][0-9A-Fa-f]$' THEN
                    hex := hex || pg_catalog.lower(pair);
                    i := i + 3;
                    CONTINUE;
                END IF;
            END IF;
            hex := hex || pg_catalog.lpad(
                       pg_catalog.to_hex(pg_catalog.ascii(ch)), 2, '0');
            i := i + 1;
        END LOOP;
        RETURN pg_catalog.decode(hex, 'hex');
    END;

    /* MIME_HEADER_ENCODE: one RFC 2047 encoded word */
    FUNCTION mime_header_encode(r IN RAW, charset IN VARCHAR2 DEFAULT 'UTF-8',
                                encoding IN VARCHAR2 DEFAULT 'B') RETURN RAW IS
        payload TEXT;
        raw64 TEXT;
        k INT;
        nlines INT;
    BEGIN
        IF r IS NULL THEN
            RETURN NULL;
        END IF;
        /*
         * Strip the line breaks base64_encode inserts.  In Oracle mode an
         * empty literal is NULL, so replace(..., '') would return NULL;
         * concatenating the split parts keeps the payload.
         */
        raw64 := pg_catalog.convert_from(base64_encode(r), 'UTF8');
        nlines := pg_catalog.array_length(
                      pg_catalog.string_to_array(raw64, pg_catalog.chr(10)), 1);
        payload := '';
        FOR k IN 1 .. nlines LOOP
            payload := payload
                       || pg_catalog.split_part(raw64, pg_catalog.chr(10), k);
        END LOOP;
        RETURN pg_catalog.convert_to(
                   '=?' || COALESCE(charset::TEXT, 'UTF-8') || '?B?'
                   || payload || '?=', 'UTF8');
    END;

    /* MIME_HEADER_DECODE: strip the encoded-word wrapper, then base64 */
    FUNCTION mime_header_decode(r IN RAW) RETURN RAW IS
        txt TEXT;
        body TEXT;
        payload TEXT;
    BEGIN
        IF r IS NULL THEN
            RETURN NULL;
        END IF;
        txt := pg_catalog.convert_from(r, 'UTF8');
        body := txt;
        IF body LIKE '=?%' THEN
            payload := pg_catalog.substr(body, pg_catalog.strpos(body, '?B?') + 3);
            payload := pg_catalog.split_part(payload, '?=', 1);
            RETURN base64_decode(pg_catalog.convert_to(payload, 'UTF8'));
        END IF;
        RETURN r;
    END;

    /* TEXT_ENCODE / TEXT_DECODE: pass bytes through for UTF-8 input */
    FUNCTION text_encode(r IN RAW, charset IN VARCHAR2 DEFAULT 'UTF8',
                         encoding IN NUMBER DEFAULT 1) RETURN RAW IS
    BEGIN
        RETURN r;
    END;

    FUNCTION text_decode(r IN RAW, charset IN VARCHAR2 DEFAULT 'UTF8',
                         encoding IN NUMBER DEFAULT 1) RETURN RAW IS
    BEGIN
        RETURN r;
    END;

END utl_encode;
