/*-------------------------------------------------------------------------
 *
 * pg_cpu_x86.c
 *	  Runtime CPU feature detection for x86
 *
 * Portions Copyright (c) 1996-2026, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	  src/port/pg_cpu_x86.c
 *
 *-------------------------------------------------------------------------
 */

#include "c.h"

#if defined(USE_SSE2) || defined(__i386__)

#if defined(HAVE__GET_CPUID) || defined(HAVE__GET_CPUID_COUNT)
#include <cpuid.h>
#endif

#if defined(HAVE__CPUID) || defined(HAVE__CPUIDEX)
#include <intrin.h>
#endif

#ifdef HAVE_XSAVE_INTRINSICS
#include <immintrin.h>
#endif

#include "port/pg_cpu.h"

/*
 * XSAVE state component bits that we need
 *
 * https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-1-manual.pdf
 * Chapter "MANAGING STATE USING THE XSAVE FEATURE SET"
 */
#define XMM			(1<<1)
#define YMM			(1<<2)
#define OPMASK		(1<<5)
#define ZMM0_15		(1<<6)
#define ZMM16_31	(1<<7)


/* array indexed by enum X86FeatureId */
bool		X86Features[X86FeaturesSize] = {0};

static bool
mask_available(uint32 value, uint32 mask)
{
	return (value & mask) == mask;
}

/*
 * Parse the CPU ID info for runtime checks.
 */
#ifdef HAVE_XSAVE_INTRINSICS
pg_attribute_target("xsave")
#endif
void
set_x86_features(void)
{
	unsigned int exx[4] = {0, 0, 0, 0};

#if defined(HAVE__GET_CPUID)
	__get_cpuid(1, &exx[0], &exx[1], &exx[2], &exx[3]);
#elif defined(HAVE__CPUID)
	__cpuid(exx, 1);
#else
#error cpuid instruction not available
#endif

	X86Features[PG_SSE4_2] = exx[2] >> 20 & 1;
	X86Features[PG_POPCNT] = exx[2] >> 23 & 1;

	/* All these features depend on OSXSAVE */
	if (exx[2] & (1 << 27))
	{
		uint32		xcr0_val = 0;

		/* second cpuid call on leaf 7 to check extended AVX-512 support */

		memset(exx, 0, 4 * sizeof(exx[0]));

#if defined(HAVE__GET_CPUID_COUNT)
		__get_cpuid_count(7, 0, &exx[0], &exx[1], &exx[2], &exx[3]);
#elif defined(HAVE__CPUIDEX)
		__cpuidex(exx, 7, 0);
#endif

#ifdef HAVE_XSAVE_INTRINSICS
		/* get value of Extended Control Register */
		xcr0_val = _xgetbv(0);
#endif

		/* Are ZMM registers enabled? */
		if (mask_available(xcr0_val, XMM | YMM |
						   OPMASK | ZMM0_15 | ZMM16_31))
		{
			X86Features[PG_AVX512_BW] = exx[1] >> 30 & 1;
			X86Features[PG_AVX512_VL] = exx[1] >> 31 & 1;

			X86Features[PG_AVX512_VPCLMULQDQ] = exx[2] >> 10 & 1;
			X86Features[PG_AVX512_VPOPCNTDQ] = exx[2] >> 14 & 1;
		}
	}

	X86Features[INIT_PG_X86] = true;
}

#endif							/* defined(USE_SSE2) || defined(__i386__) */
