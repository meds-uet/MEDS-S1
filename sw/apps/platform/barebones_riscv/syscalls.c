#include <stdint.h>
#include <stddef.h>
#include <sys/stat.h>
#include <sys/types.h>

#define SPIKE_UART_TX 0x10000000UL
#define STACK_TOP     0x01010000UL

static inline void spike_uart_putc(char c)
{
    *(volatile unsigned char *)SPIKE_UART_TX = (unsigned char)c;
}

ssize_t _write(int fd, const void *buf, size_t count)
{
    const unsigned char *p = (const unsigned char *)buf;

    if (fd != 1 && fd != 2)
        return -1;

    for (size_t i = 0; i < count; i++)
    {
        if (p[i] == '\n')
            spike_uart_putc('\r');

        spike_uart_putc((char)p[i]);
    }

    return (ssize_t)count;
}

int _close(int fd)
{
    (void)fd;
    return -1;
}

int _fstat(int fd, struct stat *st)
{
    (void)fd;

    if (st)
        st->st_mode = S_IFCHR;

    return 0;
}

int _isatty(int fd)
{
    (void)fd;
    return 1;
}

off_t _lseek(int fd, off_t offset, int whence)
{
    (void)fd;
    (void)offset;
    (void)whence;

    return 0;
}

/*
 * Temporary bare-metal heap for MEDS-S1 M-07.
 *
 * The linker-defined _end symbol marks the end of the
 * program/data image. The heap grows upward from there.
 */
extern char _end;

static char *heap_end;

void *_sbrk(ptrdiff_t increment)
{
    char *prev_heap_end;

    if (heap_end == NULL)
        heap_end = &_end;

    prev_heap_end = heap_end;

    if (heap_end + increment > (char *)STACK_TOP)
        return (void *)-1;

    heap_end += increment;

    return prev_heap_end;
}

/*
 * Spike HTIF exit symbols.
 */
volatile uint64_t tohost
    __attribute__((section(".tohost"), aligned(64)));

volatile uint64_t fromhost
    __attribute__((section(".fromhost"), aligned(64)));

void _exit(int status)
{
    tohost = ((uint64_t)(unsigned int)status << 1) | 1;

    for (;;)
        asm volatile ("wfi");
}
