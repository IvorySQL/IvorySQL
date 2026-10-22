/***************************************************************
 *
 * DBMS_XMLGEN Package
 *
 * Oracle-compatible conversion of a query result set to XML.
 *
 ***************************************************************/

CREATE OR REPLACE PACKAGE dbms_xmlgen IS
    /*
     * GETXML returns the rows of a query as one document:
     *
     *   <?xml version="1.0"?>
     *   <ROWSET>
     *     <ROW>
     *       <COLUMN>value</COLUMN>
     *     </ROW>
     *   </ROWSET>
     *
     * Column names go through the same case translation as the data
     * dictionary, a NULL column becomes an empty element (<COLUMN/>), and
     * character data is escaped.  A query with no rows yields <ROWSET/>.
     */
    FUNCTION GETXML(query_string VARCHAR2) RETURN TEXT;

    /*
     * Context handles.  NEWCONTEXT stores the query and returns a handle that
     * can be tuned with SETMAXROWS / SETSKIPROWS / SETROWSETTAG / SETROWTAG and
     * rendered with GETXML(ctx); CLOSECONTEXT releases it.
     */
    FUNCTION NEWCONTEXT(query_string VARCHAR2) RETURN NUMBER;
    FUNCTION GETXML(ctx_handle NUMBER) RETURN TEXT;
    PROCEDURE SETMAXROWS(ctx_handle NUMBER, max_rows NUMBER);
    PROCEDURE SETSKIPROWS(ctx_handle NUMBER, skip_rows NUMBER);
    PROCEDURE SETROWSETTAG(ctx_handle NUMBER, rowset_tag VARCHAR2);
    PROCEDURE SETROWTAG(ctx_handle NUMBER, row_tag VARCHAR2);
    PROCEDURE CLOSECONTEXT(ctx_handle NUMBER);
    FUNCTION GETNUMROWSPROCESSED(ctx_handle NUMBER) RETURN NUMBER;
END;

CREATE OR REPLACE PACKAGE BODY dbms_xmlgen IS
    -- Context state, indexed by handle.  Index 0 is the "no context" slot
    -- used by GETXML(query_string) and never stores anything.
    g_query TEXT[] := ARRAY[]::TEXT[];
    g_maxrows INTEGER[] := ARRAY[]::INTEGER[];
    g_skiprows INTEGER[] := ARRAY[]::INTEGER[];
    g_rowsettag TEXT[] := ARRAY[]::TEXT[];
    g_rowtag TEXT[] := ARRAY[]::TEXT[];
    g_processed INTEGER[] := ARRAY[]::INTEGER[];
    g_last_handle INTEGER := 0;

    FUNCTION render(handle NUMBER, query_string TEXT, max_rows NUMBER,
                    skip_rows NUMBER, rowset_tag TEXT, row_tag TEXT)
        RETURN TEXT IS
        rec RECORD;
        kv RECORD;
        doc TEXT;
        val TEXT;
        tag TEXT;
        seen INTEGER := 0;
        emitted INTEGER := 0;
    BEGIN
        IF query_string IS NULL THEN
            RETURN NULL;
        END IF;
        doc := '<?xml version="1.0"?>' || CHR(10) || '<' || rowset_tag || '>';
        FOR rec IN EXECUTE query_string LOOP
            seen := seen + 1;
            CONTINUE WHEN seen <= skip_rows;
            EXIT WHEN max_rows IS NOT NULL AND emitted >= max_rows;
            emitted := emitted + 1;
            doc := doc || CHR(10) || '  <' || row_tag || '>';
            FOR kv IN SELECT key, value FROM JSON_EACH_TEXT(TO_JSON(rec)) LOOP
                tag := SYS.ORA_CASE_TRANS(kv.KEY::VARCHAR2);
                val := kv.VALUE;
                IF val IS NULL THEN
                    doc := doc || CHR(10) || '    <' || tag || '/>';
                ELSE
                    val := REPLACE(REPLACE(REPLACE(val, '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
                    doc := doc || CHR(10) || '    <' || tag || '>' || val || '</' || tag || '>';
                END IF;
            END LOOP;
            doc := doc || CHR(10) || '  </' || row_tag || '>';
        END LOOP;
        IF handle > 0 THEN
            g_processed[handle] := emitted;
        END IF;
        IF emitted = 0 THEN
            RETURN '<?xml version="1.0"?>' || CHR(10) || '<' || rowset_tag || '/>';
        END IF;
        RETURN doc || CHR(10) || '</' || rowset_tag || '>';
    END;

    FUNCTION GETXML(query_string VARCHAR2) RETURN TEXT IS
    BEGIN
        RETURN render(0, query_string, NULL, 0, 'ROWSET', 'ROW');
    END;

    FUNCTION NEWCONTEXT(query_string VARCHAR2) RETURN NUMBER IS
        h INTEGER;
    BEGIN
        IF query_string IS NULL THEN
            RETURN NULL;
        END IF;
        g_last_handle := g_last_handle + 1;
        h := g_last_handle;
        g_query[h] := query_string;
        g_maxrows[h] := NULL;
        g_skiprows[h] := 0;
        g_rowsettag[h] := 'ROWSET';
        g_rowtag[h] := 'ROW';
        g_processed[h] := 0;
        RETURN h;
    END;

    FUNCTION GETXML(ctx_handle NUMBER) RETURN TEXT IS
    BEGIN
        IF ctx_handle IS NULL OR g_query[ctx_handle] IS NULL THEN
            RAISE EXCEPTION 'DBMS_XMLGEN: invalid context handle %', ctx_handle;
        END IF;
        RETURN render(ctx_handle, g_query[ctx_handle], g_maxrows[ctx_handle],
                      g_skiprows[ctx_handle], g_rowsettag[ctx_handle],
                      g_rowtag[ctx_handle]);
    END;

    PROCEDURE SETMAXROWS(ctx_handle NUMBER, max_rows NUMBER) IS
    BEGIN
        g_maxrows[ctx_handle] := max_rows;
    END;

    PROCEDURE SETSKIPROWS(ctx_handle NUMBER, skip_rows NUMBER) IS
    BEGIN
        g_skiprows[ctx_handle] := coalesce(skip_rows, 0);
    END;

    PROCEDURE SETROWSETTAG(ctx_handle NUMBER, rowset_tag VARCHAR2) IS
    BEGIN
        IF rowset_tag IS NOT NULL THEN
            g_rowsettag[ctx_handle] := rowset_tag;
        END IF;
    END;

    PROCEDURE SETROWTAG(ctx_handle NUMBER, row_tag VARCHAR2) IS
    BEGIN
        IF row_tag IS NOT NULL THEN
            g_rowtag[ctx_handle] := row_tag;
        END IF;
    END;

    PROCEDURE CLOSECONTEXT(ctx_handle NUMBER) IS
    BEGIN
        IF ctx_handle IS NOT NULL AND ctx_handle <= g_last_handle THEN
            g_query[ctx_handle] := NULL;
            g_maxrows[ctx_handle] := NULL;
            g_skiprows[ctx_handle] := NULL;
            g_rowsettag[ctx_handle] := NULL;
            g_rowtag[ctx_handle] := NULL;
            g_processed[ctx_handle] := NULL;
        END IF;
    END;

    FUNCTION GETNUMROWSPROCESSED(ctx_handle NUMBER) RETURN NUMBER IS
    BEGIN
        RETURN coalesce(g_processed[ctx_handle], 0);
    END;
END;

GRANT EXECUTE ON PACKAGE dbms_xmlgen TO PUBLIC;
