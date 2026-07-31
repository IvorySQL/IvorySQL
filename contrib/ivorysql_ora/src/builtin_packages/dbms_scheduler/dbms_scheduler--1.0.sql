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
 * dbms_scheduler--1.0.sql
 *
 * Oracle-compatible DBMS_SCHEDULER package (EDB-parity subset):
 * CREATE_JOB (2 overloads), CREATE_PROGRAM, CREATE_SCHEDULE,
 * DEFINE_PROGRAM_ARGUMENT (2), DISABLE, DROP_JOB, DROP_PROGRAM,
 * DROP_PROGRAM_ARGUMENT (2), DROP_SCHEDULE, ENABLE,
 * EVALUATE_CALENDAR_STRING, RUN_JOB and SET_JOB_ARGUMENT_VALUE (2),
 * plus STOP_JOB, which Oracle has but EDB Postgres Advanced Server does not.
 *
 * Background scheduling is off by default.  Jobs run automatically only when
 * ivorysql_ora is preloaded (the oracle-mode default), ivorysql_ora.scheduler
 * is set to on, and the database is listed in ivorysql_ora.scheduler_databases.
 * Everything else in the package works regardless: RUN_JOB executes a job
 * synchronously in the current session.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_scheduler/dbms_scheduler--1.0.sql
 *
 *-------------------------------------------------------------------------
 */

/*
 * Scheduler metadata.
 *
 * Object names are stored normalized (unquoted names are upper-cased) and
 * owners are role names.  Row level security restricts users to their own
 * scheduler objects; all modifications go through the package procedures,
 * which validate ownership in C before writing with escalated rights.
 */

CREATE SEQUENCE sys.scheduler_job_id_seq;
CREATE SEQUENCE sys.scheduler_log_id_seq;

CREATE TABLE sys.scheduler_programs (
	program_owner		name NOT NULL,
	program_name		name NOT NULL,
	program_type		text COLLATE "c" NOT NULL
		CHECK (program_type IN ('PLSQL_BLOCK', 'STORED_PROCEDURE')),
	program_action		text COLLATE "c" NOT NULL,
	number_of_arguments	int NOT NULL DEFAULT 0
		CHECK (number_of_arguments >= 0 AND number_of_arguments <= 255),
	enabled				boolean NOT NULL DEFAULT false,
	comments			text COLLATE "c",
	CONSTRAINT scheduler_programs_pkey PRIMARY KEY (program_owner, program_name)
);

CREATE TABLE sys.scheduler_program_args (
	program_owner		name NOT NULL,
	program_name		name NOT NULL,
	argument_position	int NOT NULL
		CHECK (argument_position >= 1 AND argument_position <= 255),
	argument_name		name,
	argument_type		text COLLATE "c",
	default_value		text COLLATE "c",
	has_default			boolean NOT NULL DEFAULT false,
	out_argument		boolean NOT NULL DEFAULT false,
	CONSTRAINT scheduler_program_args_pkey
		PRIMARY KEY (program_owner, program_name, argument_position),
	CONSTRAINT scheduler_program_args_fk
		FOREIGN KEY (program_owner, program_name)
		REFERENCES sys.scheduler_programs (program_owner, program_name)
		ON DELETE CASCADE
);

CREATE UNIQUE INDEX scheduler_program_args_name_idx
	ON sys.scheduler_program_args (program_owner, program_name, argument_name)
	WHERE argument_name IS NOT NULL;

CREATE TABLE sys.scheduler_schedules (
	schedule_owner		name NOT NULL,
	schedule_name		name NOT NULL,
	start_date			timestamptz,
	repeat_interval		text COLLATE "c",
	end_date			timestamptz,
	comments			text COLLATE "c",
	CONSTRAINT scheduler_schedules_pkey PRIMARY KEY (schedule_owner, schedule_name)
);

