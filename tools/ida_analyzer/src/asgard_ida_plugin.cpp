/**
 * asgard_ida_plugin.cpp — Official IDA 9.x C++ SDK Analysis Plugin
 * ─────────────────────────────────────────────────────────────────────────────
 * Native C++17 plugin for IDA Pro 9.x using the modern plugmod_t architecture.
 * Evaluates binary complexity, control-flow graph flattening, indirect branch
 * dispersion, and segment entropy directly through Hex-Rays IDA SDK.
 */

#include <ida.hpp>
#include <idp.hpp>
#include <loader.hpp>
#include <kernwin.hpp>
#include <funcs.hpp>
#include <segment.hpp>
#include <bytes.hpp>
#include <gdl.hpp>
#include <ua.hpp>
#include <allins.hpp>
#include <vector>
#include <cmath>
#include <map>

// Shannon entropy calculation
static double calculate_entropy(const uint8_t *data, size_t size)
{
    if (size == 0)
        return 0.0;

    std::map<uint8_t, size_t> freq;
    for (size_t i = 0; i < size; ++i)
        freq[data[i]]++;

    double entropy = 0.0;
    for (const auto &p : freq)
    {
        double prob = (double)p.second / (double)size;
        entropy -= prob * std::log2(prob);
    }
    return entropy;
}

// Check for indirect branch instructions
static bool is_indirect_branch(const insn_t &insn)
{
    // AArch64: br, blr
    if (ph.id == PLFM_ARM)
    {
        // ARM64 canonical indirect jumps
        if (insn.itype == 0x24 || insn.itype == 0x25) // BR, BLR opcodes
            return true;
    }
    // x86 / x86_64: jmp reg/mem, call reg/mem
    else if (ph.id == PLFM_386)
    {
        if (insn.itype == NN_jmp || insn.itype == NN_jmpni || insn.itype == NN_call || insn.itype == NN_callni)
        {
            if (insn.ops[0].type == o_reg || insn.ops[0].type == o_mem || insn.ops[0].type == o_displ || insn.ops[0].type == o_phrase)
                return true;
        }
    }
    return false;
}

struct asgard_analyzer_mod_t : public plugmod_t
{
    virtual bool idaapi run(size_t arg) override;
};

bool idaapi asgard_analyzer_mod_t::run(size_t)
{
    msg("================================================================================\n");
    msg("  ASGARD BINARY & OBFUSCATION ANALYZER (IDA 9.x Native C++ SDK)\n");
    msg("================================================================================\n");

    // 1. Analyze Segments & Entropy
    size_t n_segs = get_segm_qty();
    msg("[*] Segment Entropy Analysis (%zu segments):\n", n_segs);
    for (size_t i = 0; i < n_segs; ++i)
    {
        segment_t *s = getnseg(i);
        if (!s)
            continue;

        qstring sname;
        get_segm_name(&sname, s);
        asize_t size = s->size();

        std::vector<uint8_t> buffer(size);
        get_bytes(buffer.data(), size, s->start_ea);
        double ent = calculate_entropy(buffer.data(), size);

        msg("    %-18s: start=0x%llx, size=%8llu, H=%6.4f %s\n",
            sname.c_str(), (uint64)s->start_ea, (uint64)size, ent,
            (ent > 7.5 && size > 256) ? "[HIGH ENTROPY / ENCRYPTED PAYLOAD]" : "");
    }

    // 2. Analyze Functions & CFG Complexity
    size_t fn_qty = get_func_qty();
    msg("\n[*] Function CFG & Branch Profile (%zu functions):\n", fn_qty);

    size_t total_insns_binary = 0;
    size_t total_indirect_binary = 0;
    int max_complexity = 0;

    for (size_t i = 0; i < fn_qty; ++i)
    {
        func_t *fn = getn_func(i);
        if (!fn)
            continue;

        qstring fname;
        get_func_name(&fname, fn->start_ea);

        qflow_chart_t fc("", fn, fn->start_ea, fn->end_ea, FC_PREDS);
        int n_blocks = fc.size();
        int n_edges = 0;
        int max_in_deg = 0;
        size_t total_insns = 0;
        size_t indirect_jumps = 0;

        for (int b = 0; b < n_blocks; ++b)
        {
            const qbasic_block_t &bb = fc.blocks[b];
            n_edges += fc.nsucc(b);
            int in_deg = fc.npred(b);
            if (in_deg > max_in_deg)
                max_in_deg = in_deg;

            // Walk instructions in block
            ea_t cur_ea = bb.start_ea;
            insn_t insn;
            while (cur_ea < bb.end_ea)
            {
                int len = decode_insn(&insn, cur_ea);
                if (len <= 0)
                    break;
                total_insns++;
                if (is_indirect_branch(insn))
                    indirect_jumps++;
                cur_ea += len;
            }
        }

        int cyclo = std::max(1, n_edges - n_blocks + 2);
        total_insns_binary += total_insns;
        total_indirect_binary += indirect_jumps;
        if (cyclo > max_complexity)
            max_complexity = cyclo;

        // Print functions with significant complexity or indirect branches
        if (cyclo >= 10 || indirect_jumps >= 1)
        {
            msg("    Function %-32s: blocks=%4d, edges=%4d, M=%4d, max_in_deg=%3d, indir_jmp=%2zu\n",
                fname.c_str(), n_blocks, n_edges, cyclo, max_in_deg, indirect_jumps);
        }
    }

    msg("--------------------------------------------------------------------------------\n");
    msg("SUMMARY: Total Insns=%zu | Total Indirect Jumps=%zu | Peak Cyclomatic M=%d\n",
        total_insns_binary, total_indirect_binary, max_complexity);
    msg("================================================================================\n");

    return true;
}

// Plugin initialization
static plugmod_t *idaapi init()
{
    return new asgard_analyzer_mod_t();
}

static const char comment[] = "ASGARD Binary & Obfuscation Analyzer";
static const char help[] = "Analyzes CFG complexity, indirect branch dispersion, and payload entropy";
static const char wanted_name[] = "ASGARD Binary Analyzer (C++)";
static const char wanted_hotkey[] = "Ctrl-Alt-A";

plugin_t PLUGIN =
{
    IDP_INTERFACE_VERSION,
    PLUGIN_MULTI,
    init,
    nullptr,
    nullptr,
    comment,
    help,
    wanted_name,
    wanted_hotkey
};
