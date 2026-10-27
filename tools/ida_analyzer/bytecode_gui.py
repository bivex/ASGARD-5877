"""
bytecode_gui.py — Interactive IDA Pro GUI for ASGARD Bytecode Visualization
─────────────────────────────────────────────────────────────────────────────
Dockable PluginForm tab inside IDA Pro with PySide6 for interactive
rolling-key decryption, instruction stream inspection, and CFG navigation.
"""

import os
import json
from typing import Optional, List, Dict, Any

# IDA / PySide imports
try:
    from ida_kernwin import PluginForm, msg
    import ida_segment
    import ida_bytes
    import ida_funcs
    import idc
    from PySide6 import QtWidgets, QtCore, QtGui
    HAS_GUI = True
except ImportError:
    HAS_GUI = False

try:
    from bytecode_decoder import StackVmDecoder
except ImportError:
    try:
        from tools.ida_analyzer.bytecode_decoder import StackVmDecoder
    except ImportError:
        StackVmDecoder = None


class AsgardBytecodeForm(PluginForm if HAS_GUI else object):
    """Interactive dockable form for Stack-VM bytecode disassembly."""

    def __init__(self):
        super().__init__()
        self.instructions: List[Dict[str, Any]] = []
        self.filtered_instructions: List[Dict[str, Any]] = []

    def OnCreate(self, form):
        if not HAS_GUI:
            return

        # Get parent Qt widget from IDA form
        self.parent = self.FormToPyQtWidget(form)
        self.init_ui()

    def init_ui(self):
        layout = QtWidgets.QVBoxLayout(self.parent)

        # ── Top Panel: Key & Controls ─────────────────────────────────────────
        top_group = QtWidgets.QGroupBox("ASGARD-5877 Rolling-Key Decryption Controls")
        top_layout = QtWidgets.QHBoxLayout(top_group)

        top_layout.addWidget(QtWidgets.QLabel("Seed Key (Hex):"))
        self.seed_edit = QtWidgets.QLineEdit("0x2ED2232624AED846")
        self.seed_edit.setMinimumWidth(200)
        self.seed_edit.setFont(QtGui.QFont("Menlo", 12))
        top_layout.addWidget(self.seed_edit)

        self.btn_autodetect = QtWidgets.QPushButton("Auto-Detect from Binary")
        self.btn_autodetect.clicked.connect(self.on_autodetect)
        top_layout.addWidget(self.btn_autodetect)

        self.btn_decode = QtWidgets.QPushButton("Decrypt & Disassemble")
        self.btn_decode.setStyleSheet("font-weight: bold; background-color: #2b5b84; color: white;")
        self.btn_decode.clicked.connect(self.on_decode)
        top_layout.addWidget(self.btn_decode)

        layout.addWidget(top_group)

        # ── Filter Bar ────────────────────────────────────────────────────────
        filter_layout = QtWidgets.QHBoxLayout()
        filter_layout.addWidget(QtWidgets.QLabel("Search / Filter:"))
        self.filter_edit = QtWidgets.QLineEdit()
        self.filter_edit.setPlaceholderText("Filter by mnemonic (e.g. JccRel, PushImm, Add), operand, or offset...")
        self.filter_edit.textChanged.connect(self.apply_filter)
        filter_layout.addWidget(self.filter_edit)
        layout.addLayout(filter_layout)

        # ── Splitter: Instructions & Blocks ───────────────────────────────────
        splitter = QtWidgets.QSplitter(QtCore.Qt.Horizontal)

        # 1. Main Instruction Table
        self.table = QtWidgets.QTableWidget()
        self.table.setColumnCount(6)
        self.table.setHorizontalHeaderLabels(["Offset", "Opcode", "Mnemonic", "Operands", "Delta", "Rolling Key"])
        self.table.horizontalHeader().setStretchLastSection(True)
        self.table.setAlternatingRowColors(True)
        self.table.setFont(QtGui.QFont("Menlo", 11))
        self.table.itemDoubleClicked.connect(self.on_table_double_click)
        splitter.addWidget(self.table)

        # 2. Basic Blocks List
        block_panel = QtWidgets.QWidget()
        block_layout = QtWidgets.QVBoxLayout(block_panel)
        block_layout.addWidget(QtWidgets.QLabel("<b>Reconstructed Blocks:</b>"))
        self.block_list = QtWidgets.QListWidget()
        self.block_list.itemClicked.connect(self.on_block_clicked)
        block_layout.addWidget(self.block_list)
        splitter.addWidget(block_panel)

        splitter.setStretchFactor(0, 4)
        splitter.setStretchFactor(1, 1)
        layout.addWidget(splitter)

        # ── Bottom Bar: Stats & Export ────────────────────────────────────────
        bottom_layout = QtWidgets.QHBoxLayout()
        self.status_label = QtWidgets.QLabel("Ready. Enter seed key and click Decrypt.")
        bottom_layout.addWidget(self.status_label)
        bottom_layout.addStretch()

        self.btn_export_asm = QtWidgets.QPushButton("Export .asm")
        self.btn_export_asm.clicked.connect(self.on_export_asm)
        bottom_layout.addWidget(self.btn_export_asm)

        self.btn_export_json = QtWidgets.QPushButton("Export .json")
        self.btn_export_json.clicked.connect(self.on_export_json)
        bottom_layout.addWidget(self.btn_export_json)

        layout.addLayout(bottom_layout)

    def on_autodetect(self):
        """Scans binary segments for the highest entropy section containing bytecode."""
        if not HAS_GUI:
            return
        qty = ida_segment.get_segm_qty()
        best_seg = None
        max_size = 0
        for i in range(qty):
            seg = ida_segment.getnseg(i)
            if not seg:
                continue
            name = ida_segment.get_segm_name(seg)
            sz = seg.end_ea - seg.start_ea
            if "const" in name.lower() or "data" in name.lower():
                if sz > max_size:
                    max_size = sz
                    best_seg = seg

        if best_seg:
            name = ida_segment.get_segm_name(best_seg)
            self.status_label.setText(f"Detected target segment '{name}' (0x{best_seg.start_ea:X}, {max_size} bytes)")
        else:
            self.status_label.setText("No large data segment detected.")

    def on_decode(self):
        """Decrypts and disassembles bytecode from binary or file."""
        key_str = self.seed_edit.text().strip()
        try:
            seed_key = int(key_str, 0)
        except ValueError:
            self.status_label.setText("Invalid hex seed key.")
            return

        # Attempt to grab bytecode from high-entropy section
        cipher_bytes = b""
        qty = ida_segment.get_segm_qty()
        for i in range(qty):
            seg = ida_segment.getnseg(i)
            if not seg:
                continue
            sz = seg.end_ea - seg.start_ea
            if sz > 10000:
                cipher_bytes = ida_bytes.get_bytes(seg.start_ea, min(sz, 500000)) or b""
                if len(cipher_bytes) > 0:
                    break

        if not cipher_bytes:
            # Fallback: check if protected.vanguard exists
            vanguard_path = os.path.join(os.path.dirname(idc.get_input_file_path()), "protected.vanguard")
            if os.path.exists(vanguard_path):
                with open(vanguard_path, "rb") as fh:
                    cipher_bytes = fh.read(500000)

        if not cipher_bytes:
            self.status_label.setText("Could not locate encrypted bytecode buffer.")
            return

        decoder = StackVmDecoder(seed_key)
        self.instructions = decoder.decode_stream(cipher_bytes, max_instructions=5000)
        self.filtered_instructions = list(self.instructions)

        self.populate_table()
        self.reconstruct_blocks()
        self.status_label.setText(f"Decoded {len(self.instructions)} virtual instructions successfully.")

    def populate_table(self):
        self.table.setRowCount(len(self.filtered_instructions))
        for row, insn in enumerate(self.filtered_instructions):
            self.table.setItem(row, 0, QtWidgets.QTableWidgetItem(f"+0x{insn['offset']:06X}"))
            self.table.setItem(row, 1, QtWidgets.QTableWidgetItem(f"0x{insn['opcode']:02X}"))

            item_mnem = QtWidgets.QTableWidgetItem(insn['mnemonic'])
            if "Jmp" in insn['mnemonic'] or "Jcc" in insn['mnemonic']:
                item_mnem.setForeground(QtGui.QBrush(QtGui.QColor("#2b84d2")))
                item_mnem.setFont(QtGui.QFont("Menlo", 11, QtGui.QFont.Bold))
            elif "Call" in insn['mnemonic']:
                item_mnem.setForeground(QtGui.QBrush(QtGui.QColor("#d2842b")))
                item_mnem.setFont(QtGui.QFont("Menlo", 11, QtGui.QFont.Bold))
            elif "Exit" in insn['mnemonic']:
                item_mnem.setForeground(QtGui.QBrush(QtGui.QColor("#d22b2b")))
                item_mnem.setFont(QtGui.QFont("Menlo", 11, QtGui.QFont.Bold))

            self.table.setItem(row, 2, item_mnem)
            self.table.setItem(row, 3, QtWidgets.QTableWidgetItem(insn['operands']))
            self.table.setItem(row, 4, QtWidgets.QTableWidgetItem(str(insn['delta'])))
            self.table.setItem(row, 5, QtWidgets.QTableWidgetItem(insn['key']))

        self.table.resizeColumnsToContents()

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
        if "target_bid=" in insn["operands"]:
            target_str = insn["operands"].split("target_bid=")[1].split(",")[0].strip()
            self.filter_edit.setText(f"target_bid={target_str}")

    def apply_filter(self, text):
        t = text.lower().strip()
        if not t:
            self.filtered_instructions = list(self.instructions)
        else:
            self.filtered_instructions = [
                insn for insn in self.instructions
                if t in insn["mnemonic"].lower() or t in insn["operands"].lower() or t in hex(insn["offset"])
            ]
        self.populate_table()

    def on_export_asm(self):
        if not self.instructions:
            return
        path = "asgard_decoded_bytecode.asm"
        with open(path, "w") as fh:
            for insn in self.instructions:
                fh.write(f"+0x{insn['offset']:06X}  {insn['mnemonic']:<16} {insn['operands']}\n")
        self.status_label.setText(f"Exported disassembly to {path}")

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
