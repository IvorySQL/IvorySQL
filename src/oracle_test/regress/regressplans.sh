#! /bin/sh

# This script runs the Postgres regression tests with all useful combinations
# of the backend options that disable various query plan types.  If the
# results are not all the same, it may indicate a bug in a particular
# plan type, or perhaps just a regression test whose results aren't fully
# determinate (eg, due to lack of an ORDER BY keyword).
#
# Run this in the src/test/regress directory, after doing the usual setup
# for a regular regression test, ie, "make clean all" (you should be ready
# to do "make runtest").
#
# The backend option switches that we use here are:
#	-fs	disable sequential scans
#	-fi	disable index scans
#	-fn	disable nestloop joins
#	-fm	disable merge joins
#	-fh	disable hash joins
# Only mergejoin and hashjoin are really guaranteed to turn off; the others
# just bias the optimizer's cost calculations heavily against that choice.
# There's no point in trying to turn off both scan types or all three join
# types simultaneously; ergo, we have 3*7 = 21 interesting combinations.
#
# Note that this will take *more than* 21 times longer than a regular
# regression test, since we are preventing the system from using the most
# efficient available query plans!  Have patience.


# Select make to use --- default 'make', can be overridden by env var
MAKE="${MAKE:-make}"

# If PGOPTIONS is already defined, we'll add the -f switches to it.
PGOPTIONS="${PGOPTIONS:-}"

EXITCODE=0

mkdir -p planregress || exit 1

PGOPTIONS="$PGOPTIONS                     " $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.normal || EXITCODE=1
mv -f regression.diffs planregress/diffs.normal || EXITCODE=1
PGOPTIONS="$PGOPTIONS                  -fh" $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.h || EXITCODE=1
mv -f regression.diffs planregress/diffs.h || EXITCODE=1
PGOPTIONS="$PGOPTIONS              -fm    " $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.m || EXITCODE=1
mv -f regression.diffs planregress/diffs.m || EXITCODE=1
PGOPTIONS="$PGOPTIONS              -fm -fh" $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.mh || EXITCODE=1
mv -f regression.diffs planregress/diffs.mh || EXITCODE=1
PGOPTIONS="$PGOPTIONS          -fn        " $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.n || EXITCODE=1
mv -f regression.diffs planregress/diffs.n || EXITCODE=1
PGOPTIONS="$PGOPTIONS          -fn     -fh" $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.nh || EXITCODE=1
mv -f regression.diffs planregress/diffs.nh || EXITCODE=1
PGOPTIONS="$PGOPTIONS          -fn -fm    " $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.nm || EXITCODE=1
mv -f regression.diffs planregress/diffs.nm || EXITCODE=1
PGOPTIONS="$PGOPTIONS      -fi            " $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.i || EXITCODE=1
mv -f regression.diffs planregress/diffs.i || EXITCODE=1
PGOPTIONS="$PGOPTIONS      -fi         -fh" $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.ih || EXITCODE=1
mv -f regression.diffs planregress/diffs.ih || EXITCODE=1
PGOPTIONS="$PGOPTIONS      -fi     -fm    " $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.im || EXITCODE=1
mv -f regression.diffs planregress/diffs.im || EXITCODE=1
PGOPTIONS="$PGOPTIONS      -fi     -fm -fh" $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.imh || EXITCODE=1
mv -f regression.diffs planregress/diffs.imh || EXITCODE=1
PGOPTIONS="$PGOPTIONS      -fi -fn        " $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.in || EXITCODE=1
mv -f regression.diffs planregress/diffs.in || EXITCODE=1
PGOPTIONS="$PGOPTIONS      -fi -fn     -fh" $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.inh || EXITCODE=1
mv -f regression.diffs planregress/diffs.inh || EXITCODE=1
PGOPTIONS="$PGOPTIONS      -fi -fn -fm    " $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.inm || EXITCODE=1
mv -f regression.diffs planregress/diffs.inm || EXITCODE=1
PGOPTIONS="$PGOPTIONS  -fs                " $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.s || EXITCODE=1
mv -f regression.diffs planregress/diffs.s || EXITCODE=1
PGOPTIONS="$PGOPTIONS  -fs             -fh" $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.sh || EXITCODE=1
mv -f regression.diffs planregress/diffs.sh || EXITCODE=1
PGOPTIONS="$PGOPTIONS  -fs         -fm    " $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.sm || EXITCODE=1
mv -f regression.diffs planregress/diffs.sm || EXITCODE=1
PGOPTIONS="$PGOPTIONS  -fs         -fm -fh" $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.smh || EXITCODE=1
mv -f regression.diffs planregress/diffs.smh || EXITCODE=1
PGOPTIONS="$PGOPTIONS  -fs     -fn        " $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.sn || EXITCODE=1
mv -f regression.diffs planregress/diffs.sn || EXITCODE=1
PGOPTIONS="$PGOPTIONS  -fs     -fn     -fh" $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.snh || EXITCODE=1
mv -f regression.diffs planregress/diffs.snh || EXITCODE=1
PGOPTIONS="$PGOPTIONS  -fs     -fn -fm    " $MAKE runtest || EXITCODE=1
mv -f regression.out planregress/out.snm || EXITCODE=1
mv -f regression.diffs planregress/diffs.snm || EXITCODE=1

exit $EXITCODE