CREATE TABLE sys.scheduler_jobs (
	job_owner			name NOT NULL,
	job_name			name NOT NULL,
	job_id				bigint NOT NULL DEFAULT nextval('sys.scheduler_job_id_seq'),
	/* inline-style jobs */
	job_type			text COLLATE "c"
		CHECK (job_type IN ('PLSQL_BLOCK', 'STORED_PROCEDURE')),
	job_action			text COLLATE "c",
	number_of_arguments	int NOT NULL DEFAULT 0
		CHECK (number_of_arguments >= 0 AND number_of_arguments <= 255),
	/* named-program jobs */
	program_owner		name,
	program_name		name,
	schedule_owner		name,
	schedule_name		name,
	/* scheduling */
	start_date			timestamptz,
	repeat_interval		text COLLATE "c",
	end_date			timestamptz,
	next_run_date		timestamptz,
	/* accepted for Oracle compatibility; not acted upon */
	job_class			text COLLATE "c",
	auto_drop			boolean NOT NULL DEFAULT true,
	comments			text COLLATE "c",
	/* state */
	enabled				boolean NOT NULL DEFAULT false,
	state				text COLLATE "c" NOT NULL DEFAULT 'DISABLED'
		CHECK (state IN ('DISABLED', 'SCHEDULED', 'RUNNING',
						 'SUCCEEDED', 'FAILED', 'COMPLETED')),
	run_count			bigint NOT NULL DEFAULT 0,
	failure_count		bigint NOT NULL DEFAULT 0,
	last_start_date		timestamptz,
	last_end_date		timestamptz,
	CONSTRAINT scheduler_jobs_pkey PRIMARY KEY (job_owner, job_name),
	CONSTRAINT scheduler_jobs_style_check CHECK (
		(job_type IS NOT NULL AND job_action IS NOT NULL
		 AND program_name IS NULL AND schedule_name IS NULL)
		OR
		(job_type IS NULL AND job_action IS NULL
		 AND program_name IS NOT NULL AND schedule_name IS NOT NULL)
	)
);

CREATE UNIQUE INDEX scheduler_jobs_job_id_idx ON sys.scheduler_jobs (job_id);
CREATE INDEX scheduler_jobs_next_run_idx ON sys.scheduler_jobs (next_run_date)
	WHERE enabled;

CREATE TABLE sys.scheduler_job_args (
	job_owner			name NOT NULL,
	job_name			name NOT NULL,
	argument_position	int NOT NULL
		CHECK (argument_position >= 1 AND argument_position <= 255),
	argument_value		text COLLATE "c",
	CONSTRAINT scheduler_job_args_pkey
		PRIMARY KEY (job_owner, job_name, argument_position),
	CONSTRAINT scheduler_job_args_fk
		FOREIGN KEY (job_owner, job_name)
		REFERENCES sys.scheduler_jobs (job_owner, job_name)
		ON DELETE CASCADE
);

/*
 * Job run log.  No foreign key: history outlives its job, matching Oracle's
 * *_SCHEDULER_JOB_RUN_DETAILS behavior.
 */
CREATE TABLE sys.scheduler_job_run_details (
	log_id				bigint NOT NULL DEFAULT nextval('sys.scheduler_log_id_seq'),
	log_date			timestamptz NOT NULL DEFAULT now(),
	job_owner			name NOT NULL,
	job_name			name NOT NULL,
	job_id				bigint,
	status				text COLLATE "c" NOT NULL CHECK (status IN ('r', 's', 'f')),
	error_no			int,
	error_message		text COLLATE "c",
	req_start_date		timestamptz,
	actual_start_date	timestamptz,
	/* process running the job, so STOP_JOB can find it */
	worker_pid			int,
	/* qualified: bare "interval" does not parse as a type in oracle mode */
	run_duration		pg_catalog.interval,
	CONSTRAINT scheduler_job_run_details_pkey PRIMARY KEY (log_id)
);

CREATE INDEX scheduler_job_run_details_job_idx
	ON sys.scheduler_job_run_details (job_owner, job_name);

/*
 * Visibility.
 *
 * The base tables carry no PUBLIC privileges (initdb-created relations have
 * OIDs below FirstNormalObjectId, which exempts them from row level
 * security, so RLS cannot be used here).  Users work through the
 * USER_SCHEDULER_* dictionary views below, which expose only their own
 * objects; DBA_SCHEDULER_* views expose everything and are not granted to
 * PUBLIC (superusers and explicitly granted roles only).  All writes go
 * through the package procedures, which validate ownership in C.
 */

CREATE VIEW sys.dba_scheduler_programs AS
	SELECT program_owner AS owner, program_name, program_type,
		   program_action, number_of_arguments, enabled, comments
	FROM sys.scheduler_programs;

