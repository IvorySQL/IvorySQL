/*-------------------------------------------------------------------------
 *
 * pg_synonym.h
 *	  definition of the "synonym" system catalog (pg_synonym)
 *
 *
 * Portions Copyright (c) 1996-2019, PostgreSQL Highgh Chengdu Group
 *
 * src/include/catalog/pg_synonym.h
 *
 * NOTES
 *	  The Catalog.pm module reads this file and derives schema
 *	  information.
 *
 *-------------------------------------------------------------------------
 */
#ifndef PG_SYNONYM_H_
#define PG_SYNONYM_H_

#include "catalog/genbki.h"
#include "catalog/pg_synonym_d.h"
#include "catalog/objectaddress.h"
#include "nodes/nodes.h"

/* ----------------
 *		pg_synonym definition.  cpp turns this into
 *		typedef struct FormData_pg_synonym
 *
 *		Some of the values in a pg_synonym instance are copied into
 *		pg_attribute instances.  Some parts of Postgres use the pg_synonym copy.
 * ----------------
 */
CATALOG(pg_synonym,4549,SynonymRelationId)
{
		/* oid */
		Oid 		oid;
	
		/* synonym name */
		NameData	synname;
	
		/* OID of namespace containing this synonym */
		Oid 		synnamespace BKI_DEFAULT(PGNSP);;
	
		/* synonym owner */
		Oid 		synowner BKI_DEFAULT(PGUID);
	
		/* Is it a public synonym */
		bool		synispub;
	
		/* Schema name of associated object */
		text		synobjschema;
	
		/* The name of the associated object */
		text		synobjname;
	
		/* Refer to the name of the database link */
		text		synlink;

} FormData_pg_synonym;

/* ----------------
 *		Form_pg_synonym corresponds to a pointer to a row with
 *		the format of pg_synonym relation.
 * ----------------
 */
typedef FormData_pg_synonym *Form_pg_synonym;

DECLARE_UNIQUE_INDEX_PKEY(pg_synonym_oid_index, 4550, SynonymOidIndexId, on pg_synonym using btree(oid oid_ops));

DECLARE_UNIQUE_INDEX(pg_synonym_synonymname_nsp_synpub_index, 4551, SynonyNameNspmpubIndexId, on pg_synonym using btree(synname name_ops, synnamespace oid_ops, synispub bool_ops));

extern ObjectAddress CreateSynonym(CreateSynonymStmt *stmt);
extern void DropSynonym(DropSynonymStmt *stmt);
extern Oid get_synonym_oid(List *synnamelist, bool pubflg, bool missing_ok);
extern char *get_synonym_name(Oid synonymid, bool missing_ok);
#endif							/* PG_SYNONYM_H_ */
