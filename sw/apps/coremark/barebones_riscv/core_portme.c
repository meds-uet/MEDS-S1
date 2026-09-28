/*
 * CoreMark porting layer for MEDS-S1 temporary bare-metal harness.
 *
 * Target:
 *   RISC-V RV64IMAC
 *   ABI: lp64
 *
 * Purpose:
 *   This is a temporary standalone port used to run CoreMark under
 *   Spike before the official MEDS-S1 BSP/CRT0/linker/UART/performance
 *   library are available.
 *
 * This file provides:
 *   - timing using RISC-V mcycle
 *   - minimal bare-metal system-call stubs
 *   - temporary _sbrk() heap
 *   - Spike UART output through 0x10000000
 *   - Spike tohost/fromhost symbols
 */

#include <stdint.h>
#include <stddef.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>

#include "coremark.h"
#include "core_portme.h"


/* ================================================================
 * CoreMark required benchmark variables
 * ================================================================ */

/*
 * CoreMark uses these variables for the benchmark seeds.
 *
 * Validation run:
 *   seed1 = 0x3415
 *   seed2 = 0x3415
 *   seed3 = 0x66
 *
 * Performance run:
 *   seed1 = 0
 *   seed2 = 0
 *   seed3 = 0x66
 *
 * Profile run:
 *   seed1 = 8
 *   seed2 = 8
 *   seed3 = 8
 */

#if VALIDATION_RUN

volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;

#endif


#if PERFORMANCE_RUN

volatile ee_s32 seed1_volatile = 0;
volatile ee_s32 seed2_volatile = 0;
volatile ee_s32 seed3_volatile = 0x66;

#endif


#if PROFILE_RUN

volatile ee_s32 seed1_volatile = 8;
volatile ee_s32 seed2_volatile = 8;
volatile ee_s32 seed3_volatile = 8;

#endif


/*
 * seed4 controls the number of iterations.
 */
volatile ee_s32 seed4_volatile = ITERATIONS;


/*
 * seed5 is reserved by CoreMark for the context configuration.
 */
volatile ee_s32 seed5_volatile = 0;


/*
 * Temporary harness uses a single CoreMark context.
 */
ee_u32 default_num_contexts = 1;


/* ================================================================
 * Spike UART
 * ================================================================
 *
 * Spike's simple UART/console output device is mapped at:
 *
 *     0x10000000
 *
 * The temporary harness writes characters directly to this address.
 */

#define SPIKE_UART_TX 0x10000000UL

static inline void spike_uart_putc(char c)
{
    *(volatile unsigned char *)SPIKE_UART_TX = (unsigned char)c;
}


/* ================================================================
 * Timing
 * ================================================================
 *
 * CoreMark timing is based on the RISC-V mcycle CSR.
 *
 * The official MEDS-S1 integration will later provide the actual
 * processor clock frequency through CLOCKS_PER_SEC.
 */

static inline uint64_t riscv_read_cycle(void)
{
    uint64_t value;

    asm volatile (
        "csrr %0, mcycle"
        : "=r"(value)
    );

    return value;
}


CORETIMETYPE barebones_clock(void)
{
    return (CORETIMETYPE)riscv_read_cycle();
}


/*
 * CoreMark timing macros.
 */

#define GETMYTIME(_t) \
    (*(_t) = barebones_clock())

#define MYTIMEDIFF(fin, ini) \
    ((fin) - (ini))


#define SAMPLE_TIME_IMPLEMENTATION 1


/* ================================================================
 * CoreMark start/stop timing
 * ================================================================ */

static CORETIMETYPE start_time_val;
static CORETIMETYPE stop_time_val;


void start_time(void)
{
    GETMYTIME(&start_time_val);
}


void stop_time(void)
{
    GETMYTIME(&stop_time_val);
}


CORE_TICKS get_time(void)
{
    return (CORE_TICKS)
        MYTIMEDIFF(stop_time_val, start_time_val);
}


