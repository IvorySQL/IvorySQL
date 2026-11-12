/*-------------------------------------------------------------------------
 *
 * pg_regress_main --- regression test for the main backend
 *
 * This is a C implementation of the previous shell script for running
 * the regression tests, and should be mostly compatible with it.
 * Initial author of C translation: Magnus Hagander
 *
 * This code is released under the terms of the PostgreSQL License.
 *
 * Portions Copyright (c) 1996-2026, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 *
 * src/test/regress/pg_regress_main.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres_fe.h"

#include "lib/stringinfo.h"
#include "pg_regress.h"


static int	psql_get_ivorysql_port(const char *database);

/*
 * start a psql test process for specified file (including redirection),
 * and return process ID
 */
static PID_TYPE
psql_start_test(const char *testname,
				_stringlist **resultfiles,
				_stringlist **expectfiles,
				_stringlist **tags)
{
	static int	oracle_port = 0;
	PID_TYPE	pid;
	char		infile[MAXPGPATH];
	char		outfile[MAXPGPATH];
	char		expectfile[MAXPGPATH];
	StringInfoData psql_cmd;
	char	   *appnameenv;

	/*
	 * Look for files in the output dir first, consistent with a vpath search.
	 * This is mainly to create more reasonable error messages if the file is
	 * not found.  It also allows local test overrides when running pg_regress
	 * outside of the source tree.
	 */
	snprintf(infile, sizeof(infile), "%s/sql/%s.sql",
			 outputdir, testname);
	if (!file_exists(infile))
		snprintf(infile, sizeof(infile), "%s/sql/%s.sql",
				 inputdir, testname);

	snprintf(outfile, sizeof(outfile), "%s/results/%s.out",
			 outputdir, testname);

	snprintf(expectfile, sizeof(expectfile), "%s/expected/%s.out",
			 expecteddir, testname);
	if (!file_exists(expectfile))
		snprintf(expectfile, sizeof(expectfile), "%s/expected/%s.out",
				 inputdir, testname);

	add_stringlist_item(resultfiles, outfile);
	add_stringlist_item(expectfiles, expectfile);

	/* The port is fixed for the lifetime of the server under test. */
	if (oracle_port == 0)
		oracle_port = psql_get_ivorysql_port(dblist->str);

	initStringInfo(&psql_cmd);

	if (launcher)
		appendStringInfo(&psql_cmd, "%s ", launcher);

	/*
	 * Use HIDE_TABLEAM to hide different AMs to allow to use regression tests
	 * against different AMs without unnecessary differences.
	 */
	appendStringInfo(&psql_cmd,
					 "\"%s%spsql\" -p %d -X -a -q -d \"%s\" %s < \"%s\" > \"%s\" 2>&1",
					 bindir ? bindir : "",
					 bindir ? "/" : "",
					 oracle_port,
					 dblist->str,
					 "-v HIDE_TABLEAM=on -v HIDE_TOAST_COMPRESSION=on",
					 infile,
					 outfile);

	appnameenv = psprintf("pg_regress/%s", testname);
	setenv("PGAPPNAME", appnameenv, 1);
	free(appnameenv);

	pid = spawn_process(psql_cmd.data);

	if (pid == INVALID_PID)
	{
		fprintf(stderr, _("could not start process for test %s\n"),
				testname);
		exit(2);
	}

	unsetenv("PGAPPNAME");

	pfree(psql_cmd.data);

	return pid;
}

static void
psql_init(int argc, char **argv)
{
	/* set default regression database name */
	add_stringlist_item(&dblist, "regression");
}

int
main(int argc, char *argv[])
{
	return regression_main(argc, argv,
						   psql_init,
						   psql_start_test,
						   NULL /* no postfunc needed */ );
}


static int
psql_get_ivorysql_port(const char *database)
{
	StringInfoData cmd;
	FILE	   *pipe;
	char		result[32];
	char	   *end;
	long		port;
	bool		have_result;
	int			status;

	initStringInfo(&cmd);
	appendStringInfo(&cmd,
					 "\"%s%spsql\" -X -A -t -c \"show ivorysql.port\" -d \"%s\"",
					 bindir ? bindir : "",
					 bindir ? "/" : "",
					 database);
	pipe = popen(cmd.data, "r");
	pfree(cmd.data);
	if (pipe == NULL)
	{
		fprintf(stderr, _("could not start psql to determine the Oracle port: %m\n"));
		exit(2);
	}

	have_result = fgets(result, sizeof(result), pipe) != NULL;
	status = pclose(pipe);
	if (!have_result || status != 0)
	{
		fprintf(stderr, _("could not determine the Oracle port for database \"%s\"\n"),
				database);
		exit(2);
	}

	errno = 0;
	port = strtol(result, &end, 10);
	if (errno != 0 || end == result || end[strspn(end, "\r\n")] != '\0' ||
		port < 1 || port > 65535)
	{
		fprintf(stderr, _("database \"%s\" did not report a valid Oracle port\n"),
				database);
		exit(2);
	}

	return (int) port;
}
