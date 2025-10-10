/*
 * psql - the PostgreSQL interactive terminal
 *
 * Copyright (c) 2000-2025, PostgreSQL Global Development Group
 *
 * src/bin/psql/variables.c
 */
#include "postgres_fe.h"

#include <math.h>

#include "common.h"
#include "common/logging.h"
#include "fe_utils/string_utils.h"
#include "psqlplus.h"
#include "settings.h"
#include "variables.h"

/*
 * Check whether a variable's name is allowed.
 *
 * We allow any non-ASCII character, as well as ASCII letters, digits, and
 * underscore.  Keep this in sync with the definition of variable_char in
 * psqlscan.l and psqlscanslash.l.
 */
static bool
valid_variable_name(const char *name)
{
	const unsigned char *ptr = (const unsigned char *) name;

	/* Mustn't be zero-length */
	if (*ptr == '\0')
		return false;

	while (*ptr)
	{
		if (IS_HIGHBIT_SET(*ptr) ||
			strchr("ABCDEFGHIJKLMNOPQRSTUVWXYZ" "abcdefghijklmnopqrstuvwxyz"
				   "_0123456789", *ptr) != NULL)
			ptr++;
		else
			return false;
	}

	return true;
}

/*
 * Check whether a variable's value is allowed.
 *
 * Return the value of the corresponding datatype 
 * on successfully, return NULL on failure.
 */
static char *
valid_bind_variable_value(const int typoid, const int typmod, const char *value)
{
	PQExpBuffer query = createPQExpBuffer();
	PGresult	*res = NULL;
	char		*val = NULL;

	if (!value)
		return NULL;

	switch(typoid)
	{
		case ORACHARCHAROID:
			{
				appendPQExpBufferStr(query, "select sys.oracharcharin(");
				appendStringLiteralConn(query, value, pset.db);
				appendPQExpBuffer(query, ", 0 , %d) from dual;", typmod);
				res = PQexec(pset.db, query->data);

				if (PQresultStatus(res) == PGRES_TUPLES_OK &&
					PQntuples(res) == 1 &&
					!PQgetisnull(res, 0, 0))
				{
					val = pg_strdup(PQgetvalue(res, 0, 0));
				}
				else
				{
					pg_log_error("String beginning \"%s\" is too long.", value);
				}
			}
			break;
		case ORACHARBYTEOID:
			{
				appendPQExpBufferStr(query, "select sys.oracharbytein(");
				appendStringLiteralConn(query, value, pset.db);
				appendPQExpBuffer(query, ", 0 , %d) from dual;", typmod);
				res = PQexec(pset.db, query->data);

				if (PQresultStatus(res) == PGRES_TUPLES_OK &&
					PQntuples(res) == 1 &&
					!PQgetisnull(res, 0, 0))
				{
					val = pg_strdup(PQgetvalue(res, 0, 0));
				}
				else
				{
					pg_log_error("String beginning \"%s\" is too long.", value);
				}
			}
			break;
		case ORAVARCHARCHAROID:
			{
				appendPQExpBufferStr(query, "select sys.oravarcharcharin(");
				appendStringLiteralConn(query, value, pset.db);
				appendPQExpBuffer(query, ", 0 , %d) from dual;", typmod);
				res = PQexec(pset.db, query->data);

				if (PQresultStatus(res) == PGRES_TUPLES_OK &&
					PQntuples(res) == 1 &&
					!PQgetisnull(res, 0, 0))
				{
					val = pg_strdup(PQgetvalue(res, 0, 0));
				}
				else
				{
					pg_log_error("String beginning \"%s\" is too long.", value);
				}
			}
			break;
		case ORAVARCHARBYTEOID:
			{
				appendPQExpBufferStr(query, "select sys.oravarcharbytein(");
				appendStringLiteralConn(query, value, pset.db);
				appendPQExpBuffer(query, ", 0 , %d) from dual;", typmod);
				res = PQexec(pset.db, query->data);

				if (PQresultStatus(res) == PGRES_TUPLES_OK &&
					PQntuples(res) == 1 &&
					!PQgetisnull(res, 0, 0))
				{
					val = pg_strdup(PQgetvalue(res, 0, 0));
				}
				else
				{
					pg_log_error("String beginning \"%s\" is too long.", value);
				}
			}
			break;
		case NUMBEROID:
			{
				appendPQExpBufferStr(query, "select sys.number_in(");
				appendStringLiteralConn(query, value, pset.db);
				appendPQExpBuffer(query, ", 0 , %d) from dual;", typmod);
				res = PQexec(pset.db, query->data);

				if (PQresultStatus(res) == PGRES_TUPLES_OK &&
					PQntuples(res) == 1 &&
					!PQgetisnull(res, 0, 0))
				{
					val = pg_strdup(PQgetvalue(res, 0, 0));
				}
				else
				{
					pg_log_error("\"%s\" is not a valid NUMBER.", value);
				}
			}
			break;
		case BINARY_FLOATOID:
			{
				appendPQExpBufferStr(query, "select sys.binary_float_in(");
				appendStringLiteralConn(query, value, pset.db);
				appendPQExpBufferStr(query, ") from dual;");
				res = PQexec(pset.db, query->data);

				if (PQresultStatus(res) == PGRES_TUPLES_OK &&
					PQntuples(res) == 1 &&
					!PQgetisnull(res, 0, 0))
				{
					val = pg_strdup(PQgetvalue(res, 0, 0));
				}
				else
				{
					pg_log_error("\"%s\" is not a valid BINARY_FLOAT.", value);
				}
			}
			break;
		case BINARY_DOUBLEOID:
			{
				appendPQExpBufferStr(query, "select sys.binary_double_in(");
				appendStringLiteralConn(query, value, pset.db);
				appendPQExpBufferStr(query, ") from dual;");
				res = PQexec(pset.db, query->data);

				if (PQresultStatus(res) == PGRES_TUPLES_OK &&
					PQntuples(res) == 1 &&
					!PQgetisnull(res, 0, 0))
				{
					val = pg_strdup(PQgetvalue(res, 0, 0));
				}
				else
				{
					pg_log_error("\"%s\" is not a valid BINARY_DOUBLE.", value);
				}
			}
			break;
		/* TODO */
		//case REFCURSOR:
		//case BLOB:
		//case CLOB:
		//case NCLOB:
		//case BFILE:
		default:
			pg_log_error("The datatype of the bind variable is not supported.");
			break;
	}

	PQclear(res);
	destroyPQExpBuffer(query);

	return val;
}

