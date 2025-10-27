/*-------------------------------------------------------------------------
 * Copyright 2025 IvorySQL Global Development Team
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
 * ivy_guc.c
 *
 * Support for grand unified configuration scheme(for ivorysql), including SET
 * command, configuration file, and command line options
 *
 * Authored by lanke@highgo.com, 20220819.
 *
 * Copyright (c) 2022-2025, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *        src/backend/utils/misc/ivy_guc.c
 *
 *-------------------------------------------------------------------------
 */
#ifdef IVY_GUC_VAR_DEFINE
#define ISLOADIVORYSQL_ORA pg_transform_merge_stmt_hook

int			identifier_case_switch = INTERCHANGE;
bool		identifier_case_from_pg_dump = false;
bool		enable_case_switch = true;

char	   *nls_territory = "AMERICA";
char	   *nls_currency = "$";
char	   *nls_iso_currency = "AMERICA";

bool		enable_emptystring_to_NULL = false;

int			database_mode = DB_PG;
int			compatible_db = PG_PARSER;

bool		allow_out_parameter_const = false;
bool		out_parameter_column_position = false;

bool		seq_scale_fixed = false;
bool		internal_warning = false;

bool		default_with_rowids = false;
int			rowid_seq_cache = 20;

#endif

#ifdef IVY_GUC_VAR_STRUCT

/* The comments shown as blow define the
 * value range of guc parameters "database_mode"
 * and "compatible_db".
 */
static const struct config_enum_entry db_mode_options[] = {
	{"pg", DB_PG, false},
	{"oracle", DB_ORACLE, false},
	{"0", DB_PG, false},
	{"1", DB_ORACLE, false},
	{NULL, 0, false}
};

static const struct config_enum_entry db_parser_options[] = {
	{"pg", PG_PARSER, false},
	{"oracle", ORA_PARSER, false},
	{NULL, 0, false}

};


static const struct config_enum_entry case_conversion_mode[] = {
	{"normal", NORMAL, false},
	{"interchange", INTERCHANGE, false},
	{"lowercase", LOWERCASE, false},
	{"0", NORMAL, false},
	{"1", INTERCHANGE, false},
	{"2", LOWERCASE, false},
	{NULL, 0, false}
};

static const struct config_enum_entry nls_length_options[] = {
	{"byte", NLS_LENGTH_BYTE, false},
	{"char", NLS_LENGTH_CHAR, false},
	{NULL, 0, false}
};

#endif

#ifdef IVY_GUC_FUNC_DECLARE

static bool check_nls_length_semantics(int *newval, void **extra, GucSource source);

static bool check_compatible_mode(int *newval, void **extra, GucSource source);
static bool check_database_mode(int *newval, void **extra, GucSource source);
void		assign_compatible_mode(int newval, void *extra);

static void nls_case_conversion(char **param, char type);
static bool nls_length_check(char **newval, void **extra, GucSource source);
static bool nls_territory_check(char **newval, void **extra, GucSource source);
#endif

#if 0
static struct config_bool Ivy_ConfigureNamesBool[] =
{
#endif
#ifdef IVY_GUC_BOOL_PARAMS

	{
		/* Not for general use --- used by pg_dump */
		{"ivorysql.identifier_case_from_pg_dump", PGC_USERSET, UNGROUPED,
			gettext_noop("Shows whether the identifier with quotes is from pg dump."),
			NULL,
			GUC_REPORT | GUC_NO_SHOW_ALL | GUC_NO_RESET_ALL | GUC_NOT_IN_SAMPLE | GUC_DISALLOW_IN_FILE
		},
		&identifier_case_from_pg_dump,
		false,
		NULL, NULL, NULL
	},
	{
		{"ivorysql.enable_case_switch", PGC_USERSET, CLIENT_CONN_STATEMENT,
			gettext_noop("whether enable case conversion feature in oracle compatible mode."),
			NULL,
			GUC_NO_SHOW_ALL | GUC_NOT_IN_SAMPLE | GUC_DISALLOW_IN_FILE
		},
		&enable_case_switch,
		true,
		NULL, NULL, NULL
	},

	{
		{"ivorysql.enable_emptystring_to_NULL", PGC_USERSET, COMPAT_ORACLE_OPTIONS,
			gettext_noop("whether convert empty string to NULL."),
			NULL
		},
		&enable_emptystring_to_NULL,
		false,
		NULL, NULL, NULL
	},

