--
-- ORA_DBMS_SESSION_SLEEP
-- DBMS_SESSION.SLEEP -- Oracle semantics
--
-- Oracle treats 0 as a no-op, accepts fractional seconds, and rejects a
-- negative time limit with ORA-38148 ("invalid time limit specified").
--

-- zero returns immediately
DO LANGUAGE plisql $$
DECLARE
    t0 float8;
BEGIN
    t0 := extract(epoch from clock_timestamp());
    dbms_session.sleep(0);
    RAISE NOTICE 'sleep(0) under 50ms: %',
        (extract(epoch from clock_timestamp()) - t0) < 0.05;
END;
$$;

-- fractional seconds are honoured
DO LANGUAGE plisql $$
DECLARE
    t0 float8;
BEGIN
    t0 := extract(epoch from clock_timestamp());
    dbms_session.sleep(0.2);
    RAISE NOTICE 'sleep(0.2) at least 200ms: %',
        (extract(epoch from clock_timestamp()) - t0) >= 0.2;
END;
$$;

-- negative time limit is rejected
DO LANGUAGE plisql $$
BEGIN
    dbms_session.sleep(-1);
    RAISE NOTICE 'negative slept without error';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'sleep(-1) raised: %', SQLERRM;
END;
$$;
