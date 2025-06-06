#!/usr/bin/perl
#----------------------------------------------------------------------
#
# File: gensql.pl
#
# Abstract:
#    Perl script that generates ivorysql_ora--x.x.sql
#    specified by DATA in Makefile usings SQL files specified
#    in ivorysql_ora_merge_sqls.
#
# Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
#
# Identification:
#     contrib/ivorysql_ora/gensql.pl
#
#----------------------------------------------------------------------


use strict;
use warnings FATAL => 'all';
use Carp;

use File::Spec;

my @sql_set;

my $first_arg = $ARGV[0];

sql_merge();

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
		open(INFO, "<", File::Spec->rel2abs("ivorysql_ora_merge_sqls"))
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
			push @sql_set, "$_";
		}
	}
	close INFO;

	shift @ARGV;
	foreach my $v (@ARGV)
	{
		# Delete ivorysql_ora--x.x(--x.x).sql files generated before.
		unlink(File::Spec->rel2abs("ivorysql_ora--$v.sql"))
			if (-e File::Spec->rel2abs("ivorysql_ora--$v.sql"));

		# Open(create if necessary) ivorysql_ora--x.x(--x.x).sql.
		if ($first_arg eq 'meson'){
			open(OUTFILE, ">contrib/ivorysql_ora/ivorysql_ora--$v.sql")
                        || croak "Could not open ivorysql_ora--$v.sql : $!";
		}
		else {
			open(OUTFILE, ">ivorysql_ora--$v.sql")
			|| croak "Could not open ivorysql_ora--$v.sql : $!";
		}

		# Write "extension file loading information" into it.
		# Create extension when this version is "x.x".
		if ($v =~ /^\d+\.\d+$/)
		{
			if ($first_arg eq 'meson'){
				print STDOUT '\echo Use "CREATE EXTENSION ivorysql_ora"';
				print STDOUT " to load this file. \\quit\n";
			}
			else
			{
				print OUTFILE '\echo Use "CREATE EXTENSION ivorysql_ora"';
				print OUTFILE " to load this file. \\quit\n";
			}
		}
		# Update extension when this version is "x.x--x.x".
		elsif ($v =~ /^\d+\.\d+\-\-\d+\.\d+$/)
		{
			my $up2ver = (split("--", $v))[1];
			if ($first_arg eq 'meson'){
				print STDOUT '\echo Use "ALTER EXTENSION ivorysql_ora UPDATE';
				print STDOUT " TO \'$up2ver\'\" to load this file. \\quit\n";
                        }
                        else{
				print OUTFILE '\echo Use "ALTER EXTENSION ivorysql_ora UPDATE';
				print OUTFILE " TO \'$up2ver\'\" to load this file. \\quit\n";
                        }
		}
		else
		{
			croak "Invalid argument.\n";
		}

		# Write the contents of sql files
		#     (src/subdirectory/filename--<version>.sql)
		#     specified in ivorysql_ora_merge_sqls,
		#     into ivorysql_ora--<version>.sql.
		foreach my $set (@sql_set)
		{
			if (-e "$set--$v.sql")
			{
				# Add a newline.
				print OUTFILE "\n";
				# Open a sql file.
				open(INFILE, "<", File::Spec->rel2abs("$set--$v.sql"));
				while (my $line = <INFILE>)
				{
					# Delete the last tailing "\n" of this line.
					chomp($line);
					# Write.
					if ($first_arg eq 'meson'){
						print STDOUT "$line\n";
					}
					else{
						print OUTFILE "$line\n";
					}
				}
				close INFILE;
			}
		}

		close OUTFILE;
	}
}