	/*
	 * if ivorysql.allow_out_parameter_const is false, out parameter must be a
	 * var. if ivorysql.allow_out_parameter_const is true, out parameter can
	 * be a constant value
	 */
	{
		{"ivorysql.allow_out_parameter_const", PGC_USERSET, DEVELOPER_OPTIONS,
			gettext_noop("plisql function out parameter can be a constant value."),
			NULL,
			GUC_NO_SHOW_ALL | GUC_NOT_IN_SAMPLE
		},
		&allow_out_parameter_const,
		false,
		NULL, NULL, NULL
	},

	{
		{"ivorysql.out_parameter_column_position", PGC_USERSET, DEVELOPER_OPTIONS,
			gettext_noop("plisql function construct out parameter column by its position."),
			NULL,
			GUC_NO_SHOW_ALL | GUC_NOT_IN_SAMPLE
		},
		&out_parameter_column_position,
		false,
		NULL, NULL, NULL
	},

	{
		{"ivorysql.enable_seq_scale_fixed", PGC_USERSET, DEVELOPER_OPTIONS,
			gettext_noop("Sequence scale value switch."),
			NULL,
			GUC_NO_SHOW_ALL | GUC_NOT_IN_SAMPLE
		},
		&seq_scale_fixed,
		false,
		NULL, NULL, NULL
	},

	/*
 	 * ivorysql.default_with_rowids
	 *
	 * When enabled, all newly created tables will automatically include
	 * an Oracle-compatible ROWID pseudo-column. This provides compatibility
	 * with Oracle applications that rely on ROWID for row identification.
	 *
	 * Default: off
	 * Context: USERSET (can be changed by any user)
 	 */
	{
		{"ivorysql.default_with_rowids", PGC_USERSET, DEVELOPER_OPTIONS,
			gettext_noop("Automatically add rowid column when creating new tables."),
			NULL,
			GUC_NO_SHOW_ALL | GUC_NOT_IN_SAMPLE
		},
		&default_with_rowids,
		false,
		NULL, NULL, NULL
	},

	{
		{"ivorysql.enable_internal_warning", PGC_USERSET, DEVELOPER_OPTIONS,
			gettext_noop("Whether to print internal warning information."),
			NULL,
			GUC_NO_SHOW_ALL | GUC_NOT_IN_SAMPLE
		},
		&internal_warning,
		false,
		NULL, NULL, NULL
	},


#endif
#if 0
	/* End-of-list marker */
	{
		{NULL, 0, 0, NULL, NULL}, NULL, false, NULL, NULL, NULL
	}
};
#endif

#if 0
static struct config_int Ivy_ConfigureNamesInt[] =
{
#endif
#ifdef IVY_GUC_INT_PARAMS

	{
		{"ivorysql.port", PGC_POSTMASTER, CONN_AUTH_SETTINGS,
			gettext_noop("Sets the Oracle TCP port the server listens on."),
			NULL
		},
		&OraPortNumber,
		1521, 1, 65535,
		NULL, NULL, NULL
	},



	{
		{"ivorysql.datetime_ignore_nls_mask", PGC_USERSET, COMPAT_ORACLE_OPTIONS,
			gettext_noop("Sets the datetime type input is not controlled by the NLS parameter."),
			NULL,
			GUC_NOT_IN_SAMPLE
		},
		&datetime_ignore_nls_mask,
		0, 0, 15,
		NULL, NULL, NULL
	},

	{
		{"ivorysql.rowid_seq_cache", PGC_USERSET, DEVELOPER_OPTIONS,
			gettext_noop("Sets rowid Sequence cache number."),
			NULL,
			GUC_NO_SHOW_ALL | GUC_NOT_IN_SAMPLE
		},
		&rowid_seq_cache,
		20, 1, 60000,
		NULL, NULL, NULL
	},

#endif
#if 0
	/* End-of-list marker */
	{
		{NULL, 0, 0, NULL, NULL}, NULL, 0, 0, 0, NULL, NULL, NULL
	}
};
#endif

#if 0
static struct config_string Ivy_ConfigureNamesString[] =
{
#endif
#ifdef IVY_GUC_STRING_PARAMS

	{
		{"ivorysql.listen_addresses", PGC_POSTMASTER, CONN_AUTH_SETTINGS,
			gettext_noop("Sets oracle host name or IP address(es) to listen to."),
			NULL,
			GUC_LIST_INPUT
		},
		&OraListenAddresses,
		"localhost",
		NULL, NULL, NULL
	},

	{
		{"nls_date_format", PGC_USERSET, COMPAT_ORACLE_OPTIONS,
			gettext_noop("Compatible Oracle NLS parameter for date type."),
			NULL,
			GUC_NOT_IN_SAMPLE
		},
		&nls_date_format,
		"YYYY-MM-DD",
		NULL, NULL, NULL
	},

