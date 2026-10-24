#!/usr/bin/perl
#----------------------------------------------------------------------
# Copyright 2025 IvorySQL Global Development Team
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# File: gensql.pl
#
# Abstract:
#    Perl script that generates ivorysql_ora--x.x.sql
#    specified by DATA in Makefile usings SQL files specified
#    in ivorysql_ora_merge_sqls.
#
# Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
#
# Identification:
#     contrib/ivorysql_ora/gensql.pl
#
#----------------------------------------------------------------------


use strict;
use warnings FATAL => 'all';
use Carp;

use File::Spec;
use FindBin;

my @sql_set;

my $first_arg = $ARGV[0];

sql_merge();

sub version_key
{
	my ($version) = @_;

	return join('', map { sprintf("%09d", $_) } split(/\./, $version));
}

sub find_base_version
{
	my ($set, $target) = @_;
	my @versions;

	foreach my $file (glob("$set--*.sql"))
	{
		my ($version) = $file =~ /^\Q$set\E--([0-9]+\.[0-9]+)\.sql$/;
		push @versions, $version
			if defined($version) &&
				version_key($version) le version_key($target);
	}

	return (sort { version_key($b) cmp version_key($a) } @versions)[0];
}

# The subroutine which does sql merge.
#
# usage example : 
#     <src/datatype/datatype> is specified in ivorysql_ora_merge_sqls
#     <ivorysql_ora--1.0.sql> is specified in Makefile
#     <ivorysql_ora--1.0.sql> will be generated
#     using <src/datatype/datatype--1.0.sql>
#
# NOTE : THE VERSION IS SPECIFIED IN MAKEFILE (DATA).
sub sql_merge
{
	# Read information from ivorysql_ora_merge_sqls.
	#     There are SQLs specified which need to be merged.
	if ($first_arg eq 'meson') {
		open(INFO, "<", File::Spec->rel2abs("../contrib/ivorysql_ora/ivorysql_ora_merge_sqls"))
		|| croak "Could not open file ivorysql_ora_merge_sqls: $!";
	}
	else {
		open(INFO, "<", File::Spec->catfile($FindBin::Bin, "ivorysql_ora_merge_sqls"))
                || croak "Could not open file ivorysql_ora_merge_sqls: $!";
	}

	while (<INFO>)
	{
		# Delete the last tailing "\n" of this line.
		chomp($_);
		if ($first_arg eq 'meson') {
			push @sql_set, "../contrib/ivorysql_ora/$_";
		}
		else
		{
			push @sql_set, File::Spec->catfile($FindBin::Bin, $_);
		}
	}
	close INFO;

	shift @ARGV;
	foreach my $v (@ARGV)
	{
		# For Make mode, delete the old file first.
		if ($first_arg ne 'meson') {
			unlink(File::Spec->rel2abs("ivorysql_ora--$v.sql"))
				if (-e File::Spec->rel2abs("ivorysql_ora--$v.sql"));

			# Open output file for Make mode (meson mode uses STDOUT captured by meson)
			open(OUTFILE, ">ivorysql_ora--$v.sql")
				|| croak "Could not open ivorysql_ora--$v.sql : $!";
		}

		# Write "extension file loading information".
		# Create extension when this version is "x.x".
		if ($v =~ /^\d+\.\d+$/)
		{
			my $fh = ($first_arg eq 'meson') ? *STDOUT : *OUTFILE;
			print $fh '\echo Use "CREATE EXTENSION ivorysql_ora"';
			print $fh " to load this file. \\quit\n";
		}
		# Update extension when this version is "x.x--x.x".
		elsif ($v =~ /^\d+\.\d+\-\-\d+\.\d+$/)
		{
			my $up2ver = (split("--", $v))[1];
			my $fh = ($first_arg eq 'meson') ? *STDOUT : *OUTFILE;
			print $fh '\echo Use "ALTER EXTENSION ivorysql_ora UPDATE';
			print $fh " TO \'$up2ver\'\" to load this file. \\quit\n";
		}
		else
		{
			croak "Invalid argument.\n";
		}

		# Write the contents of SQL files specified by
		# ivorysql_ora_merge_sqls.  A clean-install script without an exact
		# source file is built from the latest base script plus its upgrade
		# script, allowing later versions to reuse unchanged component SQL.
		foreach my $set (@sql_set)
		{
			my @sources;

			if (-e "$set--$v.sql")
			{
				push @sources, "$set--$v.sql";
			}
			elsif ($v =~ /^(\d+\.\d+)$/)
			{
				my $base = find_base_version($set, $v);

				croak "No base SQL can be used to generate $set--$v.sql\n"
					if !defined($base);
				push @sources, "$set--$base.sql";
				push @sources, "$set--$base--$v.sql"
					if -e "$set--$base--$v.sql";
			}

			foreach my $source (@sources)
			{
				# Add a newline.
				my $fh = ($first_arg eq 'meson') ? *STDOUT : *OUTFILE;
				print $fh "\n";

				# Open a sql file.
				open(INFILE, "<", File::Spec->rel2abs($source))
					|| croak "Could not open file $source : $!";
				while (my $line = <INFILE>)
				{
					# Delete the last tailing "\n" of this line.
					chomp($line);
					# Write.
					print $fh "$line\n";
				}
				close INFILE;
			}
		}

		# Close OUTFILE for Make mode (meson mode doesn't open it)
		close OUTFILE if ($first_arg ne 'meson');
	}
}