CREATE VIEW sys.user_scheduler_programs AS
	SELECT program_name, program_type, program_action,
		   number_of_arguments, enabled, comments
	FROM sys.scheduler_programs
	WHERE program_owner = current_user::text;

CREATE VIEW sys.dba_scheduler_program_args AS
	SELECT program_owner AS owner, program_name, argument_name,
		   argument_position, argument_type, default_value, out_argument
	FROM sys.scheduler_program_args;

CREATE VIEW sys.user_scheduler_program_args AS
	SELECT program_name, argument_name, argument_position, argument_type,
		   default_value, out_argument
	FROM sys.scheduler_program_args
	WHERE program_owner = current_user::text;

CREATE VIEW sys.dba_scheduler_schedules AS
	SELECT schedule_owner AS owner, schedule_name, start_date,
		   repeat_interval, end_date, comments
	FROM sys.scheduler_schedules;

CREATE VIEW sys.user_scheduler_schedules AS
	SELECT schedule_name, start_date, repeat_interval, end_date, comments
	FROM sys.scheduler_schedules
	WHERE schedule_owner = current_user::text;

CREATE VIEW sys.dba_scheduler_jobs AS
	SELECT job_owner AS owner, job_name, job_id, program_owner, program_name,
		   job_type, job_action, number_of_arguments,
		   schedule_owner, schedule_name, start_date, repeat_interval,
		   end_date, next_run_date, job_class, auto_drop, enabled, state,
		   run_count, failure_count, last_start_date,
		   (last_end_date - last_start_date) AS last_run_duration, comments
	FROM sys.scheduler_jobs;

CREATE VIEW sys.user_scheduler_jobs AS
	SELECT job_name, job_id, program_owner, program_name,
		   job_type, job_action, number_of_arguments,
		   schedule_owner, schedule_name, start_date, repeat_interval,
		   end_date, next_run_date, job_class, auto_drop, enabled, state,
		   run_count, failure_count, last_start_date,
		   (last_end_date - last_start_date) AS last_run_duration, comments
	FROM sys.scheduler_jobs
	WHERE job_owner = current_user::text;

CREATE VIEW sys.dba_scheduler_job_args AS
	SELECT job_owner AS owner, job_name, argument_position, argument_value AS value
	FROM sys.scheduler_job_args;

CREATE VIEW sys.user_scheduler_job_args AS
	SELECT job_name, argument_position, argument_value AS value
	FROM sys.scheduler_job_args
	WHERE job_owner = current_user::text;

/* worker_pid is exposed under Oracle's column name for the same thing. */
CREATE VIEW sys.dba_scheduler_job_run_details AS
	SELECT log_id, log_date, job_owner AS owner, job_name, job_id, status,
		   error_no, error_message, req_start_date, actual_start_date,
		   worker_pid AS slave_pid, run_duration
	FROM sys.scheduler_job_run_details;

CREATE VIEW sys.user_scheduler_job_run_details AS
	SELECT log_id, log_date, job_name, job_id, status,
		   error_no, error_message, req_start_date, actual_start_date,
		   worker_pid AS slave_pid, run_duration
	FROM sys.scheduler_job_run_details
	WHERE job_owner = current_user::text;

GRANT SELECT ON sys.user_scheduler_programs TO PUBLIC;
GRANT SELECT ON sys.user_scheduler_program_args TO PUBLIC;
GRANT SELECT ON sys.user_scheduler_schedules TO PUBLIC;
GRANT SELECT ON sys.user_scheduler_jobs TO PUBLIC;
GRANT SELECT ON sys.user_scheduler_job_args TO PUBLIC;
GRANT SELECT ON sys.user_scheduler_job_run_details TO PUBLIC;

/* Keep user-created scheduler metadata in dumps. */
SELECT pg_catalog.pg_extension_config_dump('sys.scheduler_programs', '');
SELECT pg_catalog.pg_extension_config_dump('sys.scheduler_program_args', '');
SELECT pg_catalog.pg_extension_config_dump('sys.scheduler_schedules', '');
SELECT pg_catalog.pg_extension_config_dump('sys.scheduler_jobs', '');
SELECT pg_catalog.pg_extension_config_dump('sys.scheduler_job_args', '');
SELECT pg_catalog.pg_extension_config_dump('sys.scheduler_job_run_details', '');
SELECT pg_catalog.pg_extension_config_dump('sys.scheduler_job_id_seq', '');
SELECT pg_catalog.pg_extension_config_dump('sys.scheduler_log_id_seq', '');

