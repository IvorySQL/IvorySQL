/*
 * psql - the PostgreSQL interactive terminal
 *
 * Copyright (c) 2022, PostgreSQL Global Development Group
 *
 * src/bin/psql/prompt.h
 */
#ifndef ORA_PROMPT_H
#define ORA_PROMPT_H

#include "fe_utils/conditional.h"
/* enum promptStatus_t is now defined by psqlscan.h */
#include "oracle_fe_utils/ora_psqlscan.h"

char	   *ora_get_prompt(Ora_promptStatus_t status, ConditionalStack cstack);

#endif							/* PROMPT_H */
