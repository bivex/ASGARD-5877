(** ASGARD-5877: Tech-2601 (arXiv:2601.10261)
    Implementation of Shadow Unwind Generation, Cryptographic Sealing,
    Stack Rollback Arithmetic, and Exception Dispatch FSM. *)

open Tech_2601_types
open Bytecode_crypto

let default_shadow_alloc = 32
let default_interceptor_symbol = "tech_2601_interceptor"

let generate_shadow_record
    ?(alloc_size = default_shadow_alloc)
    ~interceptor_symbol
    (_meta : original_metadata) : (shadow_unwind_record, tech_2601_error) result =
  let ops = [ AllocStack alloc_size ] in
  match validate_abi_shadow_rules ops with
  | Error err ->
      let msg = match err with
        | UnalignedStackAllocation sz -> Printf.sprintf "Stack alloc %d is not 16-byte aligned" sz
        | ClobberedNonVolatileReg reg -> Printf.sprintf "Shadow unwind clobbered register %s" reg
        | InvalidFrameOffset off -> Printf.sprintf "Invalid frame offset %d" off
        | EmptyUnwindOps -> "Shadow unwind codes list is empty"
      in
      Error (AbiConstraintViolation msg)
  | Ok () ->
      Ok {
        shadow_alloc_size = alloc_size;
        shadow_ops = ops;
        interceptor_symbol;
      }

let compute_stack_rollback_delta (shadow : shadow_unwind_record) : int =
  (* Shadow global unwinding allocated shadow_alloc_size bytes on the stack.
     To restore stack frame layout for genuine VM execution, we reverse this offset. *)
  -shadow.shadow_alloc_size

(* --- Canonical Binary Serialization for Metadata & LSData --- *)

let magic_header = 0x54454348l (* "TECH" *)
let format_version = 1

let write_int32 buf v =
  let b = Bytes.create 4 in
  Bytes.set_int32_le b 0 v;
  Buffer.add_bytes buf b

let write_int64 buf v =
  let b = Bytes.create 8 in
  Bytes.set_int64_le b 0 v;
  Buffer.add_bytes buf b

let write_int16 buf v =
  let b = Bytes.create 2 in
  Bytes.set_uint16_le b 0 v;
  Buffer.add_bytes buf b

let write_string buf s =
  let len = String.length s in
  write_int16 buf len;
  Buffer.add_string buf s

let read_int32 bytes off =
  (Bytes.get_int32_le bytes off, off + 4)

let read_int64 bytes off =
  (Bytes.get_int64_le bytes off, off + 8)

let read_int16 bytes off =
  (Bytes.get_uint16_le bytes off, off + 2)

let read_string bytes off =
  let len, off1 = read_int16 bytes off in
  let s = Bytes.sub_string bytes off1 len in
  (s, off1 + len)

let serialize_unwind_op buf = function
  | AllocStack sz ->
      Buffer.add_char buf '\x01';
      write_int32 buf (Int32.of_int sz)
  | PushReg reg ->
      Buffer.add_char buf '\x02';
      write_string buf reg
  | SetFramePointer (reg, off) ->
      Buffer.add_char buf '\x03';
      write_string buf reg;
      write_int32 buf (Int32.of_int off)
  | SaveReg (reg, off) ->
      Buffer.add_char buf '\x04';
      write_string buf reg;
      write_int32 buf (Int32.of_int off)

let deserialize_unwind_op bytes off =
  let tag = Bytes.get bytes off in
  let off = off + 1 in
  match tag with
  | '\x01' ->
      let sz, off1 = read_int32 bytes off in
      (AllocStack (Int32.to_int sz), off1)
  | '\x02' ->
      let reg, off1 = read_string bytes off in
      (PushReg reg, off1)
  | '\x03' ->
      let reg, off1 = read_string bytes off in
      let off_val, off2 = read_int32 bytes off1 in
      (SetFramePointer (reg, Int32.to_int off_val), off2)
  | '\x04' ->
      let reg, off1 = read_string bytes off in
      let off_val, off2 = read_int32 bytes off1 in
      (SaveReg (reg, Int32.to_int off_val), off2)
  | _ -> failwith "Invalid unwind_op tag"