/* Register C functions for DBMS_SCHEDULER */

CREATE FUNCTION sys.ora_dbms_scheduler_create_job_inline(
	job_name text, job_type text, job_action text,
	number_of_arguments integer, start_date timestamptz,
	repeat_interval text, end_date timestamptz, job_class text,
	enabled boolean, auto_drop boolean, comments text)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_create_job_inline'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_create_job_named(
	job_name text, program_name text, schedule_name text,
	job_class text, enabled boolean, auto_drop boolean, comments text)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_create_job_named'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_create_program(
	program_name text, program_type text, program_action text,
	number_of_arguments integer, enabled boolean, comments text)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_create_program'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_create_schedule(
	schedule_name text, start_date timestamptz, repeat_interval text,
	end_date timestamptz, comments text)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_create_schedule'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_define_program_argument(
	program_name text, argument_position integer, argument_name text,
	argument_type text, default_value text, has_default boolean,
	out_argument boolean)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_define_program_argument'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_drop_program_argument_pos(
	program_name text, argument_position integer)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_drop_program_argument_pos'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_drop_program_argument_name(
	program_name text, argument_name text)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_drop_program_argument_name'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_enable(
	name text, commit_semantics text)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_enable'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_disable(
	name text, force boolean, commit_semantics text)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_disable'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_drop_job(
	job_name text, force boolean, defer boolean, commit_semantics text)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_drop_job'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_drop_program(
	program_name text, force boolean)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_drop_program'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_drop_schedule(
	schedule_name text, force boolean)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_drop_schedule'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_evaluate_calendar_string(
	calendar_string text, start_date timestamptz, return_date_after timestamptz)
RETURNS timestamptz
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_evaluate_calendar_string'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_run_job(
	job_name text, use_current_session boolean)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_run_job'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_stop_job(
	job_name text, force boolean, commit_semantics text)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_stop_job'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_set_job_argument_value_pos(
	job_name text, argument_position integer, argument_value text)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_set_job_argument_value_pos'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_scheduler_set_job_argument_value_name(
	job_name text, argument_name text, argument_value text)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_set_job_argument_value_name'
LANGUAGE C VOLATILE;

/* SYS_CONTEXT('USERENV', ...) readers */
CREATE FUNCTION sys.get_bg_job_id()
RETURNS text
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_get_bg_job_id'
LANGUAGE C STABLE;

CREATE FUNCTION sys.get_fg_job_id()
RETURNS text
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_get_fg_job_id'
LANGUAGE C STABLE;

CREATE FUNCTION sys.get_scheduler_job()
RETURNS text
AS 'MODULE_PATHNAME', 'ora_dbms_scheduler_get_scheduler_job'
LANGUAGE C STABLE;

