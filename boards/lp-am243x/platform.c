/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
/*
 * pqr5f bare-metal platform for the AM243x LaunchPad: UART0 transmit, the R5F
 * cycle counter, and the mupq HAL on top of them.
 */
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#include "hal.h"
#include "platform.h"

/* UART0, the LaunchPad's console, as the SDK configures it: 48 MHz input,
 * 115200 8N1. 48e6 / (16 * 115200) = 26.04. */
#define UART0_BASE   0x02800000u
#define UART_DIVISOR 26u

#define UART_THR  (*(volatile uint32_t *)(UART0_BASE + 0x00))
#define UART_DLL  (*(volatile uint32_t *)(UART0_BASE + 0x00))
#define UART_IER  (*(volatile uint32_t *)(UART0_BASE + 0x04))
#define UART_DLH  (*(volatile uint32_t *)(UART0_BASE + 0x04))
#define UART_FCR  (*(volatile uint32_t *)(UART0_BASE + 0x08))
#define UART_LCR  (*(volatile uint32_t *)(UART0_BASE + 0x0C))
#define UART_MCR  (*(volatile uint32_t *)(UART0_BASE + 0x10))
#define UART_LSR  (*(volatile uint32_t *)(UART0_BASE + 0x14))
#define UART_MDR1 (*(volatile uint32_t *)(UART0_BASE + 0x20))

#define LSR_THRE  (1u << 5)
#define LCR_DLAB  (1u << 7)
#define MDR1_DISABLE 0x7u
#define MDR1_UART16X 0x0u

#define R5F_CLOCK_HZ 800000000u

static void uart_init(void)
{
    UART_MDR1 = MDR1_DISABLE;       /* the divisor latch is only writable here */
    UART_LCR  = LCR_DLAB;
    UART_DLL  = UART_DIVISOR & 0xFFu;
    UART_DLH  = (UART_DIVISOR >> 8) & 0xFFu;
    UART_LCR  = 0x03u;              /* 8 bits, no parity, 1 stop, DLAB clear */
    UART_IER  = 0x00u;
    UART_MCR  = 0x03u;              /* RTS, DTR */
    UART_FCR  = 0x07u;              /* FIFO on, clear both */
    UART_MDR1 = MDR1_UART16X;
}

static void uart_putc(char c)
{
    while ((UART_LSR & LSR_THRE) == 0u) {
        /* wait for the holding register */
    }
    UART_THR = (uint32_t)(unsigned char)c;
}

/* PMCCNTR, with the /64 divider disabled by startup.S so one tick is one
 * cycle. */
uint32_t pqr5f_cycles(void)
{
    uint32_t v;
    __asm__ volatile("mrc p15, 0, %0, c9, c13, 0" : "=r"(v));
    return v;
}

uint32_t pqr5f_cpu_hz(void) { return R5F_CLOCK_HZ; }

static void pmu_reset(void)
{
    uint32_t pmcr;
    __asm__ volatile("mrc p15, 0, %0, c9, c12, 0" : "=r"(pmcr));
    pmcr |= (1u << 2);
    __asm__ volatile("mcr p15, 0, %0, c9, c12, 0" :: "r"(pmcr));
    __asm__ volatile("isb");
}

void hal_setup(const enum clock_mode clock)
{
    (void)clock;                    /* the SBL has already clocked the core */
    uart_init();
    pmu_reset();
}

/* No newline translation: pqr5f_bench.c writes "\r\n" itself, as it must for
 * the TI build too. */
void hal_send_str(const char *in)
{
    for (; *in != '\0'; ++in) {
        uart_putc(*in);
    }
}

uint64_t hal_get_time(void) { return (uint64_t)pqr5f_cycles(); }

void pqr5f_puts(const char *s) { hal_send_str(s); }

void pqr5f_puts_pad(const char *s, int width)
{
    int n = 0;

    for (; s[n] != '\0'; n++) {
        uart_putc(s[n]);
    }
    for (; n < width; n++) {
        uart_putc(' ');
    }
}

/* Restoring division, so nothing here calls into libgcc. 32 iterations is a
 * few hundred cycles and only ever runs while printing. */
uint32_t pqr5f_udiv(uint32_t n, uint32_t d)
{
    uint32_t q = 0, r = 0;

    if (d == 0u) {
        return 0u;
    }
    for (int i = 31; i >= 0; i--) {
        r = (r << 1) | ((n >> i) & 1u);
        if (r >= d) {
            r -= d;
            q |= 1u << i;
        }
    }
    return q;
}

void pqr5f_putdec(uint32_t v, int width)
{
    char buf[10];
    int n = 0;

    do {
        /* A literal divisor, so the compiler folds it to a multiply. */
        uint32_t next = v / 10u;
        buf[n++] = (char)('0' + (v - next * 10u));
        v = next;
    } while (v != 0u);

    for (int pad = width - n; pad > 0; pad--) {
        uart_putc(' ');
    }
    while (n-- > 0) {
        uart_putc(buf[n]);
    }
}

void pqr5f_puthex8(uint32_t v)
{
    static const char hex[] = "0123456789abcdef";

    for (int shift = 28; shift >= 0; shift -= 4) {
        uart_putc(hex[(v >> shift) & 0xFu]);
    }
}

#ifdef PQR5F_STACK_PAINT
/*
 * Stack painting: fill the unused stack with a pattern, run an operation, then
 * find how far down the pattern survives. The deepest word that changed is the
 * high-water mark.
 *
 * Only the part below the live frame is painted, with a margin, because this
 * function is itself standing on the stack. The margin and the frames of the
 * caller are counted as used, which overstates the result by of the order of a
 * hundred bytes.
 */
extern uint32_t __stack_start[];
extern uint32_t __stack_top[];

#define PAINT        0xdeadbeefu
#define PAINT_MARGIN 256u

size_t hal_get_stack_size(void)
{
    return (size_t)((uint8_t *)__stack_top - (uint8_t *)__stack_start);
}

void hal_spraystack(void)
{
    uint32_t sp;
    uint32_t *p = __stack_start;
    uint32_t *limit;

    __asm__ volatile("mov %0, sp" : "=r"(sp));
    limit = (uint32_t *)((sp - PAINT_MARGIN) & ~3u);

    while (p < limit) {
        *p++ = PAINT;
    }
}

size_t hal_checkstack(void)
{
    uint32_t *p = __stack_start;

    while (p < __stack_top && *p == PAINT) {
        p++;
    }
    return (size_t)((uint8_t *)__stack_top - (uint8_t *)p);
}
#endif

void pqr5f_bench_main(void *args);

/* Stage markers. The banner needs snprintf, a stack and a working UART all at
 * once; a bare character needs only the UART, so it tells apart "died before
 * main" from "died while printing". */
void pqr5f_mark(char c)
{
    uart_putc(c);
}

int main(void)
{
    uart_init();
#if defined(PQR5F_ACVP)
    {
        void pqr5f_acvp(void);
        pqr5f_acvp();
    }
#elif defined(PQR5F_MULTEST)
    pqr5f_multest();
#else
    pqr5f_bench_main(NULL);
#endif
    for (;;) {
        /* nothing left to do; the SBL has no one to return to */
    }
}
