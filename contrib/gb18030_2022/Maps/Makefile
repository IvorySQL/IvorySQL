subdir = contrib/gb18030_2022/Maps
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global


MAPS = 	gb18030_2022_to_utf8.map utf8_to_gb18030_2022.map 

all: $(MAPS)

GEN_MAPS = $(PERL) -I $(srcdir) $(srcdir)/UCS_to_GB18030.pl $(srcdir)/gb-18030-2022.xml

# The generator writes both maps.  Serialize their generation as in
# src/backend/utils/mb/Unicode/Makefile so parallel make invokes it only once.
gb18030_2022_to_utf8.map: UCS_to_GB18030.pl gb-18030-2022.xml convutils.pm
	$(GEN_MAPS)

utf8_to_gb18030_2022.map: gb18030_2022_to_utf8.map
	@test -f $@ || $(GEN_MAPS)
	@touch $@


