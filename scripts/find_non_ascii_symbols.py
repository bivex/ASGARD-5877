#!/usr/bin/env python3
"""
find_non_ascii_symbols.py - Finds non-English (non-ASCII) symbols in OCaml code.

Features:
  - Scans the repository recursively for OCaml sources (.ml, .mli, .mll, .mly).
  - Runs a real OCaml lexer, so it can tell code apart from comments and strings.
  - Classifies every non-ASCII occurrence:
      symbol    an identifier / operator (e.g. a Cyrillic variable name)
      string    a string literal (e.g. a UTF-8 arrow inside a printf format)
      char      a character literal
      comment   prose inside a comment (usually harmless)
  - Flags homoglyph / confusable identifiers (Cyrillic 'а' next to Latin 'a'),
    which are invisible in most editors and can hide a backdoor.
  - Suggests an ASCII transliteration for every offending identifier.
  - Supports an allowlist so known-good occurrences can be waived.
  - Emits grep-friendly lines, or JSON for CI consumption.

Usage:
  scripts/find_non_ascii_symbols.py                       # scan the repository
  scripts/find_non_ascii_symbols.py --symbols-only        # identifiers only
  scripts/find_non_ascii_symbols.py --include-comments    # also list comments
  scripts/find_non_ascii_symbols.py --strict              # strings are errors too
  scripts/find_non_ascii_symbols.py --json                # machine readable

Exit codes:
  0  no error-level findings
  1  at least one error-level finding
  2  bad usage or I/O failure
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_EXTENSIONS = [".ml", ".mli", ".mll", ".mly"]

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
    "binaries",
    "__pycache__",
    ".idea",
    ".vscode",
}

# Characters that render like an ASCII letter but are not one.
CONFUSABLES = {
    # Cyrillic
    "а": "a", "в": "b", "е": "e", "к": "k", "м": "m", "н": "h", "о": "o",
    "р": "p", "с": "c", "т": "t", "у": "y", "х": "x", "і": "i", "ј": "j",
    "ѕ": "s", "һ": "h", "ԁ": "d", "ԛ": "q", "ԝ": "w", "г": "r", "т": "t",
    "п": "n", "и": "u", "л": "n",
    "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H", "О": "O",
    "Р": "P", "С": "C", "Т": "T", "У": "Y", "Х": "X", "І": "I", "Ј": "J",
    "Ѕ": "S", "Һ": "H", "Ԛ": "Q", "Ԝ": "W", "Г": "r",
    # Greek
    "α": "a", "β": "b", "ε": "e", "η": "n", "ι": "i", "κ": "k", "ν": "v",
    "ο": "o", "ρ": "p", "σ": "o", "τ": "t", "υ": "u", "χ": "x", "γ": "y",
    "Α": "A", "Β": "B", "Ε": "E", "Ζ": "Z", "Η": "H", "Ι": "I", "Κ": "K",
    "Μ": "M", "Ν": "N", "Ο": "O", "Ρ": "P", "Τ": "T", "Υ": "Y", "Χ": "X",
    # Latin lookalikes and fullwidth forms
    "ɑ": "a", "ɐ": "a", "ɓ": "b", "ϲ": "c", "ɗ": "d", "е": "e", "ɠ": "g",
    "ɡ": "g", "ɥ": "h", "ɨ": "i", "ɩ": "i", "ɫ": "l", "ɯ": "m", "ɴ": "n",
    "ᴏ": "o", "ɵ": "o", "ɿ": "r", "ʀ": "r", "ʂ": "s", "ʇ": "t", "ʉ": "u",
    "ᴠ": "v", "ʋ": "v", "ѵ": "v", "ʍ": "w", "ʏ": "y", "ʐ": "z", "ᴢ": "z",
    "ⅰ": "i", "ⅼ": "l", "ⅿ": "m", "ⅾ": "d", "ϳ": "f", "ⅻ": "l",
    "ᴀ": "a", "ᴄ": "c", "ᴅ": "d", "ᴇ": "e", "ɢ": "g", "ʜ": "h", "ɪ": "i",
    "ᴊ": "j", "ᴋ": "k", "ʟ": "l", "ᴍ": "m", "ɴ": "n", "ᴏ": "o", "ᴘ": "p",
    "ʀ": "r", "ᴛ": "t", "ᴜ": "u", "ᴠ": "v", "ᴡ": "w", "ʏ": "y", "ᴢ": "z",
}

# Rough transliteration used for the ASCII rename suggestion.
TRANSLIT = {
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e",
    "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
    "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
    "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch",
    "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
    "і": "i", "ї": "yi", "є": "ye", "ґ": "g", "ў": "u",
    "α": "a", "β": "b", "γ": "g", "δ": "d", "ε": "e", "ζ": "z", "η": "i",
    "θ": "th", "ι": "i", "κ": "k", "λ": "l", "μ": "m", "ν": "n", "ξ": "x",
    "ο": "o", "π": "pi", "ρ": "r", "σ": "s", "τ": "t", "υ": "u", "φ": "f",
    "χ": "ch", "ψ": "ps", "ω": "o",
}

OPERATOR_CHARS = set("!$%&*+-./:<=>?@^|~")


@dataclass
class Token:
    kind: str
    text: str
    line: int
    col: int


@dataclass
class Finding:
    path: str
    line: int
    col: int
    category: str
    severity: str
    message: str
    detail: dict = field(default_factory=dict)


def is_ident_start(ch: str) -> bool:
    return ch == "_" or ch.isalpha()


def is_ident_part(ch: str) -> bool:
    return ch == "_" or ch == "'" or ch.isalnum()


class Lexer:
    """A minimal OCaml lexer, enough to separate code from comments and strings."""

    def __init__(self, src: str) -> None:
        self.src = src
        self.i = 0
        self.n = len(src)
        self.line = 1
        self.col = 1

    def _advance(self, count: int) -> None:
        for _ in range(count):
            if self.i >= self.n:
                return
            if self.src[self.i] == "\n":
                self.line += 1
                self.col = 1
            else:
                self.col += 1
            self.i += 1

    def _quoted_string(self) -> Token | None:
        """Match {| ... |} and {id| ... |id} string literals."""
        if self.src[self.i] != "{":
            return None
        j = self.i + 1
        ident = ""
        while j < self.n and (self.src[j].isalnum() or self.src[j] == "_"):
            ident += self.src[j]
            j += 1
        if j >= self.n or self.src[j] != "|":
            return None
        if ident and not (ident[0].islower() or ident[0] == "_"):
            return None
        closing = "|}" if not ident else f"|{ident}}}"
        start, start_line, start_col = self.i, self.line, self.col
        self._advance(j - self.i + 1)
        while self.i < self.n and not self.src.startswith(closing, self.i):
            self._advance(1)
        end = min(self.i + len(closing), self.n)
        self._advance(end - self.i)
        return Token("string", self.src[start:end], start_line, start_col)

    def _comment(self) -> list[Token]:
        """Lex a (possibly nested) comment, keeping embedded strings apart.

        The OCaml lexer treats every double quote inside a comment as the
        start of a string literal that runs to the next unescaped quote, so
        (*" abc "*) holds a string while (* a " b *) is an unterminated one.
        """
        tokens: list[Token] = []
        start, start_line, start_col = self.i, self.line, self.col
        depth = 1
        self._advance(2)
        chunk_start, chunk_line, chunk_col = start, start_line, start_col
        while self.i < self.n and depth > 0:
            if self.src.startswith("(*", self.i):
                depth += 1
                self._advance(2)
                continue
            if self.src.startswith("*)", self.i):
                depth -= 1
                self._advance(2)
                continue
            if self.src[self.i] == '"':
                tokens.append(
                    Token("comment", self.src[chunk_start:self.i], chunk_line, chunk_col)
                )
                str_start, str_line, str_col = self.i, self.line, self.col
                self._advance(1)
                while self.i < self.n:
                    if self.src[self.i] == "\\":
                        self._advance(2)
                        continue
                    if self.src[self.i] == '"':
                        self._advance(1)
                        break
                    self._advance(1)
                tokens.append(Token("string", self.src[str_start:self.i], str_line, str_col))
                chunk_start, chunk_line, chunk_col = self.i, self.line, self.col
                continue
            self._advance(1)
        tokens.append(Token("comment", self.src[chunk_start:self.i], chunk_line, chunk_col))
        return tokens

    def _char_literal(self) -> Token | None:
        """Match a character literal; None means the quote starts an identifier."""
        start, start_line, start_col = self.i, self.line, self.col
        if self.i + 2 < self.n and self.src[self.i + 1] == "\\":
            j = self.i + 2
            if j < self.n and self.src[j] in "xX":
                j += 1
                while j < self.n and self.src[j] in "0123456789abcdefABCDEF":
                    j += 1
            elif j < self.n and self.src[j] in "oO":
                j += 1
                while j < self.n and self.src[j] in "01234567":
                    j += 1
            elif j < self.n and self.src[j].isdigit():
                while j < self.n and self.src[j].isdigit():
                    j += 1
            else:
                j += 1
            if j < self.n and self.src[j] == "'":
                self._advance(j + 1 - self.i)
                return Token("char", self.src[start:self.i], start_line, start_col)
            return None
        if self.i + 2 < self.n and self.src[self.i + 2] == "'":
            self._advance(3)
            return Token("char", self.src[start:self.i], start_line, start_col)
        return None

    def tokens(self) -> list[Token]:
        out: list[Token] = []
        while self.i < self.n:
            ch = self.src[self.i]
            if ch in " \t\r\n\f":
                self._advance(1)
                continue
            if self.src.startswith("(*", self.i):
                out.extend(self._comment())
                continue
            if ch == "{":
                quoted = self._quoted_string()
                if quoted is not None:
                    out.append(quoted)
                    continue
            if ch == '"':
                start, start_line, start_col = self.i, self.line, self.col
                self._advance(1)
                while self.i < self.n:
                    if self.src[self.i] == "\\":
                        self._advance(2)
                        continue
                    if self.src[self.i] == '"':
                        self._advance(1)
                        break
                    self._advance(1)
                out.append(Token("string", self.src[start:self.i], start_line, start_col))
                continue
            if ch == "'":
                literal = self._char_literal()
                if literal is not None:
                    out.append(literal)
                    continue
                start, start_line, start_col = self.i, self.line, self.col
                self._advance(1)
                while self.i < self.n and is_ident_part(self.src[self.i]) and self.src[self.i] != "'":
                    self._advance(1)
                out.append(Token("ident", self.src[start:self.i], start_line, start_col))
                continue
            if is_ident_start(ch):
                start, start_line, start_col = self.i, self.line, self.col
                self._advance(1)
                while self.i < self.n and is_ident_part(self.src[self.i]):
                    self._advance(1)
                out.append(Token("ident", self.src[start:self.i], start_line, start_col))
                continue
            if ch.isdigit():
                start, start_line, start_col = self.i, self.line, self.col
                while self.i < self.n and (self.src[self.i].isalnum() or self.src[self.i] in "._'"):
                    self._advance(1)
                out.append(Token("number", self.src[start:self.i], start_line, start_col))
                continue
            if ch in OPERATOR_CHARS:
                start, start_line, start_col = self.i, self.line, self.col
                while self.i < self.n and self.src[self.i] in OPERATOR_CHARS:
                    self._advance(1)
                out.append(Token("op", self.src[start:self.i], start_line, start_col))
                continue
            self._advance(1)
        return out


def char_detail(ch: str) -> str:
    try:
        name = unicodedata.name(ch)
    except ValueError:
        name = "UNKNOWN"
    return f"U+{ord(ch):04X} {name}"


def describe_chars(text: str, limit: int = 4) -> str:
    seen: list[str] = []
    for ch in text:
        if ord(ch) < 128:
            continue
        detail = char_detail(ch)
        if detail not in seen:
            seen.append(detail)
        if len(seen) >= limit:
            break
    return "; ".join(seen)


def classify_non_ascii(text: str) -> tuple[list[str], list[str]]:
    """Split the non-ASCII characters of a text into letters and decorations.

    Letters (Unicode categories L*) come from a writing system, so a Cyrillic
    word is text that has to be translated. Decorations (box drawing, arrows,
    dashes, bullets) are punctuation and carry no language.
    """
    letters: list[str] = []
    symbols: list[str] = []
    for ch in text:
        if ord(ch) < 128:
            continue
        (letters if ch.isalpha() else symbols).append(ch)
    return letters, symbols


def scripts_of(text: str) -> list[str]:
    """Names of the writing systems present in the text, most frequent first."""
    counts: dict[str, int] = {}
    for ch in text:
        if ord(ch) < 128 or not ch.isalpha():
            continue
        try:
            script = unicodedata.name(ch).split(" ")[0].title()
        except ValueError:
            continue
        counts[script] = counts.get(script, 0) + 1
    return [s for s, _ in sorted(counts.items(), key=lambda kv: -kv[1])]


def script_of(text: str) -> str:
    """Return the dominant writing system of the given text."""
    scripts = scripts_of(text)
    return scripts[0] if scripts else "Unknown"


def transliterate(text: str) -> str:
    out: list[str] = []
    for ch in text:
        if ord(ch) < 128:
            out.append(ch)
            continue
        repl = TRANSLIT.get(ch.lower())
        if repl is None:
            repl = CONFUSABLES.get(ch)
        out.append(repl if repl is not None else "_")
    return "".join(out)


def confusable_info(text: str) -> tuple[str, str] | None:
    """Describe how an identifier renders if the foreign characters are overlooked.

    Returns (kind, skeleton) where kind is:
      exact  every foreign character has an ASCII lookalike, so the whole
             identifier reads as a plain ASCII name ("pаssword" -> "password")
      mixed  the identifier mixes scripts, so foreign letters sit next to
             ASCII ones and the name still reads as ASCII at a glance
    Returns None when the identifier is not a homoglyph risk: a fully foreign
    word (no ASCII letters) cannot be mistaken for an English identifier.
    """
    non_ascii = [ch for ch in text if ord(ch) > 127]
    if not non_ascii:
        return None
    if not any(ch.isascii() and ch.isalpha() for ch in text):
        return None
    if not any(ch in CONFUSABLES or ch.lower() in CONFUSABLES for ch in non_ascii):
        return None

    skeleton: list[str] = []
    unmapped = 0
    for ch in text:
        if ord(ch) < 128:
            skeleton.append(ch)
            continue
        repl = CONFUSABLES.get(ch) or CONFUSABLES.get(ch.lower())
        if repl is None:
            skeleton.append("?")
            unmapped += 1
        else:
            skeleton.append(repl)
    return ("mixed" if unmapped else "exact", "".join(skeleton))


def analyze_file(path: Path, rel: str, opts: argparse.Namespace) -> list[Finding]:
    findings: list[Finding] = []
    try:
        src = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        print(f"[!] Error reading '{rel}': {exc}", file=sys.stderr)
        return findings

    def report(
        tok: Token,
        category: str,
        severity: str,
        message: str,
        letters: list[str],
        symbols: list[str],
        extra: dict | None = None,
    ) -> None:
        detail = {
            "chars": describe_chars("".join(letters + symbols)),
            "letters": len(letters),
            "symbols": len(symbols),
        }
        if letters:
            detail["scripts"] = scripts_of("".join(letters))
        if extra:
            detail.update(extra)
        findings.append(
            Finding(
                path=rel,
                line=tok.line,
                col=tok.col,
                category=category,
                severity=severity,
                message=message,
                detail=detail,
            )
        )

    for tok in Lexer(src).tokens():
        if tok.kind == "comment":
            if not opts.include_comments:
                continue
            letters, symbols = classify_non_ascii(tok.text)
            if letters:
                report(
                    tok,
                    "comment",
                    "info",
                    "non-English text in comment",
                    letters,
                    symbols,
                    {"scripts": scripts_of("".join(letters))},
                )
            elif symbols and opts.include_symbols:
                report(
                    tok,
                    "decoration",
                    "info",
                    "decorative non-ASCII characters in comment",
                    letters,
                    symbols,
                )
            continue

        if tok.kind == "string":
            if opts.symbols_only:
                continue
            letters, symbols = classify_non_ascii(tok.text)
            if not letters and not (symbols and opts.include_symbols):
                continue
            if opts.letters_only and not letters:
                continue
            report(
                tok,
                "string",
                "error" if opts.strict else "warning",
                "non-ASCII bytes in string literal",
                letters,
                symbols,
                {
                    "scripts": scripts_of(tok.text),
                    "snippet": tok.text.strip()[:120],
                },
            )
            continue

        if tok.kind == "char":
            if opts.symbols_only:
                continue
            letters, symbols = classify_non_ascii(tok.text)
            if not letters and not (symbols and opts.include_symbols):
                continue
            if opts.letters_only and not letters:
                continue
            report(
                tok,
                "char",
                "error" if opts.strict else "warning",
                "non-ASCII character literal",
                letters,
                symbols,
                {"snippet": tok.text},
            )
            continue

        if tok.kind not in ("ident", "op"):
            continue

        if not any(ord(c) > 127 for c in tok.text):
            continue

        letters, symbols = classify_non_ascii(tok.text)
        if opts.letters_only and not letters:
            continue

        category = "symbol" if tok.kind == "ident" else "operator"
        report(
            tok,
            category,
            "error",
            f"non-ASCII {category} '{tok.text}'",
            letters,
            symbols,
            {
                "symbol": tok.text,
                "scripts": scripts_of(tok.text),
                "suggestion": transliterate(tok.text),
            },
        )

        ascii_form = confusable_info(tok.text)
        if ascii_form is not None:
            kind, skeleton = ascii_form
            if kind == "exact":
                message = f"'{tok.text}' renders as '{skeleton}' (homoglyph)"
            else:
                message = (
                    f"mixed-script identifier '{tok.text}': "
                    f"foreign letters hide among ASCII ones ({skeleton})"
                )
            findings.append(
                Finding(
                    path=rel,
                    line=tok.line,
                    col=tok.col,
                    category="confusable",
                    severity="error",
                    message=message,
                    detail={
                        "symbol": tok.text,
                        "looks_like": skeleton,
                        "kind": kind,
                        "scripts": scripts_of(tok.text),
                        "suggestion": skeleton.replace("?", ""),
                    },
                )
            )
    return findings


def collect_files(
    root: Path,
    dirs: list[str] | None,
    extensions: set[str],
    excluded_dirs: set[str],
) -> list[Path]:
    matched: list[Path] = []
    roots = [root / d for d in dirs] if dirs else [root]
    for scan_root in roots:
        if not scan_root.exists():
            print(f"[!] Warning: directory '{scan_root}' does not exist, skipping.", file=sys.stderr)
            continue
        for dirpath, dirnames, filenames in os.walk(scan_root):
            dirnames[:] = [
                d for d in dirnames if d not in excluded_dirs and not d.startswith(".")
            ]
            for fname in filenames:
                candidate = Path(dirpath) / fname
                if candidate.suffix in extensions:
                    matched.append(candidate)
    matched.sort(key=lambda p: str(p.relative_to(root)) if p.is_relative_to(root) else str(p))
    return matched


def load_allowlist(path: Path | None) -> list[tuple[str, str]]:
    """Read an allowlist of 'path', 'path:line' or 'symbol:<name>' entries."""
    if path is None:
        return []
    if not path.is_file():
        print(f"[!] Allowlist not found: {path}", file=sys.stderr)
        return []
    entries: list[tuple[str, str]] = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("symbol:"):
            entries.append(("symbol", line[len("symbol:"):].strip()))
        elif ":" in line:
            entries.append(("path:line", line))
        else:
            entries.append(("path", line))
    return entries


def path_matches(found: str, entry: str) -> bool:
    """Match a reported path against an allowlist entry (absolute or relative)."""
    if not entry:
        return False
    found_norm = found.replace("\\", "/").lstrip("./")
    entry_norm = entry.replace("\\", "/").lstrip("./")
    if found_norm == entry_norm:
        return True
    if entry_norm.endswith("/" + found_norm):
        return True
    return os.path.basename(found_norm) == os.path.basename(entry_norm)


def is_allowed(finding: Finding, allowlist: list[tuple[str, str]]) -> bool:
    for kind, value in allowlist:
        if kind == "path" and path_matches(finding.path, value):
            return True
        if kind == "path:line":
            parts = value.rsplit(":", 1)
            if len(parts) == 2 and path_matches(finding.path, parts[0]):
                try:
                    if int(parts[1]) == finding.line:
                        return True
                except ValueError:
                    continue
        if kind == "symbol" and finding.detail.get("symbol") == value:
            return True
    return False


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Find non-English (non-ASCII) symbols in OCaml sources."
    )
    parser.add_argument(
        "-r", "--root", default=".", help="Root directory to scan (default: current directory)"
    )
    parser.add_argument(
        "-d",
        "--dirs",
        nargs="+",
        default=None,
        help="Subdirectories to scan (e.g. lib bin test). Default: the whole root.",
    )
    parser.add_argument(
        "--ext",
        nargs="+",
        default=DEFAULT_EXTENSIONS,
        help=f"File extensions to include (default: {' '.join(DEFAULT_EXTENSIONS)})",
    )
    parser.add_argument(
        "--symbols-only",
        action="store_true",
        help="Report identifiers/operators only, ignore string literals",
    )
    parser.add_argument(
        "--letters-only",
        action="store_true",
        help="Report only characters that belong to a writing system, skip decorations",
    )
    parser.add_argument(
        "--include-comments",
        action="store_true",
        help="Also report non-English text inside comments (informational)",
    )
    parser.add_argument(
        "--include-symbols",
        action="store_true",
        help="Also report decorative non-ASCII characters (box drawing, arrows, dashes)",
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="Print a per-file table of what has to be translated",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Treat non-ASCII string literals as errors as well",
    )
    parser.add_argument(
        "--allowlist",
        type=str,
        default=None,
        help="File with waived findings: 'path', 'path:line' or 'symbol:<name>' entries",
    )
    parser.add_argument(
        "--list-symbols",
        action="store_true",
        help="Print a summary of the offending identifiers and where they appear",
    )
    parser.add_argument("--json", action="store_true", help="Emit findings as JSON")
    parser.add_argument(
        "--quiet", action="store_true", help="Only print the final summary line"
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = Path(args.root).resolve()
    allowlist = load_allowlist(Path(args.allowlist).resolve() if args.allowlist else None)

    files = collect_files(
        root=root,
        dirs=args.dirs,
        extensions=set(args.ext),
        excluded_dirs=DEFAULT_EXCLUDED_DIRS,
    )
    if not files:
        print(f"[!] No OCaml sources found under {root}", file=sys.stderr)
        sys.exit(2)

    findings: list[Finding] = []
    for file_path in files:
        try:
            rel = str(file_path.relative_to(root))
        except ValueError:
            rel = str(file_path)
        findings.extend(analyze_file(file_path, rel, args))

    findings = [f for f in findings if not is_allowed(f, allowlist)]
    findings.sort(key=lambda f: (f.path, f.line, f.col, f.category))

    errors = [f for f in findings if f.severity == "error"]
    warnings = [f for f in findings if f.severity == "warning"]
    infos = [f for f in findings if f.severity == "info"]

    if args.json:
        print(
            json.dumps(
                {
                    "root": str(root),
                    "files_scanned": len(files),
                    "errors": len(errors),
                    "warnings": len(warnings),
                    "info": len(infos),
                    "findings": [
                        {
                            "path": f.path,
                            "line": f.line,
                            "col": f.col,
                            "category": f.category,
                            "severity": f.severity,
                            "message": f.message,
                            **f.detail,
                        }
                        for f in findings
                    ],
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        sys.exit(1 if errors else 0)

    if not args.quiet:
        for f in findings:
            print(f"{f.path}:{f.line}:{f.col}: {f.severity}: [{f.category}] {f.message}")
            if f.detail.get("chars"):
                print(f"{f.path}:{f.line}:{f.col}:   chars: {f.detail['chars']}")
            if f.category in ("symbol", "confusable") and f.detail.get("suggestion"):
                print(
                    f"{f.path}:{f.line}:{f.col}:   suggested ASCII name: "
                    f"{f.detail['suggestion']}"
                )
            if f.detail.get("snippet"):
                print(f"{f.path}:{f.line}:{f.col}:   text: {f.detail['snippet']}")

    if args.list_symbols:
        by_symbol: dict[str, list[str]] = {}
        for f in findings:
            if f.category not in ("symbol", "confusable"):
                continue
            sym = f.detail.get("symbol", f.message)
            by_symbol.setdefault(sym, []).append(f"{f.path}:{f.line}")
        if by_symbol:
            print()
            print("Offending identifiers:")
            for sym in sorted(by_symbol):
                where = by_symbol[sym]
                print(f"  {sym!r} -> {by_symbol[sym][0]} ({len(where)} occurrence(s))")

    if args.summary:
        per_file: dict[str, dict[str, int]] = {}
        for f in findings:
            if f.category in ("decoration",):
                continue
            bucket = per_file.setdefault(f.path, {})
            bucket[f.category] = bucket.get(f.category, 0) + 1
        if per_file:
            print()
            print("Files to fix (non-English text):")
            print(f"  {'file':<48} {'lines':>6}  {'code':>5}  {'str':>5}  {'cmt':>5}")
            print(f"  {'-' * 48} {'-' * 6}  {'-' * 5}  {'-' * 5}  {'-' * 5}")
            for path_name in sorted(
                per_file, key=lambda p: (-sum(per_file[p].values()), p)
            ):
                bucket = per_file[path_name]
                code = bucket.get("symbol", 0) + bucket.get("operator", 0) + bucket.get("confusable", 0)
                print(
                    f"  {path_name:<48} {sum(bucket.values()):>6}  "
                    f"{code:>5}  {bucket.get('string', 0) + bucket.get('char', 0):>5}  "
                    f"{bucket.get('comment', 0):>5}"
                )

    print(
        f"\nScanned {len(files)} OCaml file(s): "
        f"{len(errors)} error(s), {len(warnings)} warning(s), {len(infos)} info(s)."
    )
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
