#! /usr/bin/perl
#
# ------------------------------------------------ 
# 
# File: UCS_to_GB18030.pl
#
# Abstract: 
# 		This file generate UTF-8 <--> GB18030_2022 code conversion tables from
# 	"gb-18030-2022.xml", obtained from
# 	http://source.icu-project.org/repos/icu/data/trunk/charset/data/xml/
#
#
#  Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
#
# Identification:
#		contrib/gb18030_2022/Maps/UCS_to_GB18030.pl
#
#-------------------------------------------------
#
use strict;
use warnings;

use convutils;

my $this_script = 'src/backend/utils/mb/Unicode/UCS_to_GB18030.pl';

# Read the input

my $in_file = "gb-18030-2022.xml";

open(my $in, '<', $in_file) || die("cannot open $in_file");

my @mapping;

while (<$in>)
{
	next if (!m/<a u="([0-9A-F]+)" b="([0-9A-F ]+)"/);
	my ($u, $c) = ($1, $2);
	$c =~ s/ //g;
	my $ucs  = hex($u);
	my $code = hex($c);
	if ($code >= 0x80 && $ucs >= 0x0080)
	{
		push @mapping,
		  {
			ucs       => $ucs,
			code      => $code,
			direction => BOTH,
			f         => $in_file,
			l         => $.
		  };
	}
}
close($in);

print_conversion_tables($this_script, "GB18030_2022", \@mapping);
