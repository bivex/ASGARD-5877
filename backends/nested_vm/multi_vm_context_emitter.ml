(** Multi_vm_context_emitter — Typed C++ AST code generation for Multi-VM contexts and bridges. *)

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

let emit_math_vm_context () : top_decl =
  struct_def "MathVMContext" [
    member_field (Array (UInt64, 32)) "gprs";
    member_field UInt64 "vip";
    member_field (Array (UInt64, 4)) "rns_slots";
    member_field UInt64 "trace_digest";
    member_method ~attrs:[AlwaysInline] Void "init"
      [(UInt64, "init_digest")]
      [
        expr_stmt (call "memset" [var "this"; i32 0; call "sizeof" [deref (var "this")]]);
        var "trace_digest" := var "init_digest";
      ];
  ]

let emit_flow_vm_context () : top_decl =
  struct_def "FlowVMContext" [
    member_field (Array (UInt64, 64)) "vstack";
    member_field UInt64 "vsp";
    member_field UInt64 "vip";
    member_field UInt64 "state_var";
    member_field UInt64 "trace_digest";
    member_method ~attrs:[AlwaysInline] Void "init"
      [(UInt64, "init_digest")]
      [
        expr_stmt (call "memset" [var "this"; i32 0; call "sizeof" [deref (var "this")]]);
        var "trace_digest" := var "init_digest";
      ];
  ]

let emit_shared_vm_context () : top_decl =
  union_def "SharedVMContext" [
    member_field (StructType "MathVMContext") "math";
    member_field (StructType "FlowVMContext") "flow";
    member_field (Array (UInt8, 1024)) "raw";
  ]

let emit_bridge_switch_to_flow () : top_decl =
  func_decl
    ~attrs:[StaticFn; AlwaysInline]
    Void
    "bridge_switch_to_flow"
    [(Ref (StructType "SharedVMContext"), "ctx")]
    [
      let_u64 "cur_digest" (var "ctx" $. "math" $. "trace_digest");
      decl_var (Array (UInt64, 16)) "temp_math_regs";
      for_range "i" (i32 0) (i32 16) [
        idx (var "temp_math_regs") (var "i") := idx (var "ctx" $. "math" $. "gprs") (var "i");
      ];
      expr_stmt (call "ctx.flow.init" [var "cur_digest"]);
      expr_stmt (call "in_place_morph_math_to_flow" [
        var "temp_math_regs";
        var "ctx" $. "flow" $. "vstack";
        var "cur_digest";
      ]);
    ]

let emit_bridge_switch_to_math () : top_decl =
  func_decl
    ~attrs:[StaticFn; AlwaysInline]
    Void
    "bridge_switch_to_math"
    [(Ref (StructType "SharedVMContext"), "ctx")]
    [
      let_u64 "cur_digest" (var "ctx" $. "flow" $. "trace_digest");
      decl_var (Array (UInt64, 16)) "temp_flow_stack";
      for_range "i" (i32 0) (i32 16) [
        idx (var "temp_flow_stack") (var "i") := idx (var "ctx" $. "flow" $. "vstack") (var "i");
      ];
      expr_stmt (call "ctx.math.init" [var "cur_digest"]);
      expr_stmt (call "in_place_morph_flow_to_math" [
        var "temp_flow_stack";
        var "ctx" $. "math" $. "gprs";
        var "cur_digest";
      ]);
    ]


let emit_nested_dispatch_table () : top_decl =
  let elements =
    Array.to_list (Array.map (fun v -> LitInt v) Nested_stack.a004001_table)
  in
  global_var ~is_static:true ~is_const:true
    (Array (UInt16, 256))
    "g_nested_dispatch_a004001"
    ~init:(init_list elements)

let emit_nested_tier_of_step () : top_decl =
  func_decl
    ~attrs:[StaticFn; AlwaysInline]
    UInt32
    "nested_tier_of_step"
    [(UInt32, "step"); (UInt32, "depth")]
    [
      if_then_else (var "depth" <=~ u32 1l)
        [ ret (u32 0l) ]
        [
          let_u32 "idx" (var "step" %~ u32 256l);
          let_u32 "term" (cast UInt32 (idx (var "g_nested_dispatch_a004001") (var "idx")));
          ret (var "term" %~ var "depth");
        ];
    ]

let emit_nested_topology_salt () : top_decl =
  global_var ~is_static:true ~is_const:true
    UInt64
    "g_nested_topology_salt"
    ~init:(u64 Random_visa_constants.Magic_numbers.nested_topology_salt)

let emit_nested_topology_digest () : top_decl =
  func_decl
    ~attrs:[StaticFn; AlwaysInline]
    UInt64
    "nested_topology_digest"
    [(UInt32, "matula_num"); (UInt64, "salt")]
    [
      let_u64 "z" ((cast UInt64 (var "matula_num")) ^~ ((var "salt") *~ (u64 Random_visa_constants.Magic_numbers.splitmix64_gamma)));
      var "z" := ((var "z") ^~ ((var "z") >>~ (u64 30L))) *~ (u64 Random_visa_constants.Magic_numbers.splitmix64_mix);
      var "z" := ((var "z") ^~ ((var "z") >>~ (u64 27L))) *~ (u64 0x94D049BB133111EBL);
      ret ((var "z") ^~ ((var "z") >>~ (u64 31L)));
    ]

let emit_nested_stack_decls () : top_decl list = [
  emit_nested_dispatch_table ();
  emit_nested_tier_of_step ();
  emit_nested_topology_salt ();
  emit_nested_topology_digest ();
]
let emit_asgard_multi_vm_namespace () : top_decl =
  Namespace ("asgard_multi_vm", [
    emit_math_vm_context ();
    emit_flow_vm_context ();
    emit_shared_vm_context ();
    emit_bridge_switch_to_flow ();
    emit_bridge_switch_to_math ();
  ] @ emit_nested_stack_decls ())
let emit_asgard_multi_vm_source () : string =
  render_top_decls [emit_asgard_multi_vm_namespace ()]
