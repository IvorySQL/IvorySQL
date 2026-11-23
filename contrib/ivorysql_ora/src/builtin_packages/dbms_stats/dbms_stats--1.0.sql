/*
 * Copyright 2026 IvorySQL Global Development Team
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy at http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


-- All helpers are invoker rights. Never expose pg_statistic through a definer.
CREATE FUNCTION sys.ora_stats_ident(raw_name text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET ivorysql.identifier_case_switch = normal SET search_path = pg_catalog, pg_temp AS $$
DECLARE parts text[];
BEGIN
  IF raw_name IS NULL OR raw_name = '' THEN
    RAISE EXCEPTION 'statistics object name must not be null' USING ERRCODE = '22004';
  END IF;
  parts := pg_catalog.parse_ident(raw_name, true);
  IF cardinality(parts) <> 1 OR octet_length(parts[1]) > 63 THEN
    RAISE EXCEPTION 'expected a single identifier of at most 63 bytes' USING ERRCODE = '42602';
  END IF;
  RETURN parts[1];
END $$;

CREATE FUNCTION sys.ora_stats_relation(ownname text, tabname text) RETURNS oid
LANGUAGE plpgsql VOLATILE SET ivorysql.identifier_case_switch = normal SET search_path = pg_catalog, pg_temp AS $$
DECLARE ns text := sys.ora_stats_ident(ownname);
        nm text := sys.ora_stats_ident(tabname);
        obj oid; kind "char";
BEGIN
  obj := pg_catalog.to_regclass(pg_catalog.format('%I.%I', ns, nm));
  IF obj IS NULL THEN
    RAISE EXCEPTION 'statistics target %.% does not exist', ns, nm USING ERRCODE = '42P01';
  END IF;
  IF NOT pg_catalog.has_schema_privilege(ns, 'USAGE') OR
     NOT (pg_catalog.has_table_privilege(obj, 'MAINTAIN') OR
          pg_catalog.pg_has_role((SELECT datdba FROM pg_catalog.pg_database
                                  WHERE datname = current_database()), 'USAGE')) THEN
    RAISE EXCEPTION 'permission denied for statistics target %.%', ns, nm USING ERRCODE = '42501';
  END IF;
  SELECT relkind INTO kind FROM pg_catalog.pg_class WHERE oid = obj;
  IF kind NOT IN ('r', 'm') THEN
    RAISE EXCEPTION 'only ordinary tables and materialized views are supported' USING ERRCODE = '0A000';
  END IF;
  EXECUTE pg_catalog.format('LOCK TABLE %I.%I IN SHARE UPDATE EXCLUSIVE MODE', ns, nm);
  IF pg_catalog.to_regclass(pg_catalog.format('%I.%I', ns, nm)) <> obj THEN
    RAISE EXCEPTION 'statistics target changed concurrently' USING ERRCODE = '40001';
  END IF;
  RETURN obj;
END $$;

CREATE FUNCTION sys.ora_stats_gather(ownname text, tabname text, estimate_percent numeric,
                                    method_opt text, degree numeric, cascade boolean)
RETURNS void LANGUAGE plpgsql VOLATILE SET ivorysql.identifier_case_switch = normal SET search_path = pg_catalog, pg_temp AS $$
DECLARE obj oid;
BEGIN
  IF estimate_percent IS DISTINCT FROM 0::numeric OR
     method_opt IS DISTINCT FROM 'FOR ALL COLUMNS SIZE AUTO' OR
     degree IS DISTINCT FROM NULL::numeric OR cascade IS DISTINCT FROM NULL::boolean THEN
    RAISE EXCEPTION 'only automatic sampling, default method_opt, degree and cascade are supported'
      USING ERRCODE = '0A000';
  END IF;
  obj := sys.ora_stats_relation(ownname, tabname);
  EXECUTE pg_catalog.format('ANALYZE %s', obj::regclass);
END $$;

CREATE FUNCTION sys.ora_stats_gather_schema(ownname text, estimate_percent numeric,
                                           method_opt text, degree numeric, cascade boolean)
RETURNS void LANGUAGE plpgsql VOLATILE SET ivorysql.identifier_case_switch = normal SET search_path = pg_catalog, pg_temp AS $$
DECLARE item record; ns text := sys.ora_stats_ident(ownname);
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_namespace WHERE nspname = ns) THEN
    RAISE EXCEPTION 'schema % does not exist', ns USING ERRCODE = '3F000';
  END IF;
  -- Do not silently skip inaccessible tables: any failure rolls back this call.
  FOR item IN SELECT c.relname FROM pg_catalog.pg_class c
              JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
              WHERE n.nspname = ns AND c.relkind IN ('r', 'm') ORDER BY c.oid LOOP
    PERFORM sys.ora_stats_gather(pg_catalog.quote_ident(ns),
      pg_catalog.quote_ident(item.relname), estimate_percent, method_opt, degree, cascade);
  END LOOP;
END $$;

CREATE FUNCTION sys.ora_stats_get(ownname text, tabname text,
                                 OUT numrows numeric, OUT numblks numeric, OUT avgrlen numeric)
LANGUAGE plpgsql VOLATILE SET ivorysql.identifier_case_switch = normal SET search_path = pg_catalog, pg_temp AS $$
DECLARE obj oid := sys.ora_stats_relation(ownname, tabname);
BEGIN
  SELECT c.reltuples::numeric, c.relpages::numeric INTO numrows, numblks
    FROM pg_catalog.pg_class c WHERE c.oid = obj;
  -- PostgreSQL does not persist Oracle's average row length statistic.
  avgrlen := NULL;
END $$;

CREATE FUNCTION sys.ora_stats_set(ownname text, tabname text, numrows numeric, numblks numeric)
RETURNS void LANGUAGE plpgsql VOLATILE SET ivorysql.identifier_case_switch = normal SET search_path = pg_catalog, pg_temp AS $$
DECLARE obj oid := sys.ora_stats_relation(ownname, tabname);
        ns text; nm text; ok boolean;
BEGIN
  IF numrows < 0 OR numblks < 0 OR numblks <> trunc(numblks) OR
     numrows::text IN ('NaN', 'Infinity', '-Infinity') OR
     numblks::text IN ('NaN', 'Infinity', '-Infinity') THEN
    RAISE EXCEPTION 'invalid table statistics values' USING ERRCODE = '22023';
  END IF;
  SELECT n.nspname, c.relname INTO ns, nm FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace WHERE c.oid = obj;
  ok := pg_catalog.pg_restore_relation_stats('schemaname', ns, 'relname', nm,
    'reltuples', numrows::real, 'relpages', numblks::integer);
  IF NOT ok THEN RAISE EXCEPTION 'table statistics were not completely restored'; END IF;
END $$;

CREATE FUNCTION sys.ora_stats_delete(ownname text, tabname text, colname text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql VOLATILE SET ivorysql.identifier_case_switch = normal SET search_path = pg_catalog, pg_temp AS $$
DECLARE obj oid := sys.ora_stats_relation(ownname, tabname);
        ns text; nm text; item record; idx record;
BEGIN
  SELECT n.nspname, c.relname INTO ns, nm FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace WHERE c.oid = obj;
  IF colname IS NULL THEN
    PERFORM pg_catalog.pg_clear_relation_stats(ns, nm);
    FOR idx IN SELECT c.relname FROM pg_catalog.pg_index i
        JOIN pg_catalog.pg_class c ON c.oid = i.indexrelid WHERE i.indrelid = obj LOOP
      PERFORM pg_catalog.pg_clear_relation_stats(ns, idx.relname);
      FOR item IN SELECT attname FROM pg_catalog.pg_attribute
          WHERE attrelid = pg_catalog.to_regclass(pg_catalog.format('%I.%I', ns, idx.relname))
          AND attnum > 0 AND NOT attisdropped LOOP
        PERFORM pg_catalog.pg_clear_attribute_stats(ns, idx.relname, item.attname, false);
        PERFORM pg_catalog.pg_clear_attribute_stats(ns, idx.relname, item.attname, true);
      END LOOP;
    END LOOP;
  ELSIF NOT EXISTS (SELECT FROM pg_catalog.pg_attribute
       WHERE attrelid = obj AND attname = sys.ora_stats_ident(colname)
       AND attnum > 0 AND NOT attisdropped) THEN
    RAISE EXCEPTION 'statistics column does not exist' USING ERRCODE = '42703';
  END IF;
  FOR item IN SELECT attname FROM pg_catalog.pg_attribute WHERE attrelid = obj
      AND attnum > 0 AND NOT attisdropped
      AND (colname IS NULL OR attname = sys.ora_stats_ident(colname)) LOOP
    PERFORM pg_catalog.pg_clear_attribute_stats(ns, nm, item.attname, false);
    PERFORM pg_catalog.pg_clear_attribute_stats(ns, nm, item.attname, true);
  END LOOP;
END $$;

CREATE FUNCTION sys.ora_stats_stattab(ownname text, stattab text, create_it boolean)
RETURNS void LANGUAGE plpgsql VOLATILE SET ivorysql.identifier_case_switch = normal SET search_path = pg_catalog, pg_temp AS $$
DECLARE ns text := sys.ora_stats_ident(ownname); nm text := sys.ora_stats_ident(stattab);
BEGIN
  IF create_it THEN
    EXECUTE pg_catalog.format('CREATE TABLE %I.%I (
      statid text NOT NULL, owner_name text NOT NULL, table_name text NOT NULL,
      format_version integer NOT NULL CHECK (format_version = 1),
      relation_stats jsonb NOT NULL, column_stats jsonb NOT NULL,
      PRIMARY KEY (statid, owner_name, table_name))', ns, nm);
    EXECUTE pg_catalog.format('COMMENT ON TABLE %I.%I IS %L', ns, nm,
      'IvorySQL DBMS_STATS snapshot format 1');
  ELSE
    -- DROP retains ordinary ownership checks; never runs as the extension owner.
    IF pg_catalog.obj_description(pg_catalog.to_regclass(pg_catalog.format('%I.%I', ns, nm)),
        'pg_class') IS DISTINCT FROM 'IvorySQL DBMS_STATS snapshot format 1' THEN
      RAISE EXCEPTION 'not a DBMS_STATS snapshot table' USING ERRCODE = '42809';
    END IF;
    EXECUTE pg_catalog.format('DROP TABLE %I.%I', ns, nm);
  END IF;
END $$;

CREATE FUNCTION sys.ora_stats_export(ownname text, tabname text, stattab text,
                                    statid text, statown text)
RETURNS void LANGUAGE plpgsql VOLATILE SET ivorysql.identifier_case_switch = normal SET search_path = pg_catalog, pg_temp AS $$
DECLARE obj oid := sys.ora_stats_relation(ownname, tabname);
        ns text; nm text; rel jsonb; cols jsonb; indexes jsonb;
        dest_ns text := sys.ora_stats_ident(coalesce(statown, ownname));
        dest_nm text := sys.ora_stats_ident(stattab);
BEGIN
  IF NOT pg_catalog.has_table_privilege(obj, 'SELECT') OR pg_catalog.row_security_active(obj) THEN
    RAISE EXCEPTION 'export requires SELECT and unrestricted row visibility' USING ERRCODE = '42501';
  END IF;
  SELECT n.nspname, c.relname,
    pg_catalog.jsonb_build_object('reltuples', c.reltuples, 'relpages', c.relpages,
      'relallvisible', c.relallvisible, 'relallfrozen', c.relallfrozen)
    INTO ns, nm, rel FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n
    ON n.oid = c.relnamespace WHERE c.oid = obj;
  SELECT coalesce(jsonb_agg(jsonb_build_object('name', c.relname,
    'definition', pg_catalog.pg_get_indexdef(c.oid), 'reltuples', c.reltuples,
    'relpages', c.relpages, 'relallvisible', c.relallvisible, 'relallfrozen', c.relallfrozen)
    ORDER BY c.relname), '[]'::jsonb) INTO indexes FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class c ON c.oid = i.indexrelid WHERE i.indrelid = obj;
  rel := rel || jsonb_build_object('indexes', indexes, 'columns',
    (SELECT jsonb_agg(jsonb_build_array(attname, atttypid, atttypmod, attcollation) ORDER BY attnum)
     FROM pg_catalog.pg_attribute WHERE attrelid = obj AND attnum > 0 AND NOT attisdropped));
  SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(s)), '[]'::jsonb) INTO cols
    FROM (SELECT tc.relname AS source_rel, a.attname, a.atttypid, a.atttypmod, s.inherited, s.null_frac,
      s.avg_width, s.n_distinct, s.most_common_vals::text, s.most_common_freqs::text,
      s.histogram_bounds::text, s.correlation, s.most_common_elems::text,
      s.most_common_elem_freqs::text, s.elem_count_histogram::text,
      s.range_length_histogram::text, s.range_empty_frac, s.range_bounds_histogram::text
      FROM pg_catalog.pg_stats s JOIN pg_catalog.pg_class tc ON tc.relname = s.tablename
      JOIN pg_catalog.pg_namespace tn ON tn.oid = tc.relnamespace AND tn.nspname = s.schemaname
      JOIN pg_catalog.pg_attribute a ON a.attrelid = tc.oid AND a.attname = s.attname
      AND NOT a.attisdropped WHERE s.schemaname = ns AND
      (tc.oid = obj OR tc.oid IN (SELECT indexrelid FROM pg_catalog.pg_index WHERE indrelid = obj))
      ORDER BY tc.oid, a.attnum, s.inherited) s;
  EXECUTE pg_catalog.format('INSERT INTO %I.%I VALUES ($1,$2,$3,1,$4,$5)
    ON CONFLICT (statid,owner_name,table_name) DO UPDATE SET
      format_version = 1, relation_stats = EXCLUDED.relation_stats,
      column_stats = EXCLUDED.column_stats', dest_ns, dest_nm)
    USING coalesce(statid, ''), ns, nm, rel, cols;
END $$;

CREATE FUNCTION sys.ora_stats_import(ownname text, tabname text, stattab text,
                                    statid text, statown text)
RETURNS void LANGUAGE plpgsql VOLATILE SET ivorysql.identifier_case_switch = normal SET search_path = pg_catalog, pg_temp AS $$
DECLARE obj oid := sys.ora_stats_relation(ownname, tabname);
        ns text; nm text; rel jsonb; cols jsonb; col jsonb; idx jsonb;
        source_oid oid; ver integer; ok boolean;
        src_ns text := sys.ora_stats_ident(coalesce(statown, ownname));
        src_nm text := sys.ora_stats_ident(stattab);
BEGIN
  SELECT n.nspname, c.relname INTO ns, nm FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace WHERE c.oid = obj;
  EXECUTE pg_catalog.format('SELECT format_version, relation_stats, column_stats
    FROM %I.%I WHERE statid=$1 AND owner_name=$2 AND table_name=$3', src_ns, src_nm)
    INTO ver, rel, cols USING coalesce(statid, ''), ns, nm;
  IF ver IS NULL THEN RAISE EXCEPTION 'statistics snapshot does not exist' USING ERRCODE = 'P0002'; END IF;
  IF ver <> 1 OR jsonb_typeof(rel) <> 'object' OR jsonb_typeof(cols) <> 'array' OR
     NOT (rel ?& ARRAY['reltuples','relpages','relallvisible','relallfrozen','indexes','columns']) OR
     jsonb_typeof(rel->'indexes') <> 'array' THEN
    RAISE EXCEPTION 'invalid statistics snapshot format' USING ERRCODE = '22023';
  END IF;
  -- Validate every column before changing any catalog statistics.
  IF (rel->'columns') IS DISTINCT FROM
    (SELECT jsonb_agg(jsonb_build_array(attname, atttypid, atttypmod, attcollation) ORDER BY attnum)
     FROM pg_catalog.pg_attribute WHERE attrelid = obj AND attnum > 0 AND NOT attisdropped) OR
     jsonb_array_length(rel->'indexes') <> (SELECT count(*) FROM pg_catalog.pg_index WHERE indrelid = obj) THEN
    RAISE EXCEPTION 'statistics snapshot table structure no longer matches' USING ERRCODE = '42804';
  END IF;
  FOR idx IN SELECT value FROM pg_catalog.jsonb_array_elements(rel->'indexes') LOOP
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c
      ON c.oid = i.indexrelid WHERE i.indrelid = obj AND c.relname = idx->>'name'
      AND pg_catalog.pg_get_indexdef(c.oid) = idx->>'definition') THEN
      RAISE EXCEPTION 'statistics snapshot index no longer matches' USING ERRCODE = '42804';
    END IF;
  END LOOP;
  FOR col IN SELECT value FROM pg_catalog.jsonb_array_elements(cols) LOOP
    source_oid := pg_catalog.to_regclass(pg_catalog.format('%I.%I', ns, col->>'source_rel'));
    IF source_oid IS NULL OR (source_oid <> obj AND NOT EXISTS
      (SELECT FROM pg_catalog.pg_index WHERE indrelid = obj AND indexrelid = source_oid)) OR
      NOT EXISTS (SELECT FROM pg_catalog.pg_attribute WHERE attrelid = source_oid
      AND attnum > 0 AND NOT attisdropped AND attname = col->>'attname'
      AND atttypid = (col->>'atttypid')::oid AND atttypmod = (col->>'atttypmod')::integer) THEN
      RAISE EXCEPTION 'statistics snapshot column type or name no longer matches'
        USING ERRCODE = '42804';
    END IF;
  END LOOP;
  -- Clear old slots first, so missing/NULL statistics do not retain stale slots.
  PERFORM sys.ora_stats_delete(ownname, tabname);
  ok := pg_catalog.pg_restore_relation_stats('schemaname', ns, 'relname', nm,
    'reltuples', (rel->>'reltuples')::real, 'relpages', (rel->>'relpages')::integer,
    'relallvisible', (rel->>'relallvisible')::integer, 'relallfrozen', (rel->>'relallfrozen')::integer);
  IF NOT ok THEN RAISE EXCEPTION 'relation statistics import failed'; END IF;
  FOR idx IN SELECT value FROM pg_catalog.jsonb_array_elements(rel->'indexes') LOOP
    ok := pg_catalog.pg_restore_relation_stats('schemaname', ns, 'relname', idx->>'name',
      'reltuples', (idx->>'reltuples')::real, 'relpages', (idx->>'relpages')::integer,
      'relallvisible', (idx->>'relallvisible')::integer, 'relallfrozen', (idx->>'relallfrozen')::integer);
    IF NOT ok THEN RAISE EXCEPTION 'index statistics import failed'; END IF;
  END LOOP;
  FOR col IN SELECT value FROM pg_catalog.jsonb_array_elements(cols) LOOP
    ok := pg_catalog.pg_restore_attribute_stats('schemaname', ns, 'relname', col->>'source_rel',
      'attname', col->>'attname', 'inherited', (col->>'inherited')::boolean,
      'null_frac', (col->>'null_frac')::real, 'avg_width', (col->>'avg_width')::integer,
      'n_distinct', (col->>'n_distinct')::real,
      'most_common_vals', col->>'most_common_vals',
      'most_common_freqs', (col->>'most_common_freqs')::real[],
      'histogram_bounds', col->>'histogram_bounds', 'correlation', (col->>'correlation')::real,
      'most_common_elems', col->>'most_common_elems',
      'most_common_elem_freqs', (col->>'most_common_elem_freqs')::real[],
      'elem_count_histogram', (col->>'elem_count_histogram')::real[],
      'range_length_histogram', col->>'range_length_histogram',
      'range_empty_frac', (col->>'range_empty_frac')::real,
      'range_bounds_histogram', col->>'range_bounds_histogram');
    IF NOT ok THEN RAISE EXCEPTION 'column statistics import failed'; END IF;
  END LOOP;
END $$;

CREATE OR REPLACE PACKAGE dbms_stats AUTHID CURRENT_USER IS
  auto_sample_size CONSTANT NUMBER := 0;
  PROCEDURE gather_table_stats(ownname VARCHAR2, tabname VARCHAR2, partname VARCHAR2 DEFAULT NULL, estimate_percent NUMBER DEFAULT 0, block_sample BOOLEAN DEFAULT FALSE, method_opt VARCHAR2 DEFAULT 'FOR ALL COLUMNS SIZE AUTO', degree NUMBER DEFAULT NULL, granularity VARCHAR2 DEFAULT 'AUTO', cascade BOOLEAN DEFAULT NULL);
  PROCEDURE gather_schema_stats(ownname VARCHAR2, estimate_percent NUMBER DEFAULT 0, block_sample BOOLEAN DEFAULT FALSE, method_opt VARCHAR2 DEFAULT 'FOR ALL COLUMNS SIZE AUTO', degree NUMBER DEFAULT NULL, granularity VARCHAR2 DEFAULT 'AUTO', cascade BOOLEAN DEFAULT NULL);
  PROCEDURE get_table_stats(ownname VARCHAR2, tabname VARCHAR2, partname VARCHAR2 DEFAULT NULL, stattab VARCHAR2 DEFAULT NULL, statid VARCHAR2 DEFAULT NULL, numrows OUT NUMBER, numblks OUT NUMBER, avgrlen OUT NUMBER, statown VARCHAR2 DEFAULT NULL);
  PROCEDURE set_table_stats(ownname VARCHAR2, tabname VARCHAR2, partname VARCHAR2 DEFAULT NULL, stattab VARCHAR2 DEFAULT NULL, statid VARCHAR2 DEFAULT NULL, numrows NUMBER DEFAULT NULL, numblks NUMBER DEFAULT NULL, avgrlen NUMBER DEFAULT NULL, flags NUMBER DEFAULT NULL, statown VARCHAR2 DEFAULT NULL);
  PROCEDURE delete_table_stats(ownname VARCHAR2, tabname VARCHAR2);
  PROCEDURE delete_column_stats(ownname VARCHAR2, tabname VARCHAR2, colname VARCHAR2);
  PROCEDURE create_stat_table(ownname VARCHAR2, stattab VARCHAR2);
  PROCEDURE drop_stat_table(ownname VARCHAR2, stattab VARCHAR2);
  PROCEDURE export_table_stats(ownname VARCHAR2, tabname VARCHAR2, partname VARCHAR2 DEFAULT NULL, stattab VARCHAR2 DEFAULT NULL, statid VARCHAR2 DEFAULT NULL, cascade BOOLEAN DEFAULT TRUE, statown VARCHAR2 DEFAULT NULL);
  PROCEDURE import_table_stats(ownname VARCHAR2, tabname VARCHAR2, partname VARCHAR2 DEFAULT NULL, stattab VARCHAR2 DEFAULT NULL, statid VARCHAR2 DEFAULT NULL, cascade BOOLEAN DEFAULT TRUE, statown VARCHAR2 DEFAULT NULL);
END dbms_stats;

CREATE OR REPLACE PACKAGE BODY dbms_stats IS
  PROCEDURE gather_table_stats(ownname VARCHAR2, tabname VARCHAR2, partname VARCHAR2 DEFAULT NULL, estimate_percent NUMBER DEFAULT 0, block_sample BOOLEAN DEFAULT FALSE, method_opt VARCHAR2 DEFAULT 'FOR ALL COLUMNS SIZE AUTO', degree NUMBER DEFAULT NULL, granularity VARCHAR2 DEFAULT 'AUTO', cascade BOOLEAN DEFAULT NULL) IS
  BEGIN
    IF partname IS NOT NULL OR block_sample IS DISTINCT FROM FALSE OR granularity IS DISTINCT FROM 'AUTO' THEN RAISE EXCEPTION 'requested statistics option is not supported' USING ERRCODE = '0A000'; END IF; PERFORM sys.ora_stats_gather(ownname, tabname, estimate_percent, method_opt, degree, cascade);
  END;
  PROCEDURE gather_schema_stats(ownname VARCHAR2, estimate_percent NUMBER DEFAULT 0, block_sample BOOLEAN DEFAULT FALSE, method_opt VARCHAR2 DEFAULT 'FOR ALL COLUMNS SIZE AUTO', degree NUMBER DEFAULT NULL, granularity VARCHAR2 DEFAULT 'AUTO', cascade BOOLEAN DEFAULT NULL) IS
  BEGIN
    IF block_sample IS DISTINCT FROM FALSE OR granularity IS DISTINCT FROM 'AUTO' THEN RAISE EXCEPTION 'requested statistics option is not supported' USING ERRCODE = '0A000'; END IF; PERFORM sys.ora_stats_gather_schema(ownname, estimate_percent, method_opt, degree, cascade);
  END;
  PROCEDURE get_table_stats(ownname VARCHAR2, tabname VARCHAR2, partname VARCHAR2 DEFAULT NULL, stattab VARCHAR2 DEFAULT NULL, statid VARCHAR2 DEFAULT NULL, numrows OUT NUMBER, numblks OUT NUMBER, avgrlen OUT NUMBER, statown VARCHAR2 DEFAULT NULL) IS
  BEGIN
    IF partname IS NOT NULL OR stattab IS NOT NULL OR statid IS NOT NULL OR statown IS NOT NULL THEN RAISE EXCEPTION 'requested statistics option is not supported' USING ERRCODE = '0A000'; END IF; SELECT s.numrows, s.numblks, s.avgrlen INTO numrows, numblks, avgrlen FROM sys.ora_stats_get(ownname, tabname) s;
  END;
  PROCEDURE set_table_stats(ownname VARCHAR2, tabname VARCHAR2, partname VARCHAR2 DEFAULT NULL, stattab VARCHAR2 DEFAULT NULL, statid VARCHAR2 DEFAULT NULL, numrows NUMBER DEFAULT NULL, numblks NUMBER DEFAULT NULL, avgrlen NUMBER DEFAULT NULL, flags NUMBER DEFAULT NULL, statown VARCHAR2 DEFAULT NULL) IS
  BEGIN
    IF partname IS NOT NULL OR stattab IS NOT NULL OR statid IS NOT NULL OR avgrlen IS NOT NULL OR flags IS NOT NULL OR statown IS NOT NULL THEN RAISE EXCEPTION 'requested statistics option is not supported' USING ERRCODE = '0A000'; END IF; PERFORM sys.ora_stats_set(ownname, tabname, numrows, numblks);
  END;
  PROCEDURE delete_table_stats(ownname VARCHAR2, tabname VARCHAR2) IS
  BEGIN
    PERFORM sys.ora_stats_delete(ownname, tabname);
  END;
  PROCEDURE delete_column_stats(ownname VARCHAR2, tabname VARCHAR2, colname VARCHAR2) IS
  BEGIN
    IF colname IS NULL THEN RAISE EXCEPTION 'column name must not be null'; END IF; PERFORM sys.ora_stats_delete(ownname, tabname, colname);
  END;
  PROCEDURE create_stat_table(ownname VARCHAR2, stattab VARCHAR2) IS
  BEGIN
    PERFORM sys.ora_stats_stattab(ownname, stattab, true);
  END;
  PROCEDURE drop_stat_table(ownname VARCHAR2, stattab VARCHAR2) IS
  BEGIN
    PERFORM sys.ora_stats_stattab(ownname, stattab, false);
  END;
  PROCEDURE export_table_stats(ownname VARCHAR2, tabname VARCHAR2, partname VARCHAR2 DEFAULT NULL, stattab VARCHAR2 DEFAULT NULL, statid VARCHAR2 DEFAULT NULL, cascade BOOLEAN DEFAULT TRUE, statown VARCHAR2 DEFAULT NULL) IS
  BEGIN
    IF partname IS NOT NULL OR cascade IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'requested statistics option is not supported' USING ERRCODE = '0A000'; END IF; PERFORM sys.ora_stats_export(ownname, tabname, stattab, statid, statown);
  END;
  PROCEDURE import_table_stats(ownname VARCHAR2, tabname VARCHAR2, partname VARCHAR2 DEFAULT NULL, stattab VARCHAR2 DEFAULT NULL, statid VARCHAR2 DEFAULT NULL, cascade BOOLEAN DEFAULT TRUE, statown VARCHAR2 DEFAULT NULL) IS
  BEGIN
    IF partname IS NOT NULL OR cascade IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'requested statistics option is not supported' USING ERRCODE = '0A000'; END IF; PERFORM sys.ora_stats_import(ownname, tabname, stattab, statid, statown);
  END;
END dbms_stats;
