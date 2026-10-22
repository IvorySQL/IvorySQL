# Copyright (c) 2026, IvorySQL Global Development Team

use strict;
use warnings FATAL => 'all';

use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $generator = "$FindBin::RealBin/../ora_gen_keywordlist.pl";
my $tempdir = tempdir(CLEANUP => 1);
my $input = "$tempdir/keywords.h";
my $output = "$tempdir/keywords_d.h";

sub write_keywords
{
	open(my $fh, '>', $input) or die "$input: $!";
	print $fh map { qq{PG_KEYWORD("$_", TOKEN)\n} } @_;
	close($fh) or die "$input: $!";
	return;
}

sub read_output
{
	open(my $fh, '<', $output) or die "$output: $!";
	local $/;
	return <$fh>;
}

sub generate
{
	return system($^X, $generator, '--output', $tempdir, $input);
}

write_keywords('alpha', 'beta');
is(generate(), 0, 'valid keyword list generates a header');
my $valid_header = read_output();
like($valid_header, qr/#define ORASCANKEYWORDS_NUM_KEYWORDS 2/,
	'generated header contains both keywords');

for my $case (
	['uppercase', 'Alpha', 'beta'],
	['out of order', 'beta', 'alpha'],
	['duplicate', 'alpha', 'alpha'])
{
	my ($name, @keywords) = @$case;
	open(my $fh, '>', $output) or die "$output: $!";
	print $fh $valid_header;
	close($fh) or die "$output: $!";
	write_keywords(@keywords);
	isnt(generate(), 0, "$name keywords are rejected");
	is(read_output(), $valid_header,
		"$name keywords leave the existing header intact");
}

unlink($output) or die "$output: $!";
isnt(generate(), 0, 'invalid input without an existing header is rejected');
ok(!-e $output, 'invalid input does not create a partial header');

done_testing();
