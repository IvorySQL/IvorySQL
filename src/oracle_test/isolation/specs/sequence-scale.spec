# A session that has used a SCALE sequence follows SCALE settings that
# another session changes.

setup
{
    CREATE SEQUENCE seq_scale SCALE EXTEND NOCACHE;
}

teardown
{
    DROP SEQUENCE seq_scale;
}

session s1
setup           { SET ivorysql.enable_seq_scale_fixed = TRUE; }
step s1nv       { SELECT seq_scale.nextval FROM dual; }
step s1cv       { SELECT seq_scale.currval FROM dual; }
step s1nvfunc   { SELECT nextval('seq_scale'); }

session s2
step s2noextend { ALTER SEQUENCE seq_scale SCALE NOEXTEND MAXVALUE 9999999999999; }

permutation s1nv s2noextend s1cv s1nv s1nvfunc
