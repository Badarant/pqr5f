/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
@ pqr5f: wrapper giving the assembly Keccak an object name no .c file can
@ claim. The SDK makefile's "vpath %.c" finds mupq/common/keccakf1600.c first
@ for the target keccakf1600.obj, so listing keccakf1600.S in ASMFILES
@ silently compiles the C reference instead.
#include "keccakf1600.S"
