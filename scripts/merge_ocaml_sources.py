#!/usr/bin/env python3
"""
merge_ocaml_sources.py - Merges all OCaml source files (.ml, .mli) into a single text file.

Features:
  - Scans repository recursively for .ml and .mli files.
  - Excludes build artifacts (_build), vcs (.git), scratch dirs, and output dumps.
  - Generates a structured header and Table of Contents (TOC) with file offsets and line counts.
  - Formats each source block with clear visual banners and file paths.
  - Supports CLI flags to filter directories, extensions, or include dune build files.
"""

from __future__ import annotations

import argparse
import datetime
import os
import sys
from pathlib import Path

DEFAULT_EXTENSIONS = [".ml", ".mli"]
DEFAULT_EXCLUDED_DIRS = {
    "_build",
    ".git",
    ".system_generated",
    ".agents",
    "scratch",
    "protected_arm64_out",
    "demo_c_out",
    "demo_test_threaded",
    "demo_test_stack",
    "backup",
    "__pycache__",
    ".idea",
    ".vscode",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Merge OCaml source files into a single text file."
    )
    parser.add_argument(
        "-o",
        "--output",
        type=str,
        default="ocaml_sources_merged.txt",
        help="Target output text file path (default: ocaml_sources_merged.txt)",
    )
    parser.add_argument(
        "-r",
        "--root",
        type=str,
        default=".",
        help="Root directory of the project to scan (default: current directory)",
    )
    parser.add_argument(
        "-d",
        "--dirs",
        nargs="+",
        default=None,
        help="Specific subdirectories to scan (e.g. lib bin test). If omitted, scans entire root.",
    )
    parser.add_argument(
        "--ext",
        nargs="+",
        default=DEFAULT_EXTENSIONS,
        help=f"File extensions to include (default: {' '.join(DEFAULT_EXTENSIONS)})",
    )
    parser.add_argument(
        "--include-dune",
        action="store_true",
        help="Also include 'dune' and 'dune-project' configuration files",
    )
    parser.add_argument(
        "--no-toc",
        action="store_true",
        help="Omit the Table of Contents at the start of the output file",
    )
    return parser.parse_args()


def collect_files(
    root_path: Path,
    dirs: list[str] | None,
    extensions: set[str],
    include_dune: bool,
    excluded_dirs: set[str],
) -> list[Path]:
    matched_files: list[Path] = []
    scan_roots = [root_path / d for d in dirs] if dirs else [root_path]

    for scan_root in scan_roots:
        if not scan_root.exists():
            print(f"[!] Warning: Directory '{scan_root}' does not exist, skipping.", file=sys.stderr)
            continue

        for dirpath, dirnames, filenames in os.walk(scan_root):
            # Prune excluded directories in-place so os.walk does not traverse them
            dirnames[:] = [
                d for d in dirnames
                if d not in excluded_dirs and not d.startswith(".")
            ]

            for fname in filenames:
                file_path = Path(dirpath) / fname
                is_ext_match = file_path.suffix in extensions
                is_dune_match = include_dune and (fname == "dune" or fname == "dune-project")

                if is_ext_match or is_dune_match:
                    matched_files.append(file_path)

    # Sort files deterministically by relative path
    matched_files.sort(key=lambda p: str(p.relative_to(root_path)))
    return matched_files


def merge_sources(
    root_path: Path,
    files: list[Path],
    output_path: Path,
    include_toc: bool,
) -> tuple[int, int, int]:
    """
    Merges files into output_path.
    Returns (total_files, total_lines, total_bytes).
    """
    total_files = len(files)
    total_lines = 0
    total_bytes = 0

    # First pass: read file stats for metadata and TOC
    file_metadata: list[dict] = []
    for f in files:
        rel_path = str(f.relative_to(root_path))
        try:
            content = f.read_text(encoding="utf-8", errors="replace")
            lines = content.splitlines(keepends=True)
            line_count = len(lines)
            byte_count = len(content.encode("utf-8"))
            file_metadata.append({
                "path": f,
                "rel_path": rel_path,
                "lines": line_count,
                "bytes": byte_count,
                "content": content,
            })
            total_lines += line_count
            total_bytes += byte_count
        except Exception as e:
            print(f"[!] Error reading '{rel_path}': {e}", file=sys.stderr)

    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    banner_width = 80
    sep_double = "=" * banner_width
    sep_single = "-" * banner_width

    with open(output_path, "w", encoding="utf-8") as out:
        # Header
        out.write(f"{sep_double}\n")
        out.write(" ASGARD-5877 OCaml Sources Consolidated Dump\n")
        out.write(f" Generated:    {timestamp}\n")
        out.write(f" Total Files:  {len(file_metadata)}\n")
        out.write(f" Total Lines:  {total_lines:,}\n")
        out.write(f" Total Size:   {total_bytes / (1024 * 1024):.2f} MB ({total_bytes:,} bytes)\n")
        out.write(f"{sep_double}\n\n")

        # Table of Contents
        if include_toc:
            out.write("TABLE OF CONTENTS\n")
            out.write(f"{sep_single}\n")
            out.write(f"{'#':<4} {'Lines':<8} {'Size':<10} {'Path'}\n")
            out.write(f"{sep_single}\n")
            for idx, meta in enumerate(file_metadata, start=1):
                size_str = f"{meta['bytes']:,} B"
                out.write(f"{idx:<4} {meta['lines']:<8} {size_str:<10} {meta['rel_path']}\n")
            out.write(f"{sep_single}\n\n")

        # File contents
        for idx, meta in enumerate(file_metadata, start=1):
            out.write(f"{sep_double}\n")
            out.write(f"[{idx}/{len(file_metadata)}] FILE: {meta['rel_path']}\n")
            out.write(f"Lines: {meta['lines']:,} | Bytes: {meta['bytes']:,}\n")
            out.write(f"{sep_double}\n")

            content = meta["content"]
            out.write(content)
            if not content.endswith("\n"):
                out.write("\n")
            out.write("\n")

    return len(file_metadata), total_lines, total_bytes


def main() -> None:
    args = parse_args()
    root_path = Path(args.root).resolve()
    output_path = Path(args.output).resolve()
    extensions = set(args.ext)

    print(f"[*] Scanning for OCaml sources in: {root_path}")
    if args.dirs:
        print(f"[*] Limiting scan to subdirectories: {', '.join(args.dirs)}")
    print(f"[*] Extensions: {', '.join(sorted(extensions))}")

    files = collect_files(
        root_path=root_path,
        dirs=args.dirs,
        extensions=extensions,
        include_dune=args.include_dune,
        excluded_dirs=DEFAULT_EXCLUDED_DIRS,
    )

    if not files:
        print("[-] No matching source files found.", file=sys.stderr)
        sys.exit(1)

    print(f"[*] Found {len(files)} source files. Merging into: {output_path}")

    total_files, total_lines, total_bytes = merge_sources(
        root_path=root_path,
        files=files,
        output_path=output_path,
        include_toc=not args.no_toc,
    )

    out_size_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"[+] Successfully created '{output_path.name}':")
    print(f"    - Files merged: {total_files:,}")
    print(f"    - Total lines:  {total_lines:,}")
    print(f"    - Output size:  {out_size_mb:.2f} MB ({output_path.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
