(** Stack_handlers_emitter — Typed C++ AST code generation for Stack-VM manipulation handlers. *)

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

let vm_handler_params : (ctype * string) list = [
  (Ptr (StructType "stack_vm_t"), "vm");
  (ConstPtr UInt8, "bytecode");
  (Ptr SizeT, "vip");
]

let vm_vsp_idx = var "vm" $-> "vsp_idx"
let vm_vsp = var "vm" $-> "vsp"
let vm_halted = var "vm" $-> "halted"
let vm_ctx = var "vm" $-> "ctx"

let vsp_encode slot_expr val_expr =
  call "VSP_ENCODE" [slot_expr; val_expr]

let emit_h_push_imm () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_push_imm";
    params = vm_handler_params;
    body = [
      let_u64 "imm" (cast UInt64 (call "fetch_i64" [var "vm"; var "bytecode"; var "vip"]));
      if_then_else (vm_vsp_idx <~ i32 4096)
        [
          idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "imm");
          vm_vsp_idx += i32 1;
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_push_imm32 () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_push_imm32";
    params = vm_handler_params;
    body = [
      decl_var Int32 "imm32" ~init:(call "fetch_i32" [var "vm"; var "bytecode"; var "vip"]);
      let_u64 "imm" (cast UInt64 (cast Int64 (var "imm32")));
      if_then_else (vm_vsp_idx <~ i32 4096)
        [
          idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "imm");
          vm_vsp_idx += i32 1;
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let sizeof e = call "sizeof" [e]

let emit_h_push_reg () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_push_reg";
    params = vm_handler_params;
    body = [
      decl_var ~is_const:true Int32 "max_ctx"
        ~init:(cast Int32 (sizeof vm_ctx /~ sizeof (idx vm_ctx (i32 0))));
      decl_var Int16 "idx" ~init:(call "fetch_i16" [var "vm"; var "bytecode"; var "vip"]);
      if_then_else ((vm_vsp_idx <~ i32 4096) &&~ ((var "idx" >=~ i32 0) &&~ (var "idx" <~ var "max_ctx")))
        [
          idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (idx vm_ctx (var "idx"));
          vm_vsp_idx += i32 1;
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_pop_reg () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_pop_reg";
    params = vm_handler_params;
    body = [
      decl_var ~is_const:true Int32 "max_ctx"
        ~init:(cast Int32 (sizeof vm_ctx /~ sizeof (idx vm_ctx (i32 0))));
      decl_var Int16 "idx" ~init:(call "fetch_i16" [var "vm"; var "bytecode"; var "vip"]);
      if_then_else ((vm_vsp_idx >~ i32 0) &&~ ((var "idx" >=~ i32 0) &&~ (var "idx" <~ var "max_ctx")))
        [
          vm_vsp_idx -= i32 1;
          idx vm_ctx (var "idx") := vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx);
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_dup () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_dup";
    params = vm_handler_params;
    body = [
      expr_stmt (cast Void (var "bytecode"));
      expr_stmt (cast Void (var "vip"));
      if_then_else ((vm_vsp_idx >~ i32 0) &&~ (vm_vsp_idx <~ i32 4096))
        [
          decl_var Int32 "src" ~init:(vm_vsp_idx -~ i32 1);
          let_u64 "decoded" (vsp_encode (var "src") (idx vm_vsp (var "src")));
          idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "decoded");
          vm_vsp_idx += i32 1;
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_dup2 () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_dup2";
    params = vm_handler_params;
    body = [
      expr_stmt (cast Void (var "bytecode"));
      expr_stmt (cast Void (var "vip"));
      if_then_else ((vm_vsp_idx >=~ i32 2) &&~ (vm_vsp_idx +~ i32 2 <=~ i32 4096))
        [
          decl_var Int32 "ib" ~init:(vm_vsp_idx -~ i32 2);
          decl_var Int32 "ia" ~init:(vm_vsp_idx -~ i32 1);
          let_u64 "db" (vsp_encode (var "ib") (idx vm_vsp (var "ib")));
          let_u64 "da" (vsp_encode (var "ia") (idx vm_vsp (var "ia")));
          idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "db");
          idx vm_vsp (vm_vsp_idx +~ i32 1) := vsp_encode (vm_vsp_idx +~ i32 1) (var "da");
          vm_vsp_idx += i32 2;
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_rot () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_rot";
    params = vm_handler_params;
    body = [
      expr_stmt (cast Void (var "bytecode"));
      expr_stmt (cast Void (var "vip"));
      if_then_else (vm_vsp_idx >=~ i32 3)
        [
          decl_var Int32 "ic" ~init:(vm_vsp_idx -~ i32 3);
          decl_var Int32 "ib" ~init:(vm_vsp_idx -~ i32 2);
          decl_var Int32 "ia" ~init:(vm_vsp_idx -~ i32 1);
          let_u64 "dc" (vsp_encode (var "ic") (idx vm_vsp (var "ic")));
          let_u64 "db" (vsp_encode (var "ib") (idx vm_vsp (var "ib")));
          let_u64 "da" (vsp_encode (var "ia") (idx vm_vsp (var "ia")));
          idx vm_vsp (var "ic") := vsp_encode (var "ic") (var "db");
          idx vm_vsp (var "ib") := vsp_encode (var "ib") (var "da");
          idx vm_vsp (var "ia") := vsp_encode (var "ia") (var "dc");
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_swap () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_swap";
    params = vm_handler_params;
    body = [
      expr_stmt (cast Void (var "bytecode"));
      expr_stmt (cast Void (var "vip"));
      if_then_else (vm_vsp_idx >=~ i32 2)
        [
          decl_var Int32 "ia" ~init:(vm_vsp_idx -~ i32 1);
          decl_var Int32 "ib" ~init:(vm_vsp_idx -~ i32 2);
          let_u64 "da" (vsp_encode (var "ia") (idx vm_vsp (var "ia")));
          let_u64 "db" (vsp_encode (var "ib") (idx vm_vsp (var "ib")));
          idx vm_vsp (var "ia") := vsp_encode (var "ia") (var "db");
          idx vm_vsp (var "ib") := vsp_encode (var "ib") (var "da");
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_push_pop_handlers () : top_decl list = [
  emit_h_push_imm ();
  emit_h_push_imm32 ();
  emit_h_push_reg ();
  emit_h_pop_reg ();
]

let emit_dup_swap_handlers () : top_decl list = [
  emit_h_dup ();
  emit_h_dup2 ();
  emit_h_rot ();
  emit_h_swap ();
]

let vm_zf = var "vm" $-> "zf"
let vm_sf = var "vm" $-> "sf"
let vm_cf = var "vm" $-> "cf"
let vm_pf = var "vm" $-> "pf"
let vm_of = var "vm" $-> "of"

let emit_h_read_mem () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_read_mem";
    params = vm_handler_params;
    body = [
      decl_var UInt8 "w" ~init:(call "fetch_byte" [var "vm"; var "bytecode"; var "vip"]);
      let_u64 "addr" (u64 0L);
      decl_var Int32 "have_addr" ~init:(i32 0);
      if_then_else (vm_vsp_idx >~ i32 0)
        [
          vm_vsp_idx -= i32 1;
          var "addr" := vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx);
          var "have_addr" := i32 1;
        ]
        [
          vm_halted := i32 1;
        ];
      let_u64 "val" (u64 0L);
      if_then (var "have_addr" <>~ i32 0)
        [
          if_then_else (log_not (call "asg_mem_access_ok" [var "addr"; var "w"]))
            [
              vm_halted := i32 1;
            ]
            [
              if_then_else (var "w" ==~ i32 1)
                [ var "val" := cast UInt64 (deref (reinterpret_cast (ConstPtr UInt8) (var "addr"))) ]
                [
                  if_then_else (var "w" ==~ i32 2)
                    [ var "val" := cast UInt64 (deref (reinterpret_cast (ConstPtr UInt16) (var "addr"))) ]
                    [
                      if_then_else (var "w" ==~ i32 4)
                        [ var "val" := cast UInt64 (deref (reinterpret_cast (ConstPtr UInt32) (var "addr"))) ]
                        [ var "val" := deref (reinterpret_cast (ConstPtr UInt64) (var "addr")) ]
                    ]
                ]
            ];
        ];
      if_then_else (vm_vsp_idx <~ i32 4096)
        [
          idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "val");
          vm_vsp_idx += i32 1;
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_write_mem () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_write_mem";
    params = vm_handler_params;
    body = [
      decl_var UInt8 "w" ~init:(call "fetch_byte" [var "vm"; var "bytecode"; var "vip"]);
      if_then_else (vm_vsp_idx >=~ i32 2)
        [
          vm_vsp_idx -= i32 1;
          let_u64 "val" (vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx));
          vm_vsp_idx -= i32 1;
          let_u64 "addr" (vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx));
          if_then_else (log_not (call "asg_mem_access_ok" [var "addr"; var "w"]))
            [
              vm_halted := i32 1;
            ]
            [
              if_then_else (var "w" ==~ i32 1)
                [ deref (reinterpret_cast (Ptr UInt8) (var "addr")) := cast UInt8 (var "val") ]
                [
                  if_then_else (var "w" ==~ i32 2)
                    [ deref (reinterpret_cast (Ptr UInt16) (var "addr")) := cast UInt16 (var "val") ]
                    [
                      if_then_else (var "w" ==~ i32 4)
                        [ deref (reinterpret_cast (Ptr UInt32) (var "addr")) := cast UInt32 (var "val") ]
                        [ deref (reinterpret_cast (Ptr UInt64) (var "addr")) := var "val" ]
                    ]
                ]
            ];
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_binary_op_handler name inner_body : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name;
    params = vm_handler_params;
    body = [
      expr_stmt (cast Void (var "bytecode"));
      expr_stmt (cast Void (var "vip"));
      if_then_else (vm_vsp_idx >=~ i32 2)
        ([
          vm_vsp_idx -= i32 1;
          let_u64 "b" (vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx));
          vm_vsp_idx -= i32 1;
          let_u64 "a" (vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx));
        ] @ inner_body)
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_add () : top_decl =
  emit_binary_op_handler "h_add" [
    let_u64 "res" (var "a" +~ var "b");
    vm_zf := cast UInt8 (var "res" ==~ u64 0L);
    vm_sf := cast UInt8 (cast Int64 (var "res") <~ i64 0L);
    vm_cf := cast UInt8 (var "res" <~ var "a");
    vm_of := cast UInt8 (((bit_not (var "a" ^~ var "b") &~ (var "a" ^~ var "res")) >>~ i32 63) &~ u64 1L);
    vm_pf := call "parity8" [var "res"];
    idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "res");
    vm_vsp_idx += i32 1;
  ]

let emit_h_sub () : top_decl =
  emit_binary_op_handler "h_sub" [
    let_u64 "res" (var "a" -~ var "b");
    vm_zf := cast UInt8 (var "res" ==~ u64 0L);
    vm_sf := cast UInt8 (cast Int64 (var "res") <~ i64 0L);
    vm_cf := cast UInt8 (var "a" <~ var "b");
    vm_of := cast UInt8 ((((var "a" ^~ var "b") &~ (var "a" ^~ var "res")) >>~ i32 63) &~ u64 1L);
    vm_pf := call "parity8" [var "res"];
    idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "res");
    vm_vsp_idx += i32 1;
  ]

let emit_h_mul () : top_decl =
  emit_binary_op_handler "h_mul" [
    idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "a" *~ var "b");
    vm_vsp_idx += i32 1;
  ]

let emit_h_nor () : top_decl =
  emit_binary_op_handler "h_nor" [
    let_u64 "res" (bit_not (var "a" |~ var "b"));
    vm_zf := cast UInt8 (var "res" ==~ u64 0L);
    vm_sf := cast UInt8 (cast Int64 (var "res") <~ i64 0L);
    vm_cf := cast UInt8 (i32 0);
    vm_of := cast UInt8 (i32 0);
    vm_pf := call "parity8" [var "res"];
    idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "res");
    vm_vsp_idx += i32 1;
  ]

let emit_h_nand () : top_decl =
  emit_binary_op_handler "h_nand" [
    let_u64 "res" (bit_not (var "a" &~ var "b"));
    vm_zf := cast UInt8 (var "res" ==~ u64 0L);
    vm_sf := cast UInt8 (cast Int64 (var "res") <~ i64 0L);
    vm_cf := cast UInt8 (i32 0);
    vm_of := cast UInt8 (i32 0);
    vm_pf := call "parity8" [var "res"];
    idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "res");
    vm_vsp_idx += i32 1;
  ]

let emit_h_shl () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_shl";
    params = vm_handler_params;
    body = [
      expr_stmt (cast Void (var "bytecode"));
      expr_stmt (cast Void (var "vip"));
      if_then_else (vm_vsp_idx >=~ i32 2)
        [
          vm_vsp_idx -= i32 1;
          let_u64 "count" (vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx));
          vm_vsp_idx -= i32 1;
          let_u64 "val" (vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx));
          let_u64 "res" (var "val" <<~ (var "count" &~ u64 63L));
          vm_zf := cast UInt8 (var "res" ==~ u64 0L);
          vm_sf := cast UInt8 (cast Int64 (var "res") <~ i64 0L);
          vm_cf := cast UInt8 (i32 0);
          vm_of := cast UInt8 (i32 0);
          vm_pf := call "parity8" [var "res"];
          idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "res");
          vm_vsp_idx += i32 1;
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_shr () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_shr";
    params = vm_handler_params;
    body = [
      expr_stmt (cast Void (var "bytecode"));
      expr_stmt (cast Void (var "vip"));
      if_then_else (vm_vsp_idx >=~ i32 2)
        [
          vm_vsp_idx -= i32 1;
          let_u64 "count" (vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx));
          vm_vsp_idx -= i32 1;
          let_u64 "val" (vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx));
          let_u64 "res" (var "val" >>~ (var "count" &~ u64 63L));
          vm_zf := cast UInt8 (var "res" ==~ u64 0L);
          vm_sf := cast UInt8 (cast Int64 (var "res") <~ i64 0L);
          vm_cf := cast UInt8 (i32 0);
          vm_of := cast UInt8 (i32 0);
          vm_pf := call "parity8" [var "res"];
          idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "res");
          vm_vsp_idx += i32 1;
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_sar () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_sar";
    params = vm_handler_params;
    body = [
      expr_stmt (cast Void (var "bytecode"));
      expr_stmt (cast Void (var "vip"));
      if_then_else (vm_vsp_idx >=~ i32 2)
        [
          vm_vsp_idx -= i32 1;
          let_u64 "count" (vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx));
          vm_vsp_idx -= i32 1;
          let_u64 "val" (vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx));
          let_u64 "res" (cast UInt64 (cast Int64 (var "val") >>~ (var "count" &~ u64 63L)));
          vm_zf := cast UInt8 (var "res" ==~ u64 0L);
          vm_sf := cast UInt8 (cast Int64 (var "res") <~ i64 0L);
          vm_cf := cast UInt8 (i32 0);
          vm_of := cast UInt8 (i32 0);
          vm_pf := call "parity8" [var "res"];
          idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "res");
          vm_vsp_idx += i32 1;
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_div () : top_decl =
  emit_binary_op_handler "h_div" [
    let_u64 "res" (ternary (var "b" <>~ u64 0L) (var "a" /~ var "b") (u64 0L));
    idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "res");
    vm_vsp_idx += i32 1;
  ]

let emit_h_idiv () : top_decl =
  emit_binary_op_handler "h_idiv" [
    decl_var Int64 "sa" ~init:(cast Int64 (var "a"));
    decl_var Int64 "sb" ~init:(cast Int64 (var "b"));
    let_u64 "res" (
      ternary
        ((var "sb" ==~ i64 0L) ||~ ((var "sa" ==~ var "INT64_MIN") &&~ (var "sb" ==~ i64 (-1L))))
        (u64 0L)
        (cast UInt64 (var "sa" /~ var "sb"))
    );
    idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "res");
    vm_vsp_idx += i32 1;
  ]

