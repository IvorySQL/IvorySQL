# -*-perl-*- hey - emacs - this is a perl file

# Copyright (c) 2022, PostgreSQL Global Development Group

#
# Script that provides batch regression testing.
#
# src/tools/msvc/bat_regress.pl
#
use strict;
use warnings;

our $config;
import sys;
use Cwd;
use File::Path qw(rmtree);

if(@ARGV != 1){
	die "please enter the installation  directory!\n";
}
my $startdir = getcwd();
print "$startdir\n";
print "$ARGV[0]\n";

my $installdir = $ARGV[0];
print "install dir is : $installdir\n";

my @vcregress_pg = ("check","recoverycheck","bincheck","upgradecheck");
foreach $a (@vcregress_pg){
	system("vcregress_pg.bat $a");
	my $status = $? >> 8;
	exit $status if $status;
	print "=======end vcregress_pg.bat $a regression================\n";
}

chdir($installdir) or die "can not change install dir!";
rmtree("data");
chdir("bin") or die "can not change bin dir!";
system("initdb.exe -D ../data -m pg");
my $status1 = $? >> 8;
exit $status1 if $status1;
system("pg_ctl.exe -D ../data start");
my $status2 = $? >> 8;
exit $status2 if $status2;
chdir "$startdir";
$ENV{PGPORT} = 5432;

my @vcregress_pg_install = ("installcheck","plcheck","contribcheck","modulescheck","ecpgcheck","isolationcheck");
foreach $a (@vcregress_pg_install){
	system("vcregress_pg.bat $a");
	my $status3 = $? >> 8;
#	exit $status3 if $status3;
	print "=======end vcregress_pg.bat $a regression================\n";
}
chdir($installdir) or die "can not change install dir!";
chdir("bin") or die "can not change to bin dir!";
system("pg_ctl.exe -D ../data stop");
my $status4 = $? >> 8;
exit $status4 if $status4;
chdir($installdir) or die "can not change install dir!";
rmtree("data");
chdir "$startdir";
delete $ENV{PGPORT};


my @vcregress_ora_pg = ("check","recoverycheck","bincheck","upgradecheck");
foreach $a (@vcregress_ora_pg){
	system("vcregress_ora_pg.bat $a");
	my $status5 = $? >> 8;
	exit $status5 if $status5;
	print "=======end vcregress_ora_pg.bat $a regression================\n";
}

chdir($installdir) or die "can not change install dir!";
chdir("bin") or die "can not change bin dir!";
system("initdb.exe -D ../data -m oracle");
my $status6 = $? >> 8;
exit $status6 if $status6;
system("pg_ctl.exe -D ../data start");
my $status7 = $? >> 8;
exit $status7 if $status7;
chdir "$startdir";

$ENV{PGPORT} = 5432;

my @vcregress_ora_pg_install = ("installcheck","plcheck","contribcheck","modulescheck","ecpgcheck","isolationcheck");
foreach $a (@vcregress_ora_pg_install){
	system("vcregress_ora_pg.bat $a");
	my $status8 = $? >> 8;
#	exit $status8 if $status8;
	print "=======end vcregress_ora_pg.bat $a regression================\n";
}
chdir($installdir) or die "can not change install dir!";
chdir("bin") or die "can not change bin dir!";
system("pg_ctl.exe -D ../data stop");
my $status9 = $? >> 8;
exit $status9 if $status9;
chdir($installdir) or die "can not change install dir!";
rmtree("data");
chdir "$startdir";
delete $ENV{PGPORT};

my @vcregress_ora = ("check","recoverycheck","bincheck","upgradecheck");
foreach $a (@vcregress_ora){
	system("vcregress_ora.bat $a");
	my $status10 = $? >> 8;
	exit $status10 if $status10;
	print "=======end vcregress_ora.bat $a regression================\n";
}

chdir($installdir) or die "can not change install dir!";
chdir("bin") or die "can not change bin dir!";
system("initdb.exe -D ../data -c normal");
my $status11 = $? >> 8;
exit $status11 if $status11;
system("pg_ctl.exe -D ../data start");
my $status12 = $? >> 8;
exit $status12 if $status12;
chdir "$startdir";

$ENV{PGPORT} = 1521;

my @vcregress_ora_install = ("installcheck","plcheck","modulescheck","ecpgcheck","isolationcheck");
foreach $a (@vcregress_ora_install){
	system("vcregress_ora.bat $a");
	my $status13 = $? >> 8;
	exit $status13 if $status13;
	print "=======end vcregress_ora.bat $a regression================\n";
}
chdir($installdir) or die "can not change install dir!";
chdir("bin") or die "can not change bin dir!";
system("pg_ctl.exe -D ../data stop");
my $status14 = $? >> 8;
exit $status14 if $status14;
chdir($installdir) or die "can not change install dir!";
rmtree("data");
chdir "$startdir";
print "===============================finish all regress check========================================\n";