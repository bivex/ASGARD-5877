# tools/ida_analyzer — IDA Pro Binary & Obfuscation Analyzer

IDA Pro plugin suite for evaluating binary complexity, control-flow graph (CFG) flattening, indirect branch dispersion, and encrypted bytecode entropy.

Provides two interfaces:
1. **IDAPython Plugin (`asgard_analyzer.py`)**: Ready to run out-of-the-box in IDA Pro 8.x and 9.x GUI or headless batch CLI without compilation.
2. **Native C++ SDK Plugin (`src/asgard_ida_plugin.cpp`)**: High-performance C++17 plugin built against the official IDA 9.x SDK (`/Users/password9090/Desktop/test/ida-sdk`).

---

## 1. Capabilities

* **Control-Flow Graph Complexity**:
  * Calculates cyclomatic complexity $M = E - N + 2P$ across all functions.
  * Discovers central dispatcher hubs by finding basic blocks with peak in-degree (identifying Control-Flow Flattening).
* **Indirect Branch Profiling**:
  * Counts and categorizes direct vs indirect branches (`BR Xn` on ARM64, `jmp [reg]` on x86-64).
  * Computes indirect branch ratio to measure VM interpreter loops and computed goto dispersion.
* **Shannon Entropy Scanner**:
  * Computes byte entropy per segment ($0.0$ to $8.0$).
  * Flags encrypted bytecode payloads ($H > 7.5$) and scrambled constants.
* **Interactive Bytecode Visualizer GUI (`bytecode_gui.py` & `bytecode_decoder.py`)**:
  * Dockable IDA Pro tab (`PluginForm`) built with PySide6.
  * Rolling-key decryption engine reproducing Murmur3 fmix64 non-linear byte-rolling and dynamic SplitMix64 opcode permutation.
  * Interactive instruction table with offset navigation, color-coded branches/calls/exits, and real-time mnemonic filtering.
  * Reconstructed Virtual Basic Block tree with double-click navigation.
  * Direct export of decoded virtual assembly to `.asm` and `.json`.
* **Automated Audit Export**:
  * Generates structured `asgard_ida_audit.json` report.
---

## 2. Usage

### A. Headless Batch Execution (CLI)

Run automated analysis from terminal using IDA's headless runner `idat`:

```bash
# Analyze unprotected binary
"/Applications/IDA Professional 9.3.app/Contents/MacOS/idat" -A \
  -Stools/ida_analyzer/asgard_analyzer.py examples/ida_demo/unprotected_license_checker

# Analyze ASGARD-protected binary
ASGARD_IDA_OUT="protected_audit.json" \
  "/Applications/IDA Professional 9.3.app/Contents/MacOS/idat" -A \
  -Stools/ida_analyzer/asgard_analyzer.py ./protected_arm64_out/protected_app
```

### B. Interactive GUI Mode in IDA Pro

1. Copy the plugin files to your IDA plugins directory:
   ```bash
   cp tools/ida_analyzer/*.py ~/.idapro/plugins/
   ```
2. Open target binary in IDA Pro.
3. Press **`Ctrl+Alt+A`** (or go to **Edit $\to$ Plugins $\to$ ASGARD Binary Analyzer**).
4. The plugin prints the audit report to the **Output Window** and docks the **ASGARD Bytecode Visualizer** GUI tab.
5. Enter the 64-bit rolling seed key (e.g. `0x2ED2232624AED846`), click **Decrypt & Disassemble**, and explore the virtual instructions and basic blocks.

### C. Building Native C++ Plugin (IDA 9.x SDK)

cd tools/ida_analyzer
mkdir build && cd build
cmake -DIDA_SDK_DIR="/Users/password9090/Desktop/test/ida-sdk" ..
make
```
Copy `asgard_ida_plugin.dylib` into the IDA plugins directory.
