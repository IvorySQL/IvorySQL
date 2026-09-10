/***************************************************************
 *
 * DBMS_LOB Package
 *
 * Oracle-compatible LOB manipulation for oracle mode.  IvorySQL models
 * clob/nclob/blob as domains over text/bytea (value semantics, no LOB
 * locators), so the package operates on LOB values directly and the
 * locator-only subprograms (OPEN/CLOSE, CREATETEMPORARY, the FILE*
 * family, CONVERTTOBLOB/CONVERTTOCLOB) have no meaningful equivalent.
 *
 * Semantics verified against Oracle 23ai Free:
 *   - positions are 1-based; NUMBER arguments are truncated toward zero
 *     when fractional (SUBSTR('abcde', 2.7, 2.7) = 'bc')
 *   - SUBSTR: offset < 1, amount < 1, offset > length or amount > 32767
 *     -> NULL; amount is clamped to the end of the LOB
 *   - INSTR: offset < 1 or occurrence < 1 -> NULL, no match (including a
 *     pattern longer than the LOB, or offset > length) -> 0
 *   - COMPARE compares the first min(amount, remaining_1, remaining_2)
 *     characters and returns a strcmp-style result: -1 when lob_1 sorts
 *     before lob_2, +1 when it sorts after, 0 when equal over the whole
 *     compared range (amount-limited comparisons that match return 0).
 *     An exhausted side counts as empty: with pos beyond the LOB length
 *     the result is -1/+1 against the other side, and 0 when both are
 *     exhausted.  Returns NULL when either LOB is NULL or amount/offsets
 *     are NULL or < 1.
 *   - APPEND ignores a NULL source and initializes a NULL destination
 *     from the source (Oracle raises ORA-22275 for uninitialized
 *     locators, an error path that cannot exist in the value model)
 *   - COPY overwrites from dest_offset and preserves the rest of dest;
 *     when dest_offset extends beyond the destination end, the gap is
 *     padded with spaces (CLOB) or zero bytes (BLOB), as Oracle does
 *   - TRIM raises (ORA-21560 text) for a NULL/negative newlen and
 *     (ORA-22926 text) when newlen exceeds the current length
 *   - ERASE replaces with spaces (CLOB/NCLOB) or zero bytes (BLOB),
 *     reports the erased amount through its IN OUT argument (clamped to
 *     the LOB end), leaves the amount untouched when pos is beyond the
 *     end, and raises (ORA-21560 text) for NULL/negative amount or
 *     NULL/<1 pos
 *
 * The package body calls pg_catalog primitives explicitly (never its own
 * member names) so that unqualified member resolution cannot recurse.
 *
 ***************************************************************
*/

CREATE PACKAGE dbms_lob AS

    lobmaxsize CONSTANT NUMBER := 18446744073709551615;

    FUNCTION getlength(lob CLOB) RETURN NUMBER;
    FUNCTION getlength(lob NCLOB) RETURN NUMBER;
    FUNCTION getlength(lob BLOB) RETURN NUMBER;

    FUNCTION substr(lob CLOB, amount NUMBER DEFAULT 32767, pos NUMBER DEFAULT 1) RETURN VARCHAR2;
    FUNCTION substr(lob BLOB, amount NUMBER DEFAULT 32767, pos NUMBER DEFAULT 1) RETURN sys.raw;

    FUNCTION instr(lob CLOB, pattern CLOB, pos NUMBER DEFAULT 1, occurrence NUMBER DEFAULT 1) RETURN NUMBER;
    FUNCTION instr(lob BLOB, pattern sys.raw, pos NUMBER DEFAULT 1, occurrence NUMBER DEFAULT 1) RETURN NUMBER;

    FUNCTION compare(lob_1 CLOB, lob_2 CLOB, amount NUMBER DEFAULT 18446744073709551615,
                     pos_1 NUMBER DEFAULT 1, pos_2 NUMBER DEFAULT 1) RETURN NUMBER;
    FUNCTION compare(lob_1 BLOB, lob_2 BLOB, amount NUMBER DEFAULT 18446744073709551615,
                     pos_1 NUMBER DEFAULT 1, pos_2 NUMBER DEFAULT 1) RETURN NUMBER;

    PROCEDURE append(dest_lob IN OUT CLOB, src_lob CLOB);
    PROCEDURE append(dest_lob IN OUT BLOB, src_lob BLOB);

    PROCEDURE copy(dest_lob IN OUT CLOB, src_lob CLOB, amount NUMBER DEFAULT 18446744073709551615,
                   dest_pos NUMBER DEFAULT 1, src_pos NUMBER DEFAULT 1);
    PROCEDURE copy(dest_lob IN OUT BLOB, src_lob BLOB, amount NUMBER DEFAULT 18446744073709551615,
                   dest_pos NUMBER DEFAULT 1, src_pos NUMBER DEFAULT 1);

    PROCEDURE trim(dest_lob IN OUT CLOB, newlen NUMBER);
    PROCEDURE trim(dest_lob IN OUT BLOB, newlen NUMBER);

    PROCEDURE erase(dest_lob IN OUT CLOB, amount IN OUT NUMBER, pos NUMBER DEFAULT 1);
    PROCEDURE erase(dest_lob IN OUT BLOB, amount IN OUT NUMBER, pos NUMBER DEFAULT 1);

