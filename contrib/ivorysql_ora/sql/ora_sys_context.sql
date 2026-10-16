--
-- ora_sys_context.sql
--
-- Tests the session-level NLS_DATE_LANGUAGE setting exposed through
-- SYS_CONTEXT('USERENV', ...).
--
-- The default session language must be Oracle's AMERICAN value.
SELECT current_setting('nls_date_language') AS session_language,
       sys_context('USERENV', 'NLS_DATE_LANGUAGE') AS context_language;

-- SYS_CONTEXT must stay in sync with the session GUC after it is overridden.
SET nls_date_language = 'FRENCH';

SELECT sys_context('USERENV', 'NLS_DATE_LANGUAGE') =
       current_setting('nls_date_language') AS language_synced;

-- Assert the concrete value returned by SYS_CONTEXT.
SELECT sys_context('USERENV', 'NLS_DATE_LANGUAGE') AS nls_date_language;

RESET nls_date_language;
