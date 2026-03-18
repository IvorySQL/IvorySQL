# Copyright (c) 2021, PostgreSQL Global Development Group
#
# Test for logical_replication_fallback_to_full_identity GUC parameter
# This tests the functionality that allows tables without primary keys
# to use REPLICA IDENTITY FULL automatically when the GUC is enabled.
use strict;
use warnings;
use PostgresNode;
use Test::More tests => 23;

# Initialize publisher node
my $node_publisher = get_new_node('publisher');
$node_publisher->init(allows_streaming => 'logical');
$node_publisher->start;

# Create subscriber node
my $node_subscriber = get_new_node('subscriber');
$node_subscriber->init(allows_streaming => 'logical');
$node_subscriber->start;

# Create table without primary key on publisher
$node_publisher->safe_psql('postgres',
	"CREATE TABLE test_no_pk (id int, name text)");

# Create table with primary key for comparison
$node_publisher->safe_psql('postgres',
	"CREATE TABLE test_with_pk (id int primary key, name text)");

# Create matching tables on subscriber
$node_subscriber->safe_psql('postgres',
	"CREATE TABLE test_no_pk (id int, name text)");
$node_subscriber->safe_psql('postgres',
	"CREATE TABLE test_with_pk (id int primary key, name text)");

# Setup logical replication
my $publisher_connstr = $node_publisher->connstr . ' dbname=postgres';

$node_publisher->safe_psql('postgres', "CREATE PUBLICATION tap_pub");
$node_publisher->safe_psql('postgres',
	"ALTER PUBLICATION tap_pub ADD TABLE test_no_pk, test_with_pk");

$node_subscriber->safe_psql('postgres',
	"CREATE SUBSCRIPTION tap_sub CONNECTION '$publisher_connstr' PUBLICATION tap_pub");

# Wait for initial sync
$node_subscriber->wait_for_subscription_sync($node_publisher, 'tap_sub');

# Insert initial data
$node_publisher->safe_psql('postgres',
	"INSERT INTO test_no_pk VALUES (1, 'before_guc_enable')");
$node_publisher->safe_psql('postgres',
	"INSERT INTO test_with_pk VALUES (1, 'with_pk')");

$node_publisher->wait_for_catchup('tap_sub');

my $result;

# Test 1: Verify initial data is replicated to table without PK
$result = $node_subscriber->safe_psql('postgres',
	"SELECT count(*) FROM test_no_pk");
is($result, qq(1), 'initial data replicated to table without pk');

# Test 2: Verify initial data is replicated to table with PK
$result = $node_subscriber->safe_psql('postgres',
	"SELECT count(*) FROM test_with_pk");
is($result, qq(1), 'initial data replicated to table with pk');

$node_publisher->append_conf('postgresql.conf',
	"logical_replication_fallback_to_full_identity = off");
$node_publisher->reload;

# Test 3: Without GUC enabled, INSERT on table without PK should work
# (INSERT doesn't require replica identity)
my $ret = $node_publisher->psql('postgres',
	"INSERT INTO test_no_pk VALUES (2, 'test_without_pk2')");
is($ret, 0, 'INSERT on table without PK works when GUC is off');

$node_publisher->wait_for_catchup('tap_sub');

$result = $node_subscriber->safe_psql('postgres',
	"SELECT count(*) FROM test_no_pk");
is($result, qq(2), 'INSERT replicated after enabling GUC');

# Test 4: Without GUC enabled, UPDATE on table without PK should fail
# (the GUC defaults to off, and CheckCmdReplicaIdentity should reject this)
$ret = $node_publisher->psql('postgres',
	"UPDATE test_no_pk SET name = 'should_fail' WHERE id = 1");
isnt($ret, 0, 'UPDATE on table without PK fails when GUC is off');

# Test 5: Without GUC enabled, DELETE on table without PK should fail
$ret = $node_publisher->psql('postgres',
	"DELETE FROM test_no_pk WHERE id = 1");
isnt($ret, 0, 'DELETE on table without PK fails when GUC is off');