/* Create DBMS_SCHEDULER package */
CREATE OR REPLACE PACKAGE dbms_scheduler IS

	PROCEDURE create_job(job_name VARCHAR2, job_type VARCHAR2,
		job_action VARCHAR2,
		number_of_arguments INTEGER DEFAULT 0,
		start_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
		repeat_interval VARCHAR2 DEFAULT NULL,
		end_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
		job_class VARCHAR2 DEFAULT 'DEFAULT_JOB_CLASS',
		enabled BOOLEAN DEFAULT FALSE,
		auto_drop BOOLEAN DEFAULT TRUE,
		comments VARCHAR2 DEFAULT NULL);

	PROCEDURE create_job(job_name VARCHAR2, program_name VARCHAR2,
		schedule_name VARCHAR2,
		job_class VARCHAR2 DEFAULT 'DEFAULT_JOB_CLASS',
		enabled BOOLEAN DEFAULT FALSE,
		auto_drop BOOLEAN DEFAULT TRUE,
		comments VARCHAR2 DEFAULT NULL);

	PROCEDURE create_program(program_name VARCHAR2, program_type VARCHAR2,
		program_action VARCHAR2,
		number_of_arguments INTEGER DEFAULT 0,
		enabled BOOLEAN DEFAULT FALSE,
		comments VARCHAR2 DEFAULT NULL);

	PROCEDURE create_schedule(schedule_name VARCHAR2,
		start_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
		repeat_interval VARCHAR2 DEFAULT NULL,
		end_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
		comments VARCHAR2 DEFAULT NULL);

	PROCEDURE define_program_argument(program_name VARCHAR2,
		argument_position INTEGER,
		argument_name VARCHAR2 DEFAULT NULL,
		argument_type VARCHAR2,
		out_argument BOOLEAN DEFAULT FALSE);

	PROCEDURE define_program_argument(program_name VARCHAR2,
		argument_position INTEGER,
		argument_name VARCHAR2 DEFAULT NULL,
		argument_type VARCHAR2,
		default_value VARCHAR2,
		out_argument BOOLEAN DEFAULT FALSE);

	PROCEDURE disable(name VARCHAR2,
		force BOOLEAN DEFAULT FALSE,
		commit_semantics VARCHAR2 DEFAULT 'STOP_ON_FIRST_ERROR');

	PROCEDURE drop_job(job_name VARCHAR2,
		force BOOLEAN DEFAULT FALSE,
		defer BOOLEAN DEFAULT FALSE,
		commit_semantics VARCHAR2 DEFAULT 'STOP_ON_FIRST_ERROR');

	PROCEDURE drop_program(program_name VARCHAR2,
		force BOOLEAN DEFAULT FALSE);

	PROCEDURE drop_program_argument(program_name VARCHAR2,
		argument_position INTEGER);

	PROCEDURE drop_program_argument(program_name VARCHAR2,
		argument_name VARCHAR2);

	PROCEDURE drop_schedule(schedule_name VARCHAR2,
		force BOOLEAN DEFAULT FALSE);

	PROCEDURE enable(name VARCHAR2,
		commit_semantics VARCHAR2 DEFAULT 'STOP_ON_FIRST_ERROR');

	PROCEDURE evaluate_calendar_string(calendar_string VARCHAR2,
		start_date IN TIMESTAMP WITH TIME ZONE,
		return_date_after IN TIMESTAMP WITH TIME ZONE,
		next_run_date OUT TIMESTAMP WITH TIME ZONE);

	PROCEDURE run_job(job_name VARCHAR2,
		use_current_session BOOLEAN DEFAULT TRUE);

	PROCEDURE stop_job(job_name VARCHAR2,
		force BOOLEAN DEFAULT FALSE,
		commit_semantics VARCHAR2 DEFAULT 'STOP_ON_FIRST_ERROR');

	PROCEDURE set_job_argument_value(job_name VARCHAR2,
		argument_position INTEGER,
		argument_value VARCHAR2);

	PROCEDURE set_job_argument_value(job_name VARCHAR2,
		argument_name VARCHAR2,
		argument_value VARCHAR2);

END dbms_scheduler;

