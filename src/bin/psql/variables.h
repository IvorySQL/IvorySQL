/*
 * psql - the PostgreSQL interactive terminal
 *
 * Copyright (c) 2000-2025, PostgreSQL Global Development Group
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

#include "fe_utils/psqlscan_int.h"

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

/*
 * Variable Types
 * 
 * Differentiates between native PostgreSQL shell variables and
 * Oracle SQL*Plus bind variables.
 */
typedef enum
{
	PSQL_SHELL_VAR,		/* Native Postgres shell variables */
	PSQL_BIND_VAR,		/* Oracle SQL*PLUS bind variables */
	PSQL_UNKNOWN_VAR	/* Currently used for the header of variable list */
} PsqlVarKind;

/*
 * Variable Data Structure
 *
 * Represents a single variable in the repository.
 *
 * Note: For shell variables, value == NULL indicates the variable is logically
 *       unset, but we keep the struct to preserve hook functions.
 *
 * Side Effect: Shell variables and bind variables cannot share names because
 *              we cannot determine the variable type by name alone when
 *              referenced by a colon prefix.
 */
struct _variable
{
    char                   *name;             /* Variable name */
    char                   *value;            /* Variable value (NULL = unset) */
    PsqlVarKind             varkind;          /* Variable type */
    
    /* Fields specific to bind variables */
    Oid                     typoid;           /* Type OID for bind variables */
    int                     typmod;           /* Type modifier for bind variables */
    VariableSubstituteHook  substitute_hook;  /* Value substitution hook */
    VariableAssignHook      assign_hook;      /* Value assignment hook */
    struct _variable       *next;             /* Next variable in linked list */
};

/* Variable space - a collection of variables */
typedef struct _variable *VariableSpace;


VariableSpace CreateVariableSpace(void);
const char *GetVariable(VariableSpace space, const char *name);

bool		ParseVariableBool(const char *value, const char *name,
							  bool *result);

bool		ParseVariableNum(const char *value, const char *name,
							 int *result);

bool		ParseVariableDouble(const char *value, const char *name,
								double *result, double min, double max);

void		PrintVariables(VariableSpace space);

bool		SetVariable(VariableSpace space, const char *name, const char *value);
bool		SetVariableBool(VariableSpace space, const char *name);
bool		DeleteVariable(VariableSpace space, const char *name);

void		SetVariableHooks(VariableSpace space, const char *name,
							 VariableSubstituteHook shook,
							 VariableAssignHook ahook);
bool		VariableHasHook(VariableSpace space, const char *name);

void		PsqlVarEnumError(const char *name, const char *value, const char *suggestions);

bool		SetBindVariable(VariableSpace space, const char *name, 
							const int typoid, const int typmod,
							const char *initval, bool notnull);
void		ListBindVariables(VariableSpace space, const char *name);
void		PrintBindVariables(VariableSpace space, print_list *bvlist);
bool		AssignBindVariable(VariableSpace space, const char *name, const char *value);
bool		ValidBindVariableName(const char *name);
struct _variable *BindVariableExist(VariableSpace space, const char *name);

#endif							/* VARIABLES_H */
