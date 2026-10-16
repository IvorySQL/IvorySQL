# src/oracle_test/locale/Makefile
# add the file for requirement "SQL PARSER"

subdir = src/oracle_test/locale
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global


PROGS = test-ctype
DIRS = de_DE.ISO8859-1 gr_GR.ISO8859-7 koi8-r koi8-to-win1251

all: $(PROGS)

clean distclean maintainer-clean:
	rm -f $(PROGS) *.o
	rm -rf tmp_check
	for d in $(DIRS); do \
		$(MAKE) -C $$d clean || exit; \
	done

# These behave like installcheck targets.
oracle-check-%: all
	@$(MAKE) -C `echo $@ | sed 's/^check-//'` test
