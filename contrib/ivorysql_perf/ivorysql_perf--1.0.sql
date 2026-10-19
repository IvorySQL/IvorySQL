/* Copyright 2026 IvorySQL Global Development Team
 * Licensed under the Apache License, Version 2.0. See LICENSE.
 */
\echo Use "CREATE EXTENSION ivorysql_perf" to load this file. \quit

CREATE TABLE ivorysql_perf.settings (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  sample_interval_ms integer NOT NULL CHECK (sample_interval_ms BETWEEN 100 AND 60000),
  snapshot_interval_s integer NOT NULL CHECK (snapshot_interval_s BETWEEN 1 AND 86400),
  sample_limit integer NOT NULL CHECK (sample_limit BETWEEN 1 AND 1000000),
  snapshot_limit integer NOT NULL CHECK (snapshot_limit BETWEEN 2 AND 10000),
  retention interval NOT NULL CHECK (retention BETWEEN interval '1 second' AND interval '30 days'),
  sql_limit integer NOT NULL CHECK (sql_limit BETWEEN 1 AND 10000)
);
INSERT INTO ivorysql_perf.settings VALUES (true,1000,60,100000,1440,'1 day',1000);

CREATE TABLE ivorysql_perf.samples (
  sample_id bigserial PRIMARY KEY, sampled_at timestamptz NOT NULL,
  pid integer NOT NULL, backend_start timestamptz NOT NULL,
  userid oid, application_name text, queryid bigint,
  wait_event_type text, wait_event text, blocking_pids integer[],
  xact_start timestamptz, query_start timestamptz, query_text text
);
CREATE INDEX samples_time_idx ON ivorysql_perf.samples(sampled_at);
CREATE TABLE ivorysql_perf.snapshots (
  snapshot_id bigserial PRIMARY KEY, captured_at timestamptz NOT NULL,
  postmaster_start timestamptz NOT NULL, database_stats jsonb NOT NULL,
  sql_available boolean NOT NULL DEFAULT false, sql_info jsonb,
  sql_truncated boolean NOT NULL DEFAULT false
);
CREATE TABLE ivorysql_perf.statement_snapshots (
  snapshot_id bigint NOT NULL REFERENCES ivorysql_perf.snapshots ON DELETE CASCADE,
  userid oid NOT NULL, dbid oid NOT NULL, toplevel boolean NOT NULL, queryid bigint NOT NULL,
  calls bigint NOT NULL, exec_ms double precision NOT NULL, rows bigint NOT NULL,
  shared_blks_hit bigint NOT NULL, shared_blks_read bigint NOT NULL,
  stats_since timestamptz NOT NULL, query_text text,
  PRIMARY KEY(snapshot_id,userid,dbid,toplevel,queryid)
);

CREATE FUNCTION ivorysql_perf.configure(
  sample_interval_ms integer DEFAULT 1000, snapshot_interval_s integer DEFAULT 60,
  sample_limit integer DEFAULT 100000, snapshot_limit integer DEFAULT 1440,
  retention interval DEFAULT '1 day', sql_limit integer DEFAULT 1000)
RETURNS void LANGUAGE sql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp SET ivorysql.identifier_case_switch = normal AS $$
  UPDATE ivorysql_perf.settings SET sample_interval_ms=$1, snapshot_interval_s=$2,
    sample_limit=$3, snapshot_limit=$4, retention=$5, sql_limit=$6 WHERE singleton;
$$;

CREATE FUNCTION ivorysql_perf.purge() RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp SET ivorysql.identifier_case_switch = normal AS $$
DECLARE cfg ivorysql_perf.settings%ROWTYPE;
BEGIN
  SELECT * INTO STRICT cfg FROM ivorysql_perf.settings WHERE singleton FOR UPDATE;
  DELETE FROM ivorysql_perf.samples WHERE sampled_at < clock_timestamp()-cfg.retention;
  DELETE FROM ivorysql_perf.samples WHERE sample_id <= coalesce(
    (SELECT sample_id FROM ivorysql_perf.samples ORDER BY sample_id DESC OFFSET cfg.sample_limit LIMIT 1),-1);
  DELETE FROM ivorysql_perf.snapshots WHERE captured_at < clock_timestamp()-cfg.retention;
  DELETE FROM ivorysql_perf.snapshots WHERE snapshot_id <= coalesce(
    (SELECT snapshot_id FROM ivorysql_perf.snapshots ORDER BY snapshot_id DESC OFFSET cfg.snapshot_limit LIMIT 1),-1);