	{
		{"nls_timestamp_format", PGC_USERSET, COMPAT_ORACLE_OPTIONS,
			gettext_noop("Compatible Oracle NLS parameter for timestamp type."),
			NULL,
			GUC_NOT_IN_SAMPLE
		},
		&nls_timestamp_format,
		"YYYY-MM-DD HH24:MI:SS.FF6",
		NULL, NULL, NULL
	},

	{
		{"nls_timestamp_tz_format", PGC_USERSET, COMPAT_ORACLE_OPTIONS,
			gettext_noop("Compatible Oracle NLS parameter for timestamp with time zone type."),
			NULL,
			GUC_NOT_IN_SAMPLE
		},
		&nls_timestamp_tz_format,
		"YYYY-MM-DD HH24:MI:SS.FF6 TZH:TZM",
		NULL, NULL, NULL
	},
	{
		{"nls_territory", PGC_USERSET, COMPAT_ORACLE_OPTIONS,
			gettext_noop("Compatible Oracle NLS parameter for NLS_TERRITORY."),
			NULL,
			GUC_NOT_IN_SAMPLE
		},
		&nls_territory,
		"AMERICA",
		nls_territory_check, NULL, NULL
	},

	{
		{"nls_currency", PGC_USERSET, COMPAT_ORACLE_OPTIONS,
			gettext_noop("Compatible Oracle NLS parameter for NLS_CURRENCY."),
			NULL,
			GUC_NOT_IN_SAMPLE
		},
		&nls_currency,
		"$",
		nls_length_check, NULL, NULL
	},

	{
		{"nls_iso_currency", PGC_USERSET, COMPAT_ORACLE_OPTIONS,
			gettext_noop("Compatible Oracle NLS parameter for NLS_ISO_CURRENCY."),
			NULL,
			GUC_NOT_IN_SAMPLE
		},
		&nls_iso_currency,
		"AMERICA",
		nls_territory_check, NULL, NULL
	},
#endif
#if 0
	/* End-of-list marker */
	{
		{NULL, 0, 0, NULL, NULL}, NULL, NULL, NULL, NULL, NULL
	}
};
#endif

#if 0
static struct config_real Ivy_ConfigureNamesReal[] =
{
#endif
#ifdef IVY_GUC_REAL_PARAMS
	/* Add real guc param at here */

#endif
#if 0
	/* End-of-list marker */
	{
		{NULL, 0, 0, NULL, NULL}, NULL, 0.0, 0.0, 0.0, NULL, NULL, NULL
	}
};
#endif

#if 0
static struct config_enum Ivy_ConfigureNamesEnum[] =
{
#endif
#ifdef IVY_GUC_ENUM_PARAMS

	{
		{"ivorysql.database_mode", PGC_INTERNAL, PRESET_OPTIONS,
			gettext_noop("Set database mode"),
			NULL,
			GUC_NOT_IN_SAMPLE | GUC_DISALLOW_IN_FILE
		},
		&database_mode,
		DB_PG, db_mode_options,
		check_database_mode, NULL, NULL
	},

	{
		{"ivorysql.compatible_mode", PGC_USERSET, CLIENT_CONN_STATEMENT,
			gettext_noop("Set default sql parser compatibility mode"),
			NULL,
			GUC_NOT_IN_SAMPLE | GUC_DISALLOW_IN_FILE
		},
		&compatible_db,
		PG_PARSER, db_parser_options,
		check_compatible_mode, assign_compatible_mode, NULL
	},

	{
		{"ivorysql.identifier_case_switch", PGC_USERSET, COMPAT_ORACLE_OPTIONS,
			gettext_noop("Set character case conversion mode."),
			NULL
		},
		&identifier_case_switch,
		INTERCHANGE, case_conversion_mode,
		NULL, NULL, NULL
	},

	{
		{"nls_length_semantics", PGC_USERSET, COMPAT_ORACLE_OPTIONS,
			gettext_noop("Compatible Oracle NLS parameter for charater data type."),
			gettext_noop("Valid values are CHAR, BYTE."),
			GUC_IS_NAME | GUC_NOT_IN_SAMPLE
		},
		&nls_length_semantics,
		NLS_LENGTH_BYTE, nls_length_options,
		check_nls_length_semantics, NULL, NULL
	},

#endif
#if 0
	/* End-of-list marker */
	{
		{NULL, 0, 0, NULL, NULL}, NULL, 0, NULL, NULL, NULL, NULL
	}
};
#endif

#ifdef IVY_GUC_FUNC_DEFINE

static bool
check_nls_length_semantics(int *newval, void **extra, GucSource source)
{
	if (IsUnderPostmaster && DB_PG == database_mode)
		ereport(WARNING,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("Do not use this GUC variable in the current cluster (PG).")));


	return true;
}


