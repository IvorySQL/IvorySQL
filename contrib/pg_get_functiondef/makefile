# makefile for the pg_get_functiondef

# Basic information of the pg_get_functiondef

EXTENSION = pg_get_functiondef
EXTVERSION = 1.0
DATA = pg_get_functiondef--1.0.sql

MODULE_big = pg_get_functiondef
OBJS = pg_get_functiondef_no_input.o pg_get_functiondef_mul.o pg_get_functiondef_extend.o

# PGXS

USE_PGXS = 1
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
