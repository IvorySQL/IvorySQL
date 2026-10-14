set enable_seqscan=off;

CREATE TABLE test_timestamp (
	i timestamp
);

INSERT INTO test_timestamp VALUES
	( '2004-10-26 03:55:08' ),
	( '2004-10-26 04:55:08' ),
	( '2004-10-26 05:55:08' ),
	( '2004-10-26 08:55:08' ),
	( '2004-10-26 09:55:08' ),
	( '2004-10-26 10:55:08' )
;

CREATE INDEX idx_timestamp ON test_timestamp USING gin (i);

SELECT * FROM test_timestamp WHERE i<'2004-10-26 08:55:08'::timestamp ORDER BY i;
SELECT * FROM test_timestamp WHERE i<='2004-10-26 08:55:08'::timestamp ORDER BY i;
SELECT * FROM test_timestamp WHERE i='2004-10-26 08:55:08'::timestamp ORDER BY i;
SELECT * FROM test_timestamp WHERE i>='2004-10-26 08:55:08'::timestamp ORDER BY i;
SELECT * FROM test_timestamp WHERE i>'2004-10-26 08:55:08'::timestamp ORDER BY i;

-- Check endpoint and out-of-range cases

INSERT INTO test_timestamp VALUES ('-infinity'), ('infinity');
SELECT gin_clean_pending_list('idx_timestamp');

-- Check that we aren't fooled by ambiguous timestamps near a DST transition
INSERT INTO test_timestamp VALUES
  ('2026-11-01 00:50'), ('2026-11-01 01:10'), ('2026-11-01 01:20'),
  ('2026-11-01 01:40'), ('2026-11-01 02:10');
SET TimeZone = 'America/New_York';
SELECT * FROM test_timestamp WHERE i>='2026-11-01 01:30-04'::timestamptz ORDER BY i;
SELECT * FROM test_timestamp WHERE i>'2026-11-01 01:30-04'::timestamptz ORDER BY i;
RESET TimeZone;