CREATE OR REPLACE PACKAGE BODY dbms_scheduler IS

	PROCEDURE create_job(job_name VARCHAR2, job_type VARCHAR2,
		job_action VARCHAR2,
		number_of_arguments INTEGER DEFAULT 0,
		start_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
		repeat_interval VARCHAR2 DEFAULT NULL,
		end_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
		job_class VARCHAR2 DEFAULT 'DEFAULT_JOB_CLASS',
		enabled BOOLEAN DEFAULT FALSE,
		auto_drop BOOLEAN DEFAULT TRUE,
		comments VARCHAR2 DEFAULT NULL) IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_create_job_inline(job_name, job_type,
			job_action, number_of_arguments, start_date, repeat_interval,
			end_date, job_class, enabled, auto_drop, comments);
	END;

	PROCEDURE create_job(job_name VARCHAR2, program_name VARCHAR2,
		schedule_name VARCHAR2,
		job_class VARCHAR2 DEFAULT 'DEFAULT_JOB_CLASS',
		enabled BOOLEAN DEFAULT FALSE,
		auto_drop BOOLEAN DEFAULT TRUE,
		comments VARCHAR2 DEFAULT NULL) IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_create_job_named(job_name, program_name,
			schedule_name, job_class, enabled, auto_drop, comments);
	END;

	PROCEDURE create_program(program_name VARCHAR2, program_type VARCHAR2,
		program_action VARCHAR2,
		number_of_arguments INTEGER DEFAULT 0,
		enabled BOOLEAN DEFAULT FALSE,
		comments VARCHAR2 DEFAULT NULL) IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_create_program(program_name,
			program_type, program_action, number_of_arguments, enabled,
			comments);
	END;

	PROCEDURE create_schedule(schedule_name VARCHAR2,
		start_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
		repeat_interval VARCHAR2 DEFAULT NULL,
		end_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
		comments VARCHAR2 DEFAULT NULL) IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_create_schedule(schedule_name,
			start_date, repeat_interval, end_date, comments);
	END;

	PROCEDURE define_program_argument(program_name VARCHAR2,
		argument_position INTEGER,
		argument_name VARCHAR2 DEFAULT NULL,
		argument_type VARCHAR2,
		out_argument BOOLEAN DEFAULT FALSE) IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_define_program_argument(program_name,
			argument_position, argument_name, argument_type, NULL, false,
			out_argument);
	END;

	PROCEDURE define_program_argument(program_name VARCHAR2,
		argument_position INTEGER,
		argument_name VARCHAR2 DEFAULT NULL,
		argument_type VARCHAR2,
		default_value VARCHAR2,
		out_argument BOOLEAN DEFAULT FALSE) IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_define_program_argument(program_name,
			argument_position, argument_name, argument_type, default_value,
			true, out_argument);
	END;

	PROCEDURE disable(name VARCHAR2,
		force BOOLEAN DEFAULT FALSE,
		commit_semantics VARCHAR2 DEFAULT 'STOP_ON_FIRST_ERROR') IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_disable(name, force, commit_semantics);
	END;

	PROCEDURE drop_job(job_name VARCHAR2,
		force BOOLEAN DEFAULT FALSE,
		defer BOOLEAN DEFAULT FALSE,
		commit_semantics VARCHAR2 DEFAULT 'STOP_ON_FIRST_ERROR') IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_drop_job(job_name, force, defer,
			commit_semantics);
	END;

	PROCEDURE drop_program(program_name VARCHAR2,
		force BOOLEAN DEFAULT FALSE) IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_drop_program(program_name, force);
	END;

	PROCEDURE drop_program_argument(program_name VARCHAR2,
		argument_position INTEGER) IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_drop_program_argument_pos(program_name,
			argument_position);
	END;

	PROCEDURE drop_program_argument(program_name VARCHAR2,
		argument_name VARCHAR2) IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_drop_program_argument_name(program_name,
			argument_name);
	END;

	PROCEDURE drop_schedule(schedule_name VARCHAR2,
		force BOOLEAN DEFAULT FALSE) IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_drop_schedule(schedule_name, force);
	END;

	PROCEDURE enable(name VARCHAR2,
		commit_semantics VARCHAR2 DEFAULT 'STOP_ON_FIRST_ERROR') IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_enable(name, commit_semantics);
	END;

	PROCEDURE evaluate_calendar_string(calendar_string VARCHAR2,
		start_date IN TIMESTAMP WITH TIME ZONE,
		return_date_after IN TIMESTAMP WITH TIME ZONE,
		next_run_date OUT TIMESTAMP WITH TIME ZONE) IS
	BEGIN
		next_run_date := sys.ora_dbms_scheduler_evaluate_calendar_string(
			calendar_string, start_date, return_date_after);
	END;

	PROCEDURE run_job(job_name VARCHAR2,
		use_current_session BOOLEAN DEFAULT TRUE) IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_run_job(job_name, use_current_session);
	END;

	PROCEDURE stop_job(job_name VARCHAR2,
		force BOOLEAN DEFAULT FALSE,
		commit_semantics VARCHAR2 DEFAULT 'STOP_ON_FIRST_ERROR') IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_stop_job(job_name, force,
			commit_semantics);
	END;

	PROCEDURE set_job_argument_value(job_name VARCHAR2,
		argument_position INTEGER,
		argument_value VARCHAR2) IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_set_job_argument_value_pos(job_name,
			argument_position, argument_value);
	END;

	PROCEDURE set_job_argument_value(job_name VARCHAR2,
		argument_name VARCHAR2,
		argument_value VARCHAR2) IS
	BEGIN
		PERFORM sys.ora_dbms_scheduler_set_job_argument_value_name(job_name,
			argument_name, argument_value);
	END;

END dbms_scheduler;

GRANT EXECUTE ON PACKAGE dbms_scheduler TO PUBLIC;
