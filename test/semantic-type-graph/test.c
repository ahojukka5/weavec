// SPDX-License-Identifier: Apache-2.0

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../../runtime/semantic_type_graph.c"

static void build_graph(
    weave_type_graph *graph,
    int reverse,
    weave_type_ref *vector_i32,
    weave_type_ref *function,
    weave_type_ref *ok_variant) {
    assert(weave_type_graph_init(graph));

    weave_type_ref i32 = weave_type_graph_from_legacy_code(graph, 2);
    weave_type_ref i64 = weave_type_graph_from_legacy_code(graph, 3);
    weave_type_ref boolean = weave_type_graph_from_legacy_code(graph, 6);
    weave_type_ref vector;
    weave_type_ref result;
    if (reverse) {
        result = weave_type_graph_nominal(graph, "core", "Result");
        vector = weave_type_graph_nominal(graph, "collections", "Vector");
    } else {
        vector = weave_type_graph_nominal(graph, "collections", "Vector");
        result = weave_type_graph_nominal(graph, "core", "Result");
    }
    weave_type_ref argument = i32;
    *vector_i32 = weave_type_graph_application(graph, vector, &argument, 1);
    weave_type_ref params[] = {*vector_i32, boolean};
    *function = weave_type_graph_function(graph, params, 2, i64);
    weave_type_ref result_args[] = {i32, boolean};
    weave_type_ref result_i32_bool =
        weave_type_graph_application(graph, result, result_args, 2);
    *ok_variant =
        weave_type_graph_variant(graph, result_i32_bool, "Ok", &i32, 1);
}

int main(void) {
    weave_type_graph left;
    weave_type_graph right;
    weave_type_ref left_vector;
    weave_type_ref right_vector;
    weave_type_ref left_function;
    weave_type_ref right_function;
    weave_type_ref left_ok;
    weave_type_ref right_ok;
    build_graph(&left, 0, &left_vector, &left_function, &left_ok);
    build_graph(&right, 1, &right_vector, &right_function, &right_ok);

    assert(weave_type_graph_equal(&left, left_vector, &right, right_vector));
    assert(weave_type_graph_equal(&left, left_function, &right, right_function));
    assert(weave_type_graph_equal(&left, left_ok, &right, right_ok));
    assert(weave_type_graph_hash(&left, left_function) ==
           weave_type_graph_hash(&right, right_function));
    assert(strcmp(
        weave_type_graph_identity(&left, left_function),
        weave_type_graph_identity(&right, right_function)) == 0);
    assert(strcmp(
        weave_type_graph_display(&left, left_function),
        "fn(collections::Vector<i32>, bool) -> i64") == 0);
    assert(strcmp(
        weave_type_graph_display(&left, left_ok),
        "core::Result<i32, bool>::Ok(i32)") == 0);

    weave_type_ref vector = weave_type_graph_nominal(
        &left, "collections", "Vector");
    weave_type_ref i32 = weave_type_graph_from_legacy_code(&left, 2);
    assert(left_vector == weave_type_graph_application(&left, vector, &i32, 1));

    weave_type_ref point_a = weave_type_graph_nominal(&left, "a", "Point");
    weave_type_ref point_b = weave_type_graph_nominal(&left, "b", "Point");
    assert(!weave_type_graph_equal(&left, point_a, &left, point_b));

    weave_type_ref parameter = weave_type_graph_generic_parameter(
        &left, "collections::Vector", 0, "T");
    assert(weave_type_graph_kind(&left, parameter) ==
           WEAVE_TYPE_GENERIC_PARAMETER);
    assert(strcmp(weave_type_graph_owner(&left, parameter),
                  "collections::Vector") == 0);
    assert(strcmp(weave_type_graph_name(&left, parameter), "T") == 0);
    assert(weave_type_graph_ordinal(&left, parameter) == 0);

    weave_type_ref pointer = weave_type_graph_pointer(&left, point_a);
    weave_type_ref owned = weave_type_graph_owned(&left, point_a);
    weave_type_ref borrow = weave_type_graph_borrow(&left, point_a);
    weave_type_ref borrow_mut = weave_type_graph_borrow_mut(&left, point_a);
    assert(strcmp(weave_type_graph_display(&left, pointer), "ptr<a::Point>") == 0);
    assert(strcmp(weave_type_graph_display(&left, owned), "owned<a::Point>") == 0);
    assert(strcmp(weave_type_graph_display(&left, borrow), "borrow<a::Point>") == 0);
    assert(strcmp(weave_type_graph_display(&left, borrow_mut),
                  "borrow-mut<a::Point>") == 0);

    for (int32_t code = 0; code <= 7; ++code) {
        weave_type_ref type = weave_type_graph_from_legacy_code(&left, code);
        assert(type != WEAVE_TYPE_NONE);
        assert(weave_type_graph_to_legacy_code(&left, type) == code);
    }
    assert(weave_type_graph_to_legacy_code(&left, point_a) == 0);
    assert(weave_type_graph_child_count(&left, left_function) == 3);
    assert(weave_type_graph_child(&left, left_function, 99) == WEAVE_TYPE_NONE);
    assert(weave_type_graph_identity(&left, WEAVE_TYPE_NONE) == NULL);
    assert(weave_type_graph_kind(&left, WEAVE_TYPE_NONE) == WEAVE_TYPE_INVALID);
    assert(weave_type_graph_application(&left, vector, NULL, 0) ==
           WEAVE_TYPE_NONE);

    weave_type_graph_clear(&right);
    weave_type_graph_clear(&left);
    puts("semantic-type-graph: all checks passed");
    return 0;
}