static void
print_bind_variable_value(char *name, char *value)
{
	printTableContent cont;
	printTableOpt myopt = pset.popt.topt;
	char	*uppername = NULL;
	char	*p;

	Assert(name);
	myopt.default_footer = false;
	uppername = pg_strdup(name);

	/* Oracle bind variable names are displayed in uppercase */
	for (p = uppername; *p; p++)
	{
		*p = pg_toupper((unsigned char) *p);
	}
	
	printTableInit(&cont, &myopt, NULL, 1, 1);
	printTableAddHeader(&cont, uppername, false, 'l');

	if (value)
		printTableAddCell(&cont, value, false, false);
	else
		printTableAddCell(&cont, "", false, false);

	printTable(&cont, pset.queryFout, false, pset.logfile);
	printTableCleanup(&cont);
	pg_free(uppername);
}

/*
 * A "variable space" is represented by an otherwise-unused struct _variable
 * that serves as list header.
 *
 * The list entries are kept in name order (according to strcmp).  This
 * is mainly to make the output of PrintVariables() more pleasing.
 */
VariableSpace
CreateVariableSpace(void)
{
	struct _variable *ptr;

	ptr = pg_malloc(sizeof *ptr);
	ptr->varkind = PSQL_UNKNOWN_VAR;
	ptr->typoid = 0;
	ptr->typmod = -1;
	ptr->name = NULL;
	ptr->value = NULL;
	ptr->substitute_hook = NULL;
	ptr->assign_hook = NULL;
	ptr->next = NULL;

	return ptr;
}

/*
 * Get string value of shell variable, or NULL if it's not defined.
 *
 * Note: result is valid until variable is next assigned to.
 */
