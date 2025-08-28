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
 * Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
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
					 psql_get_ivorysql_port(dblist->str),
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
	char psql_cmd[1024];
	FILE *fp;
	char port_ora[10];
	char *temp_p;
	snprintf(psql_cmd, sizeof(psql_cmd),
			"\"%s%spsql\" -X -A -t -c \"show ivorysql.port\"  \"%s\"",
			bindir ? bindir : "",
			bindir ? "/" : "",
			database);
	fp = popen(psql_cmd,"r");
	temp_p = fgets(port_ora, sizeof(port_ora), fp);
	if (temp_p == NULL)
		printf("get ivorysql.port failed\n");
	return atoi(port_ora);
}
