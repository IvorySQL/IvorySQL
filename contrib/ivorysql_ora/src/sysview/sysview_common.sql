/* Begin - ReqID:SRS-SQL-SYSVIEW */
/* 
 * function which converts all-uppercase text to all-lowercase text
 * and vice versa. 
 */
CREATE OR REPLACE FUNCTION SYS.ORA_CASE_TRANS(VARCHAR2)
RETURNS VARCHAR2
AS 'MODULE_PATHNAME','ora_case_trans'
LANGUAGE C IMMUTABLE;
/* End - ReqID:SRS-SQL-SYSVIEW */
