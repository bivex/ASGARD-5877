#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include "metal_runtime.h"

CAMLprim value caml_asgard_gpu_is_available(value unit) {
    CAMLparam1(unit);
    int avail = asgard_gpu_is_available();
    CAMLreturn(Val_bool(avail));
}

CAMLprim value caml_asgard_gpu_synthesize_mba(value v_target, value v_max_results) {
    CAMLparam2(v_target, v_max_results);
    CAMLlocal1(v_res);

    uint64_t target = Int64_val(v_target);
    uint32_t max_results = Int_val(v_max_results);
    uint64_t* results = (uint64_t*)malloc(max_results * sizeof(uint64_t));
    uint32_t out_count = 0;

    int st = asgard_gpu_synthesize_mba(target, results, max_results, &out_count);
    if (st != 0) {
        free(results);
        caml_failwith("GPU Metal synthesize_mba failed");
    }

    v_res = caml_alloc(out_count, 0);
    for (uint32_t i = 0; i < out_count; ++i) {
        Store_field(v_res, i, caml_copy_int64(results[i]));
    }

    free(results);
    CAMLreturn(v_res);
}

CAMLprim value caml_asgard_gpu_batch_encrypt(value v_bytecode, value v_keys) {
    CAMLparam2(v_bytecode, v_keys);
    CAMLlocal3(v_res, v_sub, v_hd);

    size_t code_len = 0;
    value cur = v_bytecode;
    while (cur != Val_emptylist) {
        code_len++;
        cur = Field(cur, 1);
    }

    size_t num_builds = 0;
    cur = v_keys;
    while (cur != Val_emptylist) {
        num_builds++;
        cur = Field(cur, 1);
    }

    if (code_len == 0 || num_builds == 0) {
        CAMLreturn(Val_emptylist);
    }

    uint64_t* in_bc = (uint64_t*)malloc(code_len * sizeof(uint64_t));
    cur = v_bytecode;
    for (size_t i = 0; i < code_len; ++i) {
        in_bc[i] = Int64_val(Field(cur, 0));
        cur = Field(cur, 1);
    }

    uint64_t* keys = (uint64_t*)malloc(num_builds * sizeof(uint64_t));
    cur = v_keys;
    for (size_t i = 0; i < num_builds; ++i) {
        keys[i] = Int64_val(Field(cur, 0));
        cur = Field(cur, 1);
    }

    uint64_t* out_bc = (uint64_t*)malloc(code_len * num_builds * sizeof(uint64_t));
    int st = asgard_gpu_batch_encrypt(in_bc, code_len, keys, num_builds, out_bc);
    if (st != 0) {
        free(in_bc);
        free(keys);
        free(out_bc);
        caml_failwith("GPU Metal batch_encrypt failed");
    }

    v_res = Val_emptylist;
    for (int b = (int)num_builds - 1; b >= 0; --b) {
        v_sub = Val_emptylist;
        for (int w = (int)code_len - 1; w >= 0; --w) {
            v_hd = caml_copy_int64(out_bc[b * code_len + w]);
            value new_sub = caml_alloc(2, 0);
            Store_field(new_sub, 0, v_hd);
            Store_field(new_sub, 1, v_sub);
            v_sub = new_sub;
        }
        value new_res = caml_alloc(2, 0);
        Store_field(new_res, 0, v_sub);
        Store_field(new_res, 1, v_res);
        v_res = new_res;
    }

    free(in_bc);
    free(keys);
    free(out_bc);
    CAMLreturn(v_res);
}

CAMLprim value caml_asgard_gpu_verify_sac(value v_matrix_row, value v_trials) {
    CAMLparam2(v_matrix_row, v_trials);

    uint64_t mat[16];
    for (int i = 0; i < 16; ++i) {
        mat[i] = Int64_val(Field(v_matrix_row, i));
    }
    uint32_t trials = Int_val(v_trials);
    double sac = 0.0;

    int st = asgard_gpu_verify_sac(mat, trials, &sac);
    if (st != 0) {
        caml_failwith("GPU Metal verify_sac failed");
    }

    CAMLreturn(caml_copy_double(sac));
}
