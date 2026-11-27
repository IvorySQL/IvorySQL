--
-- ora_sys_context.sql
--
-- Tests for SYS_CONTEXT('USERENV', ...) NLS attributes.  These must reflect
-- the session's nls_* GUCs (nls_currency and nls_territory), exactly like
-- nls_date_format already does.
--
-- Default values
SELECT sys_context('USERENV', 'NLS_CURRENCY')     AS nls_currency,
       sys_context('USERENV', 'NLS_TERRITORY')    AS nls_territory,
       sys_context('USERENV', 'NLS_DATE_FORMAT')  AS nls_date_format;

-- SYS_CONTEXT must stay in sync with the GUC even after they are overridden.
SET nls_currency    = 'EUR';
SET nls_territory   = 'CHINA';
SET nls_date_format = 'DD/MM/YYYY';

SELECT sys_context('USERENV', 'NLS_CURRENCY') = current_setting('nls_currency')       AS currency_synced,
       sys_context('USERENV', 'NLS_TERRITORY') = current_setting('nls_territory')      AS territory_synced,
       sys_context('USERENV', 'NLS_DATE_FORMAT') = current_setting('nls_date_format') AS date_format_synced;

-- Assert the concrete values returned by SYS_CONTEXT after the overrides.
SELECT sys_context('USERENV', 'NLS_CURRENCY')  AS nls_currency,
       sys_context('USERENV', 'NLS_TERRITORY') AS nls_territory;

RESET nls_currency;
RESET nls_territory;
RESET nls_date_format;
