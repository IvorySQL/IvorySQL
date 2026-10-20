# Copyright (c) 2026, IvorySQL Global Development Team

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('ref_safety');
$node->init;
$node->start;

sub sql
{
	return $node->safe_psql('postgres', $_[0], connect_to_oraport => 1);
}

sub fails_like
{
	my ($query, $pattern, $label) = @_;
	my ($stdout, $stderr);
	my $status = $node->psql('postgres', $query, stdout => \$stdout,
		stderr => \$stderr, connect_to_oraport => 1);
	isnt($status, 0, "$label: fails");
	like($stderr, $pattern, "$label: error");
}

sql(q{
	CREATE TYPE safety_t AS OBJECT (id integer);
	CREATE TABLE safety_objects OF safety_t;
	CREATE TABLE safety_refs (r REF safety_t);
	INSERT INTO safety_objects VALUES (1);
	INSERT INTO safety_refs SELECT REF(o) FROM safety_objects o;
	DELETE FROM safety_objects;
	CREATE ROLE ref_writer;
	GRANT USAGE ON SCHEMA sys TO ref_writer;
	GRANT SELECT, INSERT ON safety_objects TO ref_writer;
	GRANT SELECT ON safety_refs TO ref_writer;
	GRANT USAGE ON SEQUENCE safety_objects_rowid_seq TO ref_writer;
	CREATE ROLE ref_no_select;
	GRANT USAGE ON SCHEMA sys TO ref_no_select;
});

fails_like(q{SET ROLE ref_writer;
	SELECT sys.ora_deref_internal(1, NULL::safety_t)},
	qr/DEREF requires an object reference/, 'unprivileged scalar DEREF is safe');
is(sql('SELECT 1'), '1', 'backend remains available after invalid DEREF');
fails_like(q{SET ROLE ref_no_select;
	SELECT sys.ora_deref_internal(
		ROW('safety_objects'::regclass, 1::bigint)::sys.object_ref, NULL::safety_t)},
	qr/permission denied for table safety_objects/,
	'direct typed helper calls cannot bypass SELECT privileges');
fails_like(q{SET ROLE ref_writer;
	SELECT sys.ora_set_next_rowid('safety_objects', 1)},
	qr/must be owner of table safety_objects/,
	'INSERT privileges do not permit restoring object identities');
sql('GRANT EXECUTE ON FUNCTION sys.ora_set_next_rowid(regclass,bigint) TO ref_writer');
fails_like(q{SET ROLE ref_writer;
	INSERT INTO safety_objects SELECT 2
	FROM sys.ora_set_next_rowid('safety_objects', 1)},
	qr/must be owner of table safety_objects/,
	'an EXECUTE grant cannot bypass the table ownership check');
is(sql(q{SET ROLE ref_writer;
	SELECT DEREF(r) IS NULL FROM safety_refs}),
	't', 'ordinary callers can still dereference a typed REF');

sql(q{
	SELECT sys.ora_set_next_rowid('safety_objects', 1);
	INSERT INTO safety_objects VALUES (2);
});
is(sql('SELECT (rowid).rowno <> 1 FROM safety_objects'),
	't', 'autocommit clears an unused restore override');
is(sql('SELECT DEREF(r) IS NULL FROM safety_refs'),
	't', 'deleted object identity remains dangling');
is(sql(q{SET ROLE ref_writer;
	SELECT (sys.ora_deref_internal(sys.make_object_ref(o.rowid), NULL::safety_t)).id
	FROM safety_objects o}), '2', 'direct object_ref calls use caller privileges');

sql(q{BEGIN;
	SELECT sys.ora_set_next_rowid('safety_objects', 42);
	INSERT INTO safety_objects VALUES (3);
	COMMIT});
is(sql('SELECT (rowid).rowno <> 42 FROM safety_objects WHERE id=3'),
	't', 'an unused override cannot cross a command boundary');
sql(q{BEGIN;
	SELECT sys.ora_set_next_rowid('safety_objects', 43);
	ROLLBACK;
	INSERT INTO safety_objects VALUES (4)});
is(sql('SELECT (rowid).rowno <> 43 FROM safety_objects WHERE id=4'),
	't', 'rollback clears restore state');
sql(q{BEGIN;
	SAVEPOINT s;
	SELECT sys.ora_set_next_rowid('safety_objects', 44);
	ROLLBACK TO s;
	INSERT INTO safety_objects VALUES (5);
	COMMIT});
is(sql('SELECT (rowid).rowno <> 44 FROM safety_objects WHERE id=5'),
	't', 'subtransaction abort clears restore state');
sql(q{BEGIN;
	SAVEPOINT s;
	SELECT sys.ora_set_next_rowid('safety_objects', 45);
	RELEASE s;
	INSERT INTO safety_objects VALUES (6);
	COMMIT});
is(sql('SELECT (rowid).rowno <> 45 FROM safety_objects WHERE id=6'),
	't', 'subtransaction commit clears restore state');

sql(q{INSERT INTO safety_objects SELECT 7
	FROM sys.ora_set_next_rowid('safety_objects', 9223372036854775807)});
is(sql('SELECT (rowid).rowno FROM safety_objects WHERE id=7'),
	'9223372036854775807', 'trusted statement-scoped restore supports INT64_MAX');

# A BEFORE trigger must not be able to consume, suppress, or redirect a restore.
$node->safe_psql('postgres', q{
	CREATE FUNCTION safety_skip() RETURNS trigger LANGUAGE plpgsql AS
	$$ BEGIN RETURN NULL; END $$;
	CREATE TRIGGER safety_skip BEFORE INSERT ON safety_objects
	FOR EACH ROW EXECUTE FUNCTION safety_skip();
});
fails_like(q{INSERT INTO safety_objects SELECT 8
	FROM sys.ora_set_next_rowid('safety_objects', 46)},
	qr/cannot restore ROWID values with enabled BEFORE INSERT triggers or INSERT rules/,
	'unsafe trigger restore is rejected');
