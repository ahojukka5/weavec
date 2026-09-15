// SPDX-License-Identifier: Apache-2.0
//
// Compiler-owned S-expression nesting budgets. Keep these integers identical
// to tree_walk_max_depth and tree_walk_internal_wir_max_depth in
// src/parser/parser.weave. See docs/syntax-depth.md.

#ifndef WEAVEC_TREE_WALK_DEPTH_H
#define WEAVEC_TREE_WALK_DEPTH_H

#define WEAVEC_TREE_WALK_MAX_DEPTH 64
#define WEAVEC_TREE_WALK_INTERNAL_WIR_MAX_DEPTH 65

#endif
