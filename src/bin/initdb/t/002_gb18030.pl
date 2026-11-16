# Copyright (c) 2026, IvorySQL Global Development Team

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# GB18030 and its explicit 2022 alias must select the same conversion tables.
# UTF8 clusters must also preload the extension for GB18030 client data.
for my $settings (
	[ 'pg', 'GB18030' ],
	[ 'oracle', 'GB18030' ],
	[ 'pg', 'GB18030_2022' ],
	[ 'oracle', 'UTF8' ])
{
	my ($mode, $encoding) = @$settings;
	my $node = PostgreSQL::Test::Cluster->new("gb18030_${mode}_${encoding}");
	$node->init(
		extra => [ '--dbmode', $mode, '--encoding', $encoding, '--no-locale' ]);
	$node->start;

	like(
		$node->safe_psql('postgres', 'SHOW shared_preload_libraries'),
		qr/\bgb18030_2022\b/,
		"$mode/$encoding preloads GB18030-2022 in every session");
	is(
		$node->safe_psql('postgres',
			"SELECT count(*) FROM pg_extension WHERE extname = 'gb18030_2022'"),
		'1',
		"$mode/$encoding installs the extension");
	is(
		$node->safe_psql('postgres', 'SHOW server_encoding'),
		$encoding eq 'UTF8' ? 'UTF8' : 'GB18030',
		"$mode/$encoding preserves the server encoding");

	# Reproduce a UTF8 database created in a GB18030-initialized cluster.
	$node->safe_psql('postgres',
		"CREATE DATABASE utf8_mapping ENCODING 'UTF8' "
		  . "LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0");

	my @mapping = (
		[ '82359037', 'e81e' ], [ '82359038', 'e826' ],
		[ '82359039', 'e82b' ], [ '82359130', 'e82c' ],
		[ '82359131', 'e832' ], [ '82359132', 'e843' ],
		[ '82359133', 'e854' ], [ '82359134', 'e864' ],
		[ 'fe59', '9fb4' ]);
	my $values = join(', ', map { "('$_->[0]')" } @mapping);
	my $expected = join("\n", map { "$_->[0]:$_->[1]" } @mapping);

	is(
		$node->safe_psql('utf8_mapping',
			"SELECT hex || ':' || to_hex(ascii(convert_from(decode(hex, 'hex'), 'GB18030'))) "
			  . "FROM (VALUES $values) AS v(hex) ORDER BY hex"),
		$expected,
		"$mode/$encoding uses 2022 Unicode mappings in a new UTF8 database");
	is(
		$node->safe_psql('utf8_mapping',
			"SELECT count(*) FROM (VALUES $values) AS v(hex) "
			  . "WHERE encode(convert_to(convert_from(decode(hex, 'hex'), 'GB18030'), 'GB18030'), 'hex') <> hex"),
		'0',
		"$mode/$encoding round-trips GB18030-2022 bytes");

	$node->stop;
}

done_testing();