let emit_h_push_flags () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_push_flags";
    params = vm_handler_params;
    body = [
      expr_stmt (cast Void (var "bytecode"));
      expr_stmt (cast Void (var "vip"));
      if_then_else (vm_vsp_idx <~ i32 4096)
        [
          let_u64 "fl" (
            (ternary (vm_zf <>~ cast UInt8 (i32 0)) (u64 0x40L) (u64 0L)) |~
            (ternary (vm_sf <>~ cast UInt8 (i32 0)) (u64 0x80L) (u64 0L)) |~
            (ternary (vm_cf <>~ cast UInt8 (i32 0)) (u64 0x01L) (u64 0L)) |~
            (ternary (vm_pf <>~ cast UInt8 (i32 0)) (u64 0x04L) (u64 0L)) |~
            (ternary (vm_of <>~ cast UInt8 (i32 0)) (u64 0x800L) (u64 0L)) |~
            u64 0x02L
          );
          idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "fl");
          vm_vsp_idx += i32 1;
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_pop_flags () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_pop_flags";
    params = vm_handler_params;
    body = [
      expr_stmt (cast Void (var "bytecode"));
      expr_stmt (cast Void (var "vip"));
      if_then_else (vm_vsp_idx >~ i32 0)
        [
          vm_vsp_idx -= i32 1;
          let_u64 "fl" (vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx));
          vm_cf := cast UInt8 ((var "fl" &~ u64 0x01L) <>~ u64 0L);
          vm_pf := cast UInt8 ((var "fl" &~ u64 0x04L) <>~ u64 0L);
          vm_zf := cast UInt8 ((var "fl" &~ u64 0x40L) <>~ u64 0L);
          vm_sf := cast UInt8 ((var "fl" &~ u64 0x80L) <>~ u64 0L);
          vm_of := cast UInt8 ((var "fl" &~ u64 0x800L) <>~ u64 0L);
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_mem_handlers () : top_decl list = [
  emit_h_read_mem ();
  emit_h_write_mem ();
]

let emit_alu_handlers () : top_decl list = [
  emit_h_add ();
  emit_h_sub ();
  emit_h_mul ();
  emit_h_nor ();
  emit_h_nand ();
  emit_h_shl ();
  emit_h_shr ();
  emit_h_sar ();
  emit_h_div ();
  emit_h_idiv ();
]

let emit_flags_handlers () : top_decl list = [
  emit_h_push_flags ();
  emit_h_pop_flags ();
]

let emit_h_cmp () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_cmp";
    params = vm_handler_params;
    body = [
      expr_stmt (cast Void (var "bytecode"));
      expr_stmt (cast Void (var "vip"));
      if_then_else (vm_vsp_idx >=~ i32 2)
        [
          vm_vsp_idx -= i32 1;
          let_u64 "b" (vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx));
          vm_vsp_idx -= i32 1;
          let_u64 "a" (vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx));
          let_u64 "res" (var "a" -~ var "b");
          vm_zf := cast UInt8 (var "res" ==~ u64 0L);
          vm_sf := cast UInt8 (cast Int64 (var "res") <~ i64 0L);
          vm_cf := cast UInt8 (var "a" <~ var "b");
          vm_of := cast UInt8 ((((var "a" ^~ var "b") &~ (var "a" ^~ var "res")) >>~ i32 63) &~ u64 1L);
          vm_pf := call "parity8" [var "res"];
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_test () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_test";
    params = vm_handler_params;
    body = [
      expr_stmt (cast Void (var "bytecode"));
      expr_stmt (cast Void (var "vip"));
      if_then_else (vm_vsp_idx >=~ i32 2)
        [
          vm_vsp_idx -= i32 1;
          let_u64 "b" (vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx));
          vm_vsp_idx -= i32 1;
          let_u64 "a" (vsp_encode vm_vsp_idx (idx vm_vsp vm_vsp_idx));
          let_u64 "res" (var "a" &~ var "b");
          vm_zf := cast UInt8 (var "res" ==~ u64 0L);
          vm_sf := cast UInt8 (cast Int64 (var "res") <~ i64 0L);
          vm_cf := cast UInt8 (i32 0);
          vm_of := cast UInt8 (i32 0);
          vm_pf := call "parity8" [var "res"];
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_add_imm () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_add_imm";
    params = vm_handler_params;
    body = [
      let_u64 "imm" (cast UInt64 (call "fetch_i64" [var "vm"; var "bytecode"; var "vip"]));
      if_then_else (vm_vsp_idx >=~ i32 1)
        [
          let_u64 "a" (vsp_encode (vm_vsp_idx -~ i32 1) (idx vm_vsp (vm_vsp_idx -~ i32 1)));
          let_u64 "b" (var "imm");
          let_u64 "res" (var "a" +~ var "b");
          vm_zf := cast UInt8 (var "res" ==~ u64 0L);
          vm_sf := cast UInt8 (cast Int64 (var "res") <~ i64 0L);
          vm_cf := cast UInt8 (var "res" <~ var "a");
          vm_of := cast UInt8 (((bit_not (var "a" ^~ var "b") &~ (var "a" ^~ var "res")) >>~ i32 63) &~ u64 1L);
          vm_pf := call "parity8" [var "res"];
          idx vm_vsp (vm_vsp_idx -~ i32 1) := vsp_encode (vm_vsp_idx -~ i32 1) (var "res");
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_sub_imm () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_sub_imm";
    params = vm_handler_params;
    body = [
      let_u64 "imm" (cast UInt64 (call "fetch_i64" [var "vm"; var "bytecode"; var "vip"]));
      if_then_else (vm_vsp_idx >=~ i32 1)
        [
          let_u64 "a" (vsp_encode (vm_vsp_idx -~ i32 1) (idx vm_vsp (vm_vsp_idx -~ i32 1)));
          let_u64 "b" (var "imm");
          let_u64 "res" (var "a" -~ var "b");
          vm_zf := cast UInt8 (var "res" ==~ u64 0L);
          vm_sf := cast UInt8 (cast Int64 (var "res") <~ i64 0L);
          vm_cf := cast UInt8 (var "a" <~ var "b");
          vm_of := cast UInt8 ((((var "a" ^~ var "b") &~ (var "a" ^~ var "res")) >>~ i32 63) &~ u64 1L);
          vm_pf := call "parity8" [var "res"];
          idx vm_vsp (vm_vsp_idx -~ i32 1) := vsp_encode (vm_vsp_idx -~ i32 1) (var "res");
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_add_ii () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_add_ii";
    params = vm_handler_params;
    body = [
      let_u64 "a" (cast UInt64 (call "fetch_i64" [var "vm"; var "bytecode"; var "vip"]));
      let_u64 "b" (cast UInt64 (call "fetch_i64" [var "vm"; var "bytecode"; var "vip"]));
      let_u64 "res" (var "a" +~ var "b");
      vm_zf := cast UInt8 (var "res" ==~ u64 0L);
      vm_sf := cast UInt8 (cast Int64 (var "res") <~ i64 0L);
      vm_cf := cast UInt8 (var "res" <~ var "a");
      vm_of := cast UInt8 (((bit_not (var "a" ^~ var "b") &~ (var "a" ^~ var "res")) >>~ i32 63) &~ u64 1L);
      vm_pf := call "parity8" [var "res"];
      if_then_else (vm_vsp_idx <~ i32 4096)
        [
          idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "res");
          vm_vsp_idx += i32 1;
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_h_sub_ii () : top_decl =
  FuncDecl {
    attrs = [StaticFn];
    ret_type = Void;
    name = "h_sub_ii";
    params = vm_handler_params;
    body = [
      let_u64 "a" (cast UInt64 (call "fetch_i64" [var "vm"; var "bytecode"; var "vip"]));
      let_u64 "b" (cast UInt64 (call "fetch_i64" [var "vm"; var "bytecode"; var "vip"]));
      let_u64 "res" (var "a" -~ var "b");
      vm_zf := cast UInt8 (var "res" ==~ u64 0L);
      vm_sf := cast UInt8 (cast Int64 (var "res") <~ i64 0L);
      vm_cf := cast UInt8 (var "a" <~ var "b");
      vm_of := cast UInt8 ((((var "a" ^~ var "b") &~ (var "a" ^~ var "res")) >>~ i32 63) &~ u64 1L);
      vm_pf := call "parity8" [var "res"];
      if_then_else (vm_vsp_idx <~ i32 4096)
        [
          idx vm_vsp vm_vsp_idx := vsp_encode vm_vsp_idx (var "res");
          vm_vsp_idx += i32 1;
        ]
        [
          vm_halted := i32 1;
        ];
    ];
  }

let emit_superop_handlers () : top_decl list = [
  emit_h_cmp ();
  emit_h_test ();
  emit_h_add_imm ();
  emit_h_sub_imm ();
  emit_h_add_ii ();
  emit_h_sub_ii ();
]

let emit_all_stack_manipulation_handlers () : top_decl list =
  emit_push_pop_handlers () @ emit_dup_swap_handlers () @
  emit_mem_handlers () @ emit_alu_handlers () @ emit_flags_handlers () @
  emit_superop_handlers ()

let emit_push_pop_handlers_string () : string =
  render_top_decls (emit_push_pop_handlers ())

let emit_dup_swap_handlers_string () : string =
  render_top_decls (emit_dup_swap_handlers ())

let emit_mem_handlers_string () : string =
  render_top_decls (emit_mem_handlers ())

let emit_alu_handlers_string () : string =
  render_top_decls (emit_alu_handlers ())

let emit_flags_handlers_string () : string =
  render_top_decls (emit_flags_handlers ())

let emit_superop_handlers_string () : string =
  render_top_decls (emit_superop_handlers ())

let emit_all_handlers_string () : string =
  render_top_decls (emit_all_stack_manipulation_handlers ())

let emit_handlers_source buf =
  Buffer.add_string buf (emit_all_handlers_string ())
