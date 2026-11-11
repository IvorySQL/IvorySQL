# Copyright (c) 2026, PostgreSQL Global Development Group

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# A missing advice field must remain distinct from an empty final field.
my @cases = (
    ['missing_advice', '', 'expected advice string'],
    ['extra_field', "\tSeqScan(t)\textra", 'expected end of line'],
    ['extra_empty_field', "\tSeqScan(t)\t", 'expected end of line'],
);

for my $case (@cases)
{
    my ($name, $tail, $error) = @$case;
    my $node = PostgreSQL::Test::Cluster->new($name);
    $node->init;
    $node->append_conf('postgresql.conf',
        "shared_preload_libraries = 'pg_plan_advice, pg_stash_advice'\n"
      . "pg_stash_advice.persist = true\n"
      . "pg_stash_advice.persist_interval = 0\n");
    append_to_file($node->data_dir . '/pg_stash_advice.tsv',
        "stash\tstash_a\nentry\tstash_a\t1001$tail\n");
    $node->start;
    $node->wait_for_log(qr/syntax error in file .* line 2: $error/);
    pass("reject $name in persisted advice");
    $node->stop;
}

done_testing();
