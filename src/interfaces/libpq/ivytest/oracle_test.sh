#!/bin/sh

# src/interfaces/libpq/ivytest/oracle_test.sh
#
# Test driver for ivylib.  Initializes a new database,
# run testlibpq

set -e

: ${MAKE=make}

# Guard against parallel make issues (see comments in pg_regress.c)
unset MAKEFLAGS
unset MAKELEVEL

# Run a given "initdb" binary and overlay the regression testing
# authentication configuration.
standard_initdb() {
	initdb -D $PGDATA -USYSTEM -moracle
	if [ -n "$TEMP_CONFIG" -a -r "$TEMP_CONFIG" ]
	then
		cat "$TEMP_CONFIG" >> "$PGDATA/postgresql.conf"
	fi
}

# Establish how the server will listen for connections
testhost=`uname -s`

case $testhost in
	MINGW*)
		LISTEN_ADDRESSES="localhost"
		PGHOST=localhost
		;;
	*)
		LISTEN_ADDRESSES=""
		# Select a socket directory.  The algorithm is from the "configure"
		# script; the outcome mimics pg_regress.c:make_temp_sockdir().
		PGHOST=$PG_REGRESS_SOCK_DIR
		if [ "x$PGHOST" = x ]; then
			{
				dir=`(umask 077 &&
					  mktemp -d /tmp/ivytest_check-XXXXXX) 2>/dev/null` &&
				[ -d "$dir" ]
			} ||
			{
				dir=/tmp/ivytest_check-$$-$RANDOM
				(umask 077 && mkdir "$dir")
			} ||
			{
				echo "could not create socket temporary directory in \"/tmp\""
				exit 1
			}

			PGHOST=$dir
			trap 'rm -rf "$PGHOST"' 0
			trap 'exit 3' 1 2 13 15
		fi
		;;
esac

POSTMASTER_OPTS="-F -c listen_addresses=$LISTEN_ADDRESSES -k \"$PGHOST\""
export PGHOST

# don't rely on $PWD here, as old shells don't set it
temp_root=`pwd`/tmp_check
echo $temp_root

if [ "$1" = '--install' ]; then
	temp_install=$temp_root/install
	bindir=$temp_install/$bindir
	libdir=$temp_install/$libdir

	"$MAKE" -s -C ../../../../ install DESTDIR="$temp_install"
	# platform-specific magic to find the shared libraries; see pg_regress.c
	LD_LIBRARY_PATH=$libdir:$LD_LIBRARY_PATH
	export LD_LIBRARY_PATH
	DYLD_LIBRARY_PATH=$libdir:$DYLD_LIBRARY_PATH
	export DYLD_LIBRARY_PATH
	LIBPATH=$libdir:$LIBPATH
	export LIBPATH
	PATH=$libdir:$PATH

	# We need to make it use psql from our temporary installation,
	# because otherwise the installcheck run below would try to
	# use psql from the proper installation directory, which might
	# be outdated or missing. But don't override anything else that's
	# already in EXTRA_REGRESS_OPTS.
	EXTRA_REGRESS_OPTS="$EXTRA_REGRESS_OPTS --bindir='$bindir'"
	export EXTRA_REGRESS_OPTS
fi

PATH=$bindir:$PATH
export PATH

BASE_PGDATA=$temp_root/oracle_data
rm -rf "$BASE_PGDATA"

logdir=`pwd`/log
rm -rf "$logdir"
mkdir "$logdir"

# Clear out any environment vars that might cause libpq to connect to
# the wrong postmaster (cf pg_regress.c)
#
# Some shells, such as NetBSD's, return non-zero from unset if the variable
# is already unset. Since we are operating under 'set -e', this causes the
# script to fail. To guard against this, set them all to an empty string first.
PGDATABASE="";        unset PGDATABASE
PGUSER="";            unset PGUSER
PGSERVICE="";         unset PGSERVICE
PGSSLMODE="";         unset PGSSLMODE
PGREQUIRESSL="";      unset PGREQUIRESSL
PGCONNECT_TIMEOUT=""; unset PGCONNECT_TIMEOUT
PGHOSTADDR="";        unset PGHOSTADDR

newsrc=../../../..
# Select a non-conflicting port number, similarly to pg_regress.c
PG_VERSION_NUM=`grep '#define PG_VERSION_NUM' "$newsrc"/src/include/pg_config.h | awk '{print $3}'`
PGPORT=`expr $PG_VERSION_NUM % 16384 + 49152`
export PGPORT

i=0
while psql -X postgres </dev/null 2>/dev/null
do
	i=`expr $i + 1`
	if [ $i -eq 16 ]
	then
		echo port $PGPORT apparently in use
		exit 1
	fi
	PGPORT=`expr $PGPORT + 1`
	export PGPORT
done

# buildfarm may try to override port via EXTRA_REGRESS_OPTS ...
EXTRA_REGRESS_OPTS="$EXTRA_REGRESS_OPTS --port=$PGPORT"
export EXTRA_REGRESS_OPTS

# enable echo so the user can see what is being executed
set -x

PGDATA=$BASE_PGDATA
export PGDATA

standard_initdb
pg_ctl start -l "$logdir/postmaster1.log" -o "$POSTMASTER_OPTS" -w

#test regression
if [ ! -d results ] ; then
	mkdir results
fi
cat regression.txt|while read line
do
 ./$line >results/$line.out
done
pg_ctl -m fast stop

#get result
cat regression.txt|while read line
do
if diff expected/$line.out results/$line.out >$line.diffs; then
	echo "$line passed"
else
	echo "$line failed see details about $line.diffs"
	exit 1
fi
done
exit 0
