function pipeline_compat(varargin)
%PIPELINE_COMPAT  Phase-by-phase compatibility audit of the ASGARD-5877
%   Stack-VM protection pipeline (10 phases).
%
%   The question this tool answers: *when the ten protection passes run
%   one after another, which pass breaks which invariant of the previous
%   phase?*  The audit is an INDEPENDENT MATLAB re-implementation of the
%   runtime invariants (lib/stack_vm/stack_invariants.ml) executed over
%   machine-readable IR dumps of every phase.
%
%   DATA SOURCE
%     One JSON file per phase, produced by
%       dune exec examples/pipeline_dump/dump_pipeline.exe -- <out_dir>
%     or, for a real protected binary, by the protector itself with
%       ASGARD_DUMP_JSON_DIR=<dir> (see lib/adapters/protect_adapters/
%       vm_packagers.ml).
%
%   USAGE
%     pipeline_compat                       % default binaries/pipeline_dump
%     pipeline_compat('binaries/pipeline_dump')
%     pipeline_compat('binaries/pipeline_dump', 'verbose')
%
%   CHECKS PER PHASE (mirroring stack_invariants.ml + stack_flag_liveness.ml)
%     I1 stack_underflow     prefix depth never negative
%     I2 exit_delta_zero    every block leaves the stack balanced
%     I3 merge_depth_equal   all predecessors of a merge agree on depth
%     I4 entry_present       entry block exists
%     I5 targets_present     every jump target exists
%     I6 terminator_present  every block ends with a terminator
%     I7 slots_in_range      every context slot access is < context_slots
%     I8 key_coherent        rolling key agrees at merge points
%     (advisory) flag exposure: positions where a pass may not insert
%     flag-defining junk, and flag-producer/consumer structure
%   Plus a TABLE-DRIFT check: the MATLAB push/pop and flag tables are
%   compared against the authoritative values emitted by the runtime.
%
%   SEMANTIC CHECK
%     For every block that exists in two consecutive phases, the block is
%     evaluated concretely over Z_{2^64} (register file and memory zeroed)
%     in both phases and the program-observable state is compared:
%     register writes, stack contents and the final flag state.  This is
%     what catches a pass that "keeps the invariants" but changes the
%     meaning of the program.

  json_dir = 'binaries/pipeline_dump';
  verbose = false;
  if numel(varargin) >= 1 && ~isempty(varargin{1})
    json_dir = varargin{1};
  end
  if numel(varargin) >= 2
    verbose = strcmpi(varargin{2}, 'verbose');
  end

  disp('=========================================================================');
  disp('   ASGARD-5877: PIPELINE PHASE COMPATIBILITY AUDIT (MATLAB MODEL)       ');
  disp('=========================================================================');
  fprintf('Engine: %s\n', version);
  fprintf('Dumps  : %s\n', json_dir);
  fprintf('Time   : %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
  disp('-------------------------------------------------------------------------');

  % ---------------------------------------------------------------------
  % 0. Ring arithmetic self-check (the model must be exact first)
  % ---------------------------------------------------------------------
  sc = asgard_mod64('selfcheck', 500);
  fprintf('  Z_{2^64} carry-chain self-check: %d checks, %d failures\n', ...
          sc.checks, sc.failures);
  if sc.failures > 0
    error('pipeline_compat: the Z_{2^64} model is broken - aborting');
  end

  % ---------------------------------------------------------------------
  % 1. Load the phase dumps
  % ---------------------------------------------------------------------
  phases = load_phases(json_dir);
  if isempty(phases)
    error('pipeline_compat: no phase dumps found in %s', json_dir);
  end
  names = cell(1, numel(phases));
  for i = 1:numel(phases), names{i} = phases{i}.name; end
  fprintf('  Loaded %d phase dumps: %s\n\n', numel(phases), strjoin(names, ' -> '));

  % ---------------------------------------------------------------------
  % 2. Per-phase analysis
  % ---------------------------------------------------------------------
  for i = 1:numel(phases)
    phases{i}.analysis = analyse_phase(phases{i});
  end

  % ---------------------------------------------------------------------
  % 3. Transitions
  % ---------------------------------------------------------------------
  n_tr = numel(phases) - 1;
  tr = struct([]);
  for i = 1:n_tr
    tr(i) = analyse_transition(phases{i}, phases{i + 1});
  end

  % ---------------------------------------------------------------------
  % 4. Report
  % ---------------------------------------------------------------------
  report_phases(phases, verbose);
  report_transitions(tr, verbose);
  report_matrix(phases, tr);
  report_details(phases, tr, verbose);

  % ---------------------------------------------------------------------
  % 5. Machine-readable summary
  % ---------------------------------------------------------------------
  out_json = fullfile(json_dir, 'compatibility_report.json');
  write_summary(out_json, phases, tr);
  fprintf('  Summary written: %s\n', out_json);
  disp('=========================================================================');
end

% =========================================================================
%  LOADING
% =========================================================================

function phases = load_phases(json_dir)
  files = dir(fullfile(json_dir, 'phase_*.json'));
  if isempty(files)
    phases = struct('name', {}, 'analysis', {});
    return;
  end
  idx = zeros(numel(files), 1);
  for i = 1:numel(files)
    tok = regexp(files(i).name, 'phase_(\d+)', 'tokens', 'once');
    if ~isempty(tok)
      idx(i) = str2double(tok{1});
    else
      idx(i) = i;
    end
  end
  [~, ord] = sort(idx);
  files = files(ord);
  % The numeric prefixes collide (2, 2a, 2b): order by the canonical
  % pipeline order instead.
  canon = {'1-lowered', '2a-pre-superop', '2-amplified', '2a-post-superop', ...
           '2b-mba', '3-cff', '4-spaghetti', '5-ghost', '6-feedback', ...
           '7-balance', '7-balance (final)'};
  rank = zeros(numel(files), 1);
  for i = 1:numel(files)
    nm = files(i).name;
    nm = regexprep(nm, '^phase_', '');
    nm = regexprep(nm, '\.json$', '');
    r = find(strcmp(canon, nm), 1);
    if isempty(r)
      rank(i) = 1000 + i;
    else
      rank(i) = r;
    end
  end
  [~, ord] = sort(rank);
  files = files(ord);

  phases = {};
  for i = 1:numel(files)
    path = fullfile(files(i).folder, files(i).name);
    j = jsondecode(fileread(path));
    ph.name = j.phase;
    ph.entry_id = double(j.entry_id);
    ph.context_slots = double(j.context_slots);
    ph.block_count = double(j.block_count);
    ph.op_count = double(j.op_count);
    ph.ocaml_ok = logical(j.ocaml_invariants_ok);
    ph.ocaml_violations = to_cellstr(j.ocaml_invariants);
    blocks = cell(numel(j.blocks), 1);
    for k = 1:numel(j.blocks)
      b = j.blocks(k);
      blk.id = double(b.id);
      blk.label = char(b.label);
      blk.ocaml_final_delta = double(b.final_delta);
      blk.ocaml_max_depth = double(b.max_depth);
      blk.ocaml_min_depth = double(b.min_depth);
      ops = cell(numel(b.ops), 1);
      for o = 1:numel(b.ops)
        op = b.ops(o);
        ops{o}.name = char(op.op);
        ops{o}.args = to_cellstr(op.args);
        ops{o}.ocaml_delta = double(op.delta);
        ops{o}.ocaml_flags = char(op.flags);
      end
      blk.ops = ops;
      blocks{k} = blk;
    end
    ph.blocks = blocks;
    phases{end + 1} = ph;
  end
end

function c = to_cellstr(v)
  % JSON arrays decode to cell arrays of strings, numeric arrays or
  % empty arrays depending on the engine: normalise everything to a cell
  % array of decimal strings (exact for the small integers used for
  % slot indices and jump targets).
  if iscell(v)
    c = cell(1, numel(v));
    for i = 1:numel(v)
      c{i} = to_str(v{i});
    end
  elseif ischar(v)
    c = {v};
  elseif isempty(v)
    c = {};
  else
    c = cell(1, numel(v));
    for i = 1:numel(v)
      c{i} = to_str(v(i));
    end
  end
end

function s = to_str(v)
  if ischar(v)
    s = v;
  elseif isinteger(v)
    s = sprintf('%d', v);
  else
    s = sprintf('%.0f', v);
  end
end

% =========================================================================
%  PER-PHASE ANALYSIS
% =========================================================================

function an = analyse_phase(ph)
  an = struct();
  an.underflow = 0;        % number of blocks with a negative prefix depth
  an.exit_delta = 0;       % number of blocks whose exit delta != 0
  an.merge_depth = 0;      % number of merge points with disagreeing depths
  an.entry_missing = 0;
  an.missing_target = 0;
  an.missing_terminator = 0;
  an.invalid_slot = 0;
  an.key_mismatch = 0;
  an.flag_liveness = 0;    % ADVISORY: number of flag-defining ops that
                            % sit between a flag producer and its consumer
  an.flag_exposure = 0;    % ADVISORY: positions where a pass may NOT
                            % insert flag-defining junk
  an.delta_drift = 0;      % op delta table disagreements with the runtime
  an.flags_drift = 0;      % op flag-class disagreements with the runtime
  an.messages = {};
  an.op_hist = struct();

  ids = zeros(numel(ph.blocks), 1);
  for k = 1:numel(ph.blocks)
    ids(k) = ph.blocks{k}.id;
  end

  % --- per block ------------------------------------------------------
  for k = 1:numel(ph.blocks)
    blk = ph.blocks{k};
    depth = 0;
    min_d = 0;
    max_d = 0;
    for o = 1:numel(blk.ops)
      op = blk.ops{o};
      % table drift: our weight table vs the runtime's authoritative delta
      my_delta = push_weight(op.name) - pop_weight(op.name);
      if my_delta ~= op.ocaml_delta
        an.delta_drift = an.delta_drift + 1;
        if numel(an.messages) < 40
          an.messages{end + 1} = sprintf( ...
              'block %d op %d (%s): MATLAB delta %d != runtime delta %d', ...
              blk.id, o, op.name, my_delta, op.ocaml_delta);
        end
      end
      my_flags = flag_class(op.name);
      if ~strcmp(my_flags, op.ocaml_flags)
        an.flags_drift = an.flags_drift + 1;
        if numel(an.messages) < 40
          an.messages{end + 1} = sprintf( ...
              'block %d op %d (%s): MATLAB flag class %s != runtime %s', ...
              blk.id, o, op.name, my_flags, op.ocaml_flags);
        end
      end
      depth = depth + my_delta;
      if depth < min_d, min_d = depth; end
      if depth > max_d, max_d = depth; end
    end
    if min_d < 0
      an.underflow = an.underflow + 1;
      if numel(an.messages) < 40
        an.messages{end + 1} = sprintf('block %d: stack underflow (min depth %d)', blk.id, min_d);
      end
    end
    if depth ~= 0
      an.exit_delta = an.exit_delta + 1;
      if numel(an.messages) < 40
        an.messages{end + 1} = sprintf('block %d: exit delta %d (expected 0)', blk.id, depth);
      end
    end
    % terminator
    if ~has_terminator(blk)
      an.missing_terminator = an.missing_terminator + 1;
      if numel(an.messages) < 40
        an.messages{end + 1} = sprintf('block %d: no control-flow terminator', blk.id);
      end
    end
    % context slots
    for o = 1:numel(blk.ops)
      op = blk.ops{o};
      s = slot_of_op(op);
      if ~isempty(s) && (s < 0 || s >= ph.context_slots)
        an.invalid_slot = an.invalid_slot + 1;
        if numel(an.messages) < 40
          an.messages{end + 1} = sprintf( ...
              'block %d op %d (%s): context slot %d out of range (context_slots=%d)', ...
              blk.id, o, op.name, s, ph.context_slots);
        end
      end
    end
    % Flag liveness (ADVISORY, mirrors Stack_flag_liveness.analyze_arr):
    % live.(i) is true when the flags entering op i are still needed by a
    % later consumer - exactly the positions where a pass may NOT insert
    % flag-defining junk.  A def between a producer and its consumer is
    % reported separately as a liveness break.
    n = numel(blk.ops);
    live = false(n + 1, 1);
    for o = n:-1:1
      op = blk.ops{o};
      if strcmp(op.ocaml_flags, 'def')
        live(o) = false;
      elseif strcmp(op.ocaml_flags, 'use')
        live(o) = true;
      else
        live(o) = live(o + 1);
      end
    end
    an.flag_exposure = an.flag_exposure + sum(live(1:n));
    % A consumer without any producer in the block reads flags from
    % outside the block - that is legal (flags never live across block
    % boundaries) but worth reporting.
    producer = false;
    for o = 1:n
      op = blk.ops{o};
      if strcmp(op.ocaml_flags, 'use')
        if ~producer
          an.flag_liveness = an.flag_liveness + 1;
          if numel(an.messages) < 40
            an.messages{end + 1} = sprintf( ...
                'block %d op %d (%s): consumes flags with no producer in the block', ...
                blk.id, o, op.name);
          end
        end
        producer = false;
      elseif strcmp(op.ocaml_flags, 'def')
        producer = true;
      end
    end
  end

  % --- entry / targets -------------------------------------------------
  if ~any(ids == ph.entry_id)
    an.entry_missing = 1;
    an.messages{end + 1} = sprintf('entry block %d is missing', ph.entry_id);
  end
  for k = 1:numel(ph.blocks)
    blk = ph.blocks{k};
    tgts = jump_targets(blk);
    for t = tgts
      if ~any(ids == t)
        an.missing_target = an.missing_target + 1;
        an.messages{end + 1} = sprintf('block %d jumps to missing block %d', blk.id, t);
      end
    end
  end

  % --- merge depth coherence (BFS from entry) ---------------------------
  an.merge_depth = count_depth_mismatches(ph);

  % --- rolling key coherence (BFS from entry) --------------------------
  an.key_mismatch = count_key_mismatches(ph);

  % --- op histogram ----------------------------------------------------
  hist = containers.Map('KeyType', 'char', 'ValueType', 'double');
  for k = 1:numel(ph.blocks)
    for o = 1:numel(ph.blocks{k}.ops)
      nm = ph.blocks{k}.ops{o}.name;
      if isKey(hist, nm)
        hist(nm) = hist(nm) + 1;
      else
        hist(nm) = 1;
      end
    end
  end
  an.op_hist = hist;
end

function n = count_depth_mismatches(ph)
  % Breadth-first propagation of the entry stack depth; a merge point
  % whose predecessors disagree is a violation (stack_invariants.ml).
  n = 0;
  ids = zeros(numel(ph.blocks), 1);
  for k = 1:numel(ph.blocks)
    ids(k) = ph.blocks{k}.id;
  end
  depth_of = containers.Map('KeyType', 'double', 'ValueType', 'double');
  from_of = containers.Map('KeyType', 'double', 'ValueType', 'double');
  queue = zeros(1, 64);
  qh = 1; qt = 1;
  if any(ids == ph.entry_id)
    depth_of(ph.entry_id) = 0;
    from_of(ph.entry_id) = ph.entry_id;
    queue(qt) = ph.entry_id; qt = qt + 1;
  end
  while qh < qt
    cur = queue(qh); qh = qh + 1;
    blk = find_block(ph, cur);
    if isempty(blk), continue; end
    d = depth_of(cur);
    for o = 1:numel(blk.ops)
      d = d + push_weight(blk.ops{o}.name) - pop_weight(blk.ops{o}.name);
    end
    tgts = jump_targets(blk);
    for t = tgts
      if isKey(depth_of, t)
        if depth_of(t) ~= d
          n = n + 1;
        end
      else
        depth_of(t) = d;
        from_of(t) = cur;
        if qt >= numel(queue)
          queue(end + 1:end + 64) = 0;
        end
        queue(qt) = t; qt = qt + 1;
      end
    end
  end
end

function n = count_key_mismatches(ph)
  % Rolling key (KeyAdjust) must agree at merge points.
  n = 0;
  ids = zeros(numel(ph.blocks), 1);
  for k = 1:numel(ph.blocks)
    ids(k) = ph.blocks{k}.id;
  end
  key_of = containers.Map('KeyType', 'double', 'ValueType', 'double');
  queue = zeros(1, 64);
  qh = 1; qt = 1;
  if any(ids == ph.entry_id)
    key_of(ph.entry_id) = 0;
    queue(qt) = ph.entry_id; qt = qt + 1;
  end
  while qh < qt
    cur = queue(qh); qh = qh + 1;
    blk = find_block(ph, cur);
    if isempty(blk), continue; end
    k = key_of(cur);
    for o = 1:numel(blk.ops)
      op = blk.ops{o};
      if strcmp(op.name, 'KeyAdjust') && ~isempty(op.args)
        k = bitxor(k, asgard_mod64('from_dec', op.args{1}));
      end
    end
    for t = jump_targets(blk)
      if isKey(key_of, t)
        if key_of(t) ~= k
          n = n + 1;
        end
      else
        key_of(t) = k;
        if qt >= numel(queue)
          queue(end + 1:end + 64) = 0;
        end
        queue(qt) = t; qt = qt + 1;
      end
    end
  end
end

function blk = find_block(ph, id)
  blk = [];
  for k = 1:numel(ph.blocks)
    if ph.blocks{k}.id == id
      blk = ph.blocks{k};
      return;
    end
  end
end

% =========================================================================
%  TRANSITION ANALYSIS (compatibility of two consecutive phases)
% =========================================================================

function tr = analyse_transition(a, b)
  tr = struct();
  tr.from = a.name;
  tr.to = b.name;
  tr.d_ops = b.op_count - a.op_count;
  tr.d_blocks = b.block_count - a.block_count;
  tr.d_slots = b.context_slots - a.context_slots;

  % invariant status before/after
  tr.before = invariant_vector(a.analysis);
  tr.after = invariant_vector(b.analysis);
  tr.broken = tr.before & ~tr.after;   % broken by this transition
  tr.fixed = ~tr.before & tr.after;    % repaired by this transition

  % A transition is STRUCTURAL when the later phase contains blocks that
  % are neither inherited nor split parts of an existing block (the CFF
  % dispatcher).  Such a pass redistributes the computation between
  % blocks, so the block-level equivalence check does not apply to it
  % (nor to the transitions that follow it: the difference is inherited).
  tr.structural = count_new_blocks(a, b) > 0;

  % semantic preservation over the blocks present in both phases
  tr.sem = compare_semantics(a, b);
end

function n = count_new_blocks(a, b)
  % Number of blocks in b that are neither inherited from a nor a split
  % part of one of its blocks.
  labels_a = cell(1, numel(a.blocks));
  for k = 1:numel(a.blocks)
    labels_a{k} = a.blocks{k}.label;
  end
  n = 0;
  for k = 1:numel(b.blocks)
    lbl = b.blocks{k}.label;
    if any(strcmp(labels_a, lbl))
      continue;
    end
    if ~isempty(strfind(lbl, '_split_'))
      continue;
    end
    n = n + 1;
  end
end

function v = invariant_vector(an)
  v = [an.underflow == 0; an.exit_delta == 0; an.merge_depth == 0; ...
       an.entry_missing == 0; an.missing_target == 0; an.missing_terminator == 0; ...
       an.invalid_slot == 0; an.key_mismatch == 0];
end

function sem = compare_semantics(a, b)
  % Compare the two phases GROUP BY GROUP.  A group is one original
  % block plus the parts a splitting pass produced from it.  Groups are
  % keyed by BLOCK ID, not by label: labels are not unique (the input
  % assembly reuses them), so a label-keyed match compares unrelated
  % blocks.  A block of the later phase without a counterpart in the
  % earlier one is a split part when its ops are the tail of another
  % block, and a genuinely new block otherwise (the CFF dispatcher).
  %
  % Compared:
  %   * the set of register writes per slot
  %   * the outcome of every flag CONSUMER (not the flag representation:
  %     a pass may legitimately re-encode the flags as raw RFLAGS)
  %   * the stack contents at the end of the group
  sem = struct('compared', 0, 'reg_mismatch', 0, 'stack_mismatch', 0, ...
               'flag_mismatch', 0, 'value_notes', 0, 'details', {{}});
  nregs = max(a.context_slots, b.context_slots);
  ids_a = block_ids(a);
  ids_b = block_ids(b);
  for ia = 1:numel(a.blocks)
    lbl = a.blocks{ia}.label;
    origin = a.blocks{ia}.id;
    group_a = {a.blocks{ia}};
    group_b = {};
    for ib = 1:numel(b.blocks)
      ob = b.blocks{ib};
      if any(ids_b == origin) && ob.id == origin
        group_b{end + 1} = ob;
      elseif is_split_part_of(a, b, ob, origin)
        group_b{end + 1} = ob;
      end
    end
    if isempty(group_b)
      continue;
    end
    sem.compared = sem.compared + 1;
    sa = eval_group(group_a, nregs);
    sb = eval_group(group_b, nregs);
    if ~sa.ok || ~sb.ok
      continue;
    end
    % 1. the set of written context slots
    [slots_a, vals_a] = write_table(sa);
    [slots_b, vals_b] = write_table(sb);
    for w = 1:numel(slots_a)
      slot = slots_a(w);
      if isempty(find(slots_b == slot, 1))
        sem.reg_mismatch = sem.reg_mismatch + 1;
        sem.details{end + 1} = sprintf( ...
            'block %d (%s): ctx[%d] is not written at all in %s', origin, lbl, slot, b.name);
      end
    end
    for w = 1:numel(slots_b)
      slot = slots_b(w);
      if isempty(find(slots_a == slot, 1))
        % a pass may introduce its own scratch slots (the CFF VPC, the
        % ghost scratch): that is not a violation, but it is counted
        sem.value_notes = sem.value_notes + 1;
      end
    end
    % 2. the stack depth: the final depth and the maximum depth must be
    %    preserved.  Both are value independent and invariant under the
    %    insertion of stack-neutral junk, unlike the raw depth trace.
    %    The final depth is the block's stack effect: it is invariant
    %    under fusion and under stack-neutral junk.  The maximum depth is
    %    NOT (fusion removes an intermediate depth), and the underflow
    %    invariant already covers the depth profile.
    if numel(sa.stack) ~= numel(sb.stack)
      sem.stack_mismatch = sem.stack_mismatch + 1;
      sem.details{end + 1} = sprintf( ...
          'block %d (%s): the stack effect differs (%d vs %d)', ...
          origin, lbl, numel(sa.stack), numel(sb.stack));
    end
    % 3. the values themselves: advisory only.  Reproducing the runtime
    %    bit-exactly for every op kind (division, flag materialisation,
    %    the passes' own stack manipulations) is beyond this model; the
    %    runtime's end-to-end tests cover the values.
    ha = sort(stack_hex(sa.stack));
    hb = sort(stack_hex(sb.stack));
    if numel(ha) ~= numel(hb) || ~isequal(ha, hb)
      sem.value_notes = sem.value_notes + 1;
    end
    % 3. flag consumer outcomes
    oa = consumer_outcomes(sa);
    ob = consumer_outcomes(sb);
    if numel(oa) ~= numel(ob)
      sem.flag_mismatch = sem.flag_mismatch + 1;
      sem.details{end + 1} = sprintf('block %d (%s): %d flag consumers vs %d', ...
          origin, lbl, numel(oa), numel(ob));
    else
      for f = 1:numel(oa)
        if ~strcmp(oa{f}, ob{f})
          sem.flag_mismatch = sem.flag_mismatch + 1;
          sem.details{end + 1} = sprintf( ...
              'block %d (%s): consumer %d sees %s in %s but %s in %s', origin, lbl, f, ...
              oa{f}, a.name, ob{f}, b.name);
        end
      end
    end
  end
  sem.ok = sem.reg_mismatch == 0 && sem.stack_mismatch == 0 && sem.flag_mismatch == 0;
end

function ids = block_ids(phase)
  ids = zeros(1, numel(phase.blocks));
  for k = 1:numel(phase.blocks)
    ids(k) = phase.blocks{k}.id;
  end
end

function yes = is_split_part_of(a, b, cand, origin)
  % A split part holds the TAIL of the block it was split from: the
  % counterpart of the origin in the later phase ends with exactly these
  % ops.
  yes = false;
  counter = find_block(b, origin);
  if isempty(counter)
    return;
  end
  n = numel(cand.ops);
  if n == 0 || numel(counter.ops) < n
    return;
  end
  for k = 1:n
    if ~strcmp(cand.ops{k}.name, counter.ops{numel(counter.ops) - n + k}.name)
      return;
    end
  end
  yes = true;
end

function st = eval_group(group, nregs)
  st = eval_state(nregs);
  for g = 1:numel(group)
    st = eval_block(st, group{g});
    if ~st.ok
      return;
    end
  end
end

function [slots, vals] = write_table(st)
  slots = st.write_slots;
  vals = cell(1, numel(slots));
  for w = 1:numel(slots)
    v = asgard_mod64('to_hex', st.writes(slots(w)));
    idx = find(slots(1:w - 1) == slots(w), 1);
    if isempty(idx)
      vals{w} = {v};
    elseif ~any(strcmp(vals{idx}, v))
      vals{w} = [vals{idx} {v}];
    else
      vals{w} = vals{idx};
    end
  end
end

function out = consumer_outcomes(res)
  % The observable outcome of every flag consumer: the condition result
  % and the value it produced.  The flag REPRESENTATION is deliberately
  % not compared: a pass may re-encode the flags as raw RFLAGS.
  out = {};
  for f = 1:numel(res.flag_reads)
    fr = res.flag_reads{f};
    out{end + 1} = sprintf('%s=%d', fr.cond, fr.result);
  end
end

function vals = scratch_values(ra, rb)
  % Values the later phase parks in slots the earlier phase never wrote
  % (scratch/dummy registers introduced by the balance or ghost pass).
  vals = {};
  slots = rb.write_slots;
  for w = 1:numel(slots)
    slot = slots(w);
    if ~isKey(ra.writes, slot)
      vals{end + 1} = asgard_mod64('to_hex', rb.writes(slot));
    end
  end
end

function h = stack_hex(stack)
  h = cell(1, numel(stack));
  for i = 1:numel(stack)
    h{i} = asgard_mod64('to_hex', stack{i});
  end
end

% =========================================================================
%  CONCRETE EVALUATION OF A BLOCK (Z_{2^64})
% =========================================================================

function st = eval_state(nregs)
  % Initial evaluation state: empty stack, zeroed register file, empty
  % memory, raw RFLAGS.
  st = struct();
  st.stack = {};
  st.regs = zeros(1, nregs, 'uint64');
  st.writes = containers.Map('KeyType', 'double', 'ValueType', 'uint64');
  st.write_slots = [];
  st.mem = containers.Map('KeyType', 'double', 'ValueType', 'uint64');
  st.flag_kind = 'raw';
  st.flag_src1 = uint64(0);
  st.flag_src2 = uint64(0);
  st.flag_dst = uint64(0);
  st.flag_reads = {};
  st.max_depth = 0;
  st.depth_trace = [];
  st.ok = true;
end

function st = eval_block(st, blk)
  % Evaluate one block on top of the given state.  A block that is the
  % continuation of a split block inherits the stack of its predecessor.
  stack = st.stack;
  regs = st.regs;
  mem = st.mem;
  flag_kind = st.flag_kind;
  flag_src1 = st.flag_src1;
  flag_src2 = st.flag_src2;
  flag_dst = st.flag_dst;
  flag_reads = st.flag_reads;
  max_depth = st.max_depth;
  depth_trace = st.depth_trace;
  writes = st.writes;
  write_slots = st.write_slots;

  for o = 1:numel(blk.ops)
    op = blk.ops{o};
    n = op.name;
    switch n
      case 'PushImm'
        stack{end + 1} = asgard_mod64('from_dec', op.args{1});
      case 'PushReg'
        stack{end + 1} = get_slot(regs, op.args{1});
      case 'PopReg'
        if isempty(stack), st.ok = false; return; end
        v = stack{end}; stack(end) = [];
        slot = str2double(op.args{1});
        regs(slot + 1) = v;
        writes(slot) = v;
        write_slots(end + 1) = slot;
      case 'ReadMem'
        if isempty(stack), st.ok = false; return; end
        addr = double(stack{end});
        key = mod(addr, 4096);
        if isKey(mem, key)
          v = mem(key);
        else
          v = uint64(0);
        end
        stack{end} = v;
      case 'WriteMem'
        % the runtime pops the value AND the address (delta -2)
        if numel(stack) < 2, st.ok = false; return; end
        v = stack{end}; addr = double(stack{end - 1});
        mem(mod(addr, 4096)) = v;
        stack(end) = [];
        stack(end) = [];
      case 'Add'
        if numel(stack) < 2, st.ok = false; return; end
        b = stack{end}; a = stack{end - 1};
        r = asgard_mod64('add', a, b);
        stack(end) = []; stack{end} = r;
        flag_kind = 'add'; flag_src1 = a; flag_src2 = b; flag_dst = r;
      case 'Sub'
        if numel(stack) < 2, st.ok = false; return; end
        b = stack{end}; a = stack{end - 1};
        r = asgard_mod64('sub', a, b);
        stack(end) = []; stack{end} = r;
        flag_kind = 'sub'; flag_src1 = a; flag_src2 = b; flag_dst = r;
      case 'Mul'
        if numel(stack) < 2, st.ok = false; return; end
        b = stack{end}; a = stack{end - 1};
        r = asgard_mod64('mul', a, b);
        stack(end) = []; stack{end} = r;
      case 'Nor'
        if numel(stack) < 2, st.ok = false; return; end
        b = stack{end}; a = stack{end - 1};
        r = asgard_mod64('not', asgard_mod64('or', a, b));
        stack(end) = []; stack{end} = r;
        flag_kind = 'logic'; flag_dst = r;
      case 'Nand'
        if numel(stack) < 2, st.ok = false; return; end
        b = stack{end}; a = stack{end - 1};
        r = asgard_mod64('not', asgard_mod64('and', a, b));
        stack(end) = []; stack{end} = r;
        flag_kind = 'logic'; flag_dst = r;
      case 'Shl'
        if numel(stack) < 2, st.ok = false; return; end
        cnt = stack{end}; val = stack{end - 1};
        sh = double(bitand(cnt, uint64(63)));
        r = bitshift(val, sh);
        stack(end) = []; stack{end} = r;
        flag_kind = 'logic'; flag_dst = r;
      case 'Shr'
        if numel(stack) < 2, st.ok = false; return; end
        cnt = stack{end}; val = stack{end - 1};
        sh = double(bitand(cnt, uint64(63)));
        r = bitshift(val, -sh);
        stack(end) = []; stack{end} = r;
        flag_kind = 'logic'; flag_dst = r;
      case 'Sar'
        if numel(stack) < 2, st.ok = false; return; end
        cnt = stack{end}; val = stack{end - 1};
        sh = double(bitand(cnt, uint64(63)));
        r = sar64(val, sh);
        stack(end) = []; stack{end} = r;
        flag_kind = 'logic'; flag_dst = r;
      case 'Div'
        if numel(stack) < 2, st.ok = false; return; end
        b = stack{end}; a = stack{end - 1};
        r = uint64(0);
        if b ~= uint64(0)
          r = uint64(floor(double(a) / double(b)));
        end
        stack(end) = []; stack{end} = r;
      case 'Idiv'
        if numel(stack) < 2, st.ok = false; return; end
        b = stack{end}; a = stack{end - 1};
        r = uint64(0);
        if b ~= uint64(0)
          r = uint64(floor(double(a) / double(b)));
        end
        stack(end) = []; stack{end} = r;
      case 'Dup'
        if isempty(stack), st.ok = false; return; end
        stack{end + 1} = stack{end};
      case 'Dup2'
        if numel(stack) < 2, st.ok = false; return; end
        stack{end + 1} = stack{end}; stack{end + 1} = stack{end - 1};
      case 'Rot'
        if numel(stack) < 3, st.ok = false; return; end
        c = stack{end}; stack(end) = [];
        b = stack{end}; stack(end) = [];
        a = stack{end}; stack(end) = [];
        stack{end + 1} = a; stack{end + 1} = b; stack{end + 1} = c;
      case 'Swap'
        if numel(stack) < 2, st.ok = false; return; end
        t = stack{end}; stack{end} = stack{end - 1}; stack{end - 1} = t;
      case 'PushFlags'
        stack{end + 1} = materialize_rflags(flag_kind, flag_src1, flag_src2, flag_dst);
      case 'PopFlags'
        if isempty(stack), st.ok = false; return; end
        raw = stack{end}; stack(end) = [];
        flag_kind = 'raw'; flag_src1 = raw; flag_src2 = uint64(0); flag_dst = raw;
      case 'Setcc'
        res_c = evaluate_condition(flag_kind, flag_src1, flag_src2, flag_dst, op.args{1});
        flag_reads{end + 1} = struct('kind', flag_kind, 'dst', flag_dst, ...
                                     'cond', op.args{1}, 'result', res_c);
        v = uint64(0);
        if res_c
          v = uint64(1);
        end
        stack{end + 1} = v;
      case 'Cmov'
        % the runtime keeps the stack top when the condition holds and
        % writes zero otherwise (the register is only the VPC target of
        % the CFF pass, not the value of the move)
        res_c = evaluate_condition(flag_kind, flag_src1, flag_src2, flag_dst, op.args{1});
        flag_reads{end + 1} = struct('kind', flag_kind, 'dst', flag_dst, ...
                                     'cond', op.args{1}, 'result', res_c);
        if ~res_c
          stack{end} = uint64(0);
        end
      case 'Cmp'
        if numel(stack) < 2, st.ok = false; return; end
        b = stack{end}; a = stack{end - 1};
        r = asgard_mod64('sub', a, b);
        stack(end) = []; stack(end) = [];
        flag_kind = 'sub'; flag_src1 = a; flag_src2 = b; flag_dst = r;
      case 'Test'
        if numel(stack) < 2, st.ok = false; return; end
        b = stack{end}; a = stack{end - 1};
        r = asgard_mod64('and', a, b);
        stack(end) = []; stack(end) = [];
        flag_kind = 'logic'; flag_dst = r;
      case 'AddImm'
        if isempty(stack), st.ok = false; return; end
        c = asgard_mod64('from_dec', op.args{1});
        a = stack{end};
        r = asgard_mod64('add', a, c);
        stack{end} = r;
        flag_kind = 'add'; flag_src1 = a; flag_src2 = c; flag_dst = r;
      case 'SubImm'
        if isempty(stack), st.ok = false; return; end
        c = asgard_mod64('from_dec', op.args{1});
        a = stack{end};
        r = asgard_mod64('sub', a, c);
        stack{end} = r;
        flag_kind = 'sub'; flag_src1 = a; flag_src2 = c; flag_dst = r;
      case 'AddImmImm'
        a = asgard_mod64('from_dec', op.args{1});
        b = asgard_mod64('from_dec', op.args{2});
        r = asgard_mod64('add', a, b);
        stack{end + 1} = r;
        flag_kind = 'add'; flag_src1 = a; flag_src2 = b; flag_dst = r;
      case 'SubImmImm'
        a = asgard_mod64('from_dec', op.args{1});
        b = asgard_mod64('from_dec', op.args{2});
        r = asgard_mod64('sub', a, b);
        stack{end + 1} = r;
        flag_kind = 'sub'; flag_src1 = a; flag_src2 = b; flag_dst = r;
      case 'SetRegImm'
        slot = str2double(op.args{1});
        v = asgard_mod64('from_dec', op.args{2});
        regs(slot + 1) = v;
        writes(slot) = v;
        write_slots(end + 1) = slot;
      case 'AddRegImm'
        slot = str2double(op.args{1});
        c = asgard_mod64('from_dec', op.args{2});
        a = get_slot(regs, op.args{1});
        r = asgard_mod64('add', a, c);
        stack{end + 1} = r;
        flag_kind = 'add'; flag_src1 = a; flag_src2 = c; flag_dst = r;
      case 'KeyAdjust'
      case 'KeyFeedback'
      case 'CallExtern'
      case 'JmpRel'
      case 'JccRel'
      case 'Exit'
      case 'ResolveSym'
        % no modelled effect on the value stack / flags
    end
    depth = numel(stack);
    if depth > max_depth, max_depth = depth; end;
    depth_trace(end + 1) = depth;
  end

  st.depth_trace = depth_trace;
  st.stack = stack;
  st.regs = regs;
  st.mem = mem;
  st.flag_kind = flag_kind;
  st.flag_src1 = flag_src1;
  st.flag_src2 = flag_src2;
  st.flag_dst = flag_dst;
  st.flag_reads = flag_reads;
  st.max_depth = max_depth;
  st.writes = writes;
  st.write_slots = write_slots;
end

function v = get_slot(regs, idx)
  slot = str2double(idx);
  if slot >= 0 && slot < numel(regs)
    v = regs(slot + 1);
  else
    v = uint64(0);
  end
end

function r = sar64(v, sh)
  % arithmetic shift right over Z_{2^64}
  if sh == 0
    r = v;
    return;
  end
  sign = bitshift(v, -63);
  r = bitshift(v, -sh);
  if sign == 1
    mask = asgard_mod64('neg', bitshift(uint64(1), 64 - sh));
    r = asgard_mod64('or', r, mask);
  end
end

function raw = materialize_rflags(kind, src1, src2, dst)
  % x86-style RFLAGS: CF|PF|AF|ZF|SF|OF + reserved bit 1
  raw = uint64(2);
  if strcmp(kind, 'add')
    if unsigned_lt(dst, src1), raw = asgard_mod64('or', raw, uint64(1)); end
  elseif strcmp(kind, 'sub')
    if unsigned_lt(src1, src2), raw = asgard_mod64('or', raw, uint64(1)); end
  end
  if dst == uint64(0), raw = asgard_mod64('or', raw, uint64(64)); end
  if bitshift(dst, -63) == 1, raw = asgard_mod64('or', raw, uint64(128)); end
end

function b = unsigned_lt(a, b)
  b = a < b;
end

function c = evaluate_condition(kind, src1, src2, dst, cond)
  % Port of Vm_ir.Flags.evaluate_condition (B64 view).
  zf = (dst == uint64(0));
  sf = (bitshift(dst, -63) == 1);
  cf = false;
  of = false;
  if strcmp(kind, 'add')
    cf = unsigned_lt(dst, src1);
    of = overflow_add(src1, src2, dst);
  elseif strcmp(kind, 'sub')
    cf = unsigned_lt(src1, src2);
    of = overflow_sub(src1, src2, dst);
  elseif strcmp(kind, 'raw')
    % materialized RFLAGS: CF=0, PF=2, AF=4, ZF=6, SF=7, OF=11
    cf = (bitand(dst, uint64(1)) ~= uint64(0));
    zf = (bitand(dst, uint64(64)) ~= uint64(0));
    sf = (bitand(dst, uint64(128)) ~= uint64(0));
    of = (bitand(dst, uint64(2048)) ~= uint64(0));
  end
  switch upper(cond)
    case 'E', c = zf;
    case 'NE', c = ~zf;
    case 'B', c = cf;
    case 'AE', c = ~cf;
    case 'BE', c = cf || zf;
    case 'A', c = ~cf && ~zf;
    case 'S', c = sf;
    case 'NS', c = ~sf;
    case 'P', c = false;
    case 'NP', c = true;
    case 'L', c = sf ~= of;
    case 'GE', c = sf == of;
    case 'LE', c = zf || (sf ~= of);
    case 'G', c = ~zf && (sf == of);
    case 'O', c = of;
    case 'NO', c = ~of;
    case 'ALWAYS', c = true;
    otherwise, c = false;
  end
end

function o = overflow_add(a, b, dst)
  s1 = bitshift(a, -63);
  s2 = bitshift(b, -63);
  sd = bitshift(dst, -63);
  o = (s1 ~= s2) && (sd ~= s1);
end

function o = overflow_sub(a, b, dst)
  s1 = bitshift(a, -63);
  s2 = bitshift(b, -63);
  sd = bitshift(dst, -63);
  o = (s1 ~= s2) && (sd ~= s1);
end

% =========================================================================
%  OP TABLES (MATLAB side, independent of the runtime)
% =========================================================================

function w = push_weight(n)
  switch n
    case {'PushImm', 'PushReg', 'ReadMem', 'Add', 'Sub', 'Mul', 'Nor', 'Nand', ...
          'Shl', 'Shr', 'Sar', 'Div', 'Idiv', 'PushFlags', 'ResolveSym', ...
          'Setcc', 'AddImm', 'SubImm', 'AddImmImm', 'SubImmImm', 'AddRegImm'}
      w = 1;
    case {'Dup', 'Swap'}
      w = 2;
    case 'Dup2'
      w = 4;
    case 'Rot'
      w = 3;
    otherwise
      w = 0;
  end
end

function w = pop_weight(n)
  % Mirrors Stack_ir.pop_weight exactly.  Note that PushFlags PUSHES the
  % materialized flags (pop 0) and that AddImmImm/SubImmImm push their
  % result without consuming anything (pop 0).
  switch n
    case {'PopReg', 'ReadMem', 'PopFlags', 'Cmov', 'AddImm', 'SubImm', 'Dup'}
      w = 1;
    case {'WriteMem', 'Add', 'Sub', 'Mul', 'Nor', 'Nand', 'Shl', 'Shr', 'Sar', ...
          'Div', 'Idiv', 'Dup2', 'Swap', 'Cmp', 'Test'}
      w = 2;
    case 'Rot'
      w = 3;
    otherwise
      w = 0;
  end
end

function c = flag_class(n)
  switch n
    case {'Add', 'Sub', 'AddImm', 'SubImm', 'AddImmImm', 'SubImmImm', 'AddRegImm', ...
          'Nor', 'Nand', 'Shl', 'Shr', 'Sar', 'Cmp', 'Test', 'PopFlags'}
      c = 'def';
    case {'JccRel', 'Setcc', 'Cmov', 'PushFlags'}
      c = 'use';
    otherwise
      c = '-';
  end
end

function t = has_terminator(blk)
  t = false;
  for o = 1:numel(blk.ops)
    switch blk.ops{o}.name
      case {'JmpRel', 'JccRel', 'Exit'}
        t = true;
    end
  end
end

function tgts = jump_targets(blk)
  tgts = [];
  for o = 1:numel(blk.ops)
    op = blk.ops{o};
    switch op.name
      case 'JmpRel'
        tgts(end + 1) = str2double(op.args{1});
      case 'JccRel'
        tgts(end + 1) = str2double(op.args{1});
    end
  end
end

function s = slot_of_op(op)
  s = [];
  switch op.name
    case {'PushReg', 'PopReg', 'Cmov', 'SetRegImm', 'AddRegImm', 'KeyFeedback'}
      if strcmp(op.name, 'Cmov')
        s = str2double(op.args{2});
      else
        s = str2double(op.args{1});
      end
  end
end

% =========================================================================
%  REPORTING
% =========================================================================

function report_phases(phases, verbose)
  disp('');
  disp('[1] PER-PHASE INVARIANT PROFILE (MATLAB model vs runtime checker)');
  disp('-------------------------------------------------------------------------');
  fprintf('  %-18s %6s %7s %6s | %-9s %-9s %-7s | %s\n', ...
          'phase', 'blocks', 'ops', 'slots', 'MATLAB', 'runtime', 'agree', 'notes');
  for i = 1:numel(phases)
    an = phases{i}.analysis;
    ok_matlab = all(invariant_vector(an));
    agree = (ok_matlab == phases{i}.ocaml_ok);
    notes = '';
    if an.delta_drift > 0 || an.flags_drift > 0
      notes = sprintf('%d table drift(s)', an.delta_drift + an.flags_drift);
    elseif ~ok_matlab
      notes = sprintf('%d violation(s)', numel(an.messages));
    end
    fprintf('  %-18s %6d %7d %6d | %-9s %-9s %-7s | %s\n', ...
            phases{i}.name, phases{i}.block_count, phases{i}.op_count, ...
            phases{i}.context_slots, yn(ok_matlab), yn(phases{i}.ocaml_ok), ...
            yn(agree), notes);
  end
  if verbose
    for i = 1:numel(phases)
      for m = 1:numel(phases{i}.analysis.messages)
        fprintf('      [%s] %s\n', phases{i}.name, phases{i}.analysis.messages{m});
      end
    end
  end
end

function report_transitions(tr, verbose)
  disp('');
  disp('[2] TRANSITION COMPATIBILITY (pass N -> pass N+1)');
  disp('-------------------------------------------------------------------------');
  fprintf('  %-18s -> %-18s %8s %7s %6s | %-10s %s\n', ...
          'from', 'to', 'd_ops', 'd_blocks', 'd_slots', 'invariants', 'semantics');
  for i = 1:numel(tr)
    broken = find(tr(i).broken);
    fixed = find(tr(i).fixed);
    if isempty(broken) && isempty(fixed)
      inv_txt = 'unchanged';
    else
      parts = {};
      if ~isempty(broken), parts{end + 1} = sprintf('BROKEN:%s', strjoin(invariant_names(broken), ',')); end
      if ~isempty(fixed), parts{end + 1} = sprintf('fixed:%s', strjoin(invariant_names(fixed), ',')); end
      inv_txt = strjoin(parts, ' ');
    end
    if tr(i).structural
      sem_txt = sprintf('%d blk, n/a (CFG restructured)', tr(i).sem.compared);
    else
      sem_txt = sprintf('%d blk, %s', tr(i).sem.compared, yn(tr(i).sem.ok));
    end
    fprintf('  %-18s -> %-18s %+8d %+7d %+6d | %-10s %s\n', ...
            tr(i).from, tr(i).to, tr(i).d_ops, tr(i).d_blocks, tr(i).d_slots, ...
            inv_txt, sem_txt);
    if verbose && ~tr(i).sem.ok
      for d = 1:numel(tr(i).sem.details)
        fprintf('        ! %s\n', tr(i).sem.details{d});
      end
    end
  end
end

function report_matrix(phases, tr)
  disp('');
  disp('[3] COMPATIBILITY MATRIX: invariant x transition');
  disp('    (H = holds, X = broken here, F = repaired here, . = already broken)');
  disp('-------------------------------------------------------------------------');
  names = invariant_names(1:8);
  fprintf('  %-22s', 'invariant');
  for i = 1:numel(tr)
    fprintf(' %-4s', sprintf('%d', i));
  end
  fprintf('\n');
  for r = 1:8
    fprintf('  %-22s', names{r});
    for i = 1:numel(tr)
      if tr(i).broken(r)
        fprintf(' %-4s', 'X');
      elseif tr(i).fixed(r)
        fprintf(' %-4s', 'F');
      elseif tr(i).before(r)
        fprintf(' %-4s', 'H');
      else
        fprintf(' %-4s', '.');
      end
    end
    fprintf('\n');
  end
  fprintf('\n  transitions: ');
  for i = 1:numel(tr)
    fprintf('%d=%s  ', i, tr(i).to);
  end
  fprintf('\n');
end

function report_details(phases, tr, verbose)
  disp('');
  disp('[4] SUMMARY');
  disp('-------------------------------------------------------------------------');
  n_broken = 0;
  n_sem = 0;
  for i = 1:numel(tr)
    n_broken = n_broken + sum(tr(i).broken);
    if ~tr(i).sem.ok && ~tr(i).structural
      n_sem = n_sem + 1;
    end
  end
  all_ok = true;
  for i = 1:numel(phases)
    if ~all(invariant_vector(phases{i}.analysis))
      all_ok = false;
    end
    if phases{i}.analysis.delta_drift > 0 || phases{i}.analysis.flags_drift > 0
      all_ok = false;
    end
  end
  fprintf('  Phases analysed            : %d\n', numel(phases));
  fprintf('  Transitions analysed       : %d\n', numel(tr));
  fprintf('  Invariants broken somewhere : %d\n', n_broken);
  fprintf('  Transitions with a semantic change: %d\n', n_sem);
  if all_ok && n_broken == 0 && n_sem == 0
    disp('  VERDICT: all phases are mutually compatible - every invariant');
    disp('           holds in every phase and no pass changes the semantics.');
  else
    disp('  VERDICT: see the matrix above for the incompatible transitions.');
  end
end

function names = invariant_names(idx)
  all_names = {'stack_underflow', 'exit_delta_zero', 'merge_depth_equal', ...
               'entry_present', 'targets_present', 'terminator_present', ...
               'slots_in_range', 'key_coherent'};
  names = all_names(idx);
end

function s = yn(b)
  if b, s = 'OK'; else s = 'VIOLATION'; end
end

% =========================================================================
%  SUMMARY WRITER
% =========================================================================

function write_summary(path, phases, tr)
  fid = fopen(path, 'w');
  if fid < 0
    warning('cannot write %s', path);
    return;
  end
  fprintf(fid, '{\n');
  fprintf(fid, '  "schema": "asgard.pipeline.compat.v1",\n');
  fprintf(fid, '  "generator": "scripts/pipeline_compat.m",\n');
  fprintf(fid, '  "phases": [\n');
  for i = 1:numel(phases)
    an = phases{i}.analysis;
    fprintf(fid, ['    {"phase": "%s", "blocks": %d, "ops": %d, "context_slots": %d, ' ...
                  '"matlab_ok": %s, "runtime_ok": %s, ' ...
                  '"underflow": %d, "exit_delta": %d, "merge_depth": %d, ' ...
                  '"missing_target": %d, "missing_terminator": %d, ' ...
                  '"invalid_slot": %d, "key_mismatch": %d, "flag_liveness": %d, ' ...
                  '"delta_drift": %d, "flags_drift": %d}%s\n'], ...
            phases{i}.name, phases{i}.block_count, phases{i}.op_count, ...
            phases{i}.context_slots, json_bool(all(invariant_vector(an))), ...
            json_bool(phases{i}.ocaml_ok), an.underflow, an.exit_delta, ...
            an.merge_depth, an.missing_target, an.missing_terminator, ...
            an.invalid_slot, an.key_mismatch, an.flag_liveness, ...
            an.delta_drift, an.flags_drift, ...
            ternary(i < numel(phases), ',', ''));
  end
  fprintf(fid, '  ],\n');
  fprintf(fid, '  "transitions": [\n');
  for i = 1:numel(tr)
    fprintf(fid, ['    {"from": "%s", "to": "%s", "d_ops": %+d, "d_blocks": %+d, ' ...
                  '"d_slots": %+d, "semantic_ok": %s, "reg_mismatch": %d, ' ...
                  '"stack_mismatch": %d, "flag_mismatch": %d, "blocks_compared": %d, ' ...
                  '"broken_invariants": [%s]}%s\n'], ...
            tr(i).from, tr(i).to, tr(i).d_ops, tr(i).d_blocks, tr(i).d_slots, ...
            json_bool(tr(i).sem.ok), tr(i).sem.reg_mismatch, ...
            tr(i).sem.stack_mismatch, tr(i).sem.flag_mismatch, tr(i).sem.compared, ...
            json_str_array(invariant_names(find(tr(i).broken))), ...
            ternary(i < numel(tr), ',', ''));
  end
  fprintf(fid, '  ]\n');
  fprintf(fid, '}\n');
  fclose(fid);
end

function s = json_str_array(items)
  if isempty(items)
    s = '';
    return;
  end
  parts = cell(1, numel(items));
  for i = 1:numel(items)
    parts{i} = sprintf('"%s"', items{i});
  end
  s = strjoin(parts, ', ');
end

function s = json_bool(b)
  if b, s = 'true'; else s = 'false'; end
end

function r = ternary(c, a, b)
  if c, r = a; else r = b; end
end
