/*
 *	version.c
 *
 *	Postgres-version-specific routines
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 *	Copyright (c) 2010-2026, PostgreSQL Global Development Group
 *	src/bin/pg_upgrade/version.c
 */

#include "postgres_fe.h"

#include "fe_utils/string_utils.h"
#include "pg_upgrade.h"

/*
 * Older servers can't support newer protocol versions, so their connection
 * strings will need to lock max_protocol_version to 3.0.
 */
bool
protocol_negotiation_supported(const ClusterInfo *cluster)
{
	/*
	 * The February 2018 patch release (9.3.21, 9.4.16, 9.5.11, 9.6.7, and
	 * 10.2) added support for NegotiateProtocolVersion. But ClusterInfo only
	 * has information about the major version number. To ensure we can still
	 * upgrade older unpatched servers, just assume anything prior to PG11
	 * can't negotiate. It's not possible for those servers to make use of
	 * newer protocols anyway, so nothing is lost.
	 */
	return (GET_MAJOR_VERSION(cluster->major_version) >= 1100);
}

/*
 * Callback function for processing results of query for
 * report_extension_updates()'s UpgradeTask.  If the query returned any rows,
 * write the details to the report file.
 */
static void
process_extension_updates(DbInfo *dbinfo, PGresult *res, void *arg)
{
	int			ntups = PQntuples(res);
	int			i_name = PQfnumber(res, "name");
	UpgradeTaskReport *report = (UpgradeTaskReport *) arg;
	PQExpBufferData connectbuf;

	if (ntups == 0)
		return;

	if (report->file == NULL &&
		(report->file = fopen_priv(report->path, "w")) == NULL)
		pg_fatal("could not open file \"%s\": %m", report->path);

	initPQExpBuffer(&connectbuf);
	appendPsqlMetaConnect(&connectbuf, dbinfo->db_name);
	fputs(connectbuf.data, report->file);
	termPQExpBuffer(&connectbuf);

	for (int rowno = 0; rowno < ntups; rowno++)
		fprintf(report->file, "ALTER EXTENSION %s UPDATE;\n",
				quote_identifier(PQgetvalue(res, rowno, i_name)));
}

/*
 * report_extension_updates()
 *	Report extensions that should be updated.
 */
void
report_extension_updates(ClusterInfo *cluster)
{
	UpgradeTaskReport report;
	UpgradeTask *task = upgrade_task_create();
	const char *query = "SELECT name "
		"FROM pg_available_extensions "
		"WHERE installed_version != default_version";

	prep_status("Checking for extension updates");

	report.file = NULL;
	strcpy(report.path, "update_extensions.sql");

	upgrade_task_add_step(task, query, process_extension_updates,
						  true, &report);

	upgrade_task_run(task, cluster);
	upgrade_task_free(task);

	if (report.file)
	{
		fclose(report.file);
		report_status(PG_REPORT, "notice");
		pg_log(PG_REPORT, "\n"
			   "Your installation contains extensions that should be updated\n"
			   "with the ALTER EXTENSION command.  The file\n"
			   "    %s\n"
			   "when executed by psql by the database superuser will update\n"
			   "these extensions.",
			   report.path);
	}
	else
		check_ok();
}