# Test 6: Without GUC enabled, UPDATE on table with PK should work
$node_publisher->safe_psql('postgres',
	"INSERT INTO test_with_pk VALUES (2, 'test_with_pk2')");
$node_publisher->safe_psql('postgres',
	"UPDATE test_with_pk SET name = 'updated_with_pk' WHERE id = 2");

$node_publisher->wait_for_catchup('tap_sub');

$result = $node_subscriber->safe_psql('postgres',
	"SELECT name FROM test_with_pk WHERE id = 2");
is($result, qq(updated_with_pk),
	'UPDATE on table with PK works without GUC');

# Test 7: Now enable the GUC and reload
$node_publisher->append_conf('postgresql.conf',
	"logical_replication_fallback_to_full_identity = on");
$node_publisher->reload;

# Test 8: With GUC enabled, INSERT on table without PK should work
$node_publisher->safe_psql('postgres',
	"INSERT INTO test_no_pk VALUES (3, 'after_guc_enable')");

$node_publisher->wait_for_catchup('tap_sub');

$result = $node_subscriber->safe_psql('postgres',
	"SELECT count(*) FROM test_no_pk");
is($result, qq(3), 'INSERT replicated after enabling GUC');

# Test 9: With GUC enabled, UPDATE on table without PK should work
$node_publisher->safe_psql('postgres',
	"UPDATE test_no_pk SET name = 'updated_after_guc' WHERE id = 3");

$node_publisher->wait_for_catchup('tap_sub');

$result = $node_subscriber->safe_psql('postgres',
	"SELECT name FROM test_no_pk WHERE id = 3");
is($result, qq(updated_after_guc), 'UPDATE replicated after enabling GUC');

# Test 10: With GUC enabled, DELETE on table without PK should work
$node_publisher->safe_psql('postgres',
	"DELETE FROM test_no_pk WHERE id = 3");

$node_publisher->wait_for_catchup('tap_sub');

$result = $node_subscriber->safe_psql('postgres',
	"SELECT count(*) FROM test_no_pk");
is($result, qq(2), 'DELETE replicated after enabling GUC');

# Test 11: Verify table with PK still works normally with GUC enabled
$node_publisher->safe_psql('postgres',
	"UPDATE test_with_pk SET name = 'updated_again' WHERE id = 1");

$node_publisher->wait_for_catchup('tap_sub');

$result = $node_subscriber->safe_psql('postgres',
	"SELECT name FROM test_with_pk WHERE id = 1");
is($result, qq(updated_again), 'table with pk still works with GUC enabled');

# Test 12: Test new table without PK after GUC is enabled
$node_publisher->safe_psql('postgres',
	"CREATE TABLE test_no_pk2 (id int, data text)");
# $node_publisher->safe_psql('postgres',
# 	"ALTER TABLE test_no_pk2 REPLICA IDENTITY DEFAULT");

$node_subscriber->safe_psql('postgres',
	"CREATE TABLE test_no_pk2 (id int, data text)");

$node_publisher->safe_psql('postgres',
	"ALTER PUBLICATION tap_pub ADD TABLE test_no_pk2");

# Refresh subscription to pick up new table
$node_subscriber->safe_psql('postgres',
	"ALTER SUBSCRIPTION tap_sub REFRESH PUBLICATION");

# Wait for new table to sync
$node_subscriber->wait_for_subscription_sync($node_publisher, 'tap_sub');

$node_publisher->safe_psql('postgres',
	"INSERT INTO test_no_pk2 VALUES (1, 'new_table_no_pk')");
$node_publisher->safe_psql('postgres',
	"UPDATE test_no_pk2 SET data = 'updated' WHERE id = 1");
$node_publisher->safe_psql('postgres',
	"DELETE FROM test_no_pk2 WHERE id = 1");

$node_publisher->wait_for_catchup('tap_sub');

$result = $node_subscriber->safe_psql('postgres',
	"SELECT count(*) FROM test_no_pk2");
is($result, qq(0), 'new table without pk also works with GUC enabled');