const char *
GetVariable(VariableSpace space, const char *name)
{
	struct _variable *current;

	if (!space)
		return NULL;

	for (current = space->next; current; current = current->next)
	{
		int			cmp;

		if (current->varkind != PSQL_SHELL_VAR)
			continue;

		cmp = strcmp(current->name, name);

		if (cmp == 0)
		{
			/* this is correct answer when value is NULL, too */
			return current->value;
		}
		if (cmp > 0)
			break;				/* it's not there */
	}

	return NULL;
}

/*
 * Try to interpret "value" as a boolean value, and if successful,
 * store it in *result.  Otherwise don't clobber *result.
 *
 * Valid values are: true, false, yes, no, on, off, 1, 0; as well as unique
 * prefixes thereof.
 *
 * "name" is the name of the variable we're assigning to, to use in error
 * report if any.  Pass name == NULL to suppress the error report.
 *
 * Return true when "value" is syntactically valid, false otherwise.
 */
bool
ParseVariableBool(const char *value, const char *name, bool *result)
{
	size_t		len;
	bool		valid = true;

	/* Treat "unset" as an empty string, which will lead to error below */
	if (value == NULL)
		value = "";

	len = strlen(value);

	if (len > 0 && pg_strncasecmp(value, "true", len) == 0)
		*result = true;
	else if (len > 0 && pg_strncasecmp(value, "false", len) == 0)
		*result = false;
	else if (len > 0 && pg_strncasecmp(value, "yes", len) == 0)
		*result = true;
	else if (len > 0 && pg_strncasecmp(value, "no", len) == 0)
		*result = false;
	/* 'o' is not unique enough */
	else if (pg_strncasecmp(value, "on", (len > 2 ? len : 2)) == 0)
		*result = true;
	else if (pg_strncasecmp(value, "off", (len > 2 ? len : 2)) == 0)
		*result = false;
	else if (pg_strcasecmp(value, "1") == 0)
		*result = true;
	else if (pg_strcasecmp(value, "0") == 0)
		*result = false;
	else
	{
		/* string is not recognized; don't clobber *result */
		if (name)
			pg_log_error("unrecognized value \"%s\" for \"%s\": Boolean expected",
						 value, name);
		valid = false;
	}
	return valid;
}

/*
 * Try to interpret "value" as an integer value, and if successful,
 * store it in *result.  Otherwise don't clobber *result.
 *
 * "name" is the name of the variable we're assigning to, to use in error
 * report if any.  Pass name == NULL to suppress the error report.
 *
 * Return true when "value" is syntactically valid, false otherwise.
 */
bool
ParseVariableNum(const char *value, const char *name, int *result)
{
	char	   *end;
	long		numval;

	/* Treat "unset" as an empty string, which will lead to error below */
	if (value == NULL)
		value = "";

	errno = 0;
	numval = strtol(value, &end, 0);
	if (errno == 0 && *end == '\0' && end != value && numval == (int) numval)
	{
		*result = (int) numval;
		return true;
	}
	else
	{
		/* string is not recognized; don't clobber *result */
		if (name)
			pg_log_error("invalid value \"%s\" for \"%s\": integer expected",
						 value, name);
		return false;
	}
}

/*
 * Try to interpret "value" as a double value, and if successful store it in
 * *result. If unsuccessful, *result isn't clobbered. "name" is the variable
 * which is being assigned, the value of which is only used to produce a good
 * error message. Pass NULL as the name to suppress the error message.  The
 * value must be within the range [min,max] in order to be considered valid.
 *
 * Returns true, with *result containing the interpreted value, if "value" is
 * syntactically valid, else false (with *result unchanged).
 */
