/*-------------------------------------------------------------------------
 * Copyright 2026 IvorySQL Global Development Team
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * dbms_job--1.0.sql
 *
 * Oracle-compatible DBMS_JOB package, the pre-10g job interface that Oracle
 * still documents.  IvorySQL already ships the scheduler, so DBMS_JOB is a thin
 * layer over the same C entry points DBMS_SCHEDULER uses: SUBMIT creates a
 * disabled job named JOB$nnn (Oracle's own naming), RUN runs it once and REMOVE
 * drops it.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_job/dbms_job--1.0.sql
 *
 *-------------------------------------------------------------------------
 */

-- Oracle names the jobs JOB$<number>; the sequence keeps them unique, and the
-- scheduler already keys jobs by owner + name.
CREATE SEQUENCE sys.dbms_job_id_seq;

CREATE OR REPLACE PACKAGE dbms_job IS
    PROCEDURE submit(job OUT NUMBER, what VARCHAR2);
    PROCEDURE run(job NUMBER);
    PROCEDURE remove(job NUMBER);
END;

CREATE OR REPLACE PACKAGE BODY dbms_job IS

    /* The scheduler identifies a job by name, DBMS_JOB by number. */
    FUNCTION job_name_of(p_job NUMBER) RETURN TEXT IS
        nm TEXT;
    BEGIN
        SELECT job_name INTO nm
          FROM sys.scheduler_jobs
         WHERE job_id = p_job::INT8;
        RETURN nm;
    END;

    PROCEDURE submit(job OUT NUMBER, what VARCHAR2) IS
        nm TEXT;
    BEGIN
        nm := 'JOB$' || nextval('sys.dbms_job_id_seq')::TEXT;
        PERFORM sys.ora_dbms_scheduler_create_job_inline(
                    nm, 'PLSQL_BLOCK', what::TEXT, 0, NULL, NULL, NULL,
                    'DEFAULT_JOB_CLASS', false, true, NULL);
        SELECT job_id INTO job
          FROM sys.scheduler_jobs
         WHERE job_name = nm;
    END;

    PROCEDURE run(job NUMBER) IS
    BEGIN
        PERFORM sys.ora_dbms_scheduler_run_job(job_name_of(job), true);
    END;

    PROCEDURE remove(job NUMBER) IS
    BEGIN
        PERFORM sys.ora_dbms_scheduler_drop_job(job_name_of(job), false, false,
                                                'STOP_ON_FIRST_ERROR');
    END;

END;

GRANT EXECUTE ON PACKAGE dbms_job TO PUBLIC;