END $$;

CREATE FUNCTION ivorysql_perf.collect_sample() RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp SET ivorysql.identifier_case_switch = normal AS $$
DECLARE captured timestamptz := clock_timestamp(); n integer; cfg ivorysql_perf.settings%ROWTYPE;
BEGIN
  SELECT * INTO STRICT cfg FROM ivorysql_perf.settings WHERE singleton FOR UPDATE;
  PERFORM pg_catalog.pg_stat_clear_snapshot();
  INSERT INTO ivorysql_perf.samples(sampled_at,pid,backend_start,userid,application_name,
    queryid,wait_event_type,wait_event,blocking_pids,xact_start,query_start,query_text)
  SELECT captured,pid,backend_start,usesysid,left(application_name,128),query_id,
    wait_event_type,wait_event,pg_catalog.pg_blocking_pids(pid),xact_start,query_start,left(query,2000)
  FROM pg_catalog.pg_stat_activity WHERE datname=current_database() AND state='active'
    AND backend_type='client backend' AND pid<>pg_backend_pid()
  ORDER BY pid LIMIT cfg.sample_limit;
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM ivorysql_perf.purge();
  RETURN n;
END $$;

CREATE FUNCTION ivorysql_perf.take_snapshot() RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp SET ivorysql.identifier_case_switch = normal AS $$
DECLARE id bigint; ext_schema text; info jsonb; total bigint; cfg ivorysql_perf.settings%ROWTYPE;
BEGIN
  SELECT * INTO STRICT cfg FROM ivorysql_perf.settings WHERE singleton FOR UPDATE;
  PERFORM pg_catalog.pg_stat_clear_snapshot();
  INSERT INTO ivorysql_perf.snapshots(captured_at,postmaster_start,database_stats)
  SELECT clock_timestamp(),pg_postmaster_start_time(),to_jsonb(d)
  FROM pg_catalog.pg_stat_database d WHERE datname=current_database() RETURNING snapshot_id INTO id;
  SELECT n.nspname INTO ext_schema FROM pg_catalog.pg_extension e JOIN pg_catalog.pg_namespace n
    ON n.oid=e.extnamespace WHERE e.extname='pg_stat_statements';
  IF ext_schema IS NOT NULL THEN
    BEGIN
      EXECUTE format('SELECT to_jsonb(i) FROM %I.pg_stat_statements_info i',ext_schema) INTO info;
      EXECUTE format('SELECT count(*) FROM %I.pg_stat_statements
        WHERE dbid=(SELECT oid FROM pg_catalog.pg_database WHERE datname=current_database())',ext_schema) INTO total;
      EXECUTE format('INSERT INTO ivorysql_perf.statement_snapshots
        SELECT $1,userid,dbid,toplevel,queryid,calls,total_exec_time,rows,shared_blks_hit,
          shared_blks_read,stats_since,left(query,2000) FROM %I.pg_stat_statements
        WHERE dbid=(SELECT oid FROM pg_catalog.pg_database WHERE datname=current_database())
        ORDER BY total_exec_time DESC,userid,queryid,toplevel LIMIT $2',ext_schema) USING id,cfg.sql_limit;
      UPDATE ivorysql_perf.snapshots SET sql_available=true,sql_info=info,
        sql_truncated=(total>cfg.sql_limit) WHERE snapshot_id=id;
    EXCEPTION WHEN undefined_table OR object_not_in_prerequisite_state THEN
      -- Installed without shared preload: retain usable database-level data.
      UPDATE ivorysql_perf.snapshots SET sql_info=jsonb_build_object('unavailable',SQLERRM)
        WHERE snapshot_id=id;
    END;
  END IF;
  PERFORM ivorysql_perf.purge();
  RETURN id;
END $$;

CREATE FUNCTION ivorysql_perf.collect_tick() RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp SET ivorysql.identifier_case_switch = normal AS $$
DECLARE cfg ivorysql_perf.settings%ROWTYPE; last_time timestamptz;
BEGIN
  SELECT * INTO STRICT cfg FROM ivorysql_perf.settings WHERE singleton FOR UPDATE;
  PERFORM ivorysql_perf.collect_sample();
  SELECT max(captured_at) INTO last_time FROM ivorysql_perf.snapshots;
  IF last_time IS NULL OR clock_timestamp()-last_time >= make_interval(secs=>cfg.snapshot_interval_s) THEN
    PERFORM ivorysql_perf.take_snapshot();
  END IF;
  RETURN cfg.sample_interval_ms;
END $$;

CREATE FUNCTION ivorysql_perf.report(begin_snapshot bigint,end_snapshot bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp
SET ivorysql.identifier_case_switch = normal AS $$
DECLARE a ivorysql_perf.snapshots%ROWTYPE; b ivorysql_perf.snapshots%ROWTYPE;
        delta jsonb; waits jsonb; queries jsonb := '[]'; sql_status text := 'unavailable';
        blocking jsonb; skipped integer := 0;
BEGIN
  SELECT * INTO a FROM ivorysql_perf.snapshots WHERE snapshot_id=begin_snapshot;
  SELECT * INTO b FROM ivorysql_perf.snapshots WHERE snapshot_id=end_snapshot;
  IF a.snapshot_id IS NULL OR b.snapshot_id IS NULL THEN
    RAISE EXCEPTION 'snapshot does not exist' USING ERRCODE='22023';
  END IF;
  IF begin_snapshot>=end_snapshot OR a.captured_at>=b.captured_at THEN
    RAISE EXCEPTION 'snapshot interval must be increasing' USING ERRCODE='22023';
  END IF;
  IF a.postmaster_start<>b.postmaster_start OR
     (a.database_stats->>'stats_reset') IS DISTINCT FROM (b.database_stats->>'stats_reset') THEN
    RAISE EXCEPTION 'snapshot interval crosses a restart or database statistics reset' USING ERRCODE='22023';
  END IF;
  SELECT jsonb_object_agg(key,(b.database_stats->>key)::numeric-(a.database_stats->>key)::numeric)
    INTO delta FROM unnest(ARRAY['xact_commit','xact_rollback','blks_read','blks_hit','tup_returned',
      'tup_fetched','tup_inserted','tup_updated','tup_deleted','temp_bytes','deadlocks',
      'blk_read_time','blk_write_time']) key;
  IF EXISTS(SELECT FROM jsonb_each_text(delta) WHERE value::numeric<0) THEN
    RAISE EXCEPTION 'database statistics counters decreased' USING ERRCODE='22023';
  END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(w)),'[]') INTO waits FROM
    (SELECT coalesce(wait_event_type,'running_or_runnable') AS wait_type,wait_event,count(*) AS samples
     FROM ivorysql_perf.samples WHERE sampled_at>=a.captured_at AND sampled_at<b.captured_at
     GROUP BY wait_event_type,wait_event ORDER BY count(*) DESC,wait_event_type,wait_event LIMIT 20) w;
  SELECT coalesce(jsonb_agg(to_jsonb(w)),'[]') INTO blocking FROM
    (SELECT pid,backend_start,blocking_pids,count(*) AS samples FROM ivorysql_perf.samples
     WHERE sampled_at>=a.captured_at AND sampled_at<b.captured_at AND cardinality(blocking_pids)>0
     GROUP BY pid,backend_start,blocking_pids ORDER BY count(*) DESC,pid LIMIT 20) w;
  IF a.sql_available AND b.sql_available THEN
    IF (a.sql_info->>'stats_reset') IS DISTINCT FROM (b.sql_info->>'stats_reset') THEN
      sql_status := 'reset';
    ELSE
      sql_status := 'ok';
      SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]') INTO queries FROM
      (SELECT e.userid,e.queryid,e.toplevel,e.query_text,
        e.calls-coalesce(s.calls,0) AS calls,e.exec_ms-coalesce(s.exec_ms,0) AS exec_ms,
        e.rows-coalesce(s.rows,0) AS rows,
        e.shared_blks_hit-coalesce(s.shared_blks_hit,0) AS shared_blks_hit,
        e.shared_blks_read-coalesce(s.shared_blks_read,0) AS shared_blks_read
       FROM ivorysql_perf.statement_snapshots e LEFT JOIN ivorysql_perf.statement_snapshots s
        ON s.snapshot_id=begin_snapshot AND (s.userid,s.dbid,s.toplevel,s.queryid)=(e.userid,e.dbid,e.toplevel,e.queryid)
       WHERE e.snapshot_id=end_snapshot AND
        ((s.snapshot_id IS NOT NULL AND e.stats_since=s.stats_since) OR
         (s.snapshot_id IS NULL AND e.stats_since>=a.captured_at))
        AND e.calls>=coalesce(s.calls,0) AND e.exec_ms>=coalesce(s.exec_ms,0)
        AND e.rows>=coalesce(s.rows,0)
        AND e.shared_blks_hit>=coalesce(s.shared_blks_hit,0) AND e.shared_blks_read>=coalesce(s.shared_blks_read,0)
       ORDER BY e.exec_ms-coalesce(s.exec_ms,0) DESC,e.queryid LIMIT 20) q;
      SELECT count(*) INTO skipped FROM ivorysql_perf.statement_snapshots e
       LEFT JOIN ivorysql_perf.statement_snapshots s ON s.snapshot_id=begin_snapshot
        AND (s.userid,s.dbid,s.toplevel,s.queryid)=(e.userid,e.dbid,e.toplevel,e.queryid)
       WHERE e.snapshot_id=end_snapshot AND NOT
        (((s.snapshot_id IS NOT NULL AND e.stats_since=s.stats_since) OR
          (s.snapshot_id IS NULL AND e.stats_since>=a.captured_at)) AND
          e.calls>=coalesce(s.calls,0) AND e.exec_ms>=coalesce(s.exec_ms,0) AND
          e.rows>=coalesce(s.rows,0) AND e.shared_blks_hit>=coalesce(s.shared_blks_hit,0) AND
          e.shared_blks_read>=coalesce(s.shared_blks_read,0));
    END IF;
  END IF;
  RETURN jsonb_build_object('begin_snapshot',begin_snapshot,'end_snapshot',end_snapshot,
    'elapsed_seconds',extract(epoch FROM b.captured_at-a.captured_at),
    'database_delta',delta,'wait_samples',waits,'blocking_samples',blocking,
    'sampling_scope','retained active-session observations; sample counts are not durations',
    'sql_status',sql_status,'top_sql',queries,'sql_not_comparable',skipped,
    'sql_coverage_limited',a.sql_truncated OR b.sql_truncated OR
      (a.sql_info->>'dealloc') IS DISTINCT FROM (b.sql_info->>'dealloc'));
