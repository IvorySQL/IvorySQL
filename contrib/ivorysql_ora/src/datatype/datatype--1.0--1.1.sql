/*
 * NCHAR and NVARCHAR2 use the same base type OIDs as the database-character
 * types.  This collation marks the Oracle NATIONAL character-set family.
 * Version 1.1 adds it to databases upgraded from ivorysql_ora 1.0.
 */
DO $nchar_collation$
DECLARE
	provider text;
	collate_name text;
	ctype_name text;
	locale_name text;
BEGIN
	SELECT datlocprovider::text, datcollate, datctype, datlocale
	  INTO provider, collate_name, ctype_name, locale_name
	  FROM pg_database
	 WHERE datname = current_database();

	IF NOT EXISTS (SELECT 1
					 FROM pg_collation
					WHERE collnamespace = 'sys'::regnamespace
					  AND collname = 'nchar_cs')
	THEN
		IF provider = 'i' THEN
			EXECUTE format(
				'CREATE COLLATION sys.nchar_cs (provider = icu, locale = %L)',
				locale_name);
		ELSIF provider = 'b' THEN
			EXECUTE format(
				'CREATE COLLATION sys.nchar_cs (provider = builtin, locale = %L)',
				locale_name);
		ELSE
			EXECUTE format(
				'CREATE COLLATION sys.nchar_cs (provider = libc, lc_collate = %L, lc_ctype = %L)',
				collate_name, ctype_name);
		END IF;
	END IF;
END
$nchar_collation$;