# Test 12: Disable GUC and verify UPDATE/DELETE on table without PK fails again
$node_publisher->append_conf('postgresql.conf',
	"logical_replication_fallback_to_full_identity = off");
$node_publisher->reload;

# INSERT should still work
$node_publisher->safe_psql('postgres',
	"INSERT INTO test_no_pk VALUES (4, 'after_guc_disable')");

$node_publisher->wait_for_catchup('tap_sub');

$result = $node_subscriber->safe_psql('postgres',
	"SELECT count(*) FROM test_no_pk");
is($result, qq(3), 'INSERT still works after disabling GUC');

# UPDATE on table without PK should fail again
$ret = $node_publisher->psql('postgres',
	"UPDATE test_no_pk SET name = 'should_fail_again' WHERE id = 4");
isnt($ret, 0, 'UPDATE on table without PK fails after disabling GUC');

# But UPDATE on table with PK should still work
$node_publisher->safe_psql('postgres',
	"UPDATE test_with_pk SET name = 'final_update' WHERE id = 1");

$node_publisher->wait_for_catchup('tap_sub');

$result = $node_subscriber->safe_psql('postgres',
	"SELECT name FROM test_with_pk WHERE id = 1");
is($result, qq(final_update), 'table with pk unaffected by GUC setting');

# ============================================================
# Test 14-16: GUC enabled does NOT override REPLICA IDENTITY NOTHING
# ============================================================

# Re-enable GUC
$node_publisher->append_conf('postgresql.conf',
	"logical_replication_fallback_to_full_identity = on");
$node_publisher->reload;

# Create table without PK, then manually set REPLICA IDENTITY NOTHING
$node_publisher->safe_psql('postgres',
	"CREATE TABLE test_nothing (id int, data text)");
$node_publisher->safe_psql('postgres',
	"ALTER TABLE test_nothing REPLICA IDENTITY NOTHING");

$node_subscriber->safe_psql('postgres',
	"CREATE TABLE test_nothing (id int, data text)");

$node_publisher->safe_psql('postgres',
	"ALTER PUBLICATION tap_pub ADD TABLE test_nothing");

# Refresh subscription to pick up new table
$node_subscriber->safe_psql('postgres',
	"ALTER SUBSCRIPTION tap_sub REFRESH PUBLICATION");

# Wait for new table to sync
$node_subscriber->wait_for_subscription_sync($node_publisher, 'tap_sub');

# Test 14: INSERT should work
$node_publisher->safe_psql('postgres',
	"INSERT INTO test_nothing VALUES (1, 'test_nothing')");

$node_publisher->wait_for_catchup('tap_sub');

$result = $node_subscriber->safe_psql('postgres',
	"SELECT count(*) FROM test_nothing");
is($result, qq(1), 'INSERT on REPLICA IDENTITY NOTHING table works');

# Test 15: UPDATE should fail even with GUC enabled
# (GUC does not override manually set REPLICA IDENTITY NOTHING)
$ret = $node_publisher->psql('postgres',
	"UPDATE test_nothing SET data = 'should_fail' WHERE id = 1");
isnt($ret, 0, 'UPDATE on REPLICA IDENTITY NOTHING table fails even with GUC on');

# Test 16: DELETE should fail even with GUC enabled
$ret = $node_publisher->psql('postgres',
	"DELETE FROM test_nothing WHERE id = 1");
isnt($ret, 0, 'DELETE on REPLICA IDENTITY NOTHING table fails even with GUC on');

# ============================================================
# Test 17-18: GUC does not affect tables with REPLICA IDENTITY FULL
# ============================================================

# Create table with explicit REPLICA IDENTITY FULL
$node_publisher->safe_psql('postgres',
	"CREATE TABLE test_full (id int, data text)");
$node_publisher->safe_psql('postgres',
	"ALTER TABLE test_full REPLICA IDENTITY FULL");

$node_subscriber->safe_psql('postgres',
	"CREATE TABLE test_full (id int, data text)");

$node_publisher->safe_psql('postgres',
	"ALTER PUBLICATION tap_pub ADD TABLE test_full");

