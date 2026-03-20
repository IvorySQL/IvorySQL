/*
 * psql - the PostgreSQL interactive terminal
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 * Copyright (c) 2000-2025, PostgreSQL Global Development Group
 *
 * src/bin/psql/mainloop.h
 */
#ifndef MAINLOOP_H
#define MAINLOOP_H

#include "fe_utils/psqlscan.h"

extern const PsqlScanCallbacks psqlscan_callbacks;
extern const Ora_psqlScanCallbacks Ora_psqlscan_callbacks;

extern int	MainLoop(FILE *source);

#endif							/* MAINLOOP_H */
