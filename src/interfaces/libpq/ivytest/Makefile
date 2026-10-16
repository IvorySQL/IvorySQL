# src/interface/libpq/ivytest/Makefile

PGFILEDESC = "ivytest - an in-place binary upgrade utility"
PGAPPICON = win32

subdir = src/interfaces/libpq/ivytest
top_builddir = ../../../..
include $(top_builddir)/src/Makefile.global

ifeq ($(PORTNAME), win32)
LDFLAGS += -lws2_32
endif

override CPPFLAGS := -I$(libpq_srcdir) $(CPPFLAGS)
LDFLAGS_INTERNAL += $(libpq_pgport)

PROGS = testlibpq testlibpqstmt2 testlibpq_nullstmt testlibpq_allout testlibpq_prepare_plsql testlibpq_prepare_dml \
        testlibpq_binary_double testlibpq_binary_float testlibpq_interval testlibpq_number testlibpq_prepare_call \
		testlibpq_call testlibpqstmt2_call

all: $(PROGS)

clean distclean maintainer-clean:
	rm -f *.o
	rm -f $(PROGS)
	rm -f *.diffs
	rm -rf results
	rm -rf tmp_check
	rm -rf log
oracle-check: oracle-subcheck
oracle-subcheck: oracle_test.sh all
	MAKE=$(MAKE) bindir=$(bindir) libdir=$(libdir) EXTRA_REGRESS_OPTS="$(EXTRA_REGRESS_OPTS)" $(SHELL) $< --install

