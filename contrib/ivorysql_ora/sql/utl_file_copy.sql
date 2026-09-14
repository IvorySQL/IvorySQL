-- FCOPY must preserve bytes and count lines independently of buffer boundaries.
INSERT INTO sys.utl_file_directory(dirname, dir)
SELECT 'fcopy_test', current_setting('data_directory');

CREATE FUNCTION fcopy_fixture(filename text, payload bytea) RETURNS void
AS $$
DECLARE
    object_id oid;
BEGIN
    object_id := lo_from_bytea(0, payload);
    PERFORM lo_export(object_id, current_setting('data_directory') || '/' || filename);
    PERFORM lo_unlink(object_id);
END;
$$ LANGUAGE plpgsql;
/

CREATE FUNCTION fcopy_shell_quote(value text) RETURNS text
AS $$
BEGIN
    RETURN $q$'$q$ || replace(value, $q$'$q$, $q$'\''$q$) || $q$'$q$;
END;
$$ LANGUAGE plpgsql;
/

CREATE FUNCTION fcopy_link_fixture(kind text, linkname text) RETURNS void
AS $$
DECLARE
    data_dir text := current_setting('data_directory');
    link_path text := data_dir || '/' || linkname;
    source_path text := data_dir || '/fcopy-source';
    command text;
BEGIN
    BEGIN
        PERFORM sys.ora_utl_file_fremove('fcopy_test', linkname);
    EXCEPTION
        WHEN others THEN
            NULL;
    END;

    IF kind = 'hard' THEN
        command := 'ln ' || fcopy_shell_quote(source_path) || ' ' ||
            fcopy_shell_quote(link_path);
    ELSIF kind = 'symbolic' THEN
        command := 'ln -s ' || fcopy_shell_quote('fcopy-source') || ' ' ||
            fcopy_shell_quote(link_path);
    ELSE
        RAISE EXCEPTION 'unexpected link kind: %', kind;
    END IF;

    EXECUTE format('COPY (SELECT NULL::text WHERE false) TO PROGRAM %L', command);
END;
$$ LANGUAGE plpgsql;
/

CREATE TABLE fcopy_cases (
    name text PRIMARY KEY,
    first_line bytea,
    middle_line bytea,
    last_line bytea
);
INSERT INTO fcopy_cases VALUES
    ('short', decode('616263', 'hex'), decode('646566', 'hex'), decode('676869', 'hex')),
    ('nul', decode('00610062', 'hex'), decode('63006400', 'hex'), decode('0065', 'hex')),
    ('empty_lines', substring(decode('00', 'hex'), 1, 0),
        substring(decode('00', 'hex'), 1, 0), substring(decode('00', 'hex'), 1, 0)),
    ('crlf', decode('610d', 'hex'), decode('620d', 'hex'), decode('630d', 'hex')),
    ('ctrl_z', decode('611a62', 'hex'), decode('631a64', 'hex'), decode('651a66', 'hex')),
    ('utf8', decode('e4b8ade69687', 'hex'), decode('c3a9f09f9880', 'hex'), decode('e697a5', 'hex')),
    ('buffer_edge', convert_to(repeat('a', 8191), 'UTF8'),
        convert_to(repeat('b', 8192), 'UTF8'), convert_to(repeat('c', 8193), 'UTF8')),
    ('long', convert_to(repeat('a', 70000), 'UTF8'),
        decode('00', 'hex') || convert_to(repeat('b', 65536), 'UTF8'),
        convert_to(repeat('c', 32768), 'UTF8'));

CREATE FUNCTION fcopy_verify(case_name text, first_no integer, last_no integer)
RETURNS boolean AS $$
DECLARE
    fixture fcopy_cases%ROWTYPE;
    payload bytea;
    expected bytea := substring(decode('00', 'hex'), 1, 0);
    lines bytea[];
    i integer;
BEGIN
    SELECT * INTO STRICT fixture FROM fcopy_cases WHERE name = case_name;
    lines := ARRAY[fixture.first_line || decode('0a', 'hex'),
                   fixture.middle_line || decode('0a', 'hex'), fixture.last_line];
    payload := lines[1] || lines[2] || lines[3];
    PERFORM fcopy_fixture('fcopy-source', payload);
    -- A shorter copy must discard the old destination tail.
    PERFORM fcopy_fixture('fcopy-destination', payload || payload || decode('ffff', 'hex'));
    PERFORM sys.ora_utl_file_fcopy('fcopy_test', 'fcopy-source',
        'fcopy_test', 'fcopy-destination', first_no, last_no);
    FOR i IN 1..3 LOOP
        IF i >= first_no AND i <= last_no THEN
            expected := expected || lines[i];
        END IF;
    END LOOP;
    RETURN pg_read_binary_file('fcopy-destination') = expected
        AND pg_read_binary_file('fcopy-source') = payload;
END;
$$ LANGUAGE plpgsql;
/