let serialize_metadata (meta : original_metadata) : bytes =
  let buf = Buffer.create 256 in
  write_int32 buf magic_header;
  write_int16 buf format_version;
  write_string buf meta.func_name;
  write_int64 buf meta.code_start_pc;
  write_int32 buf (Int32.of_int meta.code_size);

  (* Unwind ops *)
  write_int16 buf (List.length meta.unwind_ops);
  List.iter (serialize_unwind_op buf) meta.unwind_ops;

  (* Try scopes *)
  write_int16 buf (List.length meta.lsdata.scopes);
  List.iter (fun sc ->
    write_int32 buf (Int32.of_int sc.scope_id);
    write_int64 buf sc.start_pc;
    write_int64 buf sc.end_pc;
    write_int64 buf sc.landing_pad_pc;
    write_int32 buf sc.catch_type_tag
  ) meta.lsdata.scopes;

  (* Destructors *)
  write_int16 buf (List.length meta.lsdata.dtors);
  List.iter (fun dt ->
    write_int32 buf (Int32.of_int dt.obj_id);
    write_int64 buf dt.live_start_pc;
    write_int64 buf dt.live_end_pc;
    write_int64 buf dt.dtor_pc
  ) meta.lsdata.dtors;

  Buffer.to_bytes buf

let deserialize_metadata (raw : bytes) : (original_metadata, tech_2601_error) result =
  try
    let off = 0 in
    let magic, off = read_int32 raw off in
    if magic <> magic_header then
      Error (DeserializationError "Invalid magic header")
    else
      let ver, off = read_int16 raw off in
      if ver <> format_version then
        Error (DeserializationError "Unsupported format version")
      else
        let func_name, off = read_string raw off in
        let code_start_pc, off = read_int64 raw off in
        let code_size_i32, off = read_int32 raw off in
        let code_size = Int32.to_int code_size_i32 in

        (* Unwind ops *)
        let op_count, off = read_int16 raw off in
        let rec read_ops acc cur_off count =
          if count = 0 then (List.rev acc, cur_off)
          else
            let op, next_off = deserialize_unwind_op raw cur_off in
            read_ops (op :: acc) next_off (count - 1)
        in
        let unwind_ops, off = read_ops [] off op_count in

        (* Try scopes *)
        let scope_count, off = read_int16 raw off in
        let rec read_scopes acc cur_off count =
          if count = 0 then (List.rev acc, cur_off)
          else
            let sc_id, off1 = read_int32 raw cur_off in
            let st_pc, off2 = read_int64 raw off1 in
            let ed_pc, off3 = read_int64 raw off2 in
            let lp_pc, off4 = read_int64 raw off3 in
            let tag, off5 = read_int32 raw off4 in
            let sc = {
              scope_id = Int32.to_int sc_id;
              start_pc = st_pc;
              end_pc = ed_pc;
              landing_pad_pc = lp_pc;
              catch_type_tag = tag;
            } in
            read_scopes (sc :: acc) off5 (count - 1)
        in
        let scopes, off = read_scopes [] off scope_count in

        (* Destructors *)
        let dtor_count, off = read_int16 raw off in
        let rec read_dtors acc cur_off count =
          if count = 0 then (List.rev acc, cur_off)
          else
            let obj_id, off1 = read_int32 raw cur_off in
            let st_pc, off2 = read_int64 raw off1 in
            let ed_pc, off3 = read_int64 raw off2 in
            let dt_pc, off4 = read_int64 raw off3 in
            let dt = {
              obj_id = Int32.to_int obj_id;
              live_start_pc = st_pc;
              live_end_pc = ed_pc;
              dtor_pc = dt_pc;
            } in
            read_dtors (dt :: acc) off4 (count - 1)
        in
        let dtors, _ = read_dtors [] off dtor_count in

        Ok {
          func_name;
          code_start_pc;
          code_size;
          unwind_ops;
          lsdata = { scopes; dtors };
        }
  with exn ->
    Error (DeserializationError (Printexc.to_string exn))

(* --- Cryptographic Encapsulation & Counter Keystream --- *)

let derive_encryption_key ~master_key ~func_name =
  Hmac_sha256.digest ~key:master_key ~data:(Bytes.of_string ("TECH-2601-ENC:" ^ func_name))

let derive_mac_key ~master_key ~func_name =
  Hmac_sha256.digest ~key:master_key ~data:(Bytes.of_string ("TECH-2601-MAC:" ^ func_name))

