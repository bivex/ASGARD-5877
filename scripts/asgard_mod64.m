function varargout = asgard_mod64(action, varargin)
%ASGARD_MOD64  Exact arithmetic in Z_{2^64} for MATLAB / GNU Octave.
%
%   The ASGARD runtime performs every MBA computation in native OCaml
%   int64, i.e. with two's-complement WRAPAROUND.  MATLAB and Octave
%   SATURATE integer arithmetic instead, so a naive
%   "uint64(a) + uint64(b)" silently breaks the ring semantics:
%
%       uint64(2^64-1) + uint64(5)   ->  0xFFFFFFFFFFFFFFFF  (clamped)
%       the Z_{2^64} answer            ->  0x0000000000000004
%
%   This module implements the ring with an explicit carry chain built
%   from pure bit operations (bitand/bitor/bitxor/bitshift never
%   saturate), plus an INDEPENDENT 16-bit-limb reference used to
%   cross-check the carry chain itself.
%
%   API (dispatcher, all values are uint64 scalars):
%       asgard_mod64('add', a, b)      addition mod 2^64
%       asgard_mod64('mul', a, b)      multiplication mod 2^64
%       asgard_mod64('sub', a, b)      subtraction mod 2^64
%       asgard_mod64('neg', a)         two's complement negation
%       asgard_mod64('not', a)         bitwise complement (NOT)
%       asgard_mod64('xor'|'and'|'or', a, b)
%       asgard_mod64('shl'|'shr', a, n)   logical shifts
%       asgard_mod64('from_hex', s)    16 hex digits -> uint64
%       asgard_mod64('to_hex', v)      uint64 -> 16 hex digits
%       asgard_mod64('to_dec', v)      uint64 -> signed decimal (OCaml-like)
%       asgard_mod64('from_dec', s)    signed decimal string -> uint64
%       asgard_mod64('ref_add'|'ref_mul'|'ref_sub', a, b)  16-bit limb reference
%       asgard_mod64('selfcheck', n)   cross-check both implementations
%
%   Example:
%       a = asgard_mod64('from_hex', 'FFFFFFFFFFFFFFFF');
%       asgard_mod64('to_hex', asgard_mod64('add', a, uint64(5)))  % 0000000000000004

  switch lower(action)
    case 'add'
      varargout{1} = u64_add(varargin{1}, varargin{2});
    case 'mul'
      varargout{1} = u64_mul(varargin{1}, varargin{2});
    case 'sub'
      varargout{1} = u64_sub(varargin{1}, varargin{2});
    case 'neg'
      varargout{1} = u64_neg(varargin{1});
    case 'not'
      % bitwise complement (all ones minus the value)
      varargout{1} = bitxor(varargin{1}, u64_mask());
    case 'xor'
      varargout{1} = bitxor(varargin{1}, varargin{2});
    case 'and'
      varargout{1} = bitand(varargin{1}, varargin{2});
    case 'or'
      varargout{1} = bitor(varargin{1}, varargin{2});
    case 'shl'
      varargout{1} = bitshift(varargin{1}, varargin{2});
    case 'shr'
      varargout{1} = bitshift(varargin{1}, -varargin{2});
    case 'from_hex'
      varargout{1} = u64_from_hex(varargin{1});
    case 'to_hex'
      varargout{1} = u64_to_hex(varargin{1});
    case 'to_dec'
      varargout{1} = u64_to_i64_dec(varargin{1});
    case 'from_dec'
      varargout{1} = u64_from_dec(varargin{1});
    case 'ref_add'
      varargout{1} = ref_add64(varargin{1}, varargin{2});
    case 'ref_mul'
      varargout{1} = ref_mul64(varargin{1}, varargin{2});
    case 'ref_sub'
      varargout{1} = ref_sub64(varargin{1}, varargin{2});
    case 'selfcheck'
      varargout{1} = selfcheck(varargin{1});
    otherwise
      error('asgard_mod64: unknown action %S', action);
  end
end

% =========================================================================
%  Z_{2^64} RING PRIMITIVES  (pure bit operations, no saturation)
% =========================================================================

function r = u64_add(a, b)
  % Exact addition mod 2^64 via an explicit carry chain over 32-bit halves.
  mask32 = uint64(4294967295);
  lo_a = bitand(a, mask32);
  lo_b = bitand(b, mask32);
  hi_a = bitshift(a, -32);
  hi_b = bitshift(b, -32);
  lo_sum = lo_a + lo_b;               % < 2^33, far below intmax('uint64')
  carry = bitshift(lo_sum, -32);     % 0 or 1
  lo = bitand(lo_sum, mask32);
  hi_sum = hi_a + hi_b + carry;      % < 2^33
  hi = bitand(hi_sum, mask32);
  r = bitor(bitshift(hi, 32), lo);