# Refresh subscription to pick up new table
$node_subscriber->safe_psql('postgres',
	"ALTER SUBSCRIPTION tap_sub REFRESH PUBLICATION");

# Wait for new table to sync
$node_subscriber->wait_for_subscription_sync($node_publisher, 'tap_sub');

# Test 17: INSERT/UPDATE/DELETE should all work with REPLICA IDENTITY FULL
$node_publisher->safe_psql('postgres',
	"INSERT INTO test_full VALUES (1, 'test_full')");
$node_publisher->safe_psql('postgres',
	"UPDATE test_full SET data = 'updated_full' WHERE id = 1");

$node_publisher->wait_for_catchup('tap_sub');

$result = $node_subscriber->safe_psql('postgres',
	"SELECT data FROM test_full WHERE id = 1");
is($result, qq(updated_full), 'table with REPLICA IDENTITY FULL works with GUC on');

# Test 18: DELETE should work
$node_publisher->safe_psql('postgres',
	"DELETE FROM test_full WHERE id = 1");

$node_publisher->wait_for_catchup('tap_sub');

$result = $node_subscriber->safe_psql('postgres',
	"SELECT count(*) FROM test_full");
is($result, qq(0), 'DELETE on REPLICA IDENTITY FULL table works with GUC on');

# ============================================================
# Test 19-21: GUC does not affect tables with REPLICA IDENTITY INDEX
# ============================================================

# Create table with unique index and REPLICA IDENTITY INDEX
$node_publisher->safe_psql('postgres',
	"CREATE TABLE test_index (id int NOT NULL, data text)");
$node_publisher->safe_psql('postgres',
	"CREATE UNIQUE INDEX test_index_idx ON test_index (id)");
$node_publisher->safe_psql('postgres',
	"ALTER TABLE test_index REPLICA IDENTITY USING INDEX test_index_idx");

$node_subscriber->safe_psql('postgres',
	"CREATE TABLE test_index (id int NOT NULL, data text)");
$node_subscriber->safe_psql('postgres',
	"CREATE UNIQUE INDEX test_index_idx ON test_index (id)");
$node_subscriber->safe_psql('postgres',
	"ALTER TABLE test_index REPLICA IDENTITY USING INDEX test_index_idx");

$node_publisher->safe_psql('postgres',
	"ALTER PUBLICATION tap_pub ADD TABLE test_index");

# Refresh subscription to pick up new table
$node_subscriber->safe_psql('postgres',
	"ALTER SUBSCRIPTION tap_sub REFRESH PUBLICATION");

# Wait for new table to sync
$node_subscriber->wait_for_subscription_sync($node_publisher, 'tap_sub');

# Test 19: INSERT should work
$node_publisher->safe_psql('postgres',
	"INSERT INTO test_index VALUES (1, 'test_index')");

$node_publisher->wait_for_catchup('tap_sub');

$result = $node_subscriber->safe_psql('postgres',
	"SELECT count(*) FROM test_index");
is($result, qq(1), 'INSERT on REPLICA IDENTITY INDEX table works');

# Test 20: UPDATE should work (GUC does not affect it)
$node_publisher->safe_psql('postgres',
	"UPDATE test_index SET data = 'updated_index' WHERE id = 1");

$node_publisher->wait_for_catchup('tap_sub');

$result = $node_subscriber->safe_psql('postgres',
	"SELECT data FROM test_index WHERE id = 1");
is($result, qq(updated_index), 'UPDATE on REPLICA IDENTITY INDEX table works with GUC on');

# Test 21: DELETE should work (GUC does not affect it)
$node_publisher->safe_psql('postgres',
	"DELETE FROM test_index WHERE id = 1");

$node_publisher->wait_for_catchup('tap_sub');

$result = $node_subscriber->safe_psql('postgres',
	"SELECT count(*) FROM test_index");
is($result, qq(0), 'DELETE on REPLICA IDENTITY INDEX table works with GUC on');

# Cleanup
$node_subscriber->stop('fast');
$node_publisher->stop('fast');
