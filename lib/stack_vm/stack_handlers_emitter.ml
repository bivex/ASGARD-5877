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

let emit_all_stack_manipulation_handlers () : top_decl list =
  emit_push_pop_handlers () @ emit_dup_swap_handlers ()

let emit_push_pop_handlers_string () : string =
  render_top_decls (emit_push_pop_handlers ())

let emit_dup_swap_handlers_string () : string =
  render_top_decls (emit_dup_swap_handlers ())

let emit_all_handlers_string () : string =
  render_top_decls (emit_all_stack_manipulation_handlers ())

let emit_handlers_source buf =
  Buffer.add_string buf (emit_all_handlers_string ())
