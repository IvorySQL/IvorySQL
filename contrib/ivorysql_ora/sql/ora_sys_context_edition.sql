--
-- ora_sys_context_edition.sql
--
-- Tests for the USERENV edition attributes of SYS_CONTEXT.  IvorySQL has no
-- edition-based redefinition, so a session always runs in the default
-- edition, which Oracle calls ORA$BASE.
--
-- CURRENT_EDITION_ID and SESSION_EDITION_ID are not covered here: they still
-- return NULL, because the edition id of the default edition has no
-- documented value yet.
--
SET ivorysql.compatible_mode = oracle;

select sys_context('USERENV', 'CURRENT_EDITION_NAME') as current_edition_name from dual;

select sys_context('USERENV', 'SESSION_EDITION_NAME') as session_edition_name from dual;

-- the namespace and the attribute name are case insensitive
select sys_context('userenv', 'current_edition_name') as current_edition_name from dual;

-- the edition name is the default edition, not the server version
select sys_context('USERENV', 'CURRENT_EDITION_NAME') = 'ORA$BASE' as is_default_edition from dual;

-- the three argument form truncates the value
select sys_context('USERENV', 'CURRENT_EDITION_NAME', 4) as truncated_edition_name from dual;

-- the other USERENV attributes keep working next to the edition names
select sys_context('USERENV', 'SESSION_USER') is not null as session_user_present from dual;

-- a NULL or an empty attribute name is rejected by the existing
-- implementation, where Oracle raises ORA-20000 for the same input.  Recorded
-- as the current behaviour, this change does not touch it.
do $$
begin
    perform sys_context('USERENV', NULL);
    raise notice 'no error raised';
exception
    when others then
        raise notice 'rejected';
end;
$$;

do $$
begin
    perform sys_context('USERENV', '');
    raise notice 'no error raised';
exception
    when others then
        raise notice 'rejected';
end;
$$;
