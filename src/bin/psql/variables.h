/*
 * psql - the PostgreSQL interactive terminal
 *
 * Copyright (c) 2000-2024, PostgreSQL Global Development Group
 *
 * This implements a sort of variable repository.  One could also think of it
 * as a cheap version of an associative array.  Each variable has a string
 * name and a string value.  The value can't be NULL, or more precisely
 * that's not distinguishable from the variable being unset.
 *
 * src/bin/psql/variables.h
 */
#ifndef VARIABLES_H
#define VARIABLES_H

#include "fe_utils/psqlscan_int.h"	/* ReqID:SRS-CMD-PSQL */

/*
 * Variables can be given "assign hook" functions.  The assign hook can
 * prevent invalid values from being assigned, and can update internal C
 * variables to keep them in sync with the variable's current value.
 *
 * An assign hook function is called before any attempted assignment, with the
 * proposed new value of the variable (or with NULL, if an \unset is being
 * attempted).  If it returns false, the assignment doesn't occur --- it
 * should print an error message with pg_log_error() to tell the user why.
 *
 * When an assign hook function is installed with SetVariableHooks(), it is
 * called with the variable's current value (or with NULL, if it wasn't set
 * yet).  But its return value is ignored in this case.  The hook should be
 * set before any possibly-invalid value can be assigned.
 */
typedef bool (*VariableAssignHook) (const char *newval);

/*
 * Variables can also be given "substitute hook" functions.  The substitute
 * hook can replace values (including NULL) with other values, allowing
 * normalization of variable contents.  For example, for a boolean variable,
 * we wish to interpret "\unset FOO" as "\set FOO off", and we can do that
 * by installing a substitute hook.  (We can use the same substitute hook
 * for all bool or nearly-bool variables, which is why this responsibility
 * isn't part of the assign hook.)
 *
 * The substitute hook is called before any attempted assignment, and before
 * the assign hook if any, passing the proposed new value of the variable as a
 * malloc'd string (or NULL, if an \unset is being attempted).  It can return
 * the same value, or a different malloc'd string, or modify the string
 * in-place.  It should free the passed-in value if it's not returning it.
 * The substitute hook generally should not complain about erroneous values;
 * that's a job for the assign hook.
 *
 * When a substitute hook is installed with SetVariableHooks(), it is applied
 * to the variable's current value (typically NULL, if it wasn't set yet).
 * That also happens before applying the assign hook.
 */
typedef char *(*VariableSubstituteHook) (char *newval);

/* Begin - ReqID:SRS-CMD-PSQL */
typedef enum
{
	PSQL_SHELL_VAR,		/* Native Postgres shell variables */
	PSQL_BIND_VAR,		/* Oracle SQL*PLUS bind variables */
	PSQL_UNKNOWN_VAR	/* Currently used for the header of variable list */
} PsqlVarKind;
/* End - ReqID:SRS-CMD-PSQL */

/*
 * Data structure representing one variable.
 *
 * Note:
 *	For shell variables, if value == NULL then the variable is logically unset, but
 *	we are keeping the struct around so as not to forget about its hook function(s).
 *
 * Side effect:
 *	Shell variables and bind variables are not allowed to have the same name, otherwise
 *	we cannot judge the type of the variable only by the name of the variable with the
 *	same name when the variable is referenced by a colon.
 */
struct _variable
{
	char	   *name;
	char	   *value;
	/* Begin - ReqID:SRS-CMD-PSQL */
	PsqlVarKind	varkind;

	/* fields for bind variable */
	int			typoid;
	int			typmod;
	/* End - ReqID:SRS-CMD-PSQL */
	VariableSubstituteHook substitute_hook;
	VariableAssignHook assign_hook;
	struct _variable *next;
};

/* Data structure representing a set of variables */
typedef struct _variable *VariableSpace;


VariableSpace CreateVariableSpace(void);
const char *GetVariable(VariableSpace space, const char *name);

bool		ParseVariableBool(const char *value, const char *name,
							  bool *result);

bool		ParseVariableNum(const char *value, const char *name,
							 int *result);

void		PrintVariables(VariableSpace space);

bool		SetVariable(VariableSpace space, const char *name, const char *value);
bool		SetVariableBool(VariableSpace space, const char *name);
bool		DeleteVariable(VariableSpace space, const char *name);

void		SetVariableHooks(VariableSpace space, const char *name,
							 VariableSubstituteHook shook,
							 VariableAssignHook ahook);
bool		VariableHasHook(VariableSpace space, const char *name);

void		PsqlVarEnumError(const char *name, const char *value, const char *suggestions);

/* Begin - ReqID:SRS-CMD-PSQL */
bool		SetBindVariable(VariableSpace space, const char *name, 
							const int typoid, const int typmod,
							const char *initval, bool notnull);
void		ListBindVariables(VariableSpace space, const char *name);
void		PrintBindVariables(VariableSpace space, print_list *bvlist);
bool		AssignBindVariable(VariableSpace space, const char *name, const char *value);
bool		ValidBindVariableName(const char *name);
/* End - ReqID:SRS-CMD-PSQL */

#endif							/* VARIABLES_H */