end

function r = u64_mul(a, b)
  % Exact multiplication mod 2^64 (schoolbook over 32-bit halves).
  % (a_hi*2^32 + a_lo)(b_hi*2^32 + b_lo) = a_lo*b_lo
  %   + (a_lo*b_hi + a_hi*b_lo)*2^32 + a_hi*b_hi*2^64, and the last term
  %   vanishes mod 2^64 by construction.
  mask32 = uint64(4294967295);
  lo_a = bitand(a, mask32);
  lo_b = bitand(b, mask32);
  hi_a = bitshift(a, -32);
  hi_b = bitshift(b, -32);
  t = lo_a * lo_b;                   % < 2^64
  c1 = hi_a * lo_b;                  % < 2^64
  c2 = lo_a * hi_b;                  % < 2^64
  cross = bitand(u64_add(c1, c2), mask32);
  r = u64_add(t, bitshift(cross, 32));
end

function r = u64_neg(a)
  r = u64_add(bitxor(a, u64_mask()), uint64(1));
end

function r = u64_sub(a, b)
  r = u64_add(a, u64_neg(b));
end

function m = u64_mask()
  m = uint64(18446744073709551615);
end

function v = u64_from_hex(s)
  % 64-bit constant from a hex string (exact: hex2dec is exact for 8 digits).
  s = upper(strtrim(s));
  if numel(s) > 16
    error('asgard_mod64: more than 16 hex digits');
  end
  s = [repmat('0', 1, 16 - numel(s)) s];
  hi = hex2dec(s(1:8));
  lo = hex2dec(s(9:16));
  v = bitor(bitshift(uint64(hi), 32), uint64(lo));
end

function s = u64_to_hex(v)
  % Exact hexadecimal rendering (dec2hex is avoided: it is lossy above 2^53
  % and refuses uint64 on some engines).
  hi = double(bitshift(v, -32));
  lo = double(bitand(v, uint64(4294967295)));
  s = sprintf('%08x%08x', hi, lo);
end

function s = u64_to_i64_dec(v)
  % Signed decimal rendering of a 64-bit pattern, exactly as OCaml's
  % Int64.to_string prints it (so Int64.of_string parses it back).
  hi = bitshift(v, -32);
  lo = bitand(v, uint64(4294967295));
  if hi < uint64(2147483648)
    s = u64_dec_magnitude(hi, lo);
  else
    [mhi, mlo] = u64_dec_complement(hi, lo);
    s = ['-' u64_dec_magnitude(mhi, mlo)];
  end
end

function [chi, clo] = u64_dec_complement(hi, lo)
  % two's complement of the limb pair (hi:lo) -> (2^64 - value)
  chi = bitxor(uint64(hi), uint64(4294967295));
  clo = bitxor(uint64(lo), uint64(4294967295));
  [chi, clo] = u64_add_limbs(chi, clo, uint64(0), uint64(1));
end

function [chi, clo] = u64_add_limbs(hi, lo, ahi, alo)
  % add two 32-bit limb pairs, keep the low 64 bits
  lo_sum = double(lo) + double(alo);
  carry = floor(lo_sum / 4294967296);
  clo = uint64(mod(lo_sum, 4294967296));
  hi_sum = double(hi) + double(ahi) + carry;
  chi = uint64(mod(hi_sum, 4294967296));
end

function s = u64_dec_magnitude(hi, lo)
  % Exact decimal rendering of a 64-bit magnitude given as 32-bit limbs.
  % Chunks of 10^6 keep every intermediate below 2^53 (exactly
  % representable as a double), so no rounding can occur.
  chunks = {};
  h = double(hi);
  l = double(lo);
  while h > 0 || l > 0
    q_hi = floor(h / 1000000);
    r_hi = h - q_hi * 1000000;
    x = r_hi * 4294967296 + l;        % < 1e6 * 2^32 < 2^53
    q_lo = floor(x / 1000000);
    r_lo = x - q_lo * 1000000;
    chunks{end + 1} = r_lo;
    h = q_hi;
    l = q_lo;
  end
  if isempty(chunks)
    s = '0';
    return;
  end
  s = sprintf('%d', chunks{end});
  for i = numel(chunks) - 1:-1:1
    s = [s sprintf('%06d', chunks{i})];
  end