END;

CREATE PACKAGE BODY dbms_lob AS

    FUNCTION getlength(lob CLOB) RETURN NUMBER IS
    BEGIN
        RETURN pg_catalog.length(lob);
    END;

    FUNCTION getlength(lob NCLOB) RETURN NUMBER IS
    BEGIN
        RETURN pg_catalog.length(lob);
    END;

    FUNCTION getlength(lob BLOB) RETURN NUMBER IS
    BEGIN
        RETURN pg_catalog.octet_length(lob);
    END;

    FUNCTION substr(lob CLOB, amount NUMBER DEFAULT 32767, pos NUMBER DEFAULT 1) RETURN VARCHAR2 IS
        v_pos int;
        v_amount int;
    BEGIN
        IF lob IS NULL OR amount IS NULL OR pos IS NULL THEN
            RETURN NULL;
        END IF;
        v_pos := pg_catalog.trunc(pos);
        v_amount := pg_catalog.trunc(amount);
        IF v_pos < 1 OR v_amount < 1 OR v_amount > 32767
           OR v_pos > pg_catalog.length(lob) THEN
            RETURN NULL;
        END IF;
        RETURN pg_catalog.substr(lob, v_pos, v_amount);
    END;

    FUNCTION substr(lob BLOB, amount NUMBER DEFAULT 32767, pos NUMBER DEFAULT 1) RETURN sys.raw IS
        v_pos int;
        v_amount int;
    BEGIN
        IF lob IS NULL OR amount IS NULL OR pos IS NULL THEN
            RETURN NULL;
        END IF;
        v_pos := pg_catalog.trunc(pos);
        v_amount := pg_catalog.trunc(amount);
        IF v_pos < 1 OR v_amount < 1 OR v_amount > 32767
           OR v_pos > pg_catalog.octet_length(lob) THEN
            RETURN NULL;
        END IF;
        RETURN pg_catalog.substr(lob, v_pos, v_amount);
    END;

    FUNCTION instr(lob CLOB, pattern CLOB, pos NUMBER DEFAULT 1, occurrence NUMBER DEFAULT 1) RETURN NUMBER IS
    BEGIN
        IF lob IS NULL OR pattern IS NULL OR pos IS NULL OR occurrence IS NULL THEN
            RETURN NULL;
        END IF;
        IF trunc(pos) < 1 OR trunc(occurrence) < 1 THEN
            RETURN NULL;
        END IF;
        RETURN sys.instr(lob, pattern, trunc(pos)::int, trunc(occurrence)::int);
    END;

    FUNCTION instr(lob BLOB, pattern sys.raw, pos NUMBER DEFAULT 1, occurrence NUMBER DEFAULT 1) RETURN NUMBER IS
        v_pos int;
        v_start int;
        v_found int;
        v_matches int;
    BEGIN
        IF lob IS NULL OR pattern IS NULL OR pos IS NULL OR occurrence IS NULL THEN
            RETURN NULL;
        END IF;
        v_start := pg_catalog.trunc(pos);
        IF v_start < 1 OR trunc(occurrence) < 1 THEN
            RETURN NULL;
        END IF;
        v_found := 0;
        v_matches := 0;
        FOR i IN 1..trunc(occurrence)::int LOOP
            v_pos := position(pattern IN pg_catalog.substr(lob, v_start, 2147483647));
            EXIT WHEN v_pos = 0;
            v_found := v_start + v_pos - 1;
            v_start := v_found + pg_catalog.octet_length(pattern);
            v_matches := v_matches + 1;
        END LOOP;
        IF v_matches = trunc(occurrence) THEN
            RETURN v_found;
        END IF;
        RETURN 0;
    END;

    FUNCTION compare(lob_1 CLOB, lob_2 CLOB, amount NUMBER DEFAULT 18446744073709551615,
                     pos_1 NUMBER DEFAULT 1, pos_2 NUMBER DEFAULT 1) RETURN NUMBER IS
        v_p1 int;
        v_p2 int;
        v_amt number;
        v_eff1 int;
        v_eff2 int;
        v_n int;
        v_c1 varchar2;
        v_c2 varchar2;
    BEGIN
        IF lob_1 IS NULL OR lob_2 IS NULL OR amount IS NULL
           OR pos_1 IS NULL OR pos_2 IS NULL THEN
            RETURN NULL;
        END IF;
        v_amt := pg_catalog.trunc(amount);
        v_p1 := pg_catalog.trunc(pos_1);
        v_p2 := pg_catalog.trunc(pos_2);
        IF v_amt < 1 OR v_p1 < 1 OR v_p2 < 1 THEN
            RETURN NULL;
        END IF;
        v_eff1 := greatest(pg_catalog.length(lob_1) - v_p1 + 1, 0);
        v_eff2 := greatest(pg_catalog.length(lob_2) - v_p2 + 1, 0);
        v_n := least(v_amt, v_eff1, v_eff2);
        FOR i IN 1..v_n LOOP
            v_c1 := pg_catalog.substr(lob_1, v_p1 + i - 1, 1);
            v_c2 := pg_catalog.substr(lob_2, v_p2 + i - 1, 1);
            IF v_c1 IS DISTINCT FROM v_c2 THEN
                IF pg_catalog.ascii(v_c1) > pg_catalog.ascii(v_c2) THEN
                    RETURN 1;
                END IF;
                RETURN -1;
            END IF;
        END LOOP;
        IF v_amt <= v_n THEN
            RETURN 0;
        END IF;
        IF v_eff1 < v_eff2 THEN
            RETURN -1;
        END IF;
        IF v_eff1 > v_eff2 THEN
            RETURN 1;
        END IF;
        RETURN 0;
    END;

    FUNCTION compare(lob_1 BLOB, lob_2 BLOB, amount NUMBER DEFAULT 18446744073709551615,
                     pos_1 NUMBER DEFAULT 1, pos_2 NUMBER DEFAULT 1) RETURN NUMBER IS
        v_p1 int;
        v_p2 int;
        v_amt number;
        v_eff1 int;
        v_eff2 int;
        v_n int;
        v_c1 sys.raw;
        v_c2 sys.raw;
    BEGIN
        IF lob_1 IS NULL OR lob_2 IS NULL OR amount IS NULL
           OR pos_1 IS NULL OR pos_2 IS NULL THEN
            RETURN NULL;
        END IF;
        v_amt := pg_catalog.trunc(amount);
        v_p1 := pg_catalog.trunc(pos_1);
        v_p2 := pg_catalog.trunc(pos_2);
        IF v_amt < 1 OR v_p1 < 1 OR v_p2 < 1 THEN
            RETURN NULL;
        END IF;
        v_eff1 := greatest(pg_catalog.octet_length(lob_1) - v_p1 + 1, 0);
        v_eff2 := greatest(pg_catalog.octet_length(lob_2) - v_p2 + 1, 0);
        v_n := least(v_amt, v_eff1, v_eff2);
        FOR i IN 1..v_n LOOP
            v_c1 := pg_catalog.substr(lob_1, v_p1 + i - 1, 1);
            v_c2 := pg_catalog.substr(lob_2, v_p2 + i - 1, 1);
            IF v_c1 IS DISTINCT FROM v_c2 THEN
                IF pg_catalog.get_byte(v_c1, 0) > pg_catalog.get_byte(v_c2, 0) THEN
                    RETURN 1;
                END IF;
                RETURN -1;
            END IF;
        END LOOP;
        IF v_amt <= v_n THEN
            RETURN 0;
        END IF;
        IF v_eff1 < v_eff2 THEN
            RETURN -1;
        END IF;
        IF v_eff1 > v_eff2 THEN
            RETURN 1;
        END IF;
        RETURN 0;
    END;

    PROCEDURE append(dest_lob IN OUT CLOB, src_lob CLOB) IS
    BEGIN
        IF src_lob IS NULL THEN
            RETURN;
        END IF;
        IF dest_lob IS NULL THEN
            dest_lob := src_lob;
        ELSE
            dest_lob := dest_lob || src_lob;
        END IF;
    END;

    PROCEDURE append(dest_lob IN OUT BLOB, src_lob BLOB) IS
    BEGIN
        IF src_lob IS NULL THEN
            RETURN;
        END IF;
        IF dest_lob IS NULL THEN
            dest_lob := src_lob;
        ELSE
            dest_lob := dest_lob || src_lob;
        END IF;
    END;

    PROCEDURE copy(dest_lob IN OUT CLOB, src_lob CLOB, amount NUMBER DEFAULT 18446744073709551615,
                   dest_pos NUMBER DEFAULT 1, src_pos NUMBER DEFAULT 1) IS
        v_dpos int;
        v_spos int;
        v_amount number;
        v_amt int;
        v_gap int;
    BEGIN
        IF src_lob IS NULL OR amount IS NULL OR dest_pos IS NULL OR src_pos IS NULL THEN
            RETURN;
        END IF;
        v_dpos := pg_catalog.trunc(dest_pos);
        v_spos := pg_catalog.trunc(src_pos);
        v_amount := pg_catalog.trunc(amount);
        IF v_dpos < 1 OR v_spos < 1 OR v_amount < 1
           OR v_spos > pg_catalog.length(src_lob) THEN
            RETURN;
        END IF;
        v_amt := least(v_amount, pg_catalog.length(src_lob) - v_spos + 1)::int;
        v_gap := greatest(v_dpos - 1 - pg_catalog.length(dest_lob), 0);
        IF dest_lob IS NULL THEN
            dest_lob := pg_catalog.substr(src_lob, v_spos, v_amt);
        ELSE
            dest_lob := pg_catalog.substr(dest_lob, 1, v_dpos - 1)
                        || pg_catalog.repeat(' ', v_gap)
                        || pg_catalog.substr(src_lob, v_spos, v_amt)
                        || pg_catalog.substr(dest_lob, v_dpos + v_amt, 2147483647);
        END IF;
    END;

    PROCEDURE copy(dest_lob IN OUT BLOB, src_lob BLOB, amount NUMBER DEFAULT 18446744073709551615,
                   dest_pos NUMBER DEFAULT 1, src_pos NUMBER DEFAULT 1) IS
        v_dpos int;
        v_spos int;
        v_amount number;
        v_amt int;
        v_gap int;
    BEGIN
        IF src_lob IS NULL OR amount IS NULL OR dest_pos IS NULL OR src_pos IS NULL THEN
            RETURN;
        END IF;
        v_dpos := pg_catalog.trunc(dest_pos);
        v_spos := pg_catalog.trunc(src_pos);
        v_amount := pg_catalog.trunc(amount);
        IF v_dpos < 1 OR v_spos < 1 OR v_amount < 1
           OR v_spos > pg_catalog.octet_length(src_lob) THEN
            RETURN;
        END IF;
        v_amt := least(v_amount, pg_catalog.octet_length(src_lob) - v_spos + 1)::int;
        v_gap := greatest(v_dpos - 1 - pg_catalog.octet_length(dest_lob), 0);
        IF dest_lob IS NULL THEN
            dest_lob := pg_catalog.substr(src_lob, v_spos, v_amt);
        ELSE
            dest_lob := pg_catalog.substr(dest_lob, 1, v_dpos - 1)
                        || pg_catalog.decode(pg_catalog.repeat('0', v_gap * 2), 'hex')
                        || pg_catalog.substr(src_lob, v_spos, v_amt)
                        || pg_catalog.substr(dest_lob, v_dpos + v_amt, 2147483647);
        END IF;
    END;

    PROCEDURE trim(dest_lob IN OUT CLOB, newlen NUMBER) IS
    BEGIN
        IF dest_lob IS NULL THEN
            RETURN;
        END IF;
        IF newlen IS NULL OR newlen < 0 THEN
            RAISE EXCEPTION 'argument 2 is null, invalid, or out of range';
        END IF;
        IF newlen > pg_catalog.length(dest_lob) THEN
            RAISE EXCEPTION 'specified trim length is greater than current LOB value''s length';
        END IF;
        dest_lob := pg_catalog.substr(dest_lob, 1, pg_catalog.trunc(newlen)::int);
    END;

    PROCEDURE trim(dest_lob IN OUT BLOB, newlen NUMBER) IS
    BEGIN
        IF dest_lob IS NULL THEN
            RETURN;
        END IF;
        IF newlen IS NULL OR newlen < 0 THEN
            RAISE EXCEPTION 'argument 2 is null, invalid, or out of range';
        END IF;
        IF newlen > pg_catalog.octet_length(dest_lob) THEN
            RAISE EXCEPTION 'specified trim length is greater than current LOB value''s length';
        END IF;
        dest_lob := pg_catalog.substr(dest_lob, 1, pg_catalog.trunc(newlen)::int);
    END;

    PROCEDURE erase(dest_lob IN OUT CLOB, amount IN OUT NUMBER, pos NUMBER DEFAULT 1) IS
        v_pos int;
        v_amount number;
        v_erase int;
    BEGIN
        IF amount IS NULL THEN
            RAISE EXCEPTION 'argument 2 is null, invalid, or out of range';
        END IF;
        IF pos IS NULL THEN
            RAISE EXCEPTION 'argument 3 is null, invalid, or out of range';
        END IF;
        v_pos := pg_catalog.trunc(pos);
        v_amount := pg_catalog.trunc(amount);
        IF v_amount < 0 THEN
            RAISE EXCEPTION 'argument 2 is null, invalid, or out of range';
        END IF;
        IF v_pos < 1 THEN
            RAISE EXCEPTION 'argument 3 is null, invalid, or out of range';
        END IF;
        IF dest_lob IS NULL OR v_pos > pg_catalog.length(dest_lob) THEN
            RETURN;
        END IF;
        v_erase := least(v_amount, pg_catalog.length(dest_lob) - v_pos + 1)::int;
        IF v_erase > 0 THEN
            dest_lob := pg_catalog.substr(dest_lob, 1, v_pos - 1)
                        || pg_catalog.repeat(' ', v_erase)
                        || pg_catalog.substr(dest_lob, v_pos + v_erase, 2147483647);
        END IF;
        amount := v_erase;
    END;

    PROCEDURE erase(dest_lob IN OUT BLOB, amount IN OUT NUMBER, pos NUMBER DEFAULT 1) IS
        v_pos int;
        v_amount number;
        v_erase int;
    BEGIN
        IF amount IS NULL THEN
            RAISE EXCEPTION 'argument 2 is null, invalid, or out of range';
        END IF;
        IF pos IS NULL THEN
            RAISE EXCEPTION 'argument 3 is null, invalid, or out of range';
        END IF;
        v_pos := pg_catalog.trunc(pos);
        v_amount := pg_catalog.trunc(amount);
        IF v_amount < 0 THEN
            RAISE EXCEPTION 'argument 2 is null, invalid, or out of range';
        END IF;
        IF v_pos < 1 THEN
            RAISE EXCEPTION 'argument 3 is null, invalid, or out of range';
        END IF;
        IF dest_lob IS NULL OR v_pos > pg_catalog.octet_length(dest_lob) THEN
            RETURN;
        END IF;
        v_erase := least(v_amount, pg_catalog.octet_length(dest_lob) - v_pos + 1)::int;
        IF v_erase > 0 THEN
            dest_lob := pg_catalog.substr(dest_lob, 1, v_pos - 1)
                        || pg_catalog.decode(pg_catalog.repeat('0', v_erase * 2), 'hex')
                        || pg_catalog.substr(dest_lob, v_pos + v_erase, 2147483647);
        END IF;
        amount := v_erase;
    END;

END;
