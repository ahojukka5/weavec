// SPDX-License-Identifier: Apache-2.0
//
// Compatibility compilation unit for source and bootstrap builds. The actual
// responsibilities are split so release packaging can expose only the program
// runtime while keeping compiler support and the build driver private.

#include "compiler_support.c"
#include "program_runtime.c"
#include "build_driver.c"
