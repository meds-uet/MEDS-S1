/*
 * MEDS-S1 M-07 CoreMark RISC-V port
 */

#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stddef.h>
#include <stdint.h>

/*
 * Platform configuration
 */

#ifndef HAS_FLOAT
#define HAS_FLOAT 0
#endif

#ifndef HAS_TIME_H
#define HAS_TIME_H 0
#endif

#ifndef USE_CLOCK
#define USE_CLOCK 0
#endif

#ifndef HAS_STDIO
#define HAS_STDIO 1
#endif

#ifndef HAS_PRINTF
#define HAS_PRINTF 1
#endif

/*
 * Compiler information.
 *
 * CoreMark reporting requires the compiler and flags to be visible
 * in the benchmark output.
 */

#ifndef COMPILER_VERSION
#ifdef __GNUC__
#define COMPILER_VERSION "GCC " __VERSION__
#else
#define COMPILER_VERSION "Unknown compiler"
#endif
#endif

#ifndef COMPILER_FLAGS
#define COMPILER_FLAGS FLAGS_STR
#endif

/*
 * MEDS memory model.
 *
 * This is the logical description used by CoreMark's reporting layer.
 * The actual linker placement is controlled by the MEDS linker script.
 */

#ifndef MEM_LOCATION
#define MEM_LOCATION "MEDS RAM"
#endif

/*
 * CoreMark required data types.
 */

typedef signed short       ee_s16;
typedef unsigned short     ee_u16;
typedef signed int         ee_s32;
typedef unsigned int       ee_u32;
typedef unsigned char      ee_u8;

typedef float              ee_f32;

/*
 * Pointer-sized integer.
 *
 * uintptr_t is used rather than ee_u32 so that this remains correct
 * for a 64-bit RISC-V compilation environment.
 */
typedef uintptr_t          ee_ptr_int;
typedef size_t             ee_size_t;

#ifndef NULL
#define NULL ((void *)0)
#endif

/*
 * Align address to a 32-bit boundary.
 */
#define align_mem(x) \
	(void *)(4 + (((ee_ptr_int)(x) - 1) & ~(ee_ptr_int)3))

/*
 * CoreMark timing type.
 *
 * mcycle is read as a 64-bit counter.
 */
#define CORETIMETYPE uint64_t
typedef uint64_t CORE_TICKS;

/*
 * RISC-V cycle counter frequency.
 *
 * The MEDS build should override this with the actual CPU frequency:
 *
 *   -DCLOCKS_PER_SEC=<frequency>
 *
 * The value is used only for converting cycles to seconds.
 */
#ifndef CLOCKS_PER_SEC
#define CLOCKS_PER_SEC 1000000
#endif

#define TIMER_RES_DIVIDER 1

#define EE_TICKS_PER_SEC \
	(CLOCKS_PER_SEC / TIMER_RES_DIVIDER)

/*
 * CoreMark seed method.
 */
#ifndef SEED_METHOD
#define SEED_METHOD SEED_VOLATILE
#endif

/*
 * Use the CoreMark stack/static memory mechanism.
 *
 * This can be overridden by XCFLAGS when the MEDS memory layout
 * requires another implementation.
 */
#ifndef MEM_METHOD
#define MEM_METHOD MEM_STACK
#endif

/*
 * Single-context execution.
 *
 * M-07 first establishes a deterministic single-core result.
 */
#ifndef MULTITHREAD
#define MULTITHREAD 1
#define USE_PTHREAD 0
#define USE_FORK    0
#define USE_SOCKET  0
#endif

/*
 * Bare-metal main() does not require argc/argv.
 */
#ifndef MAIN_HAS_NOARGC
#define MAIN_HAS_NOARGC 1
#endif

#ifndef MAIN_HAS_NORETURN
#define MAIN_HAS_NORETURN 0
#endif

extern ee_u32 default_num_contexts;

typedef struct CORE_PORTABLE_S {
	ee_u8 portable_id;
} core_portable;

/*
 * Run selection.
 *
 * CoreMark standard:
 *
 * TOTAL_DATA_SIZE == 1200 -> PROFILE
 * TOTAL_DATA_SIZE == 2000 -> PERFORMANCE
 * otherwise                -> VALIDATION
 */
#if !defined(PROFILE_RUN) && \
    !defined(PERFORMANCE_RUN) && \
    !defined(VALIDATION_RUN)

#if (TOTAL_DATA_SIZE == 1200)
#define PROFILE_RUN 1
#elif (TOTAL_DATA_SIZE == 2000)
#define PERFORMANCE_RUN 1
#else
#define VALIDATION_RUN 1
#endif

#endif

int ee_printf(const char *fmt, ...);

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);

#endif /* CORE_PORTME_H */
