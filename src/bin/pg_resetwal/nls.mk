# src/bin/pg_resetwal/nls.mk
CATALOG_NAME     = pg_resetwal
GETTEXT_FILES    = $(FRONTEND_COMMON_GETTEXT_FILES) \
                   pg_resetwal.c \
                   ../../common/restricted_token.c
GETTEXT_TRIGGERS = $(FRONTEND_COMMON_GETTEXT_TRIGGERS)
GETTEXT_FLAGS    = $(FRONTEND_COMMON_GETTEXT_FLAGS)
