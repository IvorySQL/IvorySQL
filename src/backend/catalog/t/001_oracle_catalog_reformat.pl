# SPDX-License-Identifier: Apache-2.0
# Verify semantic Oracle catalog markers survive the real formatter.
# Uses the unchanged project pg_language.dat/header and complete Catalog.pm.
# NOT_RUN by the worker; execute only under Main's serial resource boundary.

use strict;
use warnings FATAL => 'all';
use FindBin;

BEGIN
{
	my $source_root = $ENV{IVORY_CATALOG_SOURCE_ROOT}
	  // "$FindBin::RealBin/../../../..";
	unshift @INC, "$source_root/src/backend/catalog";
}

use Catalog;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

my $root = $ENV{IVORY_CATALOG_SOURCE_ROOT}
  // "$FindBin::RealBin/../../../..";
my $catalog_dir = File::Spec->catdir($root, 'src', 'include', 'catalog');
my $input = File::Spec->catfile($catalog_dir, 'pg_language.dat');
my $header = File::Spec->catfile($catalog_dir, 'pg_language.h');
my $formatter = File::Spec->catfile($catalog_dir, 'reformat_dat_file.pl');
my $catalog = Catalog::ParseHeader($header);
my $schema = $catalog->{columns};

sub rows_in_mode
{
	my ($path, $mode) = @_;
	my $rows = Catalog::ParseData($path, $schema, 0, $mode);
	my @canonical;
	foreach my $row (@$rows)
	{
		my %copy = %$row;
		delete $copy{line_number};
		push @canonical, \%copy;
	}
	return \@canonical;
}

sub oracle_markers
{
	my $data = shift;
	return [grep { !ref($_) && m{^/\*(?:BEGIN|END)\sOracle\sCompatibility\sMetadatas\*/} }
		@$data];
}

my $source_pg = rows_in_mode($input, 'pg');
my $source_oracle = rows_in_mode($input, 'oracle');
is_deeply([map { $_->{lanname} } @$source_pg],
	['internal', 'c', 'sql'], 'real input PG-mode control');
is_deeply([map { $_->{lanname} } @$source_oracle],
	['internal', 'c', 'sql', 'plisql'], 'real input Oracle-mode control');

open(my $source_fh, '<', $input) or die "$input: $!";
my @source_lines = <$source_fh>;
close $source_fh or die "$input: $!";
my $expected_markers = oracle_markers(\@source_lines);
is(scalar @$expected_markers, 2, 'real input contains one marker pair');

my $preserved = Catalog::ParseData($input, $schema, 1, 'oracle');
is_deeply(oracle_markers($preserved), $expected_markers,
	'preserve_comments retains existing semantic marker lines');
my $data_only = Catalog::ParseData($input, $schema, 0, 'oracle');
is(scalar(grep { !ref($_) } @$data_only), 0,
	'ordinary data-only callers still receive only rows');

foreach my $full_tuples (0, 1)
{
	my $outdir = tempdir(CLEANUP => 1);
	my @command = ($^X, $formatter, '--output', $outdir);
	push @command, '--full-tuples' if $full_tuples;
	push @command, $input;
	my $label = $full_tuples ? 'full tuples' : 'compact';
	is(system(@command), 0, "real formatter completes ($label)");
	my $output = File::Spec->catfile($outdir, 'pg_language.dat');
	open(my $output_fh, '<', $output) or die "$output: $!";
	my @output_lines = <$output_fh>;
	close $output_fh or die "$output: $!";
	is_deeply(oracle_markers(\@output_lines), $expected_markers,
		"formatter emits the original marker pair ($label)");
	is_deeply(rows_in_mode($output, 'pg'), $source_pg,
		"formatter preserves PG-mode catalog rows ($label)");
	is_deeply(rows_in_mode($output, 'oracle'), $source_oracle,
		"formatter preserves Oracle-mode catalog rows ($label)");
}

done_testing();