let xor_keystream ~enc_key plaintext =
  let len = Bytes.length plaintext in
  let out = Bytes.create len in
  let block_count = (len + 31) / 32 in
  let cur_idx = ref 0 in
  for blk = 0 to block_count - 1 do
    let counter_bytes = Bytes.create 4 in
    Bytes.set_int32_le counter_bytes 0 (Int32.of_int blk);
    let key_block = Hmac_sha256.digest ~key:enc_key ~data:counter_bytes in
    let to_copy = min 32 (len - !cur_idx) in
    for i = 0 to to_copy - 1 do
      let p = Char.code (Bytes.get plaintext (!cur_idx + i)) in
      let k = Char.code (Bytes.get key_block i) in
      Bytes.set out (!cur_idx + i) (Char.chr (p lxor k))
    done;
    cur_idx := !cur_idx + to_copy
  done;
  out

let compute_container_mac ~mac_key ~func_name ~code_start_pc ~code_size ~shadow ~ciphertext =
  let buf = Buffer.create (128 + Bytes.length ciphertext) in
  write_string buf func_name;
  write_int64 buf code_start_pc;
  write_int32 buf (Int32.of_int code_size);
  write_int32 buf (Int32.of_int shadow.shadow_alloc_size);
  write_string buf shadow.interceptor_symbol;
  Buffer.add_bytes buf ciphertext;
  Hmac_sha256.digest ~key:mac_key ~data:(Buffer.to_bytes buf)

let seal_metadata
    ~master_key
    ?(alloc_size = default_shadow_alloc)
    ?(interceptor_symbol = default_interceptor_symbol)
    (meta : original_metadata) : protected_container =
  let shadow =
    match generate_shadow_record ~alloc_size ~interceptor_symbol meta with
    | Ok s -> s
    | Error _ ->
        { shadow_alloc_size = alloc_size; shadow_ops = [ AllocStack alloc_size ]; interceptor_symbol }
  in
  let plaintext = serialize_metadata meta in
  let enc_key = derive_encryption_key ~master_key ~func_name:meta.func_name in
  let ciphertext = xor_keystream ~enc_key plaintext in
  let mac_key = derive_mac_key ~master_key ~func_name:meta.func_name in
  let auth_tag = compute_container_mac
    ~mac_key
    ~func_name:meta.func_name
    ~code_start_pc:meta.code_start_pc
    ~code_size:meta.code_size
    ~shadow
    ~ciphertext
  in
  {
    func_name = meta.func_name;
    code_start_pc = meta.code_start_pc;
    code_size = meta.code_size;
    shadow;
    encrypted_metadata_blob = ciphertext;
    auth_tag;
  }

let unseal_metadata
    ~master_key
    (container : protected_container) : (original_metadata, tech_2601_error) result =
  let mac_key = derive_mac_key ~master_key ~func_name:container.func_name in
  let expected_tag = compute_container_mac
    ~mac_key
    ~func_name:container.func_name
    ~code_start_pc:container.code_start_pc
    ~code_size:container.code_size
    ~shadow:container.shadow
    ~ciphertext:container.encrypted_metadata_blob
  in
  if not (Sha256.constant_time_equal expected_tag container.auth_tag) then
    Error TamperDetected
  else
    let enc_key = derive_encryption_key ~master_key ~func_name:container.func_name in
    let decrypted = xor_keystream ~enc_key container.encrypted_metadata_blob in
    deserialize_metadata decrypted

(* --- Exception Handling Resolution FSM (Simulating EHInterceptor) --- *)

let resolve_exception
    (meta : original_metadata)
    ~(throwing_pc : int64)
    ~(exception_type : int32) : (int64 * int64 list, tech_2601_error) result =
  let catch_all_tag = -1l in (* 0xFFFFFFFF *)
  (* Find matching try scopes enclosing throwing_pc *)
  let matching_scopes =
    List.filter (fun sc ->
      throwing_pc >= sc.start_pc && throwing_pc < sc.end_pc &&
      (sc.catch_type_tag = exception_type || sc.catch_type_tag = catch_all_tag)
    ) meta.lsdata.scopes
  in
  match matching_scopes with
  | [] -> Error (ScopeNotFound throwing_pc)
  | _ ->
      (* Pick innermost scope (smallest span) *)
      let best_scope =
        List.fold_left (fun acc sc ->
          let span sc = Int64.sub sc.end_pc sc.start_pc in
          if span sc < span acc then sc else acc
        ) (List.hd matching_scopes) (List.tl matching_scopes)
      in

      (* Collect active destructors between throwing_pc and landing pad *)
      let active_dtors =
        List.filter (fun dt ->
          throwing_pc >= dt.live_start_pc && throwing_pc < dt.live_end_pc
        ) meta.lsdata.dtors
      in

      (* Order dtors in LIFO (reverse construction) order:
         Higher live_start_pc or higher obj_id comes first *)
      let sorted_dtors =
        List.sort (fun a b ->
          let c = compare b.live_start_pc a.live_start_pc in
          if c <> 0 then c else compare b.obj_id a.obj_id
        ) active_dtors
      in
      let dtor_pcs = List.map (fun dt -> dt.dtor_pc) sorted_dtors in
      Ok (best_scope.landing_pad_pc, dtor_pcs)

