// SPDX-License-Identifier: Apache-2.0
//
// Compatibility compilation unit for source and bootstrap builds. The actual
// responsibilities are split so release packaging can expose only the program
// runtime while keeping compiler support and the build driver private.

#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE 700
#endif
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include "compiler_support.c"
#include "program_runtime.c"
#include "build_driver.c"
