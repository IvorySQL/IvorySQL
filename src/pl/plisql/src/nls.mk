# src/pl/plisql/src/nls.mk
CATALOG_NAME     = plisql
GETTEXT_FILES    = pl_comp.c \
                   pl_exec.c \
                   pl_gram.c \
                   pl_funcs.c \
                   pl_handler.c \
                   pl_scanner.c
GETTEXT_TRIGGERS = $(BACKEND_COMMON_GETTEXT_TRIGGERS) yyerror plisql_yyerror
GETTEXT_FLAGS    = $(BACKEND_COMMON_GETTEXT_FLAGS)