static bool
check_compatible_mode(int *newval, void **extra, GucSource source)
{
	int			newmode = *newval;

	if (DB_PG == database_mode && newmode == ORA_PARSER)
		ereport(ERROR,
				(errcode(ERRCODE_CANT_CHANGE_RUNTIME_PARAM),
				 errmsg("parameter ivorysql.compatible_mode cannot be changed in native PG mode.")));

	if (DB_ORACLE == database_mode
		&& (IsNormalProcessingMode() || (IsUnderPostmaster && MyProcPort)))
	{
		if (newmode == ORA_PARSER)
		{
			if (ora_raw_parser == NULL)
				ereport(ERROR,
						(errcode(ERRCODE_SYSTEM_ERROR),
						 errmsg("liboracle_parser not found!"),
						 errhint("You must load liboracle_parser to use oracle parser.")));
			if (!ISLOADIVORYSQL_ORA)
				ereport(ERROR,
						(errcode(ERRCODE_SYSTEM_ERROR),
						 errmsg("IVORYSQL_ORA library not found!"),
						 errhint("You must load IVORYSQL_ORA to use oracle parser..")));
		}
	}
	return true;
}

static bool
check_database_mode(int *newval, void **extra, GucSource source)
{
	int			newmode = *newval;

	if (DB_PG == database_mode && DB_ORACLE == newmode)
		ereport(NOTICE,
				(errcode(ERRCODE_CANT_CHANGE_RUNTIME_PARAM),
				 errmsg("parameter ivorysql.database_mode cannot be changed")));

	return true;
}

void
assign_compatible_mode(int newval, void *extra)
{
	if (DB_ORACLE == database_mode
		&& (IsNormalProcessingMode() || (IsUnderPostmaster && MyProcPort)))
	{
		if (newval == ORA_PARSER)
		{
			sql_raw_parser = ora_raw_parser;


			pg_transform_merge_stmt_hook = ora_transform_merge_stmt_hook;
			pg_exec_merge_matched_hook = ora_exec_merge_matched_hook;

			assign_search_path(NULL, NULL);
		}
		else if (newval == PG_PARSER)
		{
			sql_raw_parser = standard_raw_parser;


			pg_transform_merge_stmt_hook = transformMergeStmt;
			pg_exec_merge_matched_hook = ExecMergeMatched;

			assign_search_path(NULL, NULL);
		}
	}
}

static void
nls_case_conversion(char **param, char type)
{
	char	   *p;

CASE_CONVERSION:
	if (type == 'u')
	{
		for (p = *param; p < *param + strlen(*param); ++p)
			if (97 <= *p && *p <= 122)
				*p -= 32;
		*p = '\0';
	}
	else if (type == 'l')
	{
		for (p = *param; p < *param + strlen(*param); ++p)
			if (65 <= *p && *p <= 90)
				*p += 32;
		*p = '\0';
	}
	else if (type == 'b')
	{
		bool		has_upper = false,
					has_lower = false;

		for (p = *param; p < *param + strlen(*param); ++p)
		{
			if (65 <= *p && *p <= 90)
				has_upper = true;
			else if (97 <= *p && *p <= 122)
				has_lower = true;
			if (has_upper && has_lower)
				return;
		}

		if (has_upper && !has_lower)
		{
			type = 'l';
			goto CASE_CONVERSION;
		}
		else if (!has_upper && has_lower)
		{
			type = 'u';
			goto CASE_CONVERSION;
		}
	}
}
static bool
nls_length_check(char **newval, void **extra, GucSource source)
{
	if (DB_ORACLE == database_mode
		&& (IsNormalProcessingMode() || (IsUnderPostmaster && MyProcPort)))
	{
		if (strlen(*newval) > 255)
			ereport(ERROR, (errmsg("parameter value longer than 255 characters")));
		else if (isdigit(**newval))
			ereport(ERROR, (errmsg("Cannot access NLS data files "
								   "or invalid environment specified")));
		else if (identifier_case_switch == INTERCHANGE)
			nls_case_conversion(newval, 'b');
	}

	return true;
}

static bool
nls_territory_check(char **newval, void **extra, GucSource source)
{
	if (DB_ORACLE == database_mode
		&& (IsNormalProcessingMode() || (IsUnderPostmaster && MyProcPort)))
	{
		if (pg_strcasecmp(*newval, "CHINA") == 0)
			memcpy(*newval, "CHINA", 5);
		else if (pg_strcasecmp(*newval, "AMERICA") == 0)
			memcpy(*newval, "AMERICA", 7);
		else
			ereport(ERROR, (errmsg("Cannot access NLS data files "
								   "or invalid environment specified")));
	}

	return true;
}
#endif