END $$;

CREATE FUNCTION ivorysql_perf.start_collector() RETURNS void AS 'MODULE_PATHNAME','ivorysql_perf_start'
LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION ivorysql_perf.stop_collector() RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp SET ivorysql.identifier_case_switch = normal AS $$
DECLARE n integer := 0; target record;
BEGIN
  PERFORM pg_catalog.pg_stat_clear_snapshot();
  FOR target IN SELECT pid FROM pg_catalog.pg_stat_activity
    WHERE datname=current_database() AND backend_type='ivorysql perf collector'
      AND pid<>pg_backend_pid() LOOP
    IF pg_catalog.pg_terminate_backend(target.pid) THEN n := n+1; END IF;
  END LOOP;
  RETURN n;
END $$;
CREATE VIEW ivorysql_perf.collector_status AS
SELECT pid,backend_start,state,wait_event_type,wait_event FROM pg_catalog.pg_stat_activity
WHERE datname=current_database() AND backend_type='ivorysql perf collector';

REVOKE ALL ON SCHEMA ivorysql_perf FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA ivorysql_perf FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA ivorysql_perf FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA ivorysql_perf FROM PUBLIC;
GRANT USAGE ON SCHEMA ivorysql_perf TO pg_monitor;
GRANT SELECT ON ALL TABLES IN SCHEMA ivorysql_perf TO pg_monitor;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ivorysql_perf TO pg_monitor;
