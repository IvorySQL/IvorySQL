# Copyright (c) 2026, IvorySQL Global Development Team

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('asciistr');
$node->init(extra => [ '--locale=C', '--encoding=UTF8', '-m', 'oracle' ]);
$node->start;

$node->safe_psql('postgres', 'CREATE EXTENSION IF NOT EXISTS ivorysql_ora');
$node->safe_psql(
	'postgres',
	q{CREATE DATABASE asciistr_latin1 WITH TEMPLATE template0
	   ENCODING 'LATIN1' LC_COLLATE 'C' LC_CTYPE 'C'});
$node->safe_psql('asciistr_latin1',
	'CREATE EXTENSION IF NOT EXISTS ivorysql_ora');

my $latin1_result = $node->safe_psql(
	'asciistr_latin1',
	q{
		SELECT sys.asciistr(convert_from(decode('e9', 'hex'), 'LATIN1'))
		       || '|' ||
		       sys.asciistr(convert_from(decode('a3', 'hex'), 'LATIN1'))
		       || '|' ||
		       sys.asciistr(convert_from(decode('c3a9', 'hex'), 'LATIN1'))
		       || '|' ||
		       sys.asciistr(convert_from(decode('e94142', 'hex'), 'LATIN1'))
	});

is($latin1_result, '\\00E9|\\00A3|\\00C3\\00A9|\\00E9AB',
	'ASCIISTR converts LATIN1 characters by character, not as UTF-8 bytes');

my $utf8_result = $node->safe_psql(
	'postgres',
	q{
		SELECT sys.asciistr(
		           convert_from(decode('c384', 'hex'), 'UTF8'))
		       || '|' ||
		       sys.asciistr(
		           convert_from(decode('f09f988a', 'hex'), 'UTF8'))
	});

is($utf8_result, '\\00C4|\\D83D\\DE0A',
	'ASCIISTR preserves BMP and surrogate-pair behavior in UTF8');

is($node->safe_psql('postgres', q{SELECT sys.asciistr(E'\\\\')}),
	'\\005C', 'ASCIISTR preserves the existing backslash escape behavior');

done_testing();
