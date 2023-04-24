/* contrib/pageinspect/pageinspect--1.11--1.12.sql */

-- complain if script is sourced in psql, rather than via ALTER EXTENSION
\echo Use "ALTER EXTENSION pageinspect UPDATE TO '1.12'" to load this file. \quit

--
-- bt_multi_page_stats()
--
CREATE FUNCTION bt_multi_page_stats(IN relname text, IN blkno int8, IN blk_count int8,
    OUT blkno int8,
    OUT type "char",
    OUT live_items int4,
    OUT dead_items int4,
    OUT avg_item_size int4,
    OUT page_size int4,
    OUT free_size int4,
    OUT btpo_prev int8,
    OUT btpo_next int8,
    OUT btpo_level int8,
    OUT btpo_flags int4)
RETURNS SETOF record
AS 'MODULE_PATHNAME', 'bt_multi_page_stats'
LANGUAGE C STRICT PARALLEL RESTRICTED;