sql(q{ALTER TABLE safety_objects DISABLE TRIGGER safety_skip;
	INSERT INTO safety_objects SELECT 80
	FROM sys.ora_set_next_rowid('safety_objects', 8080)});
is(sql('SELECT (rowid).rowno FROM safety_objects WHERE id=80'),
	'8080', 'a disabled BEFORE INSERT trigger does not prevent restoration');
sql(q{ALTER TABLE safety_objects ENABLE REPLICA TRIGGER safety_skip;
	INSERT INTO safety_objects SELECT 81
	FROM sys.ora_set_next_rowid('safety_objects', 8081)});
is(sql('SELECT (rowid).rowno FROM safety_objects WHERE id=81'),
	'8081', 'a replica-only trigger does not prevent origin restoration');
fails_like(q{SET session_replication_role = replica;
	SELECT sys.ora_set_next_rowid('safety_objects', 8082)},
	qr/cannot restore ROWID values with enabled BEFORE INSERT triggers or INSERT rules/,
	'a replica-only trigger prevents replica restoration');
sql(q{ALTER TABLE safety_objects ENABLE TRIGGER safety_skip;
	SET session_replication_role = replica;
	INSERT INTO safety_objects SELECT 83
	FROM sys.ora_set_next_rowid('safety_objects', 8083)});
is(sql('SELECT (rowid).rowno FROM safety_objects WHERE id=83'),
	'8083', 'an origin-only trigger does not prevent replica restoration');
sql('ALTER TABLE safety_objects ENABLE ALWAYS TRIGGER safety_skip');
foreach my $role (qw(origin replica))
{
	fails_like("SET session_replication_role = $role; " .
		q{SELECT sys.ora_set_next_rowid('safety_objects', 8084)},
		qr/cannot restore ROWID values with enabled BEFORE INSERT triggers or INSERT rules/,
		"an ALWAYS trigger prevents $role restoration");
}
sql(q{DROP TRIGGER safety_skip ON safety_objects;
	INSERT INTO safety_objects VALUES (9)});
is(sql('SELECT (rowid).rowno <> 46 FROM safety_objects WHERE id=9'),
	't', 'rejected restore leaves no pending override');

sql('CREATE TABLE safety_check (n integer CHECK (n > 0)) WITH ROWID');
fails_like(q{INSERT INTO safety_check SELECT -1
	FROM sys.ora_set_next_rowid('safety_check', 47)},
	qr/violates check constraint/, 'constraint failure aborts a pending restore');
sql('INSERT INTO safety_check VALUES (1)');
is(sql('SELECT (rowid).rowno <> 47 FROM safety_check'),
	't', 'failed insert cannot change a later identity');

# Rules for other events and disabled INSERT rules cannot redirect an INSERT.
sql('CREATE TABLE safety_rules (n integer) WITH ROWID');
$node->safe_psql('postgres', q{
	CREATE RULE safety_update AS ON UPDATE TO safety_rules DO INSTEAD NOTHING;
});
sql(q{INSERT INTO safety_rules SELECT 1
	FROM sys.ora_set_next_rowid('safety_rules', 101)});
is(sql('SELECT (rowid).rowno FROM safety_rules WHERE n=1'),
	'101', 'an UPDATE rule does not prevent ROWID restoration');
$node->safe_psql('postgres', q{
	CREATE RULE safety_insert AS ON INSERT TO safety_rules
	DO ALSO NOTIFY rowid_restore;
});
fails_like(q{SELECT sys.ora_set_next_rowid('safety_rules', 102)},
	qr/cannot restore ROWID values with enabled BEFORE INSERT triggers or INSERT rules/,
	'an enabled INSERT rule prevents restoration');
sql(q{ALTER TABLE safety_rules DISABLE RULE safety_insert;
	INSERT INTO safety_rules SELECT 2
	FROM sys.ora_set_next_rowid('safety_rules', 102)});
is(sql('SELECT (rowid).rowno FROM safety_rules WHERE n=2'),
	'102', 'a disabled INSERT rule does not prevent restoration');
sql(q{ALTER TABLE safety_rules ENABLE REPLICA RULE safety_insert;
	INSERT INTO safety_rules SELECT 3
	FROM sys.ora_set_next_rowid('safety_rules', 103)});
is(sql('SELECT (rowid).rowno FROM safety_rules WHERE n=3'),
	'103', 'a replica-only rule does not prevent origin restoration');
fails_like(q{SET session_replication_role = replica;
	SELECT sys.ora_set_next_rowid('safety_rules', 104)},
	qr/cannot restore ROWID values with enabled BEFORE INSERT triggers or INSERT rules/,
	'a replica-only rule prevents replica restoration');
sql(q{ALTER TABLE safety_rules ENABLE RULE safety_insert;
	SET session_replication_role = replica;
	INSERT INTO safety_rules SELECT 4
	FROM sys.ora_set_next_rowid('safety_rules', 104)});
is(sql('SELECT (rowid).rowno FROM safety_rules WHERE n=4'),
	'104', 'an origin-only rule does not prevent replica restoration');
sql('ALTER TABLE safety_rules ENABLE ALWAYS RULE safety_insert');
foreach my $role (qw(origin replica))
{
	fails_like("SET session_replication_role = $role; " .
		q{SELECT sys.ora_set_next_rowid('safety_rules', 105)},
		qr/cannot restore ROWID values with enabled BEFORE INSERT triggers or INSERT rules/,
		"an ALWAYS rule prevents $role restoration");
}

$node->stop('fast');
done_testing();