bool
ParseVariableDouble(const char *value, const char *name, double *result, double min, double max)
{
	char	   *end;
	double		dblval;

	/*
	 * Empty-string input has historically been treated differently by strtod
	 * on various platforms, so handle that by specifically checking for it.
	 */
	if ((value == NULL) || (*value == '\0'))
	{
		if (name)
			pg_log_error("invalid input syntax for variable \"%s\"", name);
		return false;
	}

	errno = 0;
	dblval = strtod(value, &end);
	if (errno == 0 && *end == '\0' && end != value)
	{
		if (dblval < min)
		{
			if (name)
				pg_log_error("invalid value \"%s\" for variable \"%s\": must be greater than %.2f",
							 value, name, min);
			return false;
		}
		else if (dblval > max)
		{
			if (name)
				pg_log_error("invalid value \"%s\" for variable \"%s\": must be less than %.2f",
							 value, name, max);
		}
		*result = dblval;
		return true;
	}

	/*
	 * Cater for platforms which treat values which aren't zero, but that are
	 * too close to zero to have full precision, by checking for zero or real
	 * out-of-range values.
	 */
	else if ((errno == ERANGE) &&
			 (dblval == 0.0 || dblval >= HUGE_VAL || dblval <= -HUGE_VAL))
	{
		if (name)
			pg_log_error("value \"%s\" is out of range for variable \"%s\"", value, name);
		return false;
	}
	else
	{
		if (name)
			pg_log_error("invalid value \"%s\" for variable \"%s\"", value, name);
		return false;
	}
}

/*
 * Print values of all variables.
 */
void
PrintVariables(VariableSpace space)
{
	struct _variable *ptr;

	if (!space)
		return;

	for (ptr = space->next; ptr; ptr = ptr->next)
	{
		if (ptr->varkind != PSQL_SHELL_VAR)
			continue;

		if (ptr->value)
			printf("%s = '%s'\n", ptr->name, ptr->value);
		if (cancel_pressed)
			break;
	}
}

/*
 * Set the shell variable named "name" to value "value",
 * or delete it if "value" is NULL.
 *
 * Returns true if successful, false if not; in the latter case a suitable
 * error message has been printed, except for the unexpected case of
 * space or name being NULL.
 */
bool
SetVariable(VariableSpace space, const char *name, const char *value)
{
	struct _variable *current,
			   *previous;

	if (!space || !name)
		return false;

	if (!valid_variable_name(name))
	{
		/* Deletion of non-existent variable is not an error */
		if (!value)
			return true;
		pg_log_error("invalid variable name: \"%s\"", name);
		return false;
	}

	for (previous = space, current = space->next;
		 current;
		 previous = current, current = current->next)
	{
		int			cmp = strcmp(current->name, name);

		if (cmp == 0)
		{
			/*
			 * Found entry, so update, unless assign hook returns false.
			 *
			 * We must duplicate the passed value to start with.  This
			 * simplifies the API for substitute hooks.  Moreover, some assign
			 * hooks assume that the passed value has the same lifespan as the
			 * variable.  Having to free the string again on failure is a
			 * small price to pay for keeping these APIs simple.
			 */
			char	   *new_value;
			bool		confirmed;

			if (current->varkind == PSQL_BIND_VAR)
			{
				pg_log_error("the variable name \"%s\" is already taken by a psql bind variable.", name);
				return false;
			}

			new_value = value ? pg_strdup(value) : NULL;

			if (current->substitute_hook)
				new_value = current->substitute_hook(new_value);

			if (current->assign_hook)
				confirmed = current->assign_hook(new_value);
			else
				confirmed = true;

			if (confirmed)
			{
				pg_free(current->value);
				current->value = new_value;

				/*
				 * If we deleted the value, and there are no hooks to
				 * remember, we can discard the variable altogether.
				 */
				if (new_value == NULL &&
					current->substitute_hook == NULL &&
					current->assign_hook == NULL)
				{
					previous->next = current->next;
					free(current->name);
					free(current);
				}
			}
			else
				pg_free(new_value); /* current->value is left unchanged */

			return confirmed;
		}
		if (cmp > 0)
			break;				/* it's not there */
	}

	/* not present, make new entry ... unless we were asked to delete */
	if (value)
	{
		current = pg_malloc(sizeof *current);
		current->varkind = PSQL_SHELL_VAR;
		current->typoid = 0;	/* InvalidOid */	
		current->typmod = -1;
		current->name = pg_strdup(name);
		current->value = pg_strdup(value);
		current->substitute_hook = NULL;
		current->assign_hook = NULL;
		current->next = previous->next;
		previous->next = current;
	}
	return true;
}