-- The final line is deliberately unterminated; the range includes both ends.
SELECT name, bool_and(fcopy_verify(name, first_no, last_no)) AS all_ranges_match
FROM fcopy_cases CROSS JOIN generate_series(1, 5) AS first_no
    CROSS JOIN generate_series(1, 5) AS last_no
GROUP BY name ORDER BY name;

-- Exercise omitted and explicitly NULL bounds, including an empty source.
SELECT fcopy_fixture('fcopy-source', decode('6100620a630064', 'hex'));
SELECT sys.ora_utl_file_fcopy('fcopy_test', 'fcopy-source', 'fcopy_test', 'fcopy-destination');
SELECT encode(pg_read_binary_file('fcopy-destination'), 'hex') AS whole_file;
SELECT sys.ora_utl_file_fcopy('fcopy_test', 'fcopy-source', 'fcopy_test', 'fcopy-destination', 2);
SELECT encode(pg_read_binary_file('fcopy-destination'), 'hex') AS from_second_line;
SELECT sys.ora_utl_file_fcopy('fcopy_test', 'fcopy-source', 'fcopy_test', 'fcopy-destination', NULL, NULL);
SELECT encode(pg_read_binary_file('fcopy-destination'), 'hex') AS null_bounds;
SELECT fcopy_fixture('fcopy-source', substring(decode('00', 'hex'), 1, 0));
SELECT sys.ora_utl_file_fcopy('fcopy_test', 'fcopy-source', 'fcopy_test', 'fcopy-destination');
SELECT octet_length(pg_read_binary_file('fcopy-destination')) AS empty_copy;

-- Self-copy must fail before truncation, including directory, hard-link, and
-- symbolic-link aliases.
SELECT fcopy_fixture('fcopy-source', decode('70726573657276650a', 'hex'));
SELECT sys.ora_utl_file_fcopy('fcopy_test', 'fcopy-source', 'fcopy_test', 'fcopy-source');
SELECT encode(pg_read_binary_file('fcopy-source'), 'hex') AS after_self_copy;
INSERT INTO sys.utl_file_directory(dirname, dir)
SELECT 'fcopy_alias', current_setting('data_directory');
SELECT sys.ora_utl_file_fcopy('fcopy_test', 'fcopy-source', 'fcopy_alias', 'fcopy-source', 2, 2);
SELECT encode(pg_read_binary_file('fcopy-source'), 'hex') AS after_alias_copy;
SELECT fcopy_link_fixture('hard', 'fcopy-hard-source');
SELECT sys.ora_utl_file_fcopy('fcopy_test', 'fcopy-hard-source', 'fcopy_test', 'fcopy-source', 1, 1);
SELECT encode(pg_read_binary_file('fcopy-source'), 'hex') AS after_hard_link_copy;
SELECT fcopy_link_fixture('symbolic', 'fcopy-symlink-source');
SELECT sys.ora_utl_file_fcopy('fcopy_test', 'fcopy-symlink-source', 'fcopy_test', 'fcopy-source', 1, 1);
SELECT encode(pg_read_binary_file('fcopy-source'), 'hex') AS after_symlink_copy;

-- Parameter validation must precede opening or truncating the destination.
SELECT fcopy_fixture('fcopy-destination', decode('6b656570', 'hex'));
SELECT sys.ora_utl_file_fcopy('fcopy_test', 'fcopy-source', 'fcopy_test', 'fcopy-destination', 0, 1);
SELECT sys.ora_utl_file_fcopy('fcopy_test', 'fcopy-source', 'fcopy_test', 'fcopy-destination', 1, 0);
SELECT sys.ora_utl_file_fcopy('fcopy_test', 'fcopy-source', 'fcopy_test', 'fcopy-destination', -1, 2);
SELECT encode(pg_read_binary_file('fcopy-destination'), 'hex') AS after_invalid_bounds;

-- Recovery after errors must leave copying usable in the same session.
SELECT sys.ora_utl_file_fcopy('fcopy_test', 'fcopy-source', 'fcopy_test', 'fcopy-destination');
SELECT pg_read_binary_file('fcopy-source') = pg_read_binary_file('fcopy-destination') AS recovered;
SELECT sys.ora_utl_file_fremove('fcopy_test', 'fcopy-hard-source');
SELECT sys.ora_utl_file_fremove('fcopy_test', 'fcopy-symlink-source');
SELECT sys.ora_utl_file_fremove('fcopy_test', 'fcopy-source');
SELECT sys.ora_utl_file_fremove('fcopy_test', 'fcopy-destination');
DELETE FROM sys.utl_file_directory WHERE dirname IN ('fcopy_test', 'fcopy_alias');
DROP FUNCTION fcopy_verify(text, integer, integer);
DROP FUNCTION fcopy_link_fixture(text, text);
DROP FUNCTION fcopy_shell_quote(text);
DROP FUNCTION fcopy_fixture(text, bytea);
DROP TABLE fcopy_cases;
