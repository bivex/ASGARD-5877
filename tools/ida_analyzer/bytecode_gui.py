"""
bytecode_gui.py — Interactive IDA Pro GUI for ASGARD Bytecode Visualization
─────────────────────────────────────────────────────────────────────────────
Dockable PluginForm tab inside IDA Pro with PySide6 for interactive
rolling-key decryption, instruction stream inspection, and CFG navigation.
"""

import os
import json
import collections
from typing import Optional, List, Dict, Any

# IDA / PySide imports
try:
    from ida_kernwin import PluginForm, msg, jumpto
    import ida_segment
    import ida_bytes
    import ida_funcs
    import idc
    from PySide6 import QtWidgets, QtCore, QtGui
    HAS_GUI = True
except ImportError:
    HAS_GUI = False

try:
    from bytecode_decoder import StackVmDecoder, OPCODE_SPECS
except ImportError:
    try:
        from tools.ida_analyzer.bytecode_decoder import StackVmDecoder, OPCODE_SPECS
    except ImportError:
        StackVmDecoder = None
        OPCODE_SPECS = []


class AsgardBytecodeForm(PluginForm if HAS_GUI else object):
    """Interactive dockable form for Stack-VM bytecode disassembly."""

    def __init__(self):
        super().__init__()
        self.instructions: List[Dict[str, Any]] = []
        self.filtered_instructions: List[Dict[str, Any]] = []
        self.decoder: Optional[StackVmDecoder] = None

    def OnCreate(self, form):
        if not HAS_GUI:
            return

        # Get parent Qt widget from IDA form
        self.parent = self.FormToPyQtWidget(form)
        self.init_ui()
        self.auto_populate_sources()

    def init_ui(self):
        layout = QtWidgets.QVBoxLayout(self.parent)
        layout.setContentsMargins(8, 8, 8, 8)
        layout.setSpacing(6)

        # ── Top Panel: Compact Controls ───────────────────────────────────────
        top_group = QtWidgets.QGroupBox("ASGARD-5877 Rolling-Key Decryption Controls")
        top_group.setSizePolicy(QtWidgets.QSizePolicy.Preferred, QtWidgets.QSizePolicy.Fixed)
        top_layout = QtWidgets.QVBoxLayout(top_group)
        top_layout.setContentsMargins(10, 8, 10, 8)
        top_layout.setSpacing(6)

        # Row 1: Seed Key & Source File
        row1 = QtWidgets.QHBoxLayout()
        row1.addWidget(QtWidgets.QLabel("<b>Seed Key (Hex):</b>"))
        self.seed_edit = QtWidgets.QLineEdit("0x2ED2232624AED846")
        self.seed_edit.setMaximumWidth(220)
        self.seed_edit.setFont(QtGui.QFont("Menlo", 12))
        row1.addWidget(self.seed_edit)

        row1.addSpacing(15)
        row1.addWidget(QtWidgets.QLabel("<b>Payload File:</b>"))
        self.source_edit = QtWidgets.QLineEdit()
        self.source_edit.setPlaceholderText("Path to protected.vanguard or raw bytecode...")
        self.source_edit.setFont(QtGui.QFont("Menlo", 11))
        row1.addWidget(self.source_edit)

        self.btn_browse = QtWidgets.QPushButton("Browse...")
        self.btn_browse.clicked.connect(self.on_browse)
        row1.addWidget(self.btn_browse)
        top_layout.addLayout(row1)

        # Row 2: Actions & Segments
        row2 = QtWidgets.QHBoxLayout()
        self.btn_autodetect = QtWidgets.QPushButton("Auto-Detect Payload")
        self.btn_autodetect.clicked.connect(self.auto_populate_sources)
        row2.addWidget(self.btn_autodetect)

        self.btn_from_segment = QtWidgets.QPushButton("Extract from Segment (__const)")
        self.btn_from_segment.clicked.connect(self.on_extract_segment)
        row2.addWidget(self.btn_from_segment)

        row2.addStretch()

        self.btn_decode = QtWidgets.QPushButton("  Decrypt & Disassemble  ")
        self.btn_decode.setStyleSheet(
            "font-weight: bold; font-size: 13px; background-color: #1976D2; color: white; padding: 5px 15px; border-radius: 4px;"
        )
        self.btn_decode.clicked.connect(self.on_decode)
        row2.addWidget(self.btn_decode)
        top_layout.addLayout(row2)

        layout.addWidget(top_group)

        # ── Search & Filter Bar ───────────────────────────────────────────────
        filter_layout = QtWidgets.QHBoxLayout()
        filter_layout.addWidget(QtWidgets.QLabel("<b>Search / Filter:</b>"))
        self.filter_edit = QtWidgets.QLineEdit()
        self.filter_edit.setPlaceholderText("Filter by mnemonic (e.g. JccRel, PushImm, Add), handler, operand, or offset...")
        self.filter_edit.textChanged.connect(self.apply_filter)
        filter_layout.addWidget(self.filter_edit)
        layout.addLayout(filter_layout)

        # ── Splitter: Main Instruction Table + Side Tabs ──────────────────────
        splitter = QtWidgets.QSplitter(QtCore.Qt.Horizontal)

        # 1. Main Instruction Table
        self.table = QtWidgets.QTableWidget()
        self.table.setColumnCount(7)
        self.table.setHorizontalHeaderLabels([
            "Offset", "Opcode", "Mnemonic", "Operands", "Delta", "Handler (Jump to IDA)", "Rolling Key"
        ])
        self.table.horizontalHeader().setStretchLastSection(True)
        self.table.setAlternatingRowColors(True)
        self.table.setFont(QtGui.QFont("Menlo", 11))
        self.table.itemDoubleClicked.connect(self.on_table_double_click)
        splitter.addWidget(self.table)

        # 2. Right Side: Tabs for Basic Blocks & Handlers
        side_tabs = QtWidgets.QTabWidget()

        # Tab A: Reconstructed Basic Blocks
        block_panel = QtWidgets.QWidget()
        block_layout = QtWidgets.QVBoxLayout(block_panel)
        block_layout.setContentsMargins(4, 4, 4, 4)
        self.block_list = QtWidgets.QListWidget()
        self.block_list.setFont(QtGui.QFont("Menlo", 10))
        self.block_list.itemClicked.connect(self.on_block_clicked)
        block_layout.addWidget(self.block_list)
        side_tabs.addTab(block_panel, "Basic Blocks")

        # Tab B: All 39 VM Handlers Table
        handler_panel = QtWidgets.QWidget()
        handler_layout = QtWidgets.QVBoxLayout(handler_panel)
        handler_layout.setContentsMargins(4, 4, 4, 4)
        self.handler_table = QtWidgets.QTableWidget()
        self.handler_table.setColumnCount(4)
        self.handler_table.setHorizontalHeaderLabels(["Op", "Mnemonic", "C++ Handler", "Count"])
        self.handler_table.horizontalHeader().setStretchLastSection(True)
        self.handler_table.setFont(QtGui.QFont("Menlo", 10))
        self.handler_table.setAlternatingRowColors(True)
        self.handler_table.itemDoubleClicked.connect(self.on_handler_table_double_click)
        handler_layout.addWidget(self.handler_table)
        side_tabs.addTab(handler_panel, "VM Handlers (39)")

        splitter.addWidget(side_tabs)

        splitter.setStretchFactor(0, 5)
        splitter.setStretchFactor(1, 2)
        layout.addWidget(splitter, 1)

        # ── Bottom Bar: Stats & Export ────────────────────────────────────────
        bottom_layout = QtWidgets.QHBoxLayout()
        self.status_label = QtWidgets.QLabel("Ready. Select payload source, enter seed key, and click Decrypt.")
        bottom_layout.addWidget(self.status_label)
        bottom_layout.addStretch()

        self.btn_export_asm = QtWidgets.QPushButton("Export .asm")
        self.btn_export_asm.clicked.connect(self.on_export_asm)
        bottom_layout.addWidget(self.btn_export_asm)

        self.btn_export_json = QtWidgets.QPushButton("Export .json")
        self.btn_export_json.clicked.connect(self.on_export_json)
        bottom_layout.addWidget(self.btn_export_json)

        layout.addLayout(bottom_layout)

    def auto_populate_sources(self):
        """Auto-detects protected.vanguard in candidate directories."""
        if not HAS_GUI:
            return
        input_file = idc.get_input_file_path()
        bin_dir = os.path.dirname(input_file) if input_file else ""

        candidates = [
            os.path.join(bin_dir, "protected.vanguard"),
            os.path.join(bin_dir, "../protected_arm64_out/protected.vanguard"),
            os.path.join(bin_dir, "protected_runner"),
            "protected_arm64_out/protected.vanguard",
            "examples/ida_demo/protected.vanguard"
        ]

        for cand in candidates:
            if os.path.exists(cand):
                self.source_edit.setText(os.path.abspath(cand))
                self.status_label.setText(f"Found bytecode payload: {cand}")
                return

        self.status_label.setText("No local protected.vanguard found. Use Browse or Segment extraction.")

    def on_browse(self):
        """File browser dialog."""
        path, _ = QtWidgets.QFileDialog.getOpenFileName(
            self.parent, "Select Bytecode Payload File", "", "All Files (*);;Bytecode (*.vanguard *.bin)"
        )
        if path:
            self.source_edit.setText(path)

    def on_extract_segment(self):
        """Extracts data from the binary's __const segment."""
        qty = ida_segment.get_segm_qty()
        for i in range(qty):
            seg = ida_segment.getnseg(i)
            if not seg:
                continue
            name = ida_segment.get_segm_name(seg)
            sz = seg.end_ea - seg.start_ea
            if "const" in name.lower() and sz > 10000:
                self.source_edit.setText(f"segment:{name}:0x{seg.start_ea:X}:{min(sz, 1000000)}")
                self.status_label.setText(f"Targeting segment {name} at 0x{seg.start_ea:X} ({sz} bytes)")
                return
        self.status_label.setText("Could not find __const segment in database.")

    def get_cipher_bytes(self) -> Optional[bytes]:
        """Loads cipher bytes from file path or segment specification."""
        src = self.source_edit.text().strip()
        if src.startswith("segment:"):
            parts = src.split(":")
            ea = int(parts[2], 0)
            sz = int(parts[3], 0)
            return ida_bytes.get_bytes(ea, sz) or b""

        if os.path.exists(src):
            with open(src, "rb") as fh:
                return fh.read(1000000)

        # Fallback to direct IDA database segment
        qty = ida_segment.get_segm_qty()
        for i in range(qty):
            seg = ida_segment.getnseg(i)
            if not seg:
                continue
            name = ida_segment.get_segm_name(seg)
            sz = seg.end_ea - seg.start_ea
            if sz > 10000:
                data = ida_bytes.get_bytes(seg.start_ea, min(sz, 1000000))
                if data:
                    return data
        return None

    def on_decode(self):
        """Decrypts and disassembles bytecode, updating table and handlers."""
        key_str = self.seed_edit.text().strip()
        try:
            seed_key = int(key_str, 0)
        except ValueError:
            self.status_label.setText("Invalid hex seed key.")
            return

        cipher_bytes = self.get_cipher_bytes()
        if not cipher_bytes:
            self.status_label.setText("Could not load bytecode data.")
            return

        if not StackVmDecoder:
            self.status_label.setText("Error: StackVmDecoder not loaded.")
            return

        self.decoder = StackVmDecoder(seed_key)
        self.instructions = self.decoder.decode_stream(cipher_bytes, max_instructions=5000)
        self.filtered_instructions = list(self.instructions)

        self.populate_table()
        self.reconstruct_blocks()
        self.populate_handlers_table()
        self.status_label.setText(
            f"Successfully decoded {len(self.instructions)} virtual instructions across {self.block_list.count()} blocks."
        )

    def populate_table(self):
        self.table.setRowCount(len(self.filtered_instructions))
        for row, insn in enumerate(self.filtered_instructions):
            self.table.setItem(row, 0, QtWidgets.QTableWidgetItem(f"+0x{insn['offset']:06X}"))
            self.table.setItem(row, 1, QtWidgets.QTableWidgetItem(f"0x{insn['opcode']:02X}"))

            item_mnem = QtWidgets.QTableWidgetItem(insn['mnemonic'])
            if "Jmp" in insn['mnemonic'] or "Jcc" in insn['mnemonic']:
                item_mnem.setForeground(QtGui.QBrush(QtGui.QColor("#29B6F6")))
                item_mnem.setFont(QtGui.QFont("Menlo", 11, QtGui.QFont.Bold))
            elif "Call" in insn['mnemonic']:
                item_mnem.setForeground(QtGui.QBrush(QtGui.QColor("#FFA726")))
                item_mnem.setFont(QtGui.QFont("Menlo", 11, QtGui.QFont.Bold))
            elif "Exit" in insn['mnemonic']:
                item_mnem.setForeground(QtGui.QBrush(QtGui.QColor("#EF5350")))
                item_mnem.setFont(QtGui.QFont("Menlo", 11, QtGui.QFont.Bold))
            elif "Key" in insn['mnemonic']:
                item_mnem.setForeground(QtGui.QBrush(QtGui.QColor("#AB47BC")))
                item_mnem.setFont(QtGui.QFont("Menlo", 11, QtGui.QFont.Bold))

            self.table.setItem(row, 2, item_mnem)
            self.table.setItem(row, 3, QtWidgets.QTableWidgetItem(insn['operands']))
            self.table.setItem(row, 4, QtWidgets.QTableWidgetItem(str(insn['delta'])))

            # Column 5: Handler with click hint
            h_text = f"{insn['handler']} [{insn['label']}]"
            item_h = QtWidgets.QTableWidgetItem(h_text)
            item_h.setForeground(QtGui.QBrush(QtGui.QColor("#81C784")))
            self.table.setItem(row, 5, item_h)

            self.table.setItem(row, 6, QtWidgets.QTableWidgetItem(insn['key']))

        self.table.resizeColumnsToContents()

    def populate_handlers_table(self):
        """Fills the 39 VM Handlers summary table with frequencies."""
        if not self.decoder:
            return

        freq = collections.Counter(insn["opcode"] for insn in self.instructions)
        self.handler_table.setRowCount(39)

        for row, (code, info) in enumerate(sorted(self.decoder.op_info.items())):
            self.handler_table.setItem(row, 0, QtWidgets.QTableWidgetItem(f"0x{code:02X}"))
            self.handler_table.setItem(row, 1, QtWidgets.QTableWidgetItem(info["mnemonic"]))
            self.handler_table.setItem(row, 2, QtWidgets.QTableWidgetItem(f"{info['handler']} [{info['label']}]"))
            cnt = freq.get(code, 0)
            item_cnt = QtWidgets.QTableWidgetItem(str(cnt))
            if cnt > 0:
                item_cnt.setFont(QtGui.QFont("Menlo", 10, QtGui.QFont.Bold))
                item_cnt.setForeground(QtGui.QBrush(QtGui.QColor("#4CAF50")))
            self.handler_table.setItem(row, 3, item_cnt)

        self.handler_table.resizeColumnsToContents()

    def reconstruct_blocks(self):
        self.block_list.clear()
        block_id = 0
        block_start = 0
        for i, insn in enumerate(self.instructions):
            mnem = insn["mnemonic"]
            if mnem in ("JmpRel", "JccRel", "Exit") or i == len(self.instructions) - 1:
                item_text = f"Block {block_id:3d} [insns {block_start:4d}..{i:4d}] -> {mnem}"
                list_item = QtWidgets.QListWidgetItem(item_text)
                list_item.setData(QtCore.Qt.UserRole, block_start)
                self.block_list.addItem(list_item)
                block_id += 1
                block_start = i + 1

    def on_block_clicked(self, item):
        start_idx = item.data(QtCore.Qt.UserRole)
        if start_idx < self.table.rowCount():
            self.table.selectRow(start_idx)
            self.table.scrollToItem(self.table.item(start_idx, 0))

    def on_table_double_click(self, item):
        row = item.row()
        insn = self.filtered_instructions[row]

        # Double click on Handler column -> Jump directly to handler machine code in IDA View!
        if item.column() == 5 or item.column() == 1:
            self.jump_to_handler_in_ida(insn["opcode"], insn["label"], insn["handler"])
            return

        # Double click on Jump operands -> Filter by target block
        if "target_bid=" in insn["operands"]:
            target_str = insn["operands"].split("target_bid=")[1].split(",")[0].strip()
            self.filter_edit.setText(f"target_bid={target_str}")

    def on_handler_table_double_click(self, item):
        row = item.row()
        op_text = self.handler_table.item(row, 0).text()
        opcode = int(op_text, 16)
        lbl_text = f"lbl_{opcode:02X}"
        h_name = self.handler_table.item(row, 2).text().split()[0]
        self.jump_to_handler_in_ida(opcode, lbl_text, h_name)

    def jump_to_handler_in_ida(self, opcode: int, label: str, handler_name: str):
        """Navigates the main IDA View disassembler to the handler address."""
        if not HAS_GUI:
            return

        # 1. Search for label symbol lbl_XX
        ea = idc.get_name_ea_simple(label)
        if ea != idc.BADADDR:
            jumpto(ea)
            self.status_label.setText(f"Jumped to label {label} at 0x{ea:X}")
            return

        # 2. Search for handler function h_xxx
        ea = idc.get_name_ea_simple(handler_name)
        if ea != idc.BADADDR:
            jumpto(ea)
            self.status_label.setText(f"Jumped to function {handler_name} at 0x{ea:X}")
            return

        # 3. Fallback: Search inside VM dispatcher function
        self.status_label.setText(f"Handler {label} ({handler_name}) is inlined inside VM dispatcher.")

    def apply_filter(self, text):
        t = text.lower().strip()
        if not t:
            self.filtered_instructions = list(self.instructions)
        else:
            self.filtered_instructions = [
                insn for insn in self.instructions
                if t in insn["mnemonic"].lower()
                or t in insn["operands"].lower()
                or t in insn["handler"].lower()
                or t in hex(insn["offset"])
            ]
        self.populate_table()

    def on_export_asm(self):
        if not self.instructions:
            return
        path = "asgard_decoded_bytecode.asm"
        with open(path, "w") as fh:
            fh.write("; ASGARD-5877 Stack-VM Decoded Virtual Assembly\n")
            fh.write(f"; Seed Key: {self.seed_edit.text()}\n\n")
            for insn in self.instructions:
                fh.write(f"+0x{insn['offset']:06X}  {insn['mnemonic']:<16} {insn['operands']:<30} ; handler={insn['handler']}\n")
        self.status_label.setText(f"Exported virtual assembly to {path}")

    def on_export_json(self):
        if not self.instructions:
            return
        path = "asgard_decoded_bytecode.json"
        with open(path, "w") as fh:
            json.dump(self.instructions, fh, indent=2)
        self.status_label.setText(f"Exported JSON to {path}")

    def show(self):
        """Displays the dockable form in IDA Pro."""
        if HAS_GUI:
            self.Show("ASGARD Bytecode Visualizer", options=PluginForm.WOPN_TAB | PluginForm.WOPN_RESTORE)