/*
 * Attach substitute and/or assign hook functions to the named variable.
 * If you need only one hook, pass NULL for the other.
 *
 * If the variable doesn't already exist, create it with value NULL, just so
 * we have a place to store the hook function(s).  (The substitute hook might
 * immediately change the NULL to something else; if not, this state is
 * externally the same as the variable not being defined.)
 *
 * The substitute hook, if given, is immediately called on the variable's
 * value.  Then the assign hook, if given, is called on the variable's value.
 * This is meant to let it update any derived psql state.  If the assign hook
 * doesn't like the current value, it will print a message to that effect,
 * but we'll ignore it.  Generally we do not expect any such failure here,
 * because this should get called before any user-supplied value is assigned.
 */
void
SetVariableHooks(VariableSpace space, const char *name,
				 VariableSubstituteHook shook,
				 VariableAssignHook ahook)
{
	struct _variable *current,
			   *previous;

	if (!space || !name)
		return;

	if (!valid_variable_name(name))
		return;

	for (previous = space, current = space->next;
		 current;
		 previous = current, current = current->next)
	{
		int			cmp;

		if (current->varkind != PSQL_SHELL_VAR)
			continue;

		cmp = strcmp(current->name, name);

		if (cmp == 0)
		{
			/* found entry, so update */
			current->substitute_hook = shook;
			current->assign_hook = ahook;
			if (shook)
				current->value = (*shook) (current->value);
			if (ahook)
				(void) (*ahook) (current->value);
			return;
		}
		if (cmp > 0)
			break;				/* it's not there */
	}

	/* not present, make new entry */
	current = pg_malloc(sizeof *current);
	current->name = pg_strdup(name);
	current->value = NULL;
	current->varkind = PSQL_SHELL_VAR;
	current->typoid = 0;
	current->typmod = -1;
	current->substitute_hook = shook;
	current->assign_hook = ahook;
	current->next = previous->next;
	previous->next = current;
	if (shook)
		current->value = (*shook) (current->value);
	if (ahook)
		(void) (*ahook) (current->value);
}

/*
 * Return true iff the named variable has substitute and/or assign hook
 * functions.
 */
bool
VariableHasHook(VariableSpace space, const char *name)
{
	struct _variable *current;

	Assert(space);
	Assert(name);

	for (current = space->next; current; current = current->next)
	{
		int			cmp;

		if (current->varkind != PSQL_SHELL_VAR)
			continue;

		cmp = strcmp(current->name, name);

		if (cmp == 0)
			return (current->substitute_hook != NULL ||
					current->assign_hook != NULL);
		if (cmp > 0)
			break;				/* it's not there */
	}

	return false;
}

/*
 * Convenience function to set a variable's value to "on".
 */
bool
SetVariableBool(VariableSpace space, const char *name)
{
	return SetVariable(space, name, "on");
}

/*
 * Attempt to delete variable.
 *
 * If unsuccessful, print a message and return "false".
 * Deleting a nonexistent variable is not an error.
 */
bool
DeleteVariable(VariableSpace space, const char *name)
{
	return SetVariable(space, name, NULL);
}

/*
 * Emit error with suggestions for variables or commands
 * accepting enum-style arguments.
 * This function just exists to standardize the wording.
 * suggestions should follow the format "fee, fi, fo, fum".
 */
void
PsqlVarEnumError(const char *name, const char *value, const char *suggestions)
{
	pg_log_error("unrecognized value \"%s\" for \"%s\"\n"
				 "Available values are: %s.",
				 value, name, suggestions);
}

/*
 * Set the bind variable named "name".
 *
 * Returns true if successful, false if not.
 */
