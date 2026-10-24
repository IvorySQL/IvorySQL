/***************************************************************
 *
 * DBMS_RESOURCE_MANAGER Package
 *
 * Oracle-compatible Database Resource Manager administration.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_resource_manager/dbms_resource_manager--1.0.sql
 *
 ***************************************************************/

-- Catalog tables for resource management
CREATE TABLE IF NOT EXISTS sys.resource_plans (
    plan                    varchar2(128) PRIMARY KEY,
    num_plan_directives     integer DEFAULT 0,
    comments                varchar2(2047),
    status                  varchar2(32) DEFAULT 'ACTIVE',
    mandatory               boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS sys.resource_consumer_groups (
    consumer_group          varchar2(128) PRIMARY KEY,
    comments                varchar2(2047),
    cpu_method              integer DEFAULT 1,
    status                  varchar2(32) DEFAULT 'ACTIVE',
    mandatory               boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS sys.resource_plan_directives (
    plan                    varchar2(128),
    group_or_subplan        varchar2(128),
    is_subplan              boolean DEFAULT false,
    cpu_p1                  integer DEFAULT 100,
    cpu_p2                  integer DEFAULT 0,
    active_sess_pool_limit  integer DEFAULT 0,
    comments                varchar2(2047),
    status                  varchar2(32) DEFAULT 'ACTIVE',
    mandatory               boolean DEFAULT false,
    PRIMARY KEY (plan, group_or_subplan)
);

-- Internal C resolvers
CREATE FUNCTION sys.dbms_resource_manager_create_pending_area_internal()
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_resource_manager_create_pending_area_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_resource_manager_clear_pending_area_internal()
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_resource_manager_clear_pending_area_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_resource_manager_validate_pending_area_internal()
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_resource_manager_validate_pending_area_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_resource_manager_submit_pending_area_internal()
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_resource_manager_submit_pending_area_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_resource_manager_create_plan_internal(plan text,
                                                               comments text,
                                                               cpu_mth integer,
                                                               active_sess_pool_mth integer,
                                                               parallel_degree_limit_mth integer,
                                                               queueing_mth integer)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_resource_manager_create_plan_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_resource_manager_delete_plan_internal(plan text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_resource_manager_delete_plan_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_resource_manager_create_consumer_group_internal(consumer_group text,
                                                                         comments text,
                                                                         cpu_mth integer)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_resource_manager_create_consumer_group_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_resource_manager_delete_consumer_group_internal(consumer_group text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_resource_manager_delete_consumer_group_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_resource_manager_create_plan_directive_internal(plan text,
                                                                         group_or_subplan text,
                                                                         comments text,
                                                                         cpu_p1 integer,
                                                                         cpu_p2 integer,
                                                                         active_sess_pool_limit integer,
                                                                         queueing_time_limit integer,
                                                                         parallel_degree_limit_p1 integer)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_resource_manager_create_plan_directive_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_resource_manager_delete_plan_directive_internal(plan text,
                                                                         group_or_subplan text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_resource_manager_delete_plan_directive_internal'
LANGUAGE C VOLATILE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_resource_manager_create_pending_area_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_resource_manager_clear_pending_area_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_resource_manager_validate_pending_area_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_resource_manager_submit_pending_area_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_resource_manager_create_plan_internal(text, text, integer, integer, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_resource_manager_delete_plan_internal(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_resource_manager_create_consumer_group_internal(text, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_resource_manager_delete_consumer_group_internal(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_resource_manager_create_plan_directive_internal(text, text, text, integer, integer, integer, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_resource_manager_delete_plan_directive_internal(text, text) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_resource_manager AS

    /*
     * Pending area lifecycle procedures
     */
    PROCEDURE create_pending_area;
    PROCEDURE clear_pending_area;
    PROCEDURE validate_pending_area;
    PROCEDURE submit_pending_area;

    /*
     * Resource plans
     */
    PROCEDURE create_plan(plan                      IN VARCHAR2,
                          comments                  IN VARCHAR2 DEFAULT NULL,
                          cpu_mth                   IN VARCHAR2 DEFAULT 'EMPHASIS',
                          active_sess_pool_mth      IN VARCHAR2 DEFAULT 'ACTIVE_SESS_POOL_ABSOLUTE',
                          parallel_degree_limit_mth IN VARCHAR2 DEFAULT 'PARALLEL_DEGREE_LIMIT_ABSOLUTE',
                          queueing_mth              IN VARCHAR2 DEFAULT 'FIFO_TIMEOUT');

    PROCEDURE delete_plan(plan IN VARCHAR2);

    /*
     * Consumer groups
     */
    PROCEDURE create_consumer_group(consumer_group IN VARCHAR2,
                                    comments       IN VARCHAR2 DEFAULT NULL,
                                    cpu_mth        IN VARCHAR2 DEFAULT 'ROUND-ROBIN');

    PROCEDURE delete_consumer_group(consumer_group IN VARCHAR2);

    /*
     * Plan directives
     */
    PROCEDURE create_plan_directive(plan                      IN VARCHAR2,
                                    group_or_subplan          IN VARCHAR2,
                                    comments                  IN VARCHAR2 DEFAULT NULL,
                                    cpu_p1                    IN NUMBER DEFAULT NULL,
                                    cpu_p2                    IN NUMBER DEFAULT NULL,
                                    active_sess_pool_limit    IN NUMBER DEFAULT NULL,
                                    queueing_time_limit       IN NUMBER DEFAULT NULL,
                                    parallel_degree_limit_p1  IN NUMBER DEFAULT NULL);

    PROCEDURE delete_plan_directive(plan             IN VARCHAR2,
                                    group_or_subplan IN VARCHAR2);

END dbms_resource_manager;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_resource_manager AS

    PROCEDURE create_pending_area IS
    BEGIN
        PERFORM sys.dbms_resource_manager_create_pending_area_internal();
    END;

    PROCEDURE clear_pending_area IS
    BEGIN
        PERFORM sys.dbms_resource_manager_clear_pending_area_internal();
    END;

    PROCEDURE validate_pending_area IS
    BEGIN
        PERFORM sys.dbms_resource_manager_validate_pending_area_internal();
    END;

    PROCEDURE submit_pending_area IS
    BEGIN
        PERFORM sys.dbms_resource_manager_submit_pending_area_internal();
    END;

    PROCEDURE create_plan(plan                      IN VARCHAR2,
                          comments                  IN VARCHAR2 DEFAULT NULL,
                          cpu_mth                   IN VARCHAR2 DEFAULT 'EMPHASIS',
                          active_sess_pool_mth      IN VARCHAR2 DEFAULT 'ACTIVE_SESS_POOL_ABSOLUTE',
                          parallel_degree_limit_mth IN VARCHAR2 DEFAULT 'PARALLEL_DEGREE_LIMIT_ABSOLUTE',
                          queueing_mth              IN VARCHAR2 DEFAULT 'FIFO_TIMEOUT') IS
    BEGIN
        PERFORM sys.dbms_resource_manager_create_plan_internal(plan::text,
                                                               comments::text,
                                                               1, 1, 1, 1);
    END;

    PROCEDURE delete_plan(plan IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_resource_manager_delete_plan_internal(plan::text);
    END;

    PROCEDURE create_consumer_group(consumer_group IN VARCHAR2,
                                    comments       IN VARCHAR2 DEFAULT NULL,
                                    cpu_mth        IN VARCHAR2 DEFAULT 'ROUND-ROBIN') IS
    BEGIN
        PERFORM sys.dbms_resource_manager_create_consumer_group_internal(consumer_group::text,
                                                                         comments::text,
                                                                         1);
    END;

    PROCEDURE delete_consumer_group(consumer_group IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_resource_manager_delete_consumer_group_internal(consumer_group::text);
    END;

    PROCEDURE create_plan_directive(plan                      IN VARCHAR2,
                                    group_or_subplan          IN VARCHAR2,
                                    comments                  IN VARCHAR2 DEFAULT NULL,
                                    cpu_p1                    IN NUMBER DEFAULT NULL,
                                    cpu_p2                    IN NUMBER DEFAULT NULL,
                                    active_sess_pool_limit    IN NUMBER DEFAULT NULL,
                                    queueing_time_limit       IN NUMBER DEFAULT NULL,
                                    parallel_degree_limit_p1  IN NUMBER DEFAULT NULL) IS
    BEGIN
        PERFORM sys.dbms_resource_manager_create_plan_directive_internal(plan::text,
                                                                         group_or_subplan::text,
                                                                         comments::text,
                                                                         COALESCE(cpu_p1, 0)::integer,
                                                                         COALESCE(cpu_p2, 0)::integer,
                                                                         COALESCE(active_sess_pool_limit, 0)::integer,
                                                                         COALESCE(queueing_time_limit, 0)::integer,
                                                                         COALESCE(parallel_degree_limit_p1, 0)::integer);
    END;

    PROCEDURE delete_plan_directive(plan             IN VARCHAR2,
                                    group_or_subplan IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_resource_manager_delete_plan_directive_internal(plan::text,
                                                                         group_or_subplan::text);
    END;

END dbms_resource_manager;
