subdir = contrib/gb18030_2022/Maps
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global


MAPS = 	gb18030_2022_to_utf8.map utf8_to_gb18030_2022.map 

all: $(MAPS)

gb18030_2022_to_utf8.map utf8_to_gb18030_2022.map: UCS_to_GB18030.pl gb-18030-2022.xml
	$(PERL) -I $(subdir) $<



