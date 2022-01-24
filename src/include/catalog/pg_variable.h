/*-------------------------------------------------------------------------
 *
 * pg_variable.h
 *	  definition of schema variables system catalog (pg_variables)
 *
 *
 * Portions Copyright (c) 2021-2022, IvorySQL
 * Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/catalog/pg_variable.h
 *
 * NOTES
 *	  The Catalog.pm module reads this file and derives schema
 *	  information.
 *
 *-------------------------------------------------------------------------
 */
#ifndef PG_VARIABLE_H
#define PG_VARIABLE_H

#include "catalog/genbki.h"
#include "catalog/objectaddress.h"
#include "catalog/pg_variable_d.h"
#include "utils/acl.h"

/* ----------------
 *		pg_variable definition.  cpp turns this into
 *		typedef struct FormData_pg_variable
 * ----------------
 */
CATALOG(pg_variable,561,VariableRelationId)
{
	Oid			oid;			/* oid */
	NameData	varname;		/* variable name */
	Oid			varnamespace;	/* OID of namespace containing variable class */
	Oid			vartype;		/* OID of entry in pg_type for variable's type */
	int32		vartypmod;		/* typmode for variable's type */
	Oid			varowner;		/* class owner */
	Oid			varcollation;	/* variable collation */
	bool		varisnotnull;	/* Don't allow NULL */
	bool		varisimmutable; /* Don't allow changes */
	char		vareoxaction;	/* action on transaction end */

#ifdef CATALOG_VARLEN			/* variable-length fields start here */

	/* list of expression trees for variable default (NULL if none) */
	pg_node_tree vardefexpr BKI_DEFAULT(_null_);

	aclitem		varacl[1] BKI_DEFAULT(_null_);	/* access permissions */
	char		varaccess;		/* Package variable access modifier */

#endif
} FormData_pg_variable;

typedef enum VariableEOXActionCodes
{
	VARIABLE_EOX_CODE_NOOP = 'n',	/* NOOP */
	VARIABLE_EOX_CODE_DROP = 'd',	/* ON COMMIT DROP */
	VARIABLE_EOX_CODE_RESET = 'r',	/* ON COMMIT RESET */
}			VariableEOXActionCodes;

/* ----------------
 *		Form_pg_variable corresponds to a pointer to a tuple with
 *		the format of pg_variable relation.
 * ----------------
 */
typedef FormData_pg_variable * Form_pg_variable;

DECLARE_UNIQUE_INDEX_PKEY(pg_variable_oid_index, 562, on pg_variable using btree(oid oid_ops));
#define VariableObjectIndexId 562
DECLARE_UNIQUE_INDEX(pg_variable_varname_nsp_index, 563, on pg_variable using btree(varname name_ops, varnamespace oid_ops));
#define VariableNameNspIndexId  563

typedef struct Variable
{
	Oid			oid;
	char	   *name;
	Oid			namespace;
	Oid			typid;
	int32		typmod;
	Oid			owner;
	Oid			collation;
	bool		is_not_null;
	bool		is_immutable;
	VariableEOXAction eoxaction;
	bool		has_defexpr;
	Node	   *defexpr;
	Acl		   *acl;
	char		varaccess;
} Variable;
extern ObjectAddress VariableCreate(const char *varName,
									Oid varNamespace,
									Oid variableoid,
									Oid varType,
									int32 varTypmod,
									Oid varOwner,
									Oid varCollation,
									Node *varDefexpr,
									VariableEOXAction eoxaction,
									bool is_not_null,
									bool is_immutable,
									bool ispkg,
									bool replace,
									bool isbody);

#endif							/* PG_VARIABLE_H */