bool
SetBindVariable(VariableSpace space,
						const char *name,
						const int typoid,
						const int typmod,
						const char *initval,
						bool notnull)
{
	struct _variable *current,
			   *previous;
	char	*value = valid_bind_variable_value(typoid, typmod, initval);

	if (!space || !name)
		return false;

	if (!ValidBindVariableName(name))
	{
		pg_log_error("Illegal variable name \"%s\"", name);
		return false;
	}

	if (typoid == ORACHARCHAROID ||
		typoid == ORACHARBYTEOID ||
		typoid == ORAVARCHARCHAROID ||
		typoid == ORAVARCHARBYTEOID)
	{
		if (typmod - 4 < 1)
		{
			pg_log_error("Bind variable length cannot be less than 1.");
			return false;
		}

		if ((typoid == ORACHARCHAROID || typoid == ORACHARBYTEOID) && 
			typmod - 4 > MaxOraCharLen)
		{
			pg_log_error("Bind variable length cannot exceed %d.", MaxOraCharLen);
			return false;
		}

		if ((typoid == ORAVARCHARCHAROID || typoid == ORAVARCHARBYTEOID) && 
			typmod - 4 > MaxOraVarcharLen)
		{
			pg_log_error("Bind variable length cannot exceed %d.", MaxOraVarcharLen);
			return false;
		}
	}

	if (notnull && !initval)
	{
		pg_log_error("Invalid option.\n"
				"Usage: VAR[IABLE] <variable> [type][= value]");
		return false;
	}

	for (previous = space, current = space->next;
		 current;
		 previous = current, current = current->next)
	{
		int			cmp = strcmp(current->name, name);

		if (cmp == 0)
		{
			if (current->varkind == PSQL_BIND_VAR)
			{
				/* found bind variable entry, reset it */
				current->typoid = typoid;
				current->typmod = typmod;

				if (current->value)
					pg_free(current->value);

				if (value)
					current->value = value;
				else
					current->value = NULL;

				return true;
			}
			else if (current->varkind == PSQL_SHELL_VAR)
			{
				pg_log_error("the variable name \"%s\" is already taken by a psql shell variable.", name);
				return false;
			}
		}
		if (cmp > 0)
			break;				/* it's not there */
	}

	/* not present, make new entry */
	current = pg_malloc(sizeof *current);
	current->name = pg_strdup(name);

	if (value)
		current->value = value;
	else
		current->value = NULL;

	current->varkind = PSQL_BIND_VAR;
	current->typoid = typoid;
	current->typmod = typmod;
	current->substitute_hook = NULL;
	current->assign_hook = NULL;
	current->next = previous->next;
	previous->next = current;

	return true;
}

/*
 * Lists the current display characteristics for a single variable or all variables.
 */
void
ListBindVariables(VariableSpace space, const char *name)
{
	struct _variable *ptr;
	int		bindvar_num = 0;	/* # of bind variables to list */

	if (!space)
		return;

	for (ptr = space->next; ptr; ptr = ptr->next)
	{
		if (ptr->varkind == PSQL_BIND_VAR)
		{
			PQExpBuffer query = createPQExpBuffer();
			PGresult	*res;
			char		*typdesc = NULL;

			if (name)
			{
				if (strcmp(ptr->name, name) != 0)
					continue;
			}

			bindvar_num++;
			appendPQExpBuffer(query, "SELECT format_type(%d, %d);", ptr->typoid, ptr->typmod);
			res = PQexec(pset.db, query->data);
			if (PQresultStatus(res) == PGRES_TUPLES_OK &&
				PQntuples(res) == 1 &&
				!PQgetisnull(res, 0, 0))
			{
				char	*p;
				typdesc = pg_strdup(PQgetvalue(res, 0, 0));

				/* Oracle bind variable datatype are displayed in uppercase */
				for (p = typdesc; *p; p++)
				{
					*p = pg_toupper((unsigned char) *p);
				}
			}

			if (bindvar_num != 1)
				printf("\n");
			if (ptr->name)
				printf("variable	%s\n", ptr->name);
			if (ptr->typoid)
				printf("datatype	%s\n", typdesc);

			PQclear(res);
			pg_free(typdesc);
			destroyPQExpBuffer(query);

			if (cancel_pressed)
				break;
		}
	}

	if (name && bindvar_num == 0)
		pg_log_error("Bind variable \"%s\" not declared.", name);
	else if (name == NULL && bindvar_num == 0)
		pg_log_error("No bind variables declared.");
}

/*
 * Print the value for some specific variables or all variables.
 */