let runtime_header_source = {cpp|
#ifndef ASGARD_TECH_2601_HPP
#define ASGARD_TECH_2601_HPP

#include <cstdint>
#include <cstddef>
#include <cstring>
#include <vector>
#include <string>
#include <algorithm>

namespace asgard {
namespace tech_2601 {

// Constant-time memory comparison for authentication tag validation
inline bool constant_time_memcmp(const uint8_t* a, const uint8_t* b, size_t len) {
    uint8_t diff = 0;
    for (size_t i = 0; i < len; ++i) {
        diff |= (a[i] ^ b[i]);
    }
    return diff == 0;
}

// In-place secure buffer sanitization (P2-02)
inline void secure_zeroize(void* ptr, size_t len) {
    volatile uint8_t* p = static_cast<volatile uint8_t*>(ptr);
    while (len--) {
        *p++ = 0;
    }
}

inline void secure_zero(void* ptr, size_t len) {
    secure_zeroize(ptr, len);
}

// RFC 6234 SHA-256
class Sha256 {
private:
    uint32_t state[8];
    uint64_t count;
    uint8_t buffer[64];

    static inline uint32_t rotr(uint32_t x, uint32_t n) {
        return (x >> n) | (x << (32 - n));
    }
    static inline uint32_t choose(uint32_t x, uint32_t y, uint32_t z) {
        return (x & y) ^ (~x & z);
    }
    static inline uint32_t majority(uint32_t x, uint32_t y, uint32_t z) {
        return (x & y) ^ (x & z) ^ (y & z);
    }
    static inline uint32_t big_sigma0(uint32_t x) {
        return rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
    }
    static inline uint32_t big_sigma1(uint32_t x) {
        return rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
    }
    static inline uint32_t small_sigma0(uint32_t x) {
        return rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
    }
    static inline uint32_t small_sigma1(uint32_t x) {
        return rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10);
    }

    void transform(const uint8_t block[64]) {
        static const uint32_t K[64] = {
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
            0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
            0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
            0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
            0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
            0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
            0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
            0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
            0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        };

        uint32_t W[64];
        for (int t = 0; t < 16; ++t) {
            W[t] = (static_cast<uint32_t>(block[t * 4]) << 24) |
                   (static_cast<uint32_t>(block[t * 4 + 1]) << 16) |
                   (static_cast<uint32_t>(block[t * 4 + 2]) << 8) |
                   (static_cast<uint32_t>(block[t * 4 + 3]));
        }
        for (int t = 16; t < 64; ++t) {
            W[t] = small_sigma1(W[t - 2]) + W[t - 7] + small_sigma0(W[t - 15]) + W[t - 16];
        }

        uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
        uint32_t e = state[4], f = state[5], g = state[6], h = state[7];

        for (int t = 0; t < 64; ++t) {
            uint32_t T1 = h + big_sigma1(e) + choose(e, f, g) + K[t] + W[t];
            uint32_t T2 = big_sigma0(a) + majority(a, b, c);
            h = g; g = f; f = e; e = d + T1;
            d = c; c = b; b = a; a = T1 + T2;
        }

        state[0] += a; state[1] += b; state[2] += c; state[3] += d;
        state[4] += e; state[5] += f; state[6] += g; state[7] += h;
    }

public:
    Sha256() { reset(); }

    void reset() {
        state[0] = 0x6a09e667; state[1] = 0xbb67ae85;
        state[2] = 0x3c6ef372; state[3] = 0xa54ff53a;
        state[4] = 0x510e527f; state[5] = 0x9b05688c;
        state[6] = 0x1f83d9ab; state[7] = 0x5be0cd19;
        count = 0;
    }

    void update(const uint8_t* data, size_t len) {
        size_t buffer_idx = count % 64;
        count += len;
        for (size_t i = 0; i < len; ++i) {
            buffer[buffer_idx++] = data[i];
            if (buffer_idx == 64) {
                transform(buffer);
                buffer_idx = 0;
            }
        }
    }

    void finalize(uint8_t digest[32]) {
        size_t buffer_idx = count % 64;
        buffer[buffer_idx++] = 0x80;
        if (buffer_idx > 56) {
            while (buffer_idx < 64) buffer[buffer_idx++] = 0x00;
            transform(buffer);
            buffer_idx = 0;
        }
        while (buffer_idx < 56) buffer[buffer_idx++] = 0x00;
        uint64_t bits = count * 8;
        for (int i = 7; i >= 0; --i) {
            buffer[56 + (7 - i)] = static_cast<uint8_t>((bits >> (i * 8)) & 0xFF);
        }
        transform(buffer);

        for (int i = 0; i < 8; ++i) {
            digest[i * 4] = static_cast<uint8_t>((state[i] >> 24) & 0xFF);
            digest[i * 4 + 1] = static_cast<uint8_t>((state[i] >> 16) & 0xFF);
            digest[i * 4 + 2] = static_cast<uint8_t>((state[i] >> 8) & 0xFF);
            digest[i * 4 + 3] = static_cast<uint8_t>(state[i] & 0xFF);
        }
    }

    static void hash(const uint8_t* data, size_t len, uint8_t digest[32]) {
        Sha256 ctx;
        ctx.update(data, len);
        ctx.finalize(digest);
    }
};

// RFC 2104 HMAC-SHA256
class HmacSha256 {
public:
    static void compute(const uint8_t* key, size_t key_len,
                        const uint8_t* data, size_t data_len,
                        uint8_t mac[32]) {
        uint8_t norm_key[64];
        std::memset(norm_key, 0, 64);
        if (key_len > 64) {
            Sha256::hash(key, key_len, norm_key);
        } else {
            std::memcpy(norm_key, key, key_len);
        }

        uint8_t k_ipad[64], k_opad[64];
        for (int i = 0; i < 64; ++i) {
            k_ipad[i] = norm_key[i] ^ 0x36;
            k_opad[i] = norm_key[i] ^ 0x5c;
        }

        uint8_t inner_hash[32];
        Sha256 inner_ctx;
        inner_ctx.update(k_ipad, 64);
        inner_ctx.update(data, data_len);
        inner_ctx.finalize(inner_hash);

        Sha256 outer_ctx;
        outer_ctx.update(k_opad, 64);
        outer_ctx.update(inner_hash, 32);
        outer_ctx.finalize(mac);

        secure_zero(norm_key, 64);
        secure_zero(k_ipad, 64);
        secure_zero(k_opad, 64);
        secure_zero(inner_hash, 32);
    }
};

// --- Tech-2601 Data Structures ---

struct Tech2601TryScope {
    int32_t scope_id;
    uint64_t start_pc;
    uint64_t end_pc;
    uint64_t landing_pad_pc;
    int32_t catch_type_tag;
};

struct Tech2601Destructor {
    int32_t obj_id;
    uint64_t live_start_pc;
    uint64_t live_end_pc;
    uint64_t dtor_pc;
};

struct Tech2601ShadowRecord {
    uint32_t shadow_alloc_size;
    std::string interceptor_symbol;
};

struct Tech2601OriginalMetadata {
    std::string func_name;
    uint64_t code_start_pc;
    uint32_t code_size;
    std::vector<Tech2601TryScope> scopes;
    std::vector<Tech2601Destructor> dtors;

    void secure_wipe() {
        if (!scopes.empty()) {
            secure_zeroize(scopes.data(), scopes.size() * sizeof(Tech2601TryScope));
            scopes.clear();
        }
        if (!dtors.empty()) {
            secure_zeroize(dtors.data(), dtors.size() * sizeof(Tech2601Destructor));
            dtors.clear();
        }
        if (!func_name.empty()) {
            secure_zeroize(&func_name[0], func_name.size());
            func_name.clear();
        }
        code_start_pc = 0;
        code_size = 0;
    }

    ~Tech2601OriginalMetadata() {
        secure_wipe();
    }
};

// Thread-safe shadow stack state (P0-02)
struct ShadowFrame {
    uint64_t func_pc;
    uintptr_t shadow_sp;
    uint32_t shadow_alloc_size;
    uint64_t return_address;
};

class ThreadShadowStack {
private:
    std::vector<ShadowFrame> frames;
public:
    void push(uint64_t func_pc, uintptr_t shadow_sp, uint32_t alloc_size, uint64_t ret_addr) {
        frames.push_back({func_pc, shadow_sp, alloc_size, ret_addr});
    }
    bool pop(ShadowFrame& out) {
        if (frames.empty()) return false;
        out = frames.back();
        frames.pop_back();
        return true;
    }
    const ShadowFrame* top() const {
        if (frames.empty()) return nullptr;
        return &frames.back();
    }
    size_t size() const { return frames.size(); }
    void clear() {
        for (auto& f : frames) {
            secure_zeroize(&f, sizeof(ShadowFrame));
        }
        frames.clear();
    }
    ~ThreadShadowStack() {
        clear();
    }
};

inline ThreadShadowStack& get_tls_shadow_stack() {
    thread_local ThreadShadowStack tls_stack;
    return tls_stack;
}

struct Tech2601ProtectedContainer {
    std::string func_name;
    uint64_t code_start_pc;
    uint32_t code_size;
    Tech2601ShadowRecord shadow;
    std::vector<uint8_t> encrypted_blob;
    uint8_t auth_tag[32];
};

// Stack pointer rollback arithmetic
inline uintptr_t tech_2601_rollback_stack(uintptr_t current_sp, uint32_t shadow_alloc_size) {
    // In downward-growing stack (x86-64/ARM64), global unwind restored frame by adding alloc_size.
    // Rollback subtracts the shadow allocation to return SP to inner frame state.
#if defined(_WIN32) || defined(_WIN64)
    // Windows x64 SEH requires SP to remain 16-byte aligned and within thread stack bounds
    uintptr_t target_sp = current_sp - shadow_alloc_size;
    return target_sp & ~static_cast<uintptr_t>(0xF);
#else
    return current_sp - shadow_alloc_size;
#endif
}

// Stream keystream XOR
inline void xor_keystream(const uint8_t enc_key[32], const uint8_t* in, uint8_t* out, size_t len) {
    size_t block_count = (len + 31) / 32;
    size_t cur = 0;
    for (size_t blk = 0; blk < block_count; ++blk) {
        uint8_t counter[4];
        counter[0] = static_cast<uint8_t>(blk & 0xFF);
        counter[1] = static_cast<uint8_t>((blk >> 8) & 0xFF);
        counter[2] = static_cast<uint8_t>((blk >> 16) & 0xFF);
        counter[3] = static_cast<uint8_t>((blk >> 24) & 0xFF);

        uint8_t key_block[32];
        HmacSha256::compute(enc_key, 32, counter, 4, key_block);

        size_t to_copy = std::min(static_cast<size_t>(32), len - cur);
        for (size_t i = 0; i < to_copy; ++i) {
            out[cur + i] = in[cur + i] ^ key_block[i];
        }
        cur += to_copy;
        secure_zero(key_block, 32);
    }
}

// Compute authentication MAC for container
inline void compute_container_mac(
    const uint8_t mac_key[32],
    const std::string& func_name,
    uint64_t code_start_pc,
    uint32_t code_size,
    const Tech2601ShadowRecord& shadow,
    const uint8_t* ciphertext,
    size_t ciphertext_len,
    uint8_t out_tag[32]
) {
    std::vector<uint8_t> buf;
    // write func_name (len16 + bytes)
    uint16_t name_len = static_cast<uint16_t>(func_name.length());
    buf.push_back(static_cast<uint8_t>(name_len & 0xFF));
    buf.push_back(static_cast<uint8_t>((name_len >> 8) & 0xFF));
    buf.insert(buf.end(), func_name.begin(), func_name.end());

    // write code_start_pc (8 bytes)
    for (int i = 0; i < 8; ++i) {
        buf.push_back(static_cast<uint8_t>((code_start_pc >> (i * 8)) & 0xFF));
    }
    // write code_size (4 bytes)
    for (int i = 0; i < 4; ++i) {
        buf.push_back(static_cast<uint8_t>((code_size >> (i * 8)) & 0xFF));
    }
    // write shadow_alloc_size (4 bytes)
    for (int i = 0; i < 4; ++i) {
        buf.push_back(static_cast<uint8_t>((shadow.shadow_alloc_size >> (i * 8)) & 0xFF));
    }
    // write interceptor_symbol (len16 + bytes)
    uint16_t sym_len = static_cast<uint16_t>(shadow.interceptor_symbol.length());
    buf.push_back(static_cast<uint8_t>(sym_len & 0xFF));
    buf.push_back(static_cast<uint8_t>((sym_len >> 8) & 0xFF));
    buf.insert(buf.end(), shadow.interceptor_symbol.begin(), shadow.interceptor_symbol.end());

    // write ciphertext
    buf.insert(buf.end(), ciphertext, ciphertext + ciphertext_len);

    HmacSha256::compute(mac_key, 32, buf.data(), buf.size(), out_tag);
}

// Unseal and verify container
inline bool tech_2601_unseal(
    const uint8_t* master_key,
    size_t master_key_len,
    const Tech2601ProtectedContainer& container,
    Tech2601OriginalMetadata& out_meta
) {
    // 1. Derive mac key
    std::string mac_label = "TECH-2601-MAC:" + container.func_name;
    uint8_t mac_key[32];
    HmacSha256::compute(master_key, master_key_len,
                        reinterpret_cast<const uint8_t*>(mac_label.data()), mac_label.length(),
                        mac_key);

    // 2. Verify MAC tag
    uint8_t expected_tag[32];
    compute_container_mac(
        mac_key,
        container.func_name,
        container.code_start_pc,
        container.code_size,
        container.shadow,
        container.encrypted_blob.data(),
        container.encrypted_blob.size(),
        expected_tag
    );

    if (!constant_time_memcmp(expected_tag, container.auth_tag, 32)) {
        secure_zero(mac_key, 32);
        return false; // Authentication failed (tamper detected)
    }

    // 3. Derive enc key
    std::string enc_label = "TECH-2601-ENC:" + container.func_name;
    uint8_t enc_key[32];
    HmacSha256::compute(master_key, master_key_len,
                        reinterpret_cast<const uint8_t*>(enc_label.data()), enc_label.length(),
                        enc_key);

    // 4. Decrypt
    std::vector<uint8_t> plaintext(container.encrypted_blob.size());
    xor_keystream(enc_key, container.encrypted_blob.data(), plaintext.data(), plaintext.size());

    secure_zero(mac_key, 32);
    secure_zero(enc_key, 32);

    // 5. Deserialize
    if (plaintext.size() < 18) {
        secure_zero(plaintext.data(), plaintext.size());
        return false;
    }

    size_t off = 0;
    uint32_t magic = plaintext[off] | (plaintext[off+1]<<8) | (plaintext[off+2]<<16) | (plaintext[off+3]<<24);
    off += 4;
    if (magic != 0x54454348) { // "TECH"
        secure_zero(plaintext.data(), plaintext.size());
        return false;
    }
    uint16_t ver = plaintext[off] | (plaintext[off+1]<<8);
    off += 2;
    if (ver != 1) {
        secure_zero(plaintext.data(), plaintext.size());
        return false;
    }

    uint16_t name_len = plaintext[off] | (plaintext[off+1]<<8);
    off += 2;
    std::string fn_name(reinterpret_cast<char*>(&plaintext[off]), name_len);
    off += name_len;

    uint64_t start_pc = 0;
    for (int i = 0; i < 8; ++i) start_pc |= (static_cast<uint64_t>(plaintext[off + i]) << (i * 8));
    off += 8;

    uint32_t code_sz = plaintext[off] | (plaintext[off+1]<<8) | (plaintext[off+2]<<16) | (plaintext[off+3]<<24);
    off += 4;

    // Skip unwind ops in C++ parser for dispatch
    uint16_t op_count = plaintext[off] | (plaintext[off+1]<<8);
    off += 2;
    for (uint16_t i = 0; i < op_count; ++i) {
        uint8_t tag = plaintext[off++];
        if (tag == 1) { off += 4; }
        else if (tag == 2) { uint16_t sl = plaintext[off] | (plaintext[off+1]<<8); off += 2 + sl; }
        else if (tag == 3 || tag == 4) { uint16_t sl = plaintext[off] | (plaintext[off+1]<<8); off += 2 + sl + 4; }
    }

    // Read scopes
    uint16_t scope_count = plaintext[off] | (plaintext[off+1]<<8);
    off += 2;
    std::vector<Tech2601TryScope> scopes;
    for (uint16_t i = 0; i < scope_count; ++i) {
        Tech2601TryScope sc;
        sc.scope_id = static_cast<int32_t>(plaintext[off] | (plaintext[off+1]<<8) | (plaintext[off+2]<<16) | (plaintext[off+3]<<24));
        off += 4;
        sc.start_pc = 0;
        for (int b = 0; b < 8; ++b) sc.start_pc |= (static_cast<uint64_t>(plaintext[off + b]) << (b * 8));
        off += 8;
        sc.end_pc = 0;
        for (int b = 0; b < 8; ++b) sc.end_pc |= (static_cast<uint64_t>(plaintext[off + b]) << (b * 8));
        off += 8;
        sc.landing_pad_pc = 0;
        for (int b = 0; b < 8; ++b) sc.landing_pad_pc |= (static_cast<uint64_t>(plaintext[off + b]) << (b * 8));
        off += 8;
        sc.catch_type_tag = static_cast<int32_t>(plaintext[off] | (plaintext[off+1]<<8) | (plaintext[off+2]<<16) | (plaintext[off+3]<<24));
        off += 4;
        scopes.push_back(sc);
    }

    // Read dtors
    uint16_t dtor_count = plaintext[off] | (plaintext[off+1]<<8);
    off += 2;
    std::vector<Tech2601Destructor> dtors;
    for (uint16_t i = 0; i < dtor_count; ++i) {
        Tech2601Destructor dt;
        dt.obj_id = static_cast<int32_t>(plaintext[off] | (plaintext[off+1]<<8) | (plaintext[off+2]<<16) | (plaintext[off+3]<<24));
        off += 4;
        dt.live_start_pc = 0;
        for (int b = 0; b < 8; ++b) dt.live_start_pc |= (static_cast<uint64_t>(plaintext[off + b]) << (b * 8));
        off += 8;
        dt.live_end_pc = 0;
        for (int b = 0; b < 8; ++b) dt.live_end_pc |= (static_cast<uint64_t>(plaintext[off + b]) << (b * 8));
        off += 8;
        dt.dtor_pc = 0;
        for (int b = 0; b < 8; ++b) dt.dtor_pc |= (static_cast<uint64_t>(plaintext[off + b]) << (b * 8));
        off += 8;
        dtors.push_back(dt);
    }

    out_meta.func_name = fn_name;
    out_meta.code_start_pc = start_pc;
    out_meta.code_size = code_sz;
    out_meta.scopes = scopes;
    out_meta.dtors = dtors;

    secure_zero(plaintext.data(), plaintext.size());
    return true;
}

// Exception Resolution FSM
inline bool tech_2601_resolve_exception(
    const Tech2601OriginalMetadata& meta,
    uint64_t throwing_pc,
    int32_t exception_tag,
    uint64_t* out_landing_pad,
    std::vector<uint64_t>& out_dtors
) {
    const int32_t catch_all_tag = -1;
    const Tech2601TryScope* matched_scope = nullptr;
    uint64_t min_span = UINT64_MAX;

    for (const auto& sc : meta.scopes) {
        if (throwing_pc >= sc.start_pc && throwing_pc < sc.end_pc) {
            if (sc.catch_type_tag == exception_tag || sc.catch_type_tag == catch_all_tag) {
                uint64_t span = sc.end_pc - sc.start_pc;
                if (span < min_span) {
                    min_span = span;
                    matched_scope = &sc;
                }
            }
        }
    }

    if (!matched_scope) return false;
    *out_landing_pad = matched_scope->landing_pad_pc;

    // Collect active destructors
    std::vector<Tech2601Destructor> active_dtors;
    for (const auto& dt : meta.dtors) {
        if (throwing_pc >= dt.live_start_pc && throwing_pc < dt.live_end_pc) {
            active_dtors.push_back(dt);
        }
    }

    // Sort in LIFO order (descending start_pc, then obj_id)
    std::sort(active_dtors.begin(), active_dtors.end(), [](const Tech2601Destructor& a, const Tech2601Destructor& b) {
        if (a.live_start_pc != b.live_start_pc)
            return a.live_start_pc > b.live_start_pc;
        return a.obj_id > b.obj_id;
    });

    out_dtors.clear();
    for (const auto& dt : active_dtors) {
        out_dtors.push_back(dt.dtor_pc);
    }

    return true;
}

} // namespace tech_2601
} // namespace asgard

#endif // ASGARD_TECH_2601_HPP
|cpp}
