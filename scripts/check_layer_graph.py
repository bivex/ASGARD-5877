#!/usr/bin/env python3
"""Layer dependency gate for the ASGARD-5877 dune graph.

Reads every (library ...) stanza under the layer directories, maps each
library to its layer by path, and asserts the invariants of the documented
topology (README "Repository layout"):

  I1  a library may depend only on libraries of a LOWER OR EQUAL layer
      (layer order: base < domain < contracts < infra < transforms <
       analysis < backends < adapters < pipeline < cli)
  I2  base libraries depend on no internal library
  I3  domain / contracts / transforms / analysis declare no effectful
      external library (unix, bos, fpath, domainslib)

Unknown dependency names (external opam packages) are ignored. Exit 0 with
a summary when the graph is legal, exit 1 listing every violation otherwise.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

LAYER_ORDER = [
    "base",
    "domain",
    "contracts",
    "infra",
    "transforms",
    "analysis",
    "backends",
    "adapters",
    "pipeline",
    "cli",
]
LAYER_INDEX = {name: i for i, name in enumerate(LAYER_ORDER)}

# Directories that are outside the layer chain (consumers of everything).
NON_LAYER_DIRS = {
    "test", "tools", "bench", "scripts", "docs", "examples", "samples",
    "formal", "assets", "binaries", "protected_arm64_out",
}

EFFECTFUL_EXTERNAL = {"unix", "bos", "fpath", "domainslib", "threads"}

EFFECT_FORBIDDEN_LAYERS = {"domain", "contracts", "transforms", "analysis"}


def layer_of(dune_file: Path) -> str | None:
    top = dune_file.relative_to(REPO).parts[0]
    return top if top in LAYER_INDEX else None


def extract_library_stanza(text: str) -> str | None:
    """Return the parenthesized (library ...) stanza, or None."""
    start = text.find("(library")
    if start < 0:
        return None
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    return text[start:]


def parse_lib(stanza: str) -> tuple[str | None, list[str]]:
    """Extract (name, [libraries]) from a (library ...) stanza."""
    name_m = re.search(r"\(name\s+([A-Za-z0-9_]+)\)", stanza)
    libs: list[str] = []
    libs_m = re.search(r"\(libraries((?:\s+[A-Za-z0-9_.]+)*)\s*\)", stanza)
    if libs_m:
        libs = libs_m.group(1).split()
    return (name_m.group(1) if name_m else None), libs


def main() -> int:
    libs: dict[str, tuple[str, Path]] = {}  # lib name -> (layer, dune path)
    stanzas: list[tuple[str, str, list[str], Path]] = []

    for dune_file in sorted(REPO.rglob("dune")):
        rel = dune_file.relative_to(REPO)
        if rel.parts[0] in NON_LAYER_DIRS or "_build" in rel.parts:
            continue
        layer = layer_of(dune_file)
        if layer is None:
            continue
        stanza = extract_library_stanza(dune_file.read_text())
        if stanza is None:
            continue
        name, deps = parse_lib(stanza)
        if name is None:
            continue
        libs[name] = (layer, dune_file)
        stanzas.append((layer, name, deps, dune_file))

    violations: list[str] = []
    edges = 0

    for layer, name, deps, path in stanzas:
        for dep in deps:
            if dep not in libs:
                continue  # external opam package or qualified public name
            edges += 1
            dep_layer, dep_path = libs[dep]
            if LAYER_INDEX[dep_layer] > LAYER_INDEX[layer]:
                violations.append(
                    f"I1 {layer}/{name} -> {dep_layer}/{dep} "
                    f"(upward edge, {path.relative_to(REPO)} vs {dep_path.relative_to(REPO)})"
                )
            if layer == "base":
                violations.append(f"I2 base/{name} depends on internal {dep}")
            if layer in EFFECT_FORBIDDEN_LAYERS and dep in EFFECTFUL_EXTERNAL:
                violations.append(
                    f"I3 {layer}/{name} declares effectful external '{dep}'"
                )

    print(f"layer graph: {len(stanzas)} libraries, {edges} internal edges")
    if violations:
        print(f"FAIL: {len(violations)} violation(s)")
        for v in violations:
            print(f"  {v}")
        return 1
    print("OK: layer order, base purity and effect isolation hold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