void
PrintBindVariables(VariableSpace space, print_list *bvlist)
{
	struct _variable *ptr;

	if (bvlist == NULL)
	{
		for (ptr = space->next; ptr; ptr = ptr->next)
		{
			if (ptr->varkind == PSQL_BIND_VAR)
			{
				print_bind_variable_value(ptr->name, ptr->value);
			}
		}
	}
	else
	{
		int	i;

		for (i = 0; i < bvlist->length; i++)
		{
			print_item	*item = bvlist->items[i];
			bool	found;

			if (item->valid == false)
			{
				pg_log_error("invalid host/bind variable name.");
				printf("\n");
				continue;
			}

			found = false;
			for (ptr = space->next; ptr; ptr = ptr->next)
			{
				int	cmp = strcmp(ptr->name, item->bv_name);

				if (cmp == 0 && ptr->varkind == PSQL_BIND_VAR)
				{
					/* found bind variable entry */
					found = true;
					print_bind_variable_value(ptr->name, ptr->value);
					break;
				}

				if (cmp > 0)
				{
					found = false;
					break;	/* it's not there */
				}
			}

			if (!found)
			{
				pg_log_error("Bind variable \"%s\" not declared.", item->bv_name);
				printf("\n");
			}
		}
	}
}

/*
 * Assign a new value to the bind variable.
 */
bool
AssignBindVariable(VariableSpace space, const char *name, const char *value)
{
	struct _variable *current;
	bool	found = false;

	if (!space || !name)
		return false;

	if (!ValidBindVariableName(name))
	{
		pg_log_error("Illegal variable name \"%s\"", name);
		return false;
	}

	if (value == NULL)
	{
		pg_log_error("Variable assignment requires a value following equal sign.\n"
				"Usage: VAR[IABLE] <variable> [type][= value]");
		return false;
	}

	for (current = space->next; current; current = current->next)
	{
		int			cmp = strcmp(current->name, name);

		if (cmp == 0 && current->varkind == PSQL_BIND_VAR)
		{
			found = true;
			break;
		}

		if (cmp > 0)
		{
			found = false;
			break;				/* it's not there */
		}
	}

	if (found)
	{
		char	*newvalue = valid_bind_variable_value(current->typoid, current->typmod, value);

		if (newvalue)
		{
			if (current->value)
				pg_free(current->value);
			current->value = newvalue;
		}
	}
	else
	{
		pg_log_error("Bind variable \"%s\" not declared.", name);
		return false;
	}

	return true;
}

/*
 * Check whether a bind variable's name is allowed.
 *
 * Bind variable begins with a letter and can include letters,
 * digits, and these symbols:
 *	Dollar sign ($)
 *	Number sign (#)
 *	Underscore (_)
 * Bind variables can be a multibyte character, use IS_HIGHBIT_SET() to
 * check and skip for multibyte characters.
 * Keep this in sync with the definition of identifier in psqlplusscan.l
 */
bool
ValidBindVariableName(const char *name)
{
	const unsigned char *ptr = (const unsigned char *) name;

	/* Mustn't be zero-length */
	if (*ptr == '\0')
		return false;

	/* Up to 512 bytes */
	if (strlen(name) > 512)
		return false;
	
	/* Must begin with a letter */
	if (!IS_HIGHBIT_SET(*ptr) &&
		!isalpha((unsigned char)*ptr))
		return false;

	while (*ptr)
	{
		if (IS_HIGHBIT_SET(*ptr) ||
			strchr("ABCDEFGHIJKLMNOPQRSTUVWXYZ" "abcdefghijklmnopqrstuvwxyz"
				   "0123456789" "_#$", *ptr) != NULL)
			ptr++;
		else
			return false;
	}

	return true;
}

/*
 * Checks whether a bind variable exists,and returns the
 * bind variable if exists, otherwise returns NULL.
 */
struct _variable *
BindVariableExist(VariableSpace space, const char *name)
{
	struct _variable *current;

	if (!space || !name)
		return NULL;

	if (!ValidBindVariableName(name))
	{
		/* If the name is illegal, it must not exist */
		return NULL;
	}

	for (current = space->next; current; current = current->next)
	{
		int			cmp = strcmp(current->name, name);

		if (cmp == 0 && current->varkind == PSQL_BIND_VAR)
		{
			return current;
		}

		if (cmp > 0)
			break;	/* it's not there */
	}

	return NULL;
}