secs_ret time_in_secs(CORE_TICKS ticks)
{
    secs_ret retval;

    retval = ((secs_ret)ticks) /
             ((secs_ret)EE_TICKS_PER_SEC);

    return retval;
}


/* ================================================================
 * Temporary heap
 * ================================================================
 *
 * Newlib may request heap memory through _sbrk().
 *
 * The temporary Spike memory layout is:
 *
 *     0x00010000 - 0x01010000
 *
 * CRT0 starts the stack at:
 *
 *     0x01010000
 *
 * The heap below is kept separate from the stack and program
 * startup/data area.
 */

#define COREMARK_HEAP_SIZE (64 * 1024)

static unsigned char coremark_heap[COREMARK_HEAP_SIZE]
    __attribute__((aligned(16)));

static size_t coremark_heap_used = 0;


void *_sbrk(ptrdiff_t increment)
{
    void *previous;

    if (increment < 0)
        return (void *)-1;

    if (coremark_heap_used + (size_t)increment >
        COREMARK_HEAP_SIZE)
    {
        return (void *)-1;
    }

    previous = &coremark_heap[coremark_heap_used];

    coremark_heap_used += (size_t)increment;

    return previous;
}


/* ================================================================
 * Minimal system-call stubs
 * ================================================================
 *
 * CoreMark/Newlib may reference these functions even though this
 * is a bare-metal environment with no operating system.
 */


/*
 * read()
 */
ssize_t _read(int fd, void *buf, size_t count)
{
    (void)fd;
    (void)buf;
    (void)count;

    return 0;
}


/*
 * write()
 *
 * stdout = fd 1
 * stderr = fd 2
 *
 * Characters are sent directly to Spike's UART.
 */
ssize_t _write(int fd, const void *buf, size_t count)
{
    const unsigned char *p;

    if (fd != 1 && fd != 2)
        return -1;

    p = (const unsigned char *)buf;

    for (size_t i = 0; i < count; i++)
    {
        /*
         * Convert LF to CRLF so redirected Spike output is
         * displayed correctly.
         */
        if (p[i] == '\n')
            spike_uart_putc('\r');

        spike_uart_putc((char)p[i]);
    }

    return (ssize_t)count;
}


/*
 * close()
 */
int _close(int fd)
{
    (void)fd;

    return -1;
}


/*
 * fstat()
 */
int _fstat(int fd, struct stat *st)
{
    (void)fd;

    if (st)
    {
        st->st_mode = S_IFCHR;
    }

    return 0;
}


/*
 * isatty()
 */
int _isatty(int fd)
{
    (void)fd;

    return 1;
}


/*
 * lseek()
 */
off_t _lseek(int fd, off_t offset, int whence)
{
    (void)fd;
    (void)offset;
    (void)whence;

    return 0;
}


/* ================================================================
 * Spike HTIF symbols
 * ================================================================
 *
 * These symbols prevent Spike from warning about missing
 * tohost/fromhost symbols.
 *
 * _exit() writes the exit status to tohost.
 */

volatile uint64_t tohost
    __attribute__((section(".tohost"), aligned(64)));

volatile uint64_t fromhost
    __attribute__((section(".fromhost"), aligned(64)));


void _exit(int status)
{
    /*
     * Spike HTIF exit convention:
     *
     *     bit 0 = 1
     *     remaining value contains exit status.
     */
    tohost = ((uint64_t)(unsigned int)status << 1) | 1;

    /*
     * Do not return.
     */
    for (;;)
    {
        asm volatile ("wfi");
    }
}


/* ================================================================
 * CoreMark portable initialization
 * ================================================================ */

void portable_init(core_portable *p, int *argc, char *argv[])
{
    /*
     * Nothing is required for the temporary bare-metal port.
     *
     * Keep the parameters referenced to avoid compiler warnings.
     */
    (void)argc;
    (void)argv;

    if (p)
    {
        p->portable_id = 1;
    }
}


/* ================================================================
 * CoreMark portable finalization
 * ================================================================ */

void portable_fini(core_portable *p)
{
    (void)p;
}