end


function v = u64_from_dec(s)
  % Exact parsing of a signed decimal string into a uint64 (mod 2^64).
  % str2double would lose everything above 2^53, so the digits are
  % accumulated in base 10^6 chunks with the ring multiplication.
  s = strtrim(char(s));
  neg = false;
  if ~isempty(s) && (s(1) == '-' || s(1) == '+')
    neg = (s(1) == '-');
    s = s(2:end);
  end
  s = s(s >= '0' & s <= '9');
  if isempty(s)
    v = uint64(0);
    return;
  end
  v = uint64(0);
  base = uint64(1000000);
  n = numel(s);
  first = mod(n, 6);
  if first == 0, first = 6; end
  pos = 1;
  while pos <= n
    len = 6;
    if pos == 1, len = first; end
    chunk = str2double(s(pos:pos + len - 1));
    v = asgard_mod64('add', asgard_mod64('mul', v, base), uint64(chunk));
    pos = pos + len;
  end
  if neg
    v = u64_neg(v);
  end
end

% =========================================================================
%  INDEPENDENT REFERENCE (16-bit limbs, exact double arithmetic)
% =========================================================================

function v = ref_add64(a, b)
  ah = u64_limbs16(a);
  bh = u64_limbs16(b);
  r = zeros(1, 4);
  carry = 0;
  for i = 4:-1:1
    t = ah(i) + bh(i) + carry;
    r(i) = mod(t, 65536);
    carry = floor(t / 65536);
  end
  v = u64_from_limbs16(r);
end

function v = ref_sub64(a, b)
  ah = u64_limbs16(a);
  bh = u64_limbs16(b);
  r = zeros(1, 4);
  borrow = 0;
  for i = 4:-1:1
    t = ah(i) - bh(i) - borrow;
    if t < 0
      t = t + 65536;
      borrow = 1;
    else
      borrow = 0;
    end
    r(i) = t;
  end
  v = u64_from_limbs16(r);
end

function v = ref_mul64(a, b)
  ah = u64_limbs16(a);
  bh = u64_limbs16(b);
  r = zeros(1, 8);
  for i = 1:4
    for j = 1:4
      r(i + j) += ah(i) * bh(j);
    end
  end
  carry = 0;
  for i = 8:-1:1
    t = r(i) + carry;
    r(i) = mod(t, 65536);
    carry = floor(t / 65536);
  end
  v = u64_from_limbs16(r(5:8));
end

function limbs = u64_limbs16(v)
  limbs = [mod(double(bitand(bitshift(v, -48), uint64(65535))), 65536), ...
           mod(double(bitand(bitshift(v, -32), uint64(65535))), 65536), ...
           mod(double(bitand(bitshift(v, -16), uint64(65535))), 65536), ...
           mod(double(bitand(v, uint64(65535))), 65536)];
end

function v = u64_from_limbs16(limbs)
  v = bitor(bitor(bitshift(uint64(limbs(1)), 48), bitshift(uint64(limbs(2)), 32)), ...
            bitor(bitshift(uint64(limbs(3)), 16), uint64(limbs(4))));
end

function report = selfcheck(n)
  % Cross-check the carry chain against the independent limb reference.
  if nargin < 1, n = 500; end
  bad = 0;
  seed = u64_from_hex('9E3779B97F4A7C15');
  for i = 0:(n - 1)
    x = splitmix(seed, 2 * i);
    y = splitmix(seed, 2 * i + 1);
    if u64_add(x, y) ~= ref_add64(x, y), bad = bad + 1; end
    if u64_mul(x, y) ~= ref_mul64(x, y), bad = bad + 1; end
    if u64_sub(x, y) ~= ref_sub64(x, y), bad = bad + 1; end
  end
  report = struct('checks', 3 * n, 'failures', bad);
end

function v = splitmix(seed, idx)
  golden = u64_from_hex('9E3779B97F4A7C15');
  mix1 = u64_from_hex('BF58476D1CE4E5B9');
  mix2 = u64_from_hex('94D049BB133111EB');
  st = u64_add(seed, u64_mul(uint64(idx), golden));
  z = st;
  z = u64_mul(bitxor(z, bitshift(z, -30)), mix1);
  z = u64_mul(bitxor(z, bitshift(z, -27)), mix2);
  v = bitxor(z, bitshift(z, -31));
end
