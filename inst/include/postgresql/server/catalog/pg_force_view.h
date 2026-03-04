/*-------------------------------------------------------------------------
 *
 * File:pg_force_view.h
 *
 *
 *
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *	  src/include/catalog/pg_force_view.h
 *
 * Notes:
 *		Definition of the "force view" system catalog
 *-------------------------------------------------------------------------
 */
#ifndef PG_FORCE_VIEW_H
#define PG_FORCE_VIEW_H

#include "catalog/genbki.h"
#include "catalog/pg_force_view_d.h"

/* ----------------
 *		pg_force_view definition
 *		typedef struct FormData_pg_force_view
 * ----------------
 */
CATALOG(pg_force_view,9120,ForceViewRelationId)
{
    /* oid of force view */
	Oid			fvoid;

    /* see IDENT_CASE__xxx constants below */		
	char		ident_case;		

#ifdef CATALOG_VARLEN			/* variable-length fields start here */

    /* sql definition */
	text		source;         
#endif
} FormData_pg_force_view;

/* ----------------
 *		Form_pg_force_view corresponds to a pointer to a tuple with
 *		the format of pg_force_view relation.
 * ----------------
 */
typedef FormData_pg_force_view *Form_pg_force_view;

DECLARE_TOAST(pg_force_view, 9121, 9122);

#define ForceViewFvoidIndexId	9123
/*
 * The DECLARE_UNIQUE_INDEX_PKEY macro takes the C macro name for the index's
 * OID as its third argument. This is cleaner than a separate #define.
 */
DECLARE_UNIQUE_INDEX_PKEY(pg_force_view_fvoid_index, 9123, ForceViewFvoidIndexId, pg_force_view, btree(fvoid oid_ops));

/*
 * Create a syscache for pg_force_view lookup by OID.
 * This will automatically create the FORCEVIEWOID enum member.
 */
MAKE_SYSCACHE(FORCEVIEWOID, pg_force_view_fvoid_index, 16);

/*
 * If the view fails to compile during CREATE, the definition of
 * force view is obtained from the queryString of the query, so
 * we must record the current identifier_case_switch value, otherwise
 * we will not know the meaning of the identifier within double quotes
 * when restoring.
 */
#define		  IDENT_CASE_NORMAL			'n'		/* NORMAL */
#define		  IDENT_CASE_INTERCHANGE	'i'		/* INTERCHANGE */
#define		  IDENT_CASE_LOWERCASE		'l'		/* LOWERCASE */
#define		  IDENT_CASE_UNDEFINE		'u'		/* UNDEFINE */

#endif							/* PG_FORCE_VIEW_H */
