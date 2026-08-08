/*-------------------------------------------------------------------------
 *
 * passwordcheck.c
 *
 *
 * Copyright (c) 2009-2026, PostgreSQL Global Development Group
 *
 * Author: Laurenz Albe <laurenz.albe@wien.gv.at>
 *
 * IDENTIFICATION
 *	  contrib/passwordcheck/passwordcheck.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include <ctype.h>
#include <limits.h>

#ifdef USE_CRACKLIB
#include <crack.h>
#endif

#include "commands/user.h"
#include "fmgr.h"
#include "libpq/crypt.h"

PG_MODULE_MAGIC_EXT(
					.name = "passwordcheck",
					.version = PG_VERSION
);

/* Saved hook value */
static check_password_hook_type prev_check_password_hook = NULL;

/* GUC variables */
static int	min_password_length = 8;
static bool require_uppercase = true;
static bool require_lowercase = true;
static bool require_digit = true;
static bool require_special = true;

/*
 * check_password
 *
 * performs checks on an encrypted or unencrypted password
 * ereport's if not acceptable
 *
 * username: name of role being created or changed
 * password: new password (possibly already encrypted)
 * password_type: PASSWORD_TYPE_* code, to indicate if the password is
 *			in plaintext or encrypted form.
 * validuntil_time: password expiration time, as a timestamptz Datum
 * validuntil_null: true if password expiration time is NULL
 *
 * This sample implementation doesn't pay any attention to the password
 * expiration time, but you might wish to insist that it be non-null and
 * not too far in the future.
 */
static void
check_password(const char *username,
			   const char *shadow_pass,
			   PasswordType password_type,
			   Datum validuntil_time,
			   bool validuntil_null)
{
	if (prev_check_password_hook)
		prev_check_password_hook(username, shadow_pass,
								 password_type, validuntil_time,
								 validuntil_null);

	if (password_type != PASSWORD_TYPE_PLAINTEXT)
	{
		/*
		 * Unfortunately we cannot perform exhaustive checks on encrypted
		 * passwords - we are restricted to guessing. (Alternatively, we could
		 * insist on the password being presented non-encrypted, but that has
		 * its own security disadvantages.)
		 *
		 * We only check for username = password.
		 */
		const char *logdetail = NULL;

		if (plain_crypt_verify(username, shadow_pass, username, &logdetail) == STATUS_OK)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("password must not equal user name")));
	}
	else
	{
		/*
		 * For unencrypted passwords we can perform better checks
		 */
		const char *password = shadow_pass;
		int			pwdlen = strlen(password);
		int			i;
		bool		pwd_has_letter,
					pwd_has_nonletter,
					pwd_has_uppercase,
					pwd_has_lowercase,
					pwd_has_digit,
					pwd_has_special;
#ifdef USE_CRACKLIB
		const char *reason;
#endif

		/* enforce minimum length */
		if (pwdlen < min_password_length)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("password is too short"),
					 errdetail("password must be at least \"passwordcheck.min_password_length\" (%d) bytes long",
							   min_password_length)));

		/* check if the password contains the username */
		if (strstr(password, username))
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("password must not contain user name")));

		/* check if the password contains both letters and non-letters */
		pwd_has_letter = false;
		pwd_has_nonletter = false;
		pwd_has_uppercase = false;
		pwd_has_lowercase = false;
		pwd_has_digit = false;
		pwd_has_special = false;
		for (i = 0; i < pwdlen; i++)
		{
			unsigned char ch = (unsigned char) password[i];

			/*
			 * isalpha() does not work for multibyte encodings but let's
			 * consider non-ASCII characters non-letters
			 */
			if (isalpha(ch))
				pwd_has_letter = true;
			else
				pwd_has_nonletter = true;

			if (isupper(ch))
				pwd_has_uppercase = true;
			if (islower(ch))
				pwd_has_lowercase = true;
			if (isdigit(ch))
				pwd_has_digit = true;
			if (ispunct(ch))
				pwd_has_special = true;
		}
		if (!pwd_has_letter || !pwd_has_nonletter)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("password must contain both letters and nonletters")));

		if (require_uppercase && !pwd_has_uppercase)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("password must contain an uppercase letter")));
		if (require_lowercase && !pwd_has_lowercase)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("password must contain a lowercase letter")));
		if (require_digit && !pwd_has_digit)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("password must contain a digit")));
		if (require_special && !pwd_has_special)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("password must contain a special character")));

#ifdef USE_CRACKLIB
		/* call cracklib to check password */
		if ((reason = FascistCheck(password, CRACKLIB_DICTPATH)))
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("password is easily cracked"),
					 errdetail_log("cracklib diagnostic: %s", reason)));
#endif
	}

	/* all checks passed, password is ok */
}

/*
 * Module initialization function
 */
void
_PG_init(void)
{
	/* Define custom GUC variables. */
	DefineCustomIntVariable("passwordcheck.min_password_length",
							"Minimum allowed password length.",
							NULL,
							&min_password_length,
							8,
							0, INT_MAX,
							PGC_SUSET,
							GUC_UNIT_BYTE,
							NULL, NULL, NULL);

	DefineCustomBoolVariable("passwordcheck.require_uppercase",
							 "Require at least one uppercase ASCII letter.",
							 NULL,
							 &require_uppercase,
							 true,
							 PGC_SUSET,
							 0,
							 NULL, NULL, NULL);

	DefineCustomBoolVariable("passwordcheck.require_lowercase",
							 "Require at least one lowercase ASCII letter.",
							 NULL,
							 &require_lowercase,
							 true,
							 PGC_SUSET,
							 0,
							 NULL, NULL, NULL);

	DefineCustomBoolVariable("passwordcheck.require_digit",
							 "Require at least one ASCII digit.",
							 NULL,
							 &require_digit,
							 true,
							 PGC_SUSET,
							 0,
							 NULL, NULL, NULL);

	DefineCustomBoolVariable("passwordcheck.require_special",
							 "Require at least one ASCII punctuation character.",
							 NULL,
							 &require_special,
							 true,
							 PGC_SUSET,
							 0,
							 NULL, NULL, NULL);

	MarkGUCPrefixReserved("passwordcheck");

	/* activate password checks when the module is loaded */
	prev_check_password_hook = check_password_hook;
	check_password_hook = check_password;
}
