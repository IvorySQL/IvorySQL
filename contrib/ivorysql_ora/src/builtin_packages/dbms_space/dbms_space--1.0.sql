/***************************************************************
 *
 * DBMS_SPACE Package
 *
 * Oracle-compatible space usage and capacity planning utilities.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_space/dbms_space--1.0.sql
 *
 ***************************************************************/

-- Composite return types
CREATE TYPE sys.dbms_space_unused_space_result AS (
    total_blocks                bigint,
    total_bytes                 bigint,
    unused_blocks               bigint,
    unused_bytes                bigint,
    last_used_extent_file_id    bigint,
    last_used_extent_block_id   bigint,
    last_used_block             bigint
);

CREATE TYPE sys.dbms_space_space_usage_result AS (
    unformatted_blocks  bigint,
    unformatted_bytes   bigint,
    fs1_blocks          bigint,
    fs1_bytes           bigint,
    fs2_blocks          bigint,
    fs2_bytes           bigint,
    fs3_blocks          bigint,
    fs3_bytes           bigint,
    fs4_blocks          bigint,
    fs4_bytes           bigint,
    full_blocks         bigint,
    full_bytes          bigint
);

-- Internal C resolvers
CREATE FUNCTION sys.dbms_space_unused_space_internal(segment_owner text,
                                                     segment_name text,
                                                     segment_type text,
                                                     partition_name text)
RETURNS sys.dbms_space_unused_space_result
AS 'MODULE_PATHNAME', 'dbms_space_unused_space_internal'
LANGUAGE C STABLE;

CREATE FUNCTION sys.dbms_space_space_usage_internal(segment_owner text,
                                                    segment_name text,
                                                    segment_type text,
                                                    partition_name text)
RETURNS sys.dbms_space_space_usage_result
AS 'MODULE_PATHNAME', 'dbms_space_space_usage_internal'
LANGUAGE C STABLE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_space_unused_space_internal(text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_space_space_usage_internal(text, text, text, text) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_space AS

    /*
     * UNUSED_SPACE
     * Returns total blocks, total bytes, unused blocks/bytes, and extent info.
     */
    PROCEDURE unused_space(segment_owner             IN  VARCHAR2,
                           segment_name              IN  VARCHAR2,
                           segment_type              IN  VARCHAR2,
                           total_blocks              OUT NUMBER,
                           total_bytes               OUT NUMBER,
                           unused_blocks             OUT NUMBER,
                           unused_bytes              OUT NUMBER,
                           last_used_extent_file_id  OUT NUMBER,
                           last_used_extent_block_id OUT NUMBER,
                           last_used_block           OUT NUMBER,
                           partition_name            IN  VARCHAR2 DEFAULT NULL);

    /*
     * SPACE_USAGE
     * Returns block space distribution (unformatted, free-space ranges, full).
     */
    PROCEDURE space_usage(segment_owner      IN  VARCHAR2,
                          segment_name       IN  VARCHAR2,
                          segment_type       IN  VARCHAR2,
                          unformatted_blocks OUT NUMBER,
                          unformatted_bytes  OUT NUMBER,
                          fs1_blocks         OUT NUMBER,
                          fs1_bytes          OUT NUMBER,
                          fs2_blocks         OUT NUMBER,
                          fs2_bytes          OUT NUMBER,
                          fs3_blocks         OUT NUMBER,
                          fs3_bytes          OUT NUMBER,
                          fs4_blocks         OUT NUMBER,
                          fs4_bytes          OUT NUMBER,
                          full_blocks        OUT NUMBER,
                          full_bytes         OUT NUMBER,
                          partition_name     IN  VARCHAR2 DEFAULT NULL);

END dbms_space;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_space AS

    PROCEDURE unused_space(segment_owner             IN  VARCHAR2,
                           segment_name              IN  VARCHAR2,
                           segment_type              IN  VARCHAR2,
                           total_blocks              OUT NUMBER,
                           total_bytes               OUT NUMBER,
                           unused_blocks             OUT NUMBER,
                           unused_bytes              OUT NUMBER,
                           last_used_extent_file_id  OUT NUMBER,
                           last_used_extent_block_id OUT NUMBER,
                           last_used_block           OUT NUMBER,
                           partition_name            IN  VARCHAR2 DEFAULT NULL) IS
        res sys.dbms_space_unused_space_result;
    BEGIN
        res := sys.dbms_space_unused_space_internal(segment_owner::text,
                                                    segment_name::text,
                                                    segment_type::text,
                                                    partition_name::text);
        total_blocks              := res.total_blocks;
        total_bytes               := res.total_bytes;
        unused_blocks             := res.unused_blocks;
        unused_bytes              := res.unused_bytes;
        last_used_extent_file_id  := res.last_used_extent_file_id;
        last_used_extent_block_id := res.last_used_extent_block_id;
        last_used_block           := res.last_used_block;
    END;

    PROCEDURE space_usage(segment_owner      IN  VARCHAR2,
                          segment_name       IN  VARCHAR2,
                          segment_type       IN  VARCHAR2,
                          unformatted_blocks OUT NUMBER,
                          unformatted_bytes  OUT NUMBER,
                          fs1_blocks         OUT NUMBER,
                          fs1_bytes          OUT NUMBER,
                          fs2_blocks         OUT NUMBER,
                          fs2_bytes          OUT NUMBER,
                          fs3_blocks         OUT NUMBER,
                          fs3_bytes          OUT NUMBER,
                          fs4_blocks         OUT NUMBER,
                          fs4_bytes          OUT NUMBER,
                          full_blocks        OUT NUMBER,
                          full_bytes         OUT NUMBER,
                          partition_name     IN  VARCHAR2 DEFAULT NULL) IS
        res sys.dbms_space_space_usage_result;
    BEGIN
        res := sys.dbms_space_space_usage_internal(segment_owner::text,
                                                   segment_name::text,
                                                   segment_type::text,
                                                   partition_name::text);
        unformatted_blocks := res.unformatted_blocks;
        unformatted_bytes  := res.unformatted_bytes;
        fs1_blocks         := res.fs1_blocks;
        fs1_bytes          := res.fs1_bytes;
        fs2_blocks         := res.fs2_blocks;
        fs2_bytes          := res.fs2_bytes;
        fs3_blocks         := res.fs3_blocks;
        fs3_bytes          := res.fs3_bytes;
        fs4_blocks         := res.fs4_blocks;
        fs4_bytes          := res.fs4_bytes;
        full_blocks        := res.full_blocks;
        full_bytes         := res.full_bytes;
    END;

END dbms_space;
