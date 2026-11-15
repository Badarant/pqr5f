/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
/* pqr5f board layer for the AM243x LaunchPad. Implemented in platform.c on top
 * of the R5F PMU and UART0; the mupq HAL (hal.h) sits on the same file. */
#ifndef PQR5F_PLATFORM_H
#define PQR5F_PLATFORM_H

#include <stdint.h>

/* Free-running cycle counter, 32-bit. At 800 MHz it wraps every ~5.4 s, so
 * take differences in uint32_t arithmetic and a wrap in between is harmless. */
uint32_t pqr5f_cycles(void);

uint32_t pqr5f_cpu_hz(void);

/* Writes one character straight to the UART, with no formatting and no stack
 * beyond the call itself. */
void pqr5f_mark(char c);

/* Output, with no C library behind it. newlib's snprintf reaches malloc and
 * libgcc's software divide; a benchmark does not need either, and both are
 * code we would otherwise have to trust on a core we are bringing up. */
void pqr5f_puts(const char *s);
void pqr5f_puts_pad(const char *s, int width);  /* left-aligned, padded */
void pqr5f_putdec(uint32_t v, int width);       /* right-aligned, padded */
void pqr5f_puthex8(uint32_t v);
uint32_t pqr5f_udiv(uint32_t n, uint32_t d);

/* Built only with MULTEST=1, in place of the benchmark. */
void pqr5f_multest(void);

#endif
