open Prims
type bit = Prims.bool
type word64 = bit FStar_Seq_Base.seq
type byte8 = bit FStar_Seq_Base.seq
type byte16 = bit FStar_Seq_Base.seq
type v_instr =
  {
  v_op: byte8 ;
  v_dst: byte8 ;
  v_src1: byte8 ;
  v_src2: byte8 ;
  v_imm: byte16 ;
  v_mask: byte8 ;
  v_junk: byte8 }
let __proj__Mkv_instr__item__v_op (projectee : v_instr) : byte8=
  match projectee with
  | { v_op; v_dst; v_src1; v_src2; v_imm; v_mask; v_junk;_} -> v_op
let __proj__Mkv_instr__item__v_dst (projectee : v_instr) : byte8=
  match projectee with
  | { v_op; v_dst; v_src1; v_src2; v_imm; v_mask; v_junk;_} -> v_dst
let __proj__Mkv_instr__item__v_src1 (projectee : v_instr) : byte8=
  match projectee with
  | { v_op; v_dst; v_src1; v_src2; v_imm; v_mask; v_junk;_} -> v_src1
let __proj__Mkv_instr__item__v_src2 (projectee : v_instr) : byte8=
  match projectee with
  | { v_op; v_dst; v_src1; v_src2; v_imm; v_mask; v_junk;_} -> v_src2
let __proj__Mkv_instr__item__v_imm (projectee : v_instr) : byte16=
  match projectee with
  | { v_op; v_dst; v_src1; v_src2; v_imm; v_mask; v_junk;_} -> v_imm
let __proj__Mkv_instr__item__v_mask (projectee : v_instr) : byte8=
  match projectee with
  | { v_op; v_dst; v_src1; v_src2; v_imm; v_mask; v_junk;_} -> v_mask
let __proj__Mkv_instr__item__v_junk (projectee : v_instr) : byte8=
  match projectee with
  | { v_op; v_dst; v_src1; v_src2; v_imm; v_mask; v_junk;_} -> v_junk
let pack (i : v_instr) : word64=
  let w_tail5 =
    FStar_Seq_Base.append i.v_imm (FStar_Seq_Base.append i.v_mask i.v_junk) in
  let w_tail6 = FStar_Seq_Base.append i.v_src2 w_tail5 in
  let w_tail7 = FStar_Seq_Base.append i.v_src1 w_tail6 in
  let w_tail8 = FStar_Seq_Base.append i.v_dst w_tail7 in
  FStar_Seq_Base.append i.v_op w_tail8
let unpack (w : word64) : v_instr=
  {
    v_op = (FStar_Seq_Base.slice w Prims.int_zero (Prims.of_int 8));
    v_dst = (FStar_Seq_Base.slice w (Prims.of_int 8) (Prims.of_int 16));
    v_src1 = (FStar_Seq_Base.slice w (Prims.of_int 16) (Prims.of_int 24));
    v_src2 = (FStar_Seq_Base.slice w (Prims.of_int 24) (Prims.of_int 32));
    v_imm = (FStar_Seq_Base.slice w (Prims.of_int 32) (Prims.of_int 48));
    v_mask = (FStar_Seq_Base.slice w (Prims.of_int 48) (Prims.of_int 56));
    v_junk = (FStar_Seq_Base.slice w (Prims.of_int 56) (Prims.of_int 64))
  }
let xor_words (w1 : word64) (w2 : word64) : word64=
  FStar_Seq_Base.init_aux (Prims.of_int 64) Prims.int_zero
    (fun idx ->
       (FStar_Seq_Base.index w1 idx) <> (FStar_Seq_Base.index w2 idx))
let encode (i : v_instr) (key : word64) : word64= xor_words (pack i) key
let decode (raw : word64) (key : word64) : v_instr=
  let w = xor_words raw key in unpack w
type parse_result =
  | Parse_Success of v_instr 
  | Parse_Junk of byte8 
  | Parse_Invalid of byte8 
let uu___is_Parse_Success (projectee : parse_result) : Prims.bool=
  match projectee with | Parse_Success _0 -> true | uu___ -> false
let __proj__Parse_Success__item___0 (projectee : parse_result) : v_instr=
  match projectee with | Parse_Success _0 -> _0
let uu___is_Parse_Junk (projectee : parse_result) : Prims.bool=
  match projectee with | Parse_Junk _0 -> true | uu___ -> false
let __proj__Parse_Junk__item___0 (projectee : parse_result) : byte8=
  match projectee with | Parse_Junk _0 -> _0
let uu___is_Parse_Invalid (projectee : parse_result) : Prims.bool=
  match projectee with | Parse_Invalid _0 -> true | uu___ -> false
let __proj__Parse_Invalid__item___0 (projectee : parse_result) : byte8=
  match projectee with | Parse_Invalid _0 -> _0
let parse_word (raw : word64) (key : word64) (is_junk : byte8 -> Prims.bool)
  (is_valid : byte8 -> Prims.bool) : parse_result=
  let insn = decode raw key in
  if is_junk insn.v_op
  then Parse_Junk (insn.v_op)
  else
    if is_valid insn.v_op
    then Parse_Success insn
    else Parse_Invalid (insn.v_op)
