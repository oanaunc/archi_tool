#!/usr/bin/env python3
# Oanarina Archi Tool — GPL-3.0-or-later
"""Parity catalogue generator for the Windows port.

Parses the Mac app's Swift sources (app/Sources/ArchiApp, plus the command registrations in ArchiCore) with a small
Swift expression/view-builder parser and writes

  docs/windows-parity.json   the single source of truth the Windows UI is generated from and checked against
  docs/WINDOWS-PARITY.md     the human checklist (one line per ribbon button, menu item, panel, dialog, shortcut,
                             render feature) with a status column for later rounds

Nothing is hand-copied: tabs, groups, buttons, menus, panels and dialogs are read from RibbonView.swift, ArchiApp.swift
(menu bar), CommandCatalog*/CommandCoverage/AppCommands* catalogs, ToolPalette.swift, PanelsView.swift and the *Panels*
files, MainWindow.swift, Preferences.swift, Dialogs.swift, OutputDialogs.swift, StartView.swift, StatusBarView.swift and
Theme.swift. Every registered command (CommandDef in app/Sources) is cross-checked against the ribbon/menu/palette
entries exactly like the Mac self-test (CommandCatalog.coverage).

Usage: python3 windows/tools/extract_parity.py [repo root] [--check]
  --check   exit 1 when a registered command has no UI entry or the parser reported errors
Python 3.8+, standard library only.
"""
import json, os, re, sys
from collections import OrderedDict

sys.dont_write_bytecode = True
ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else \
    os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CHECK = "--check" in sys.argv
APP = os.path.join(ROOT, "app", "Sources", "ArchiApp")
CORE = os.path.join(ROOT, "app", "Sources", "ArchiCore")
ERRORS = []

# ----------------------------------------------------------------------------------------------------------------------
# Lexer
# ----------------------------------------------------------------------------------------------------------------------
class Tok:
    __slots__ = ("k", "v", "nl", "sp", "line", "i")
    def __init__(self, k, v, nl, sp, line):
        self.k, self.v, self.nl, self.sp, self.line = k, v, nl, sp, line
    def __repr__(self): return "%s:%r" % (self.k, self.v)

OPS3 = ["..<", "...", "===", "!==", "&+=", "&-=", "&*="]
OPS2 = ["&*", "^=", "->", "==", "!=", "<=", ">=", "&&", "||", "??", "+=", "-=", "*=", "/=", "&+", "&-", "<<", ">>", "|=", "&="]

def lex(src):
    toks, i, n, line = [], 0, len(src), 1
    nl, sp = False, False
    while i < n:
        c = src[i]
        if c == "\n": nl = sp = True; line += 1; i += 1; continue
        if c in " \t\r": sp = True; i += 1; continue
        if src.startswith("//", i):
            j = src.find("\n", i); i = n if j < 0 else j; continue
        if src.startswith("/*", i):
            depth, i = 1, i + 2
            while i < n and depth:
                if src.startswith("/*", i): depth += 1; i += 2
                elif src.startswith("*/", i): depth -= 1; i += 2
                else:
                    if src[i] == "\n": line += 1; nl = True
                    i += 1
            sp = True; continue
        if c == '"' or (c == "#" and src.startswith('#"', i)):
            raw = c == "#"
            if raw: i += 1
            multi = src.startswith('"""', i)
            q = '"""' if multi else '"'
            i += len(q); j = i
            while j < n:
                if src[j] == "\\" and not raw:
                    if src.startswith("\\(", j):
                        depth, j = 1, j + 2
                        while j < n and depth:
                            if src[j] == "(": depth += 1
                            elif src[j] == ")": depth -= 1
                            elif src[j] == '"':  # nested string inside an interpolation
                                j += 1
                                while j < n and src[j] != '"':
                                    j += 2 if src[j] == "\\" else 1
                            j += 1
                        continue
                    j += 2; continue
                if src.startswith(q, j) and (not raw or src.startswith(q + "#", j)): break
                if src[j] == "\n": line += 1
                j += 1
            body = src[i:j]
            if multi:
                lines = body.split("\n")
                ind = len(lines[-1]) - len(lines[-1].lstrip()) if lines else 0
                body = "\n".join(l[ind:] for l in lines[1:-1])
            toks.append(Tok("str", body, nl, sp, line)); nl = sp = False
            i = j + len(q) + (1 if raw else 0); continue
        if c.isdigit():
            m = re.match(r"0x[0-9A-Fa-f_]+|0b[01_]+|0o[0-7_]+|\d[\d_]*(\.\d[\d_]*)?([eE][-+]?\d+)?", src[i:])
            toks.append(Tok("num", m.group(0), nl, sp, line)); nl = sp = False; i += len(m.group(0)); continue
        if c.isalpha() or c == "_" or c == "$" or c == "`":
            m = re.match(r"`[^`]+`|\$?[A-Za-z_0-9]+", src[i:])
            v = m.group(0).strip("`")
            toks.append(Tok("id", v, nl, sp, line)); nl = sp = False; i += len(m.group(0)); continue
        for o in OPS3 + OPS2:
            if src.startswith(o, i):
                toks.append(Tok("op", o, nl, sp, line)); nl = sp = False; i += len(o); break
        else:
            toks.append(Tok("op", c, nl, sp, line)); nl = sp = False; i += 1
    for k, t in enumerate(toks): t.i = k
    return toks

def match_brackets(toks):
    """Index of the matching closer for every opener ({ ( [)."""
    m, stack = {}, []
    pairs = {"}": "{", ")": "(", "]": "["}
    for k, t in enumerate(toks):
        if t.k != "op": continue
        if t.v in "{([": stack.append(k)
        elif t.v in pairs:
            while stack and toks[stack[-1]].v != pairs[t.v]: stack.pop()
            if stack: m[stack.pop()] = k
    return m

def text_of(toks, a, b):
    out = ""
    for t in toks[a:b]:
        s = '"%s"' % t.v if t.k == "str" else t.v
        out += (" " if t.sp and out else "") + s
    return out

# ----------------------------------------------------------------------------------------------------------------------
# Parser: Swift expressions, closures and view-builder statements (enough for SwiftUI declarations and catalogs)
# ----------------------------------------------------------------------------------------------------------------------
BINOPS = {"+", "-", "*", "/", "%", "==", "!=", "<", ">", "<=", ">=", "&&", "||", "??", "..<", "...", "&+", "&-",
          "=", "+=", "-=", "*=", "/=", "&+=", "|", "&", "^", "<<", ">>", "===", "!==", "&*", "^=", "|=", "&="}
KEYWORD_PREFIX = {"try", "await", "consume", "copy", "inout"}

class ParseError(Exception): pass

class Parser:
    def __init__(self, toks, a=0, b=None, match=None):
        self.t, self.p, self.end = toks, a, len(toks) if b is None else b
        self.m = match if match is not None else match_brackets(toks)
    def cur(self): return self.t[self.p] if self.p < self.end else None
    def peek(self, k=1): return self.t[self.p + k] if self.p + k < self.end else None
    def is_op(self, v, tok=None):
        t = tok if tok is not None else self.cur()
        return t is not None and t.k == "op" and t.v == v
    def is_id(self, v=None, tok=None):
        t = tok if tok is not None else self.cur()
        return t is not None and t.k == "id" and (v is None or t.v == v)
    def eat(self, v):
        if not self.is_op(v): raise ParseError("expected %r at line %s, got %r" % (v, self.cur().line if self.cur() else "EOF", self.cur()))
        self.p += 1
    def skip_to(self, k): self.p = k

    # --- statements ---
    def block(self):
        """'{' [params in] statements '}' -> ('closure', params, stmts)"""
        start = self.p
        self.eat("{")
        close = self.m.get(start, self.end - 1)
        params = self.closure_params(close)
        stmts = self.statements(close)
        self.p = close + 1
        return ("closure", params, stmts)

    def closure_params(self, close):
        k, names, depth = self.p, [], 0
        while k < close:
            t = self.t[k]
            if k > self.p and t.nl and depth == 0: return []
            if t.k == "id" and t.v == "in" and depth == 0:
                self.p = k + 1
                return names
            if t.k == "op" and t.v == "->":
                k += 1
                while k < close and not self.is_id("in", self.t[k]) and not self.t[k].nl: k += 1
                continue
            if t.k == "op" and t.v == "@": k += 2; continue
            if t.k == "op":
                if t.v in "([": depth += 1
                elif t.v in ")]": depth -= 1
                elif t.v == ":":
                    # skip the type annotation up to ',' or ')'
                    k += 1
                    while k < close and not (self.t[k].k == "op" and self.t[k].v in ",)") and not self.is_id("in", self.t[k]): k += 1
                    continue
                elif t.v not in ",_" and t.v not in "()[]": return []
            elif t.k == "id":
                if t.v in ("weak", "unowned", "self", "throws", "async"): pass
                elif depth <= 1: names.append(t.v)
            else: return []
            k += 1
        return []

    def statements(self, end):
        out = []
        while self.p < end:
            before = self.p
            try:
                s = self.statement(end)
            except ParseError as e:
                s = ("error", str(e)); ERRORS.append("parse %s: %s" % (CUR_FILE[0], e))
                self.p = max(self.p, before + 1)
                # resync at the next line start
                while self.p < end and not self.t[self.p].nl: self.p += 1
            if s is not None: out.append(s)
            if self.p == before: self.p += 1
        return out

    def raw_until_brace(self, end):
        a, depth = self.p, 0
        while self.p < end:
            t = self.t[self.p]
            if t.k == "op":
                if t.v in "([": self.p = self.m.get(self.p, self.p) + 1; continue
                if t.v == "{" and depth == 0: break
            self.p += 1
        return text_of(self.t, a, self.p), (a, self.p)

    def statement(self, end):
        t = self.cur()
        if t is None: return None
        if t.k == "op" and t.v in (";", ","): self.p += 1; return None
        if t.k == "op" and t.v == "@":
            self.p += 2
            if self.is_op("(") and not self.cur().sp: self.p = self.m[self.p] + 1
            return None
        if t.k == "id":
            v = t.v
            if v in ("private", "fileprivate", "public", "internal", "static", "nonisolated", "lazy", "weak", "final", "override", "indirect"):
                self.p += 1; return None
            if v in ("let", "var"):
                self.p += 1
                if self.is_op("("):  # tuple destructuring
                    close = self.m[self.p]; names = [x.v for x in self.t[self.p:close] if x.k == "id"]; self.p = close + 1; name = names
                else:
                    name = self.cur().v; self.p += 1
                typ = None
                if self.is_op(":"):
                    self.p += 1; a = self.p; depth = 0
                    while self.p < end:
                        x = self.t[self.p]
                        if x.k == "op" and x.v in "([<": depth += 1
                        elif x.k == "op" and x.v in ")]>": depth -= 1
                        if depth == 0 and x.k == "op" and x.v in ("=", "{", ","): break
                        if depth == 0 and self.p > a and x.nl: break
                        self.p += 1
                    typ = text_of(self.t, a, self.p)
                if self.is_op("="):
                    self.p += 1
                    e = self.expr()
                    while self.is_op(",") and not self.cur().nl:  # let a = 1, b: T = 2
                        self.p += 1
                        while self.p < end and not self.is_op("=") and not self.cur().nl: self.p += 1
                        if self.is_op("="): self.p += 1; self.expr()
                    return ("let", name, e, typ)
                if self.is_op("{"):
                    return ("let", name, ("computed", self.block()), typ)
                return ("let", name, None, typ)
            if v == "if":
                branches = []
                while True:
                    self.p += 1
                    cond, rng = self.raw_until_brace(end)
                    body = self.block()
                    branches.append((cond, body[2], rng))
                    if self.is_id("else"):
                        self.p += 1
                        if self.is_id("if"): continue
                        els = self.block()
                        return ("if", branches, els[2])
                    return ("if", branches, [])
            if v == "guard":
                self.p += 1
                cond, _ = self.raw_until_brace(end)
                body = self.block()
                return ("guard", cond, body[2])
            if v in ("for", "while"):
                self.p += 1
                head, rng = self.raw_until_brace(end)
                body = self.block()
                return ("for", head, body[2], rng)
            if v == "repeat":
                self.p += 1; self.block()
                if self.is_id("while"): self.p += 1; self.raw_until_brace(end);
                return None
            if v in ("do", "defer"):
                self.p += 1
                if self.is_op("{"):
                    b = self.block()
                    out = [("group", b[2])]
                    while self.is_id("catch"):
                        self.p += 1; self.raw_until_brace(end); self.block()
                    return out[0]
                return None
            if v == "switch":
                self.p += 1
                subj, rng = self.raw_until_brace(end)
                start = self.p; close = self.m[start]; self.p += 1
                cases = []
                while self.p < close:
                    if self.is_id("case") or self.is_id("default") or self.is_op("@"):
                        if self.is_op("@"): self.p += 2; continue
                        a = self.p; self.p += 1; depth = 0
                        while self.p < close:
                            x = self.t[self.p]
                            if x.k == "op" and x.v in "([": self.p = self.m.get(self.p, self.p) + 1; continue
                            if x.k == "op" and x.v == ":": break
                            self.p += 1
                        pat = text_of(self.t, a, self.p); self.p += 1
                        # body until next case/default at this level
                        b0 = self.p
                        k = self.p
                        while k < close:
                            x = self.t[k]
                            if x.k == "op" and x.v in "([{": k = self.m.get(k, k) + 1; continue
                            if x.k == "id" and x.v in ("case", "default") and (x.nl or (k > 0 and self.t[k - 1].k == "op" and self.t[k - 1].v == ";")): break
                            if x.k == "op" and x.v == "@" and x.nl and k + 1 < close and self.t[k + 1].v == "unknown": break
                            k += 1
                        body = self.statements(k)
                        self.p = k
                        cases.append((pat, body))
                    else:
                        self.p += 1
                self.p = close + 1
                return ("switch", subj, cases, rng)
            if v == "return":
                self.p += 1
                c = self.cur()
                if c is None or self.p >= end or c.nl or (c.k == "op" and c.v == "}"): return ("return", None)
                return ("return", self.expr())
            if v in ("break", "continue", "fallthrough"):
                self.p += 1; return None
            if v in ("func", "init", "struct", "enum", "class", "extension", "typealias"):
                # nested declaration: skip to its body end
                while self.p < end and not self.is_op("{"): self.p += 1
                if self.p < end: self.p = self.m.get(self.p, self.p) + 1
                return None
            if v == "throw":
                self.p += 1; self.expr(); return None
        return ("expr", self.expr())

    # --- expressions ---
    PREC = {"=": 1, "+=": 1, "-=": 1, "*=": 1, "/=": 1, "&+=": 1, "|=": 1, "&=": 1, "^=": 1, "&*": 9, "??": 3, "||": 4, "&&": 5,
            "==": 6, "!=": 6, "<": 6, ">": 6, "<=": 6, ">=": 6, "===": 6, "!==": 6, "..<": 7, "...": 7,
            "+": 8, "-": 8, "&+": 8, "&-": 8, "|": 8, "^": 8, "*": 9, "/": 9, "%": 9, "&": 9, "<<": 10, ">>": 10}

    def expr(self, minp=0):
        left = self.unary()
        while True:
            t = self.cur()
            if t is None: break
            if t.k == "op" and t.v == "?" and t.sp:  # ternary (precedence 2)
                if minp > 2: break
                self.p += 1
                a = self.expr()
                self.eat(":")
                b = self.expr(2)
                left = ("tern", left, a, b)
                continue
            if t.k == "op" and t.v in BINOPS:
                if t.v in ("<", ">") and not t.sp and not (self.peek() and self.peek().sp):  # generic arguments
                    break
                pr = self.PREC.get(t.v, 8)
                if pr < minp: break
                self.p += 1
                right = self.expr(pr if pr in (1, 3) else pr + 1)
                left = ("bin", t.v, left, right)
                continue
            if t.k == "id" and t.v in ("as", "is") and not t.nl:
                self.p += 1
                if self.is_op("?") or self.is_op("!"): self.p += 1
                self.type_skip()
                continue
            break
        return left

    def type_skip(self):
        if self.is_op("["): self.p = self.m[self.p] + 1
        elif self.is_op("("): self.p = self.m[self.p] + 1
        else:
            self.p += 1
            while self.is_op(".") and self.peek() and self.peek().k == "id": self.p += 2
            if self.is_op("<") and not self.cur().sp:
                depth = 0
                while self.p < self.end:
                    if self.is_op("<"): depth += 1
                    elif self.is_op(">"): depth -= 1
                    self.p += 1
                    if depth == 0: break
        while (self.is_op("?") or self.is_op("!")) and not self.cur().sp: self.p += 1

    def unary(self):
        t = self.cur()
        if t is None: raise ParseError("unexpected end")
        if t.k == "op" and t.v in ("..<", "..."):
            self.p += 1
            return ("bin", t.v, ("num", "0"), self.unary())
        if t.k == "op" and t.v in ("!", "-", "&", "~", "+"):
            self.p += 1
            return ("unary", t.v, self.unary())
        if t.k == "id" and t.v in KEYWORD_PREFIX:
            self.p += 1
            if (self.is_op("?") or self.is_op("!")) and not self.cur().sp: self.p += 1
            return self.unary()
        return self.postfix(self.primary())

    def primary(self):
        t = self.cur()
        if t.k == "str": self.p += 1; return ("str", t.v)
        if t.k == "num": self.p += 1; return ("num", t.v)
        if t.k == "id":
            self.p += 1
            if t.v in ("true", "false"): return ("bool", t.v == "true")
            if t.v == "nil": return ("nil",)
            if t.v == "if" or t.v == "switch":
                raise ParseError("if/switch expression")
            # generic type arguments: Foo<Bar>(...)
            if self.is_op("<") and not self.cur().sp and t.v[:1].isupper():
                k, depth = self.p, 0
                while k < self.end:
                    x = self.t[k]
                    if x.k == "op" and x.v == "<": depth += 1
                    elif x.k == "op" and x.v == ">":
                        depth -= 1
                        if depth == 0: break
                    elif x.k == "op" and x.v not in (",", ".", "?", "[", "]", ":"): k = -1; break
                    k += 1
                if k > 0: self.p = k + 1
            return ("id", t.v)
        if t.k == "op":
            if t.v == "[":
                close = self.m[self.p]; self.p += 1
                items, dict_items = [], []
                while self.p < close:
                    if self.is_op(","): self.p += 1; continue
                    if self.is_op(":") and self.p + 1 == close: self.p += 1; continue  # [:]
                    e = self.expr()
                    if self.is_op(":"):
                        self.p += 1; dict_items.append((e, self.expr()))
                    else: items.append(e)
                    if self.p < close and not self.is_op(","): raise ParseError("bad array element at line %d" % self.cur().line)
                self.p = close + 1
                return ("dict", dict_items) if dict_items else ("array", items)
            if t.v == "(":
                close = self.m[self.p]; self.p += 1
                items = self.args(close)
                self.p = close + 1
                if len(items) == 1 and items[0][0] is None: return ("paren", items[0][1])
                return ("tuple", items)
            if t.v == "{":
                return self.block()
            if t.v == ".":
                self.p += 1
                n = self.cur(); self.p += 1
                return ("member", None, n.v)
            if t.v == "\\":
                self.p += 1; a = self.p
                while (self.is_op(".") or self.is_id() or (self.cur() is not None and self.cur().k == "num")) and self.p < self.end:
                    if not self.is_op(".") and self.p > a and not self.is_op(".", self.t[self.p - 1]): break
                    self.p += 1
                return ("keypath", text_of(self.t, a, self.p))
            if t.v == "#":
                self.p += 1; n = self.cur(); self.p += 1
                return ("id", "#" + n.v)
            if t.v == "@":
                self.p += 2
                if self.is_op("("): self.p = self.m[self.p] + 1
                return self.primary()
        raise ParseError("unexpected %r at line %d" % (t.v, t.line))

    def args(self, close):
        items = []
        while self.p < close:
            if self.is_op(","): self.p += 1; continue
            label = None
            t, n = self.cur(), self.peek()
            if t.k == "id" and n is not None and n.k == "op" and n.v == ":" and self.p + 1 < close:
                label = t.v; self.p += 2
                if self.p >= close or self.is_op(",") or self.is_op(")"):
                    items.append((label, ("nil",))); continue
            elif t.k == "id" and n is not None and n.k == "op" and n.v == ":" and self.p + 1 == close:
                items.append((t.v, ("nil",))); self.p += 2; continue
            elif t.k == "op" and t.v in BINOPS and n is not None and n.k == "op" and n.v in (",", ")"):
                self.p += 1; items.append((label, ("op", t.v))); continue
            items.append((label, self.expr()))
            if self.p < close and not self.is_op(","): raise ParseError("bad argument at line %d: %r" % (self.cur().line, self.cur()))
        return items

    def postfix(self, e):
        while True:
            t = self.cur()
            if t is None: return e
            if t.k == "op" and t.v == "." :
                n = self.peek()
                if n is None: return e
                self.p += 2
                e = ("member", e, n.v)
                continue
            if t.k == "op" and t.v in ("?", "!") and not t.sp:
                self.p += 1; continue
            if t.k == "op" and t.v == "..." and (self.peek() is None or (self.peek().k == "op" and self.peek().v in ("]", ")", ","))):
                self.p += 1; e = ("bin", "...", e, ("id", "end")); continue
            if t.k == "id" and e[0] == "call" and e[3] and self.peek() and self.is_op(":", self.peek()) and self.peek(2) and self.is_op("{", self.peek(2)):
                lab = t.v; self.p += 2
                e = ("call", e[1], e[2], e[3] + [(lab, self.block())])
                continue
            if t.k == "op" and t.v == "(" and not t.nl:
                close = self.m[self.p]; self.p += 1
                a = self.args(close); self.p = close + 1
                e = ("call", e, a, [])
                continue
            if t.k == "op" and t.v == "[" and not t.nl:
                close = self.m[self.p]; self.p += 1
                a = self.args(close); self.p = close + 1
                e = ("sub", e, a)
                continue
            if t.k == "op" and t.v == "{" and not t.nl:
                clos = [(None, self.block())]
                while self.is_id() and self.peek() and self.is_op(":", self.peek()) and self.peek(2) and self.is_op("{", self.peek(2)) and not self.cur().nl:
                    lab = self.cur().v; self.p += 2
                    clos.append((lab, self.block()))
                if e[0] == "call": e = ("call", e[1], e[2], e[3] + clos)
                else: e = ("call", e, [], clos)
                continue
            return e

def parse_expr_text(s):
    toks = lex(s)
    if not toks: return ("str", "")
    try:
        return Parser(toks).expr()
    except (ParseError, KeyError, IndexError, AttributeError):
        return ("raw", s)

# ----------------------------------------------------------------------------------------------------------------------
# Declaration index: types, static members, enum cases, view structs, funcs
# ----------------------------------------------------------------------------------------------------------------------
class Decl:
    def __init__(self, typ, name, kind, node, typtext, file, params=None, line=0):
        self.type, self.name, self.kind, self.node, self.typtext, self.file = typ, name, kind, node, typtext, file
        self.params, self.line = params or [], line

DECLS = {}            # type -> name -> Decl
ENUMS = {}            # type -> [(case, raw)]
TYPES = {}            # type -> {"kind": struct/enum/class, "file", "conforms": text}
FILES = {}            # file -> (toks, match)
MODS = {"private", "fileprivate", "public", "internal", "static", "class", "nonisolated", "lazy", "weak", "final", "override",
        "mutating", "convenience", "required", "open", "unowned", "dynamic", "optional", "package"}

def parse_params(toks, a, b):
    """Swift parameter list tokens (inside the parens) -> [(label, name, default_text)]."""
    out, cur = [], []
    depth = 0
    for t in toks[a:b]:
        if t.k == "op" and t.v in "([<": depth += 1
        if t.k == "op" and t.v in ")]>": depth -= 1
        if t.k == "op" and t.v == "," and depth == 0:
            out.append(cur); cur = []
        else: cur.append(t)
    if cur: out.append(cur)
    res = []
    for p in out:
        if not p: continue
        ids = []
        for t in p:
            if t.k == "op" and t.v == ":": break
            if t.k == "id": ids.append(t.v)
        if not ids: continue
        label, name = (ids[0], ids[1]) if len(ids) > 1 else (ids[0], ids[0])
        dflt = None
        for k, t in enumerate(p):
            if t.k == "op" and t.v == "=": dflt = text_of(p, k + 1, len(p)); break
        res.append((label, name, dflt))
    return res

CUR_FILE = [""]

def index_file(path, keep=True):
    CUR_FILE[0] = os.path.basename(path)
    src = open(path, encoding="utf-8").read()
    toks = lex(src)
    m = match_brackets(toks)
    FILES[path] = (toks, m)
    fname = os.path.basename(path)

    def walk(a, b, typ):
        k = a
        while k < b:
            t = toks[k]
            if t.k == "op" and t.v == "@":
                k += 2
                if k < b and toks[k].k == "op" and toks[k].v == "(" and not toks[k].sp: k = m.get(k, k) + 1
                continue
            if t.k == "id" and t.v in ("enum", "struct", "class", "extension", "protocol", "actor") and k + 1 < b and toks[k + 1].k == "id":
                if t.v == "class" and toks[k + 1].v in ("func", "var", "let"): k += 1; continue
                name = toks[k + 1].v
                j = k + 2
                while j < b and toks[j].k == "op" and toks[j].v == "." and toks[j + 1].k == "id": name = toks[j + 1].v; j += 2
                if j < b and toks[j].k == "op" and toks[j].v == "<": # generic params
                    depth = 0
                    while j < b:
                        if toks[j].k == "op" and toks[j].v == "<": depth += 1
                        elif toks[j].k == "op" and toks[j].v == ">": depth -= 1
                        j += 1
                        if depth == 0: break
                cstart = j
                while j < b and not (toks[j].k == "op" and toks[j].v == "{"): j += 1
                if j >= b: return
                info = TYPES.setdefault(name, {"kind": t.v, "file": fname, "conforms": ""})
                if t.v != "extension": info["kind"], info["file"] = t.v, fname
                info["conforms"] += " " + text_of(toks, cstart, j)
                close = m.get(j, b)
                walk(j + 1, close, name)
                k = close + 1
                continue
            if t.k == "id" and t.v == "case" and typ is not None and TYPES.get(typ, {}).get("kind") in ("enum", "extension"):
                j = k + 1
                while j < b:
                    if toks[j].k != "id": break
                    cname = toks[j].v; raw = cname; j += 1
                    if j < b and toks[j].k == "op" and toks[j].v == "(": j = m.get(j, j) + 1
                    if j < b and toks[j].k == "op" and toks[j].v == "=":
                        raw = toks[j + 1].v; j += 2
                    ENUMS.setdefault(typ, []).append((cname, raw))
                    if j < b and toks[j].k == "op" and toks[j].v == "," and not toks[j + 1].nl: j += 1; continue
                    if j < b and toks[j].k == "op" and toks[j].v == ",": j += 1; continue
                    break
                k = j
                continue
            if t.k == "id" and t.v in ("let", "var", "func", "init", "subscript", "deinit"):
                kw = t.v
                j = k + 1
                name = toks[j].v if j < b else ""
                line = t.line
                if kw in ("init", "subscript", "deinit"): name = kw; j = k
                j += 1
                if kw in ("func", "init", "subscript"):
                    if j < b and toks[j].k == "op" and toks[j].v == "<":
                        depth = 0
                        while j < b:
                            if toks[j].v == "<": depth += 1
                            elif toks[j].v == ">": depth -= 1
                            j += 1
                            if depth == 0: break
                    params = []
                    if j < b and toks[j].k == "op" and toks[j].v == "(":
                        pc = m.get(j, j); params = parse_params(toks, j + 1, pc); j = pc + 1
                    rt0 = j
                    while j < b and not (toks[j].k == "op" and toks[j].v in ("{", "}")) and not (toks[j].k == "id" and toks[j].v in ("let", "var", "func") and toks[j].nl): j += 1
                    rtype = text_of(toks, rt0, j)
                    if j < b and toks[j].v == "{":
                        close = m.get(j, j)
                        if keep and typ is not None or keep and typ is None:
                            try:
                                body = Parser(toks, j, close + 1, m).block()
                            except Exception as e:  # noqa
                                ERRORS.append("%s:%d %s: %s" % (fname, line, name, e)); body = ("closure", [], [])
                            DECLS.setdefault(typ or "", {}).setdefault(name, Decl(typ, name, "func", body, rtype, fname, params, line))
                        k = close + 1
                    else: k = j
                    continue
                # let / var
                if j < b and toks[j].k == "op" and toks[j].v == ":":
                    j += 1; a2 = j; depth = 0
                    while j < b:
                        x = toks[j]
                        if x.k == "op" and x.v in "([<": depth += 1
                        elif x.k == "op" and x.v in ")]>": depth -= 1
                        if depth == 0 and x.k == "op" and x.v in ("=", "{"): break
                        if depth == 0 and j > a2 and x.nl: break
                        j += 1
                    typtext = text_of(toks, a2, j)
                else: typtext = ""
                if j < b and toks[j].k == "op" and toks[j].v == "=":
                    p = Parser(toks, j + 1, b, m)
                    try:
                        node = p.expr()
                    except Exception as e:  # noqa
                        ERRORS.append("%s:%d %s: %s" % (fname, line, name, e)); node = ("raw", "")
                        while p.p < b and not toks[p.p].nl: p.p += 1
                    DECLS.setdefault(typ or "", {}).setdefault(name, Decl(typ, name, "expr", node, typtext, fname, line=line))
                    k = p.p
                    if k < b and toks[k].k == "op" and toks[k].v == "{":  # didSet
                        k = m.get(k, k) + 1
                    continue
                if j < b and toks[j].k == "op" and toks[j].v == "{":
                    close = m.get(j, j)
                    inner = toks[j + 1] if j + 1 < close else None
                    if inner is not None and inner.k == "id" and inner.v in ("didSet", "willSet", "get", "set"):
                        k = close + 1; continue
                    try:
                        body = Parser(toks, j, close + 1, m).block()
                    except Exception as e:  # noqa
                        ERRORS.append("%s:%d %s: %s" % (fname, line, name, e)); body = ("closure", [], [])
                    DECLS.setdefault(typ or "", {}).setdefault(name, Decl(typ, name, "computed", body, typtext, fname, line=line))
                    k = close + 1
                    continue
                DECLS.setdefault(typ or "", {}).setdefault(name, Decl(typ, name, "stored", None, typtext, fname, line=line))
                k = j
                continue
            if t.k == "op" and t.v == "{":
                k = m.get(k, k) + 1; continue
            k += 1
    walk(0, len(toks), None)

# ----------------------------------------------------------------------------------------------------------------------
# Evaluator
# ----------------------------------------------------------------------------------------------------------------------
class Unknown:
    def __init__(self, text, alts=None): self.text, self.alts = text, alts or []
    def __repr__(self): return "?(%s)" % self.text
    def __bool__(self): return False

class Tup(list):
    labels = None

class Implicit(str):
    """An implicit member such as .small or .layers (raw: the enum raw value when known)."""
    raw = None

def enum_cases(typ):
    out = []
    for c, r in ENUMS.get(typ, []):
        x = Implicit(c); x.raw = r.strip('"') if isinstance(r, str) else c; out.append(x)
    return out

def is_item(v): return isinstance(v, dict) and "names" in v and "title" in v

def unparse(e):
    """Compact source text of an expression (for dynamic data and actions)."""
    if e is None: return ""
    k = e[0]
    if k == "id": return e[1]
    if k == "str": return '"%s"' % e[1]
    if k in ("num",): return e[1]
    if k == "bool": return "true" if e[1] else "false"
    if k == "nil": return "nil"
    if k == "member": return (unparse(e[1]) if e[1] is not None else "") + "." + e[2]
    if k == "call":
        s = unparse(e[1]) + "(" + ", ".join(((l + ": ") if l else "") + unparse(x) for l, x in e[2]) + ")"
        if e[3]: s += " {…}"
        return s
    if k == "sub": return unparse(e[1]) + "[" + ", ".join(unparse(x) for _, x in e[2]) + "]"
    if k == "bin": return unparse(e[2]) + " " + e[1] + " " + unparse(e[3])
    if k == "tern": return unparse(e[1]) + " ? " + unparse(e[2]) + " : " + unparse(e[3])
    if k == "unary": return e[1] + unparse(e[2])
    if k == "paren": return "(" + unparse(e[1]) + ")"
    if k == "array": return "[" + ", ".join(unparse(x) for x in e[1]) + "]"
    if k == "tuple": return "(" + ", ".join(((l + ": ") if l else "") + unparse(x) for l, x in e[1]) + ")"
    if k == "keypath": return "\\" + e[1]
    if k == "closure": return "{…}"
    return "…"

class Env:
    def __init__(self, typ=None, parent=None, vars=None):
        self.typ, self.parent, self.vars = typ, parent, vars or {}
    def get(self, n):
        e = self
        while e is not None:
            if n in e.vars: return True, e.vars[n]
            e = e.parent
        return False, None
    def child(self, vars=None, typ=None): return Env(typ or self.typ, self, dict(vars or {}))

HELPERS = set()       # helper functions returning CmdItem: c(title, symbol, names...)
_memo, _busy = {}, set()

def static_value(typ, name):
    key = (typ, name)
    if key in _memo: return _memo[key]
    d = DECLS.get(typ, {}).get(name)
    if d is None: return Unknown("%s.%s" % (typ, name))
    if key in _busy: return Unknown("%s.%s" % (typ, name))
    _busy.add(key)
    env = Env(typ)
    try:
        if d.kind == "expr": v = ev(d.node, env)
        elif d.kind == "computed": v = run_body(d.node[2], env)
        else: v = Unknown("%s.%s" % (typ, name))
    finally:
        _busy.discard(key)
    labels = re.match(r"\s*\[\s*\((.*)\)\s*\]\s*$", d.typtext or "")
    if labels and isinstance(v, list):
        labs = [x.split(":")[0].strip() for x in labels.group(1).split(",") if ":" in x]
        if labs:
            for x in v:
                if isinstance(x, Tup): x.labels = labs
    _memo[key] = v
    return v

def run_body(stmts, env):
    env = env.child()
    last = Unknown("empty")
    for s in stmts:
        if s[0] == "let" and s[2] is not None:
            env.vars[s[1] if isinstance(s[1], str) else s[1][0]] = ev(s[2], env) if s[2][0] != "computed" else Unknown(s[1])
        elif s[0] == "return": return ev(s[1], env) if s[1] is not None else None
        elif s[0] == "expr": last = ev(s[1], env)
    return last

def lookup_id(n, env):
    ok, v = env.get(n)
    if ok: return v
    t = env.typ
    while t is not None:
        if n in DECLS.get(t, {}): return static_value(t, n)
        t = None
    if n in DECLS.get("", {}): return static_value("", n)
    if n in TYPES or n in DECLS: return ("type", n)
    return Unknown(n)

def as_str(v):
    if isinstance(v, str): return v
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, (int, float)): return ("%g" % v) if isinstance(v, float) else str(v)
    if isinstance(v, Unknown):
        if v.alts: return " / ".join(as_str(a) for a in v.alts)
        return "{" + v.text + "}"
    return "{" + str(v) + "}"

def interp(s, env):
    out, i = "", 0
    while i < len(s):
        if s.startswith("\\(", i):
            depth, j = 1, i + 2
            while j < len(s) and depth:
                if s[j] == "(": depth += 1
                elif s[j] == ")": depth -= 1
                elif s[j] == '"':
                    j += 1
                    while j < len(s) and s[j] != '"': j += 2 if s[j] == "\\" else 1
                j += 1
            inner = s[i + 2:j - 1]
            v = ev(parse_expr_text(inner), env)
            out += as_str(v) if not isinstance(v, Unknown) else "{" + inner.strip() + "}"
            i = j; continue
        if s[i] == "\\" and i + 1 < len(s):
            out += {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "u": ""}.get(s[i + 1], s[i + 1])
            if s[i + 1] == "u":
                m = re.match(r"\{([0-9a-fA-F]+)\}", s[i + 2:])
                if m: out += chr(int(m.group(1), 16)); i += 2 + len(m.group(0)); continue
            i += 2; continue
        out += s[i]; i += 1
    return out

def call_closure(c, args, env):
    if not isinstance(c, tuple) or c[0] != "closure": return Unknown("closure")
    _, params, stmts = c
    vars = {}
    for k, a in enumerate(args):
        vars["$%d" % k] = a
        if k < len(params): vars[params[k]] = a
    if len(params) > 1 and len(args) == 1 and isinstance(args[0], (list, tuple)):
        for k, p in enumerate(params):
            if k < len(args[0]): vars[p] = args[0][k]
        vars["$0"] = args[0]
    return run_body(stmts, env.child(vars))

def num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)

def ev(e, env):
    try:
        return _ev(e, env)
    except RecursionError:
        return Unknown("recursion")
    except Exception as x:  # evaluation of unsupported Swift: keep the source text
        return Unknown(unparse(e) if e else str(x))

def _ev(e, env):
    if e is None: return None
    k = e[0]
    if k == "str": return interp(e[1], env)
    if k == "num":
        s = e[1].replace("_", "")
        if s.startswith("0x"): return int(s, 16)
        if s.startswith("0b"): return int(s, 2)
        return float(s) if ("." in s or "e" in s.lower()) else int(s)
    if k == "bool": return e[1]
    if k == "nil": return None
    if k == "id": return lookup_id(e[1], env)
    if k == "paren": return ev(e[1], env)
    if k == "array": return [ev(x, env) for x in e[1]]
    if k == "dict": return {as_str(ev(a, env)): ev(b, env) for a, b in e[1]}
    if k == "tuple":
        t = Tup(ev(x, env) for _, x in e[1])
        if any(l for l, _ in e[1]): t.labels = [l for l, _ in e[1]]
        return t
    if k == "closure": return e
    if k == "keypath": return ("keypath", e[1])
    if k == "unary":
        v = ev(e[2], env)
        if e[1] == "!" and isinstance(v, bool): return not v
        if e[1] == "-" and num(v): return -v
        return Unknown(unparse(e))
    if k == "tern":
        c = ev(e[1], env)
        if isinstance(c, bool): return ev(e[2] if c else e[3], env)
        a, b = ev(e[2], env), ev(e[3], env)
        return Unknown(unparse(e), [a, b])
    if k == "bin":
        op = e[1]
        if op == "??":
            a = ev(e[2], env)
            return a if a is not None and not isinstance(a, Unknown) else ev(e[3], env)
        a, b = ev(e[2], env), ev(e[3], env)
        if op in ("..<", "..."): return ("range", a, b, op == "...")
        if isinstance(a, Unknown) or isinstance(b, Unknown): return Unknown(unparse(e))
        if op == "+":
            if isinstance(a, list) and isinstance(b, list): return a + b
            if isinstance(a, str) and isinstance(b, str): return a + b
            if num(a) and num(b): return a + b
        if op == "-" and num(a) and num(b): return a - b
        if op == "*" and num(a) and num(b): return a * b
        if op == "/" and num(a) and num(b) and b: return a / b
        if op == "==": return a == b
        if op == "!=": return a != b
        if op == "&&" and isinstance(a, bool) and isinstance(b, bool): return a and b
        if op == "||" and isinstance(a, bool) and isinstance(b, bool): return a or b
        if op in ("<", ">", "<=", ">=") and num(a) and num(b): return {"<": a < b, ">": a > b, "<=": a <= b, ">=": a >= b}[op]
        return Unknown(unparse(e))
    if k == "member":
        if e[1] is None: return Implicit(e[2])
        base = ev(e[1], env)
        n = e[2]
        if isinstance(base, tuple) and base and base[0] == "type":
            if n in DECLS.get(base[1], {}): return static_value(base[1], n)
            if n in ("allCases",) and base[1] in ENUMS: return enum_cases(base[1])
            if base[1] in ENUMS and any(c == n for c, _ in ENUMS[base[1]]): return Implicit(n)
            return Unknown(unparse(e))
        if isinstance(base, Tup):
            if n.isdigit() and int(n) < len(base): return base[int(n)]
            if base.labels and n in base.labels: return base[base.labels.index(n)]
        if is_item(base):
            if n in base: return base[n]
            if n == "id": return base["title"]
        if isinstance(base, list):
            if n == "count": return len(base)
            if n == "isEmpty": return len(base) == 0
            if n == "first": return base[0] if base else None
            if n == "last": return base[-1] if base else None
        if isinstance(base, Implicit) and n == "rawValue": return base.raw or str(base)
        if isinstance(base, str):
            if n == "capitalized": return " ".join(w[:1].upper() + w[1:].lower() for w in base.split(" "))
            if n == "isEmpty": return base == ""
            if n == "uppercased": return base  # followed by a call
            if n == "rawValue": return base
        return Unknown(unparse(e))
    if k == "sub":
        base = ev(e[1], env)
        if not e[2]: return Unknown(unparse(e))
        idx = ev(e[2][0][1], env)
        if isinstance(base, list):
            if num(idx) and int(idx) < len(base): return base[int(idx)]
            if isinstance(idx, tuple) and idx[0] == "range" and num(idx[1]) and num(idx[2]):
                return base[int(idx[1]):int(idx[2]) + (1 if idx[3] else 0)]
        if isinstance(base, dict) and isinstance(idx, str): return base.get(idx, Unknown(unparse(e)))
        return Unknown(unparse(e))
    if k == "call":
        fn, args, clos = e[1], e[2], e[3]
        if fn[0] == "id":
            name = fn[1]
            if name == "CmdItem":
                d = {lab: ev(x, env) for lab, x in args}
                it = {"title": as_str(d.get("title", "")), "symbol": as_str(d.get("symbol", "")),
                      "names": [as_str(x) for x in d.get("names", [])] if isinstance(d.get("names"), list) else [as_str(d.get("names"))]}
                if d.get("args"): it["args"] = as_str(d["args"])
                return it
            if name in HELPERS and len(args) >= 3:
                vals = [ev(x, env) for _, x in args]
                return {"title": as_str(vals[0]), "symbol": as_str(vals[1]), "names": [as_str(x) for x in vals[2:]]}
            if name == "Array" and args:
                v = ev(args[0][1], env)
                return list(v) if isinstance(v, list) else v
            if name == "String" and args:
                v = ev(args[0][1], env)
                return as_str(v) if not isinstance(v, Unknown) else v
            if name in ("stride",):
                d = {lab: ev(x, env) for lab, x in args}
                if all(num(d.get(x)) for x in ("from", "to", "by")): return list(range(d["from"], d["to"], d["by"]))
            if name == "Set" and args: return ev(args[0][1], env)
            if name in ("min", "max") and len(args) == 2:
                a, b = ev(args[0][1], env), ev(args[1][1], env)
                if num(a) and num(b): return min(a, b) if name == "min" else max(a, b)
            return Unknown(unparse(e))
        if fn[0] == "member" and fn[1] is not None:
            meth = fn[2]
            if unparse(fn) in ("L10n.t",) and args: return ev(args[0][1], env)
            base = ev(fn[1], env)
            av = [ev(x, env) for _, x in args]
            if isinstance(base, list):
                if meth == "prefix" and av and num(av[0]): return base[:int(av[0])]
                if meth == "dropFirst": return base[int(av[0]) if av and num(av[0]) else 1:]
                if meth == "suffix" and av and num(av[0]): return base[-int(av[0]):] if av[0] else []
                if meth == "dropLast": n2 = int(av[0]) if av and num(av[0]) else 1; return base[:-n2] if n2 else base
                if meth in ("sorted",) and not clos and not args:
                    try: return sorted(base)
                    except TypeError: return base
                if meth == "reversed": return list(reversed(base))
                if meth == "joined":
                    sep = av[0] if av else ""
                    if all(isinstance(x, list) for x in base): return [y for x in base for y in x]
                    return sep.join(as_str(x) for x in base)
                if meth in ("map", "flatMap", "compactMap", "filter", "first", "contains"):
                    f = clos[0][1] if clos else (args[0][1] if args else None)
                    if f is not None and f[0] == "keypath":
                        path = f[1].lstrip(".")
                        res = []
                        for x in base:
                            v = x
                            for part in path.split("."):
                                v = ev(("member", ("lit", v), part), env) if False else _member_of(v, part)
                            res.append(v)
                        if meth == "flatMap": return [y for x in res for y in (x if isinstance(x, list) else [x])]
                        return res
                    if f is not None and f[0] == "closure":
                        res = [call_closure(f, [x], env) for x in base]
                        if meth == "map": return res
                        if meth == "compactMap": return [x for x in res if x is not None]
                        if meth == "flatMap": return [y for x in res for y in (x if isinstance(x, list) else [x])]
                        if meth == "filter":
                            if all(isinstance(x, bool) for x in res): return [x for x, keep in zip(base, res) if keep]
                            return Unknown(unparse(e))
                        if meth == "first":
                            for x, keep in zip(base, res):
                                if keep is True: return x
                            return None
                        if meth == "contains": return any(x is True for x in res)
                    if meth == "contains" and av: return av[0] in base
                    if meth == "first" and not args and not clos: return base[0] if base else None
                if meth == "firstIndex" and args:
                    try: return base.index(av[0])
                    except ValueError: return None
            if isinstance(base, str):
                if meth == "uppercased": return base.upper()
                if meth == "lowercased": return base.lower()
                if meth == "hasPrefix" and av and isinstance(av[0], str): return base.startswith(av[0])
                if meth == "replacingOccurrences":
                    d = {lab: v for (lab, _), v in zip(args, av)}
                    if isinstance(d.get("of"), str) and isinstance(d.get("with"), str): return base.replace(d["of"], d["with"])
            if isinstance(base, tuple) and base and base[0] == "type":
                if meth in DECLS.get(base[1], {}) and DECLS[base[1]][meth].kind == "func" and "CmdItem" in DECLS[base[1]][meth].typtext:
                    vals = av
                    return {"title": as_str(vals[0]), "symbol": as_str(vals[1]), "names": [as_str(x) for x in vals[2:]]}
            return Unknown(unparse(e))
        return Unknown(unparse(e))
    if k == "lit": return e[1]
    return Unknown(unparse(e))

def _member_of(v, part):
    if isinstance(v, Tup):
        if part.isdigit(): return v[int(part)] if int(part) < len(v) else Unknown(part)
        if v.labels and part in v.labels: return v[v.labels.index(part)]
    if is_item(v) and part in v: return v[part]
    if isinstance(v, str) and part == "rawValue": return v
    return Unknown(part)

def deep_text(n):
    """Full source-like text of an AST node, closures included (for effect matching)."""
    if n is None: return ""
    if isinstance(n, list): return "; ".join(deep_stmt(s) for s in n)
    k = n[0]
    if k == "closure": return "{ " + "; ".join(deep_stmt(s) for s in n[2]) + " }"
    if k == "call":
        s = deep_text(n[1]) + "(" + ", ".join(((l + ": ") if l else "") + deep_text(x) for l, x in n[2]) + ")"
        for l, c in n[3]: s += " " + ((l + ": ") if l else "") + deep_text(c)
        return s
    if k == "member": return (deep_text(n[1]) if n[1] is not None else "") + "." + n[2]
    if k == "bin": return deep_text(n[2]) + " " + n[1] + " " + deep_text(n[3])
    if k == "tern": return deep_text(n[1]) + " ? " + deep_text(n[2]) + " : " + deep_text(n[3])
    if k == "unary": return n[1] + deep_text(n[2])
    if k == "paren": return "(" + deep_text(n[1]) + ")"
    if k == "sub": return deep_text(n[1]) + "[" + ", ".join(deep_text(x) for _, x in n[2]) + "]"
    if k == "array": return "[" + ", ".join(deep_text(x) for x in n[1]) + "]"
    if k == "tuple": return "(" + ", ".join(((l + ": ") if l else "") + deep_text(x) for l, x in n[1]) + ")"
    return unparse(n)

def deep_stmt(s):
    k = s[0]
    if k == "expr": return deep_text(s[1])
    if k == "let": return "let %s = %s" % (s[1], deep_text(s[2]) if s[2] and s[2][0] != "computed" else "")
    if k == "return": return "return " + deep_text(s[1])
    if k == "if": return " ".join("if %s { %s }" % (c, deep_text(b)) for c, b, _ in s[1]) + (" else { %s }" % deep_text(s[2]) if s[2] else "")
    if k in ("group", "guard"): return deep_text(s[-1])
    if k == "for": return "for %s { %s }" % (s[1], deep_text(s[2]))
    if k == "switch": return "switch %s { %s }" % (s[1], " ".join("%s: %s" % (p, deep_text(b)) for p, b in s[2]))
    return ""

# ----------------------------------------------------------------------------------------------------------------------
# Registry (every CommandDef) and command effects
# ----------------------------------------------------------------------------------------------------------------------
REG, ALIAS, SUBCOMMANDS = OrderedDict(), {}, []

def load_registry():
    sys.path.insert(0, os.path.join(ROOT, "docs"))
    import gen_command_reference as g  # the same scanner that writes the USER-GUIDE command reference
    g.ROOT = ROOT
    for n, (cat, al, summary, app) in g.collect().items():
        REG[n] = {"name": n, "aliases": al, "category": cat, "summary": summary, "app": app}
    skip = {"LTSCALE", "DIMSTYLE", "TEXTSTYLE"}
    known = static_value("SystemVariables", "known"); stored = static_value("SystemVariables", "stored")
    for n in (known if isinstance(known, list) else []) + (stored if isinstance(stored, list) else []):
        if n not in skip and n not in REG:
            REG[n] = {"name": n, "aliases": [], "category": "Settings", "summary": "System variable %s." % n, "app": False}
    # CommandDefs that are only run as sub-steps of another command (static var x: CommandDef used as x.run(ed)) are not registered
    texts = {}
    for dp, _, fs in os.walk(os.path.join(ROOT, "app", "Sources")):
        for f in fs:
            if f.endswith(".swift"): texts[os.path.join(dp, f)] = open(os.path.join(dp, f), encoding="utf-8").read()
    alltext = "\n".join(texts.values())
    from collections import Counter
    words = Counter(re.findall(r"\b[a-z]\w*\b", alltext))
    runs = Counter(re.findall(r"\b([a-z]\w*)\.run\(", alltext))
    decls = Counter(re.findall(r"\b(?:let|var)\s+([a-z]\w*)", alltext))
    for t in texts.values():
        for m in re.finditer(r'static (?:let|var) (\w+)(?:\s*:\s*CommandDef)?\s*[={]\s*CommandDef\(\s*"([A-Z0-9_]+)"', t):
            member, name = m.groups()
            if name in REG and words[member] - runs[member] - decls[member] <= 0:
                REG[name]["subcommandOnly"] = True
    for n in [n for n, d in REG.items() if d.get("subcommandOnly")]:
        SUBCOMMANDS.append(n); del REG[n]
    for n, d in REG.items():
        ALIAS.setdefault(n, n)
    for n, d in REG.items():
        for a in d["aliases"]: ALIAS.setdefault(a, n)

def resolve(names):
    for n in names:
        if n.upper() in ALIAS: return ALIAS[n.upper()]
    return None

EFFECT_RES = [("sheet", r"sheet\s*=\s*\.(\w+)"), ("window", r"\b(\w+Window)\.show\((?:\.(\w+))?"), ("plotter", r"\bPlotter\.(\w+)"),
              ("render", r"\bRenderController\.(\w+)"), ("model", r"model\??\.(purge|audit)\("), ("state", r"\b(\w+State)\.shared\.toggle"),
              ("toggle", r"\.(show\w+)\.toggle\(\)"), ("handle", r"files\.handle\(\.(\w+)"), ("window", r"openWindow\(id: \"([\w-]+)\"")]

def effects(text):
    out = []
    for name, rx in EFFECT_RES:
        for m in re.finditer(rx, text): out.append(name + ":" + ".".join(g for g in m.groups() if g))
    return out

EFFECT_CMD = {}
def index_effects():
    for f in sorted(os.listdir(APP)):
        if not f.endswith(".swift"): continue
        src = open(os.path.join(APP, f), encoding="utf-8").read()
        starts = [m for m in re.finditer(r'CommandDef\(\s*"([A-Z0-9_]+)"', src)]
        for i, m in enumerate(starts):
            end = starts[i + 1].start() if i + 1 < len(starts) else min(len(src), m.end() + 4000)
            for eff in effects(src[m.end():end]):
                EFFECT_CMD.setdefault(eff, m.group(1))
        # dispatch tables such as FileController: case "drafting", "dsettings": model.sheet = .drafting
        for m in re.finditer(r'case ((?:"[\w-]+"\s*,?\s*)+):\s*([^\n]*)', src):
            names = [x.upper() for x in re.findall(r'"([\w-]+)"', m.group(1))]
            cmd = next((x for x in names if x in REG), None)
            if cmd:
                for eff in effects(m.group(2)): EFFECT_CMD.setdefault(eff, cmd)

# ----------------------------------------------------------------------------------------------------------------------
# Shortcuts
# ----------------------------------------------------------------------------------------------------------------------
MAC_GLYPH = {"command": "⌘", "shift": "⇧", "option": "⌥", "control": "⌃"}
KEYNAMES = {"return": "Enter", "defaultAction": "Enter", "cancelAction": "Esc", "escape": "Esc", "delete": "Backspace",
            "deleteForward": "Del", "space": "Space", "tab": "Tab", "upArrow": "Up", "downArrow": "Down", "leftArrow": "Left", "rightArrow": "Right"}

def shortcut_from_mod(args, env):
    if not args: return None
    key = ev(args[0][1], env)
    mods = ["command"]
    for lab, x in args[1:]:
        if lab == "modifiers":
            v = ev(x, env)
            mods = [str(m) for m in (v if isinstance(v, list) else [v])]
    if isinstance(key, Implicit):
        if key in ("defaultAction", "cancelAction"): return {"mac": KEYNAMES[key], "win": KEYNAMES[key], "role": key}
        key = KEYNAMES.get(key, key)
    key = as_str(key)
    order = ["control", "option", "shift", "command"]
    mac = "".join(MAC_GLYPH[m] for m in order if m in mods) + key.upper()
    win = []
    if "command" in mods or "control" in mods: win.append("Ctrl")
    if "option" in mods: win.append("Alt")
    if "shift" in mods: win.append("Shift")
    win.append(key.upper() if len(key) == 1 else key)
    return {"mac": mac, "win": "+".join(win), "mods": mods}

def mac_to_win(s):
    """'⇧⌘P' / '⌥⌘1 … ⌥⌘4' / '⌃0' -> Windows notation (Cmd->Ctrl, Option->Alt, Control->Ctrl)."""
    def one(m):
        g = m.group(0); key = g.lstrip("⌃⌥⇧⌘")
        mods = []
        if "⌘" in g or "⌃" in g: mods.append("Ctrl")
        if "⌥" in g: mods.append("Alt")
        if "⇧" in g: mods.append("Shift")
        return "+".join(mods + [key.upper() if len(key) == 1 else key])
    return re.sub(r"[⌃⌥⇧⌘]+(?:[A-Za-z0-9=\-/,.]|F\d+)", one, s)

# ----------------------------------------------------------------------------------------------------------------------
# Actions -> command
# ----------------------------------------------------------------------------------------------------------------------
PANEL_RAW = {}
MODE_MAP = {"plan": "2D", "model": "3D", "split": "Split", "sheet": "Sheet"}

def find_calls(n, out):
    """All ('call'|'bin =') nodes in an AST, depth first."""
    if isinstance(n, list):
        for s in n:
            if isinstance(s, tuple):
                for x in s[1:]:
                    if isinstance(x, (tuple, list)): find_calls(x, out)
        return out
    if not isinstance(n, tuple) or not n: return out
    if n[0] == "call" or (n[0] == "bin" and n[1] == "="): out.append(n)
    for x in n[1:]:
        if isinstance(x, tuple): find_calls(x, out)
        elif isinstance(x, list):
            for y in x:
                if isinstance(y, tuple):
                    if len(y) == 2 and (y[0] is None or isinstance(y[0], str)) and isinstance(y[1], tuple): find_calls(y[1], out)
                    else: find_calls(y, out)
    return out

def resolve_action(action, env, help_text="", title=""):
    """Maps a SwiftUI button action to the command the Windows shell runs: a registered command (+args) or a shell
    action "@panel:…", "@mode:…", "@zoom:…", "@export:…", … (same vocabulary as windows/src/renderer/app.ts)."""
    res = {}
    stmts = action[2] if action and action[0] == "closure" else []
    calls = find_calls(stmts, [])
    text = deep_text(stmts)
    for c in calls:
        if c[0] == "call" and unparse(c[1]).split(".")[-1] == "runCommand" and c[2]:
            line = as_str(ev(c[2][0][1], env)).strip()
            if isinstance(ev(c[2][0][1], env), Unknown) and "?" in unparse(c[2][0][1]):
                line = unparse(c[2][0][1])
            w = line.split(" ", 1)
            res = {"command": w[0]}
            if len(w) > 1: res["args"] = w[1]
            return res
    m = re.search(r"panelTab = \.(\w+)", text)
    if m: return {"command": "@panel:" + PANEL_RAW.get(m.group(1), m.group(1))}
    m = re.search(r"model\??\.mode = \.(\w+)$", text.strip("{} ;")) or (re.search(r"^\{ model\??\.mode = \.(\w+) \}$", text.strip()))
    if m: return {"command": "@mode:" + MODE_MAP.get(m.group(1), m.group(1))}
    m = re.search(r"files\.handle\(\.setViewStyle\((.*?)\)\)", text)
    if m:
        v = ev(parse_expr_text(m.group(1)), env)
        return {"command": "VSCURRENT", "args": as_str(v) if not isinstance(v, Unknown) else "{" + m.group(1) + "}"}
    m = re.search(r"files\.handle\(\.setView\((.*?)\)\)", text)
    if m:
        v = ev(parse_expr_text(m.group(1)), env)
        if isinstance(v, str):
            c = "ISOVIEW" if v == "Iso" else v.upper() + "VIEW"
            if c in REG: return {"command": c}
        return {"command": "@view:" + as_str(v)}
    m = re.search(r"FloatingPanels\.float\((.*?), model", text)
    if m:
        v = ev(parse_expr_text(m.group(1)), env)
        return {"command": "FLOATPANEL", "args": getattr(v, "raw", as_str(v))}
    m = re.search(r"openWindow\(value: DocumentRequest\(kind: \.(\w+)", text)
    if m: return {"command": "@newWindow:" + m.group(1)}
    rules = [(r"files\.saveAs\(", "SAVEAS"), (r"files\.save\(", "SAVE"), (r"openFromMenu\(", "OPEN"), (r"files\.importPanel", "IMPORT"),
             (r"performClose", "CLOSE"), (r"editor\.redo\(", "REDO"), (r"editor\.undo\(", "UNDO"), (r"Clipboard\.copy.*deleteSelection", "CUTCLIP"),
             (r"Clipboard\.copy", "COPYCLIP"), (r"Clipboard\.paste", "PASTECLIP"), (r"selection = \[\]", "@deselectAll"),
             (r"Plotter\.printDrawing", "PLOT"), (r"Plotter\.publish", "PUBLISH"), (r"RenderController\.renderImage", "RENDER"),
             (r"showViewCube\.toggle", "NAVVCUBE"), (r"showSectionBoxPanel\.toggle", "SECTIONBOX"), (r"showSunStudy\.toggle", "SUNSTUDY"),
             (r"sheet = \.saveCamera", "SAVECAMERA"), (r"showPanels\.toggle", "@panels:toggle"), (r"showQuickProperties\.toggle", "@panel:Quick Props"),
             (r"showCommandSearch = true", "COMMANDSEARCH"), (r"showStart = true", "STARTSCREEN"), (r"HelpBrowser\.show", "HELP"),
             (r"NSWorkspace\.shared\.open\(u\)|openExternal", "@openURL"),
             (r"handle\(\.walkthrough\)", "WALK"), (r"selectAll\(\)", "@selectAll"), (r"cleanScreen\.toggle", "@cleanScreen"), (r"zoomExtents\(\)", "@zoom:extents"),
             (r"zoomBy\(1 / 1\.5\)", "@zoom:out"), (r"zoomBy\(1\.5\)", "@zoom:in"), (r"zoomWindowPending = true", "@zoom:window"),
             (r"showScriptConsole\.toggle", "@scriptConsole"), (r"runScriptFile", "@runScript"), (r"toggleAgentServer", "@agent:toggle")]
    for rx, cmd in rules:
        if re.search(rx, text): return {"command": cmd}
    m = re.search(r'files\.export\(format: (.*?), path', text)
    if m:
        f = ev(parse_expr_text(m.group(1)), env)
        return {"command": "@export:" + (as_str(f) if not isinstance(f, Unknown) else m.group(1))}
    for m in re.finditer(r"\(([A-Z][A-Z0-9]{1,})[,)\s]", help_text or ""):
        if m.group(1) in ALIAS: return {"command": ALIAS[m.group(1)], "ui": effects(text)[0] if effects(text) else ""}
    for eff in effects(text):
        if eff in EFFECT_CMD: return {"command": EFFECT_CMD[eff], "ui": eff}
    effs = effects(text)
    for eff in effs:
        nm = eff.split(":", 1)[1].split(".")[0].upper()
        if nm in REG: return {"command": nm, "ui": eff}
    if effs: return {"command": "@ui:" + effs[0]}
    first = [unparse(c[1]) for c in calls if c[0] == "call"]
    return {"command": "@ui:" + (first[0] if first else text[:60])}

# ----------------------------------------------------------------------------------------------------------------------
# Generic view-tree helpers
# ----------------------------------------------------------------------------------------------------------------------
def strip_mods(e):
    """Splits `View(...).mod1(...).mod2 {...}` into (core, [(modname, args, closures)])."""
    mods = []
    while e and e[0] == "call" and e[1][0] == "member" and e[1][1] is not None and e[2] is not None:
        name = e[1][2]
        base = e[1][1]
        if not name[:1].islower(): break
        if base[0] not in ("call", "id") and not (base[0] == "member" and base[1] is not None): break
        # a method call on a value (model.runCommand(...)) is not a modifier: the base must look like a view
        if base[0] == "id" and base[1][:1].islower() and base[1] not in DECLS.get(CURRENT_TYPE[0], {}): break
        if base[0] == "member": break
        mods.insert(0, (name, e[2], e[3]))
        e = base
    return e, mods

CURRENT_TYPE = [None]

def mod(mods, name):
    for n, a, c in mods:
        if n == name: return a, c
    return None

def core_name(e):
    if e[0] == "call":
        f = e[1]
        if f[0] == "id": return f[1]
        if f[0] == "member": return unparse(f)
    if e[0] == "id": return e[1]
    return None

def arg(args, i=None, label=None):
    if label is not None:
        for l, x in args:
            if l == label: return x
        return None
    pos = [x for l, x in args if l is None]
    return pos[i] if i is not None and i < len(pos) else None

def label_of(closure, env):
    """Title and symbol of a label closure (Label / Text / Image)."""
    title, sym = None, None
    stmts = closure[2] if closure and closure[0] == "closure" else []
    stack = list(stmts)
    while stack:
        s = stack.pop(0)
        if s[0] != "expr": 
            if s[0] == "if": stack[0:0] = [x for _, b, _ in s[1] for x in b]
            continue
        core, _ = strip_mods(s[1])
        n = core_name(core)
        if n == "Label":
            if core[2]:
                a0 = arg(core[2], 0)
                if a0 is not None and title is None: title = ev(a0, env)
                si = arg(core[2], label="systemImage")
                if si is not None and sym is None: sym = ev(si, env)
            for _, c in core[3]:
                t2, s2 = label_of(c, env)
                title = title if title is not None else t2; sym = sym or s2
        elif n == "Text" and title is None and core[2]:
            title = ev(arg(core[2], 0), env)
        elif n == "Image" and sym is None and core[2]:
            si = arg(core[2], label="systemName")
            if si is not None: sym = ev(si, env)
        elif core[0] == "call":
            for _, c in core[3]: stack.append(("expr", c)) if False else stack.extend(c[2])
    return title, sym

def title_str(v):
    if v is None: return ""
    if isinstance(v, Unknown) and v.alts: return " / ".join(title_str(a) for a in v.alts)
    return as_str(v)

def member_decl(name):
    t = CURRENT_TYPE[0]
    return DECLS.get(t, {}).get(name) if t else None

def bind_params(d, args, env):
    vars = {}
    pos = [x for l, x in args if l is None]
    labeled = {l: x for l, x in args if l}
    pi = 0
    for label, name, dflt in d.params:
        if label == "_" and pi < len(pos): vars[name] = ev(pos[pi], env); pi += 1
        elif label in labeled: vars[name] = ev(labeled[label], env)
        elif label != "_" and pi < len(pos) and label not in labeled and not labeled: vars[name] = ev(pos[pi], env); pi += 1
        elif dflt is not None: vars[name] = ev(parse_expr_text(dflt), env)
    return vars

# ----------------------------------------------------------------------------------------------------------------------
# Menus (menu bar, ribbon drop-down menus, status bar menus)
# ----------------------------------------------------------------------------------------------------------------------
def cmd_item(it, extra=None):
    r = resolve(it["names"])
    d = {"title": it["title"], "symbol": it["symbol"], "command": r or it["names"][0]}
    if it.get("args"): d["args"] = it["args"]
    if len(it["names"]) > 1: d["names"] = it["names"]
    if r is None: d["unregistered"] = True
    if extra: d.update(extra)
    return d

def menu_items(stmts, env, depth=0):
    out = []
    if depth > 6: return out
    for s in stmts:
        k = s[0]
        if k == "let" and s[2] is not None and not isinstance(s[1], list):
            env = env.child({s[1]: ev(s[2], env) if s[2][0] != "computed" else Unknown(s[1])}); continue
        if k == "if":
            for c, b, _ in s[1]: out += [dict(x, when=c) if not x.get("when") else x for x in menu_items(b, env, depth + 1)]
            out += menu_items(s[2], env, depth + 1)
            continue
        if k == "switch":
            for p, b in s[2]: out += menu_items(b, env, depth + 1)
            continue
        if k == "group": out += menu_items(s[1], env, depth + 1); continue
        if k != "expr": continue
        core, mods = strip_mods(s[1])
        n = core_name(core)
        if n is None: continue
        args = core[2] if core[0] == "call" else []
        clos = core[3] if core[0] == "call" else []
        item = None
        if n == "Divider": out.append({"separator": True}); continue
        if n == "Button":
            title, sym = None, None
            a0 = arg(args, 0)
            if a0 is not None: title = ev(a0, env)
            action = arg(args, label="action")
            action = ("closure", [], [("expr", ("call", action, [], []))]) if action is not None else None
            for lab, c in clos:
                if lab is None and action is None and title is not None: action = c
                elif lab is None and action is None and title is None: action = c
                elif lab == "label": t2, sym = label_of(c, env); title = title if title is not None else t2
            if title is None and len(clos) > 1: title, sym = label_of(clos[1][1], env)
            help_m = mod(mods, "help")
            help_t = title_str(ev(help_m[0][0][1], env)) if help_m and help_m[0] else ""
            item = {"title": title_str(title)}
            if sym: item["symbol"] = title_str(sym)
            item.update(resolve_action(action, env, help_t, item["title"]))
        elif n == "Menu":
            title, sym = None, None
            a0 = arg(args, 0)
            if a0 is not None: title = ev(a0, env)
            content = next((c for l, c in clos if l is None), None)
            lab = next((c for l, c in clos if l == "label"), None)
            if lab is not None: t2, sym = label_of(lab, env); title = title if title is not None else t2
            item = {"title": title_str(title), "submenu": menu_items(content[2], env, depth + 1) if content else []}
            if sym: item["symbol"] = title_str(sym)
        elif n in ("Section",):
            a0 = arg(args, 0)
            if a0 is not None: out.append({"header": title_str(ev(a0, env))})
            for _, c in clos: out += menu_items(c[2], env, depth + 1)
            continue
        elif n == "Picker":
            content = next((c for l, c in clos if l is None), None)
            opts = []
            for x in (content[2] if content else []):
                if x[0] == "expr":
                    c2, m2 = strip_mods(x[1])
                    if core_name(c2) == "Text": opts.append({"title": title_str(ev(arg(c2[2], 0), env)), "radio": True})
            item = {"title": title_str(ev(arg(args, 0), env)), "picker": True, "submenu": opts}
        elif n == "ForEach":
            data = ev(arg(args, 0), env) if args else Unknown("?")
            body = clos[0][1] if clos else None
            if body is None: continue
            if isinstance(data, list) and len(data) <= 400:
                for x in data: out += menu_items(body[2], env.child(_bind(body[1], x)), depth + 1)
            else:
                sub = menu_items(body[2], env.child({p: Unknown(p) for p in body[1]}), depth + 1)
                out.append({"dynamic": unparse(arg(args, 0)), "template": sub})
            continue
        elif n == "menuItems":
            items = ev(arg(args, 0), env)
            if isinstance(items, list): out += [cmd_item(x) for x in items if is_item(x)]
            continue
        elif n == "extraMenu":
            i = ev(arg(args, 0), env)
            em = static_value("CommandCatalog", "extraMenus")
            if num(i) and isinstance(em, list):
                for name, items in em[int(i)][1]:
                    out.append({"header": name}); out += [cmd_item(x) for x in items]
            continue
        elif n == "Text":
            out.append({"title": title_str(ev(arg(args, 0), env)), "disabled": True}); continue
        elif n == "Label":
            continue
        else:
            d = member_decl(n) if core[0] in ("id", "call") else None
            if d is not None and d.kind in ("computed", "func"):
                out += menu_items(d.node[2], env.child(bind_params(d, args, env)), depth + 1)
            continue
        ks = mod(mods, "keyboardShortcut")
        if ks and item is not None:
            sc = shortcut_from_mod(ks[0], env)
            if sc: item["shortcut"], item["macShortcut"] = sc["win"], sc["mac"]
        dis = mod(mods, "disabled")
        if dis and item is not None:
            dv = unparse(dis[0][0][1]) if dis[0] else ""
            if dv and dv != "model == nil": item["enabledWhen"] = "!(" + dv + ")"
        if item is not None: out.append(item)
    return out

def _bind(params, x):
    if not params: return {"$0": x}
    if len(params) == 1: return {params[0]: x, "$0": x}
    v = {"$0": x}
    for k, p in enumerate(params):
        v[p] = x[k] if isinstance(x, (list, tuple)) and k < len(x) else Unknown(p)
    return v

APP_MENU_PLACE = {"appInfo": "Oanarina Archi Tool", "appSettings": "Oanarina Archi Tool", "newItem": "File", "saveItem": "File",
                  "printItem": "File", "undoRedo": "Edit", "pasteboard": "Edit", "toolbar": "View", "help": "Help", "sidebar": "View",
                  "textEditing": "Edit", "windowList": "Window", "windowSize": "Window"}
SYSTEM_ITEMS = {
    "Oanarina Archi Tool": [("Hide Oanarina Archi Tool", "⌘H"), ("Hide Others", "⌥⌘H"), ("Quit Oanarina Archi Tool", "⌘Q")],
    "View": [("Enter Full Screen", "⌃⌘F")],
    "Window": [("Minimize", "⌘M"), ("Zoom", ""), ("Bring All to Front", "")],
}

def menubar():
    body = None
    for t, members in DECLS.items():
        b = members.get("body")
        if b is not None and "Commands" in (b.typtext or ""): body = b; CURRENT_TYPE[0] = t; break
    menus = OrderedDict((k, []) for k in ["Oanarina Archi Tool", "File", "Edit", "View"])
    env = Env(CURRENT_TYPE[0])
    for s in body.node[2]:
        if s[0] != "expr": continue
        core, mods = strip_mods(s[1])
        n = core_name(core)
        if n == "CommandGroup":
            lab, x = core[2][0]
            place = APP_MENU_PLACE.get(x[2] if x[0] == "member" else "", "Other")
            items = menu_items(core[3][0][1][2], env)
            if menus.get(place): menus[place].append({"separator": True})
            menus.setdefault(place, []).extend(items)
        elif n == "CommandMenu":
            title = title_str(ev(arg(core[2], 0), env))
            menus.setdefault(title, []).extend(menu_items(core[3][0][1][2], env))
    menus.setdefault("Window", [])
    menus.move_to_end("Window"); menus.move_to_end("Help")
    for m, items in SYSTEM_ITEMS.items():
        for t, sc in items:
            d = {"title": t, "system": True}
            if sc: d["macShortcut"], d["shortcut"] = sc, mac_to_win(sc)
            menus[m].append(d)
    return [{"title": k, "items": v} for k, v in menus.items()]

# ----------------------------------------------------------------------------------------------------------------------
# Ribbon (RibbonView.swift)
# ----------------------------------------------------------------------------------------------------------------------
def rb_cmd(it, size):
    d = cmd_item(it, {"size": size})
    r = resolve(it["names"])
    if r and r in REG:
        d["help"] = "%s — %s  [%s%s]" % (it["title"], REG[r]["summary"], r, (", " + ", ".join(REG[r]["aliases"])) if REG[r]["aliases"] else "")
    return d

def mods_help(mods, env):
    h = mod(mods, "help")
    if h and h[0]: return mac_to_win(title_str(ev(h[0][0][1], env)))
    return ""

def mods_width(mods, env):
    f = mod(mods, "frame")
    if f:
        w = arg(f[0], label="width")
        if w is not None:
            v = ev(w, env)
            if num(v): return v
    return None

def rb_walk(stmts, env, depth=0):
    out = []
    for s in stmts:
        k = s[0]
        if k == "let" and s[2] is not None and not isinstance(s[1], list):
            env = env.child({s[1]: ev(s[2], env)}); continue
        if k == "if":
            for c, b, _ in s[1]: out += rb_walk(b, env, depth + 1)
            out += rb_walk(s[2], env, depth + 1); continue
        if k == "return" and s[1] is not None: s = ("expr", s[1])
        if s[0] != "expr": continue
        out += rb_expr(s[1], env, depth)
    return out

def rb_expr(e, env, depth=0):
    core, mods = strip_mods(e)
    n = core_name(core)
    args = core[2] if core[0] == "call" else []
    clos = core[3] if core[0] == "call" else []
    if n in ("Group", "HStack", "ScrollView"):
        return [x for _, c in clos for x in rb_walk(c[2], env, depth + 1)]
    if n == "VStack":
        kids = [x for _, c in clos for x in rb_walk(c[2], env, depth + 1)]
        smalls = [x for x in kids if x.get("size") == "small"]
        if smalls and "rows" not in smalls[0]: smalls[0]["rows"] = len(smalls)
        return kids
    if n == "RibbonGroup":
        title = title_str(ev(arg(args, label="title"), env))
        return [{"group": title, "items": [x for _, c in clos for x in rb_walk(c[2], env, depth + 1)]}]
    if n == "ForEach":
        data = ev(arg(args, 0), env)
        body = clos[0][1] if clos else None
        if isinstance(data, list) and body is not None:
            return [x for d in data for x in rb_walk(body[2], env.child(_bind(body[1], d)), depth + 1)]
        return [{"kind": "dynamic", "title": unparse(arg(args, 0))}]
    if n == "cmd":
        it = ev(arg(args, 0), env)
        size = ev(arg(args, 1), env) if arg(args, 1) is not None else "large"
        return [rb_cmd(it, str(size))] if is_item(it) else [{"kind": "unresolved", "title": unparse(core)}]
    if n == "smallColumns":
        items = ev(arg(args, 0), env)
        rows = ev(arg(args, label="rows"), env) if arg(args, label="rows") is not None else 3
        res = [rb_cmd(x, "small") for x in (items if isinstance(items, list) else []) if is_item(x)]
        if res: res[0]["rows"] = rows
        return res
    if n == "action":
        title = title_str(ev(arg(args, 0), env)); sym = title_str(ev(arg(args, 1), env))
        size = ev(arg(args, 2), env) if arg(args, 2) is not None else "large"
        help_t = mac_to_win(title_str(ev(arg(args, label="help"), env))) if arg(args, label="help") is not None else ""
        act = clos[0][1] if clos else None
        d = {"title": title, "symbol": sym, "size": str(size), "kind": "action"}
        d.update(resolve_action(act, env, help_t, title))
        if help_t: d["help"] = help_t
        for lab in ("active", "enabled"):
            x = arg(args, label=lab)
            if x is not None: d[lab + "When"] = unparse(x)
        return [d]
    if n == "commandMenu":
        title = title_str(ev(arg(args, 0), env)); sym = title_str(ev(arg(args, 1), env))
        items = ev(arg(args, 2), env)
        return [{"title": title, "symbol": sym, "command": "", "size": "large", "kind": "menu",
                 "help": mac_to_win(title_str(ev(arg(args, label="help"), env))),
                 "sections": [{"name": "", "items": [cmd_item(x) for x in (items if isinstance(items, list) else []) if is_item(x)]}]}]
    if n == "RibbonCatalogMenu":
        secs = ev(arg(args, label="sections"), env)
        return [{"title": title_str(ev(arg(args, label="title"), env)), "symbol": title_str(ev(arg(args, label="symbol"), env)),
                 "command": "", "size": "large", "kind": "menu", "help": mac_to_win(title_str(ev(arg(args, label="help"), env))) if arg(args, label="help") is not None else "",
                 "sections": [{"name": title_str(name), "items": [cmd_item(x) for x in items if is_item(x)]} for name, items in (secs if isinstance(secs, list) else [])]}]
    if n == "Menu":
        content = next((c for l, c in clos if l is None), None)
        lab = next((c for l, c in clos if l == "label"), None)
        title, sym = label_of(lab, env) if lab is not None else (None, None)
        items = menu_items(content[2], env) if content else []
        d = {"title": title_str(title), "symbol": title_str(sym) if sym else "", "command": "", "size": "large", "kind": "menu",
             "help": mods_help(mods, env), "sections": [{"name": "", "items": items}]}
        w = mods_width(mods, env)
        if w: d["width"] = w
        return [d]
    if n and n.endswith("Dropdown"):
        d = {"title": n[:-8], "symbol": "", "command": "", "kind": "dropdown", "dropdown": n[:-8].lower()}
        w = mods_width(mods, env)
        if w: d["width"] = w
        return [d]
    if n == "Text":
        return [{"kind": "label", "title": title_str(ev(arg(args, 0), env))}]
    if n == "Button":
        title = title_str(ev(arg(args, 0), env)) if arg(args, 0) is not None else ""
        d = {"title": title, "symbol": "", "size": "small", "kind": "button"}
        d.update(resolve_action(clos[0][1] if clos else None, env, mods_help(mods, env), title))
        return [d]
    if n in ("Circle", "Spacer", "Image", "Divider", "VSeparator", "HSeparator"): return []
    d = member_decl(n) if n else None
    if d is not None and d.kind in ("computed", "func") and depth < 6:
        return rb_walk(d.node[2], env.child(bind_params(d, args, env)), depth + 1)
    return [{"kind": "view", "title": n or unparse(core)}]

def ribbon():
    CURRENT_TYPE[0] = "RibbonView"
    tabs = ENUMS.get("RibbonTab", [])
    content = DECLS["RibbonView"]["content"].node[2]
    sw = next(s for s in content if s[0] == "switch")
    var_of = {}
    for pat, body in sw[2]:
        m = re.match(r"case \. (\w+)|case \.(\w+)", pat.replace(". ", "."))
        name = pat.replace("case", "").strip().lstrip(".").strip()
        if body and body[0][0] == "expr" and body[0][1][0] == "id": var_of[name] = body[0][1][1]
    out = []
    for case, raw in tabs:
        var = var_of.get(case)
        d = DECLS["RibbonView"].get(var)
        if d is None: ERRORS.append("ribbon tab %s: no view %s" % (raw, var)); continue
        groups = []
        for x in rb_walk(d.node[2], Env("RibbonView")):
            if "group" in x: groups.append({"name": x["group"], "items": x["items"]})
            else: ERRORS.append("ribbon %s: item outside a group: %s" % (raw, x.get("title")))
        out.append({"tab": raw, "groups": groups})
    return out

def ribbon_chrome():
    """Tab bar: quick access toolbar and right-hand buttons."""
    CURRENT_TYPE[0] = "RibbonView"
    env = Env("RibbonView")
    qa = DECLS["RibbonView"].get("quickAccessBar")
    chooser = []
    if qa:
        for c in find_calls(qa.node[2], []):
            if c[0] == "call" and core_name(c) == "ForEach":
                v = ev(arg(c[2], 0), env)
                if isinstance(v, list) and v and all(isinstance(x, str) for x in v): chooser = v
    right = []
    tb = DECLS["RibbonView"].get("tabBar")
    for c in find_calls(tb.node[2] if tb else [], []):
        if c[0] == "call" and core_name(c) == "IconButton":
            sym = ev(arg(c[2], label="symbol"), env); h = ev(arg(c[2], label="help"), env)
            d = {"symbol": title_str(sym), "help": mac_to_win(title_str(h))}
            d.update(resolve_action(c[3][0][1] if c[3] else None, env, d["help"]))
            right.append(d)
    dq = static_value("AppPreferences", "defaultQuickAccess")
    return {"quickAccessDefault": dq if isinstance(dq, list) else [], "quickAccessChoices": chooser,
            "appIconButton": {"help": "About Oanarina Archi Tool", "command": "ABOUT"}, "rightButtons": right,
            "collapsible": True, "tabHiddenPreference": "Settings ▸ Toolbar (hiddenRibbonTabs)"}

def contextual_tabs():
    d = DECLS.get("ContextualRibbon", {}).get("tab")
    if not d: return []
    common = static_value("ContextualRibbon", "common")
    out = []
    env0 = Env("ContextualRibbon")
    for s in d.node[2]:
        if s[0] != "switch": continue
        for pat, body in s[2]:
            kinds = re.findall(r'"([^"]+)"', pat) or ["(other)"]
            for kind in kinds:
                env = env0.child({"k": kind})
                title, spec = None, []
                for b in body:
                    if b[0] == "expr" and b[1][0] == "bin" and b[1][1] == "=":
                        lhs = unparse(b[1][2])
                        if lhs == "title": title = title_str(ev(b[1][3], env))
                        if lhs == "specific": spec = ev(b[1][3], env)
                items = (spec if isinstance(spec, list) else []) + (common if isinstance(common, list) else [])
                out.append({"selection": kind, "tab": title, "items": [cmd_item(x) for x in items if is_item(x)]})
    return out

# ----------------------------------------------------------------------------------------------------------------------
# Panels, dialogs, start screen, status bar: generic control extraction
# ----------------------------------------------------------------------------------------------------------------------
LEAF_VIEWS = {"IconButton", "RibbonButton", "Swatch", "PanelHeader", "HSeparator", "VSeparator", "AppIconView", "Spacer", "Divider",
              "Image", "Circle", "Rectangle", "RoundedRectangle", "Color", "ProgressView", "EmptyView", "GeometryReader"}
CONTROL_KINDS = {"Toggle", "TextField", "SecureField", "Picker", "Stepper", "Slider", "ColorPicker", "DatePicker", "TextEditor", "Link"}

def switch_map(typ, member):
    """case -> returned AST for `var member: T { switch self { case .a: return X ... } }`."""
    d = DECLS.get(typ, {}).get(member)
    out = {}
    if not d or d.kind not in ("computed", "func"): return out
    for s in d.node[2]:
        if s[0] == "switch":
            for pat, body in s[2]:
                ret = next((b[1] for b in body if b[0] == "return"), None)
                if ret is None and body and body[0][0] == "expr": ret = body[0][1]
                for c in re.findall(r"\.\s*(\w+)", pat): out[c] = ret
    return out

def is_view_struct(n):
    info = TYPES.get(n)
    return bool(info) and info["kind"] == "struct" and "View" in info["conforms"] and "body" in DECLS.get(n, {})

def binding_text(args):
    for lab in ("isOn", "text", "selection", "value"):
        x = arg(args, label=lab)
        if x is not None: return unparse(x).lstrip("$")
    return None

def controls(stmts, env, typ, depth=0, seen=None, out=None, secs=None, ctx=""):
    seen = seen if seen is not None else set()
    out = out if out is not None else []
    secs = secs if secs is not None else []
    if depth > 7: return out, secs
    prev = CURRENT_TYPE[0]; CURRENT_TYPE[0] = typ
    try:
        for s in stmts:
            k = s[0]
            if k == "let" and s[2] is not None and not isinstance(s[1], list):
                env = env.child({s[1]: ev(s[2], env) if s[2][0] != "computed" else Unknown(s[1])}); continue
            if k == "if":
                for c, b, _ in s[1]: controls(b, env, typ, depth + 1, seen, out, secs, ctx)
                controls(s[2], env, typ, depth + 1, seen, out, secs, ctx); continue
            if k == "switch":
                for p, b in s[2]:
                    tabname = re.sub(r"^case\s*", "", p).strip().replace('"', "").lstrip(". ")
                    controls(b, env, typ, depth + 1, seen, out, secs, (tabname if tabname != "default" else ctx))
                continue
            if k in ("group",): controls(s[1], env, typ, depth + 1, seen, out, secs, ctx); continue
            if k == "return" and s[1] is not None: s = ("expr", s[1])
            if s[0] != "expr": continue
            ctl_expr(s[1], env, typ, depth, seen, out, secs, ctx)
    finally:
        CURRENT_TYPE[0] = prev
    return out, secs

def add(out, d, ctx):
    if ctx: d["tab"] = ctx
    key = json.dumps(d, sort_keys=True)
    if key not in {json.dumps(x, sort_keys=True) for x in out}: out.append(d)

def ctl_expr(e, env, typ, depth, seen, out, secs, ctx):
    core, mods = strip_mods(e)
    n = core_name(core)
    if n is None: return
    args = core[2] if core[0] == "call" else []
    clos = core[3] if core[0] == "call" else []
    help_t = mods_help(mods, env)
    cm = mod(mods, "contextMenu")
    if cm and cm[1]:
        items = menu_items(cm[1][0][1][2], env)
        if items: add(out, {"kind": "contextMenu", "items": [i.get("title", "") for i in items if i.get("title")]}, ctx)
    if n in CONTROL_KINDS:
        lab = arg(args, 0)
        d = {"kind": n, "label": title_str(ev(lab, env)) if lab is not None else ""}
        b = binding_text(args)
        if b: d["binding"] = b
        if n == "Picker" and clos:
            opts = []
            for x in clos[0][1][2]:
                if x[0] == "expr":
                    c2, _ = strip_mods(x[1])
                    if core_name(c2) == "Text" and c2[2]: opts.append(title_str(ev(arg(c2[2], 0), env)))
                    elif core_name(c2) == "ForEach" and c2[2]: opts.append("{" + unparse(arg(c2[2], 0)) + "}")
            if opts: d["options"] = opts
        if n in ("Stepper", "Slider"):
            r = arg(args, label="in")
            if r is not None: d["range"] = unparse(r)
        if help_t: d["help"] = help_t
        add(out, d, ctx); return
    if n in ("Button", "IconButton"):
        if n == "IconButton":
            title = title_str(ev(arg(args, label="help"), env)); sym = title_str(ev(arg(args, label="symbol"), env)); act = clos[0][1] if clos else None
        else:
            title, sym, act = None, None, arg(args, label="action")
            if act is not None: act = ("closure", [], [("expr", ("call", act, [], []))])
            if arg(args, 0) is not None: title = ev(arg(args, 0), env)
            for lab, c in clos:
                if lab == "label": t2, sym = label_of(c, env); title = title if title is not None else t2
                elif act is None: act = c
            if title is None and len(clos) >= 2: title, sym = label_of(clos[1][1], env)
            title = title_str(title)
        if not title: title = help_t or ("[%s]" % title_str(sym) if sym else "")
        d = {"kind": "Button", "label": title}
        if sym: d["symbol"] = title_str(sym)
        r = resolve_action(act, env, help_t or title, title)
        if not r.get("command", "").startswith("@ui:"): d["command"] = r["command"] + ((" " + r["args"]) if r.get("args") else "")
        if help_t and help_t != title: d["help"] = help_t
        ks = mod(mods, "keyboardShortcut")
        if ks:
            sc = shortcut_from_mod(ks[0], env)
            if sc: d["shortcut"] = sc["win"]
        add(out, d, ctx); return
    if n == "Menu":
        a0 = arg(args, 0)
        content = next((c for l, c in clos if l is None), None)
        lab = next((c for l, c in clos if l == "label"), None)
        title = title_str(ev(a0, env)) if a0 is not None else title_str(label_of(lab, env)[0]) if lab is not None else ""
        items = menu_items(content[2], env) if content else []
        add(out, {"kind": "Menu", "label": title, "items": [i.get("title") or ("{%s}" % i["dynamic"] if i.get("dynamic") else "") for i in items if not i.get("separator")]}, ctx)
        return
    if n in ("PanelHeader", "Section", "PrefSection", "GroupBox", "DisclosureGroup", "sectionHeader"):
        a0 = arg(args, 0) if arg(args, 0) is not None else arg(args, label="title")
        if a0 is not None:
            t = title_str(ev(a0, env))
            if t and t not in secs: secs.append(t)
        for _, c in clos: controls(c[2], env, typ, depth + 1, seen, out, secs, ctx)
        return
    if n == "Text":
        a0 = arg(args, 0)
        if a0 is not None and a0[0] == "str":
            t = title_str(ev(a0, env))
            if len(t) >= 3 and t.upper() == t and re.search(r"[A-Z]", t) and "{" not in t and t not in secs: secs.append(t)
        return
    if n == "ForEach":
        data = arg(args, 0)
        body = clos[0][1] if clos else None
        if body is None: return
        sub, _ = controls(body[2], env.child({p: Unknown(p) for p in body[1]}), typ, depth + 1, seen, [], secs, ctx)
        for x in sub: x["repeated"] = unparse(data); add(out, x, ctx)
        return
    if n.endswith("Dropdown"):
        add(out, {"kind": "Dropdown", "label": n[:-8]}, ctx); return
    if n in ("TabView",):
        for _, c in clos: controls(c[2], env, typ, depth + 1, seen, out, secs, ctx)
        return
    d = DECLS.get(typ, {}).get(n) if core[0] in ("id", "call") and n[:1].islower() else None
    if d is not None and d.kind in ("computed", "func") and (typ, n) not in seen:
        seen.add((typ, n))
        controls(d.node[2], env.child(bind_params(d, args, env)), typ, depth + 1, seen, out, secs, ctx)
        seen.discard((typ, n))
        return
    if n in LEAF_VIEWS: return
    if is_view_struct(n) and n not in seen and depth < 6:
        # custom row/tile views with a title and an action are controls; other sub-views are expanded
        t = arg(args, label="title")
        container = any((x.typtext or "").strip() in ("Content", "() -> Content") for x in DECLS.get(n, {}).values())
        if container:
            a0 = t if t is not None else arg(args, 0)
            if a0 is not None:
                tt = title_str(ev(a0, env))
                if tt and tt not in secs: secs.append(tt)
            for _, c in clos:
                if c[0] == "closure": controls(c[2], env, typ, depth + 1, seen, out, secs, ctx)
            return
        if t is not None and clos:
            dd = {"kind": n, "label": title_str(ev(t, env))}
            sy = arg(args, label="symbol")
            if sy is not None: dd["symbol"] = title_str(ev(sy, env))
            r = resolve_action(clos[0][1], env, help_t, dd["label"])
            if not r.get("command", "").startswith("@ui:"): dd["command"] = r["command"] + ((" " + r["args"]) if r.get("args") else "")
            add(out, dd, ctx); return
        seen.add(n)
        controls(DECLS[n]["body"].node[2], Env(n), n, depth + 1, seen, out, secs, ctx)
        seen.discard(n)
        return
    for _, c in clos:
        if c[0] == "closure": controls(c[2], env, typ, depth + 1, seen, out, secs, ctx)

def view_spec(struct, name=None, extra=None):
    if struct not in DECLS or "body" not in DECLS[struct]:
        return {"name": name or struct, "view": struct, "missing": True}
    ctl, secs = controls(DECLS[struct]["body"].node[2], Env(struct), struct, seen={struct})
    d = {"name": name or struct, "view": struct, "file": DECLS[struct]["body"].file, "sections": secs, "controls": ctl}
    if extra: d.update(extra)
    return d

def panels():
    CURRENT_TYPE[0] = "PanelContent"
    cases = {}
    body = DECLS["PanelContent"]["body"].node[2]
    for s in body:
        if s[0] == "switch":
            for pat, b in s[2]:
                c = re.sub(r"^case\s*\.?\s*", "", pat).strip()
                names = [core_name(strip_mods(x[1])[0]) for x in b if x[0] == "expr"]
                for x in b:
                    if x[0] != "expr": continue
                    for cc in find_calls(x[1], []):
                        if cc[0] == "call" and is_view_struct(core_name(cc) or ""): names.insert(0, core_name(cc)); break
                cases[c] = next((x for x in names if x and is_view_struct(x)), names[0] if names else None)
    syms = switch_map("PanelTab", "symbol")
    out = []
    for c, raw in ENUMS.get("PanelTab", []):
        v = cases.get(c)
        spec = view_spec(v, raw) if v else {"name": raw, "missing": True}
        spec["symbol"] = title_str(ev(syms[c], Env())) if c in syms else ""
        spec["command"] = "@panel:" + raw
        out.append(spec)
    return out

def windows_opened():
    """XWindow enums (MaterialLibraryWindow.show …) -> the SwiftUI view they host."""
    res = {}
    for t, members in DECLS.items():
        if not t.endswith("Window") or "show" not in members: continue
        views = [core_name(c) for c in find_calls(members["show"].node[2], []) if c[0] == "call"]
        v = next((x for x in views if x and is_view_struct(x)), None)
        if v: res[t] = v
    return res

def dialogs():
    out = []
    mw = DECLS.get("MainWindow", {}).get("sheetView")
    if mw:
        for s in mw.node[2]:
            if s[0] != "switch": continue
            for pat, b in s[2]:
                c = re.sub(r"^case\s*\.?\s*", "", pat).split("(")[0].strip()
                for x in b:
                    if x[0] != "expr": continue
                    core, _ = strip_mods(x[1])
                    v = core_name(core)
                    if v and is_view_struct(v):
                        cmd = EFFECT_CMD.get("sheet:" + c) or (c.upper() if c.upper() in REG else None)
                        out.append(view_spec(v, v, {"kind": "sheet", "sheet": c, "command": cmd}))
    wins = windows_opened()
    for w, v in sorted(wins.items()):
        cmd = EFFECT_CMD.get("window:" + w)
        out.append(view_spec(v, w.replace("Window", "") or w, {"kind": "window", "window": w, "command": cmd}))
    for v, name, cmd in [("PreferencesView", "Settings", "OPTIONS"), ("StartView", "Start Screen", "STARTSCREEN"),
                         ("CommandSearchPalette", "Command Search", "COMMANDSEARCH"), ("ShortcutsView", "Keyboard Shortcuts", None),
                         ("CommandReferenceView", "Command Reference", None)]:
        if v in DECLS and not any(d.get("view") == v for d in out):
            spec = view_spec(v, name, {"kind": "window", "command": cmd})
            if v == "PreferencesView":
                tabs = [(c, r) for c, r in ENUMS.get("Tab", [])]
                spec["tabs"] = [r for c, r in tabs]
            out.append(spec)
    return out

def status_bar():
    CURRENT_TYPE[0] = "StatusBarView"
    env = Env("StatusBarView")
    out = []
    def walk(stmts):
        for s in stmts:
            if s[0] == "let": continue
            if s[0] == "if":
                for _, b, _ in s[1]: walk(b)
                continue
            if s[0] != "expr": continue
            core, mods = strip_mods(s[1])
            n = core_name(core)
            args = core[2] if core[0] == "call" else []
            clos = core[3] if core[0] == "call" else []
            if n in ("HStack", "Group", "VStack"):
                for _, c in clos: walk(c[2])
            elif n == "toggle":
                out.append({"kind": "toggle", "title": title_str(ev(arg(args, 0), env)), "key": title_str(ev(arg(args, 1), env)),
                            "setting": unparse(arg(args, 2)).lstrip("\\.")})
            elif n and n.endswith("Dropdown"):
                d = {"kind": "dropdown", "title": n[:-8]}
                w = mods_width(mods, env)
                if w: d["width"] = w
                out.append(d)
            elif n in ("Spacer", "VSeparator"):
                out.append({"kind": "separator" if n == "VSeparator" else "spacer"})
            elif n == "Label":
                out.append({"kind": "label", "title": title_str(ev(arg(args, 0), env)), "symbol": title_str(ev(arg(args, label="systemImage"), env)), "when": "selection not empty"})
            elif n == "Button":
                t, sym = label_of(clos[-1][1], env) if len(clos) > 1 else (None, None)
                d = {"kind": "button", "symbol": title_str(sym) if sym else "", "help": mods_help(mods, env)}
                d.update(resolve_action(clos[0][1] if clos else None, env, d["help"]))
                out.append(d)
            elif n == "Menu":
                content = next((c for l, c in clos if l is None), None)
                lab = next((c for l, c in clos if l == "label"), None)
                t, sym = label_of(lab, env) if lab else (None, None)
                out.append({"kind": "menu", "title": title_str(t), "help": mods_help(mods, env), "items": menu_items(content[2], env) if content else []})
            else:
                d = DECLS["StatusBarView"].get(n)
                if d is not None and d.kind == "computed":
                    items = []
                    for c in find_calls(d.node[2], []):
                        if c[0] == "call" and core_name(c) == "Menu":
                            content = next((cc for l, cc in c[3] if l is None), None)
                            items = menu_items(content[2], env) if content else []
                            break
                    hm = re.search(r'\.help\((.*)\)\s*$', deep_text(d.node[2]).rstrip("; }"))
                    out.append({"kind": "menu" if items else "button", "title": n, "items": items} if items else
                               dict({"kind": "button", "title": n}, **resolve_action(next((c[3][0][1] for c in find_calls(d.node[2], []) if c[0] == "call" and core_name(c) == "Button" and c[3]), None), env)))
                elif n:
                    d2 = {"kind": "view", "title": n}
                    w = mods_width(mods, env)
                    if w: d2["width"] = w
                    out.append(d2)
    walk(DECLS["StatusBarView"]["body"].node[2])
    return out

def palettes():
    pal = static_value("ToolPalettePanel", "palettes")
    out = []
    for name, items in (pal if isinstance(pal, list) else []):
        out.append({"name": name, "kind": "commands", "items": [cmd_item(x) for x in items if is_item(x)]})
    custom = static_value("ToolPalettePanel", "customRaw")
    out.append({"name": "Blocks", "kind": "blocks", "source": "blocks of the drawing (doc.blocks, thumbnails, click-to-place, drag onto the drawing)"})
    out.append({"name": "Components", "kind": "components", "source": "ComponentLibrary.families (thumbnails, click-to-place, Space rotates 90°)"})
    out.append({"name": "My Tools", "kind": "custom", "default": as_str(custom).split(",") if isinstance(custom, str) else [],
                "features": ["drag tiles in from other palettes", "drag to reorder", "right-click Remove from My Tools", "Add command field"]})
    return out

# ----------------------------------------------------------------------------------------------------------------------
# Shortcuts
# ----------------------------------------------------------------------------------------------------------------------
WIN_CONVENTIONS = {
    "⌘Q": ("Alt+F4", "Quit → File ▸ Exit (Alt+F4); Ctrl+Q is not a Windows convention"),
    "⌘H": (None, "Hide app has no Windows equivalent: drop"),
    "⌥⌘H": (None, "Hide others has no Windows equivalent: drop"),
    "⌘M": (None, "Minimize → window button / Win+Down; do not bind Ctrl+M"),
    "⌃⌘F": ("F11?", "Full screen is F11 on Windows but F11 is Object snap tracking (AutoCAD); keep F11 for OTRACK, full screen via View menu only"),
    "⇧⌘Z": ("Ctrl+Y", "Redo: Windows convention is Ctrl+Y; keep Ctrl+Shift+Z as a second binding"),
    "⌘,": ("Ctrl+,", "Settings: no Windows standard; place Options… under Tools/Edit menu as well (AutoCAD: OPTIONS)"),
    "⌃0": ("Ctrl+0", "Clean screen ⌃0 and zoom extents ⌘0 both become Ctrl+0: AutoCAD for Windows uses Ctrl+0 for Clean Screen; give Zoom Extents no Ctrl binding (double middle-click, Z E)"),
    "⌘0": ("(none)", "See ⌃0: Ctrl+0 is Clean Screen on Windows"),
    "⌥⌘P": ("Ctrl+Alt+P", "Ctrl+Alt equals AltGr on many European keyboards (may type a character); consider Ctrl+Shift+F2-style alternatives"),
    "⌥⌘J": ("Ctrl+Alt+J", "Ctrl+Alt = AltGr on European layouts"),
    "⌥⌘1": ("Ctrl+Alt+1", "Ctrl+Alt+digit = AltGr+digit on European layouts (types characters such as ~ or ¡)"),
    "⌥⌘2": ("Ctrl+Alt+2", "Ctrl+Alt = AltGr"), "⌥⌘3": ("Ctrl+Alt+3", "Ctrl+Alt = AltGr"), "⌥⌘4": ("Ctrl+Alt+4", "Ctrl+Alt = AltGr"),
    "⌥⇧⌘P": ("Ctrl+Alt+Shift+P", "Ctrl+Alt = AltGr"),
    "⇧⌘/": ("Ctrl+Shift+/", "Ctrl+? on US layouts; fine"),
    "⌘W": ("Ctrl+W", "Close: Windows also uses Ctrl+F4 for documents; add Ctrl+F4 as alias"),
    "F10": ("F10", "F10 activates the menu bar on Windows (and in Electron): the shell must preventDefault so F10 toggles POLAR as on the Mac"),
    "F12": ("F12", "Electron/Chromium opens DevTools on F12 in debug builds: disable in release so F12 toggles DYN"),
    "F1": ("F1", "Windows help key: matches the Mac (context help)"),
    "Delete": ("Del", "Mac Delete (backspace) erases the selection; on Windows use Del (and Backspace)"),
}

def collect_shortcuts(menus, sbar, chrome):
    out = []
    def walk(items, path):
        for it in items:
            if it.get("macShortcut"):
                out.append({"keys": it["shortcut"], "mac": it["macShortcut"], "action": " ▸ ".join(path + [it.get("title", "")]),
                            "command": it.get("command", ""), "source": "menu"})
            if it.get("submenu"): walk(it["submenu"], path + [it.get("title", "")])
    for m in menus: walk(m["items"], [m["title"]])
    rows = static_value("ShortcutsView", "rows")
    for k, v in (rows if isinstance(rows, list) else []):
        out.append({"keys": mac_to_win(k).replace("Delete", "Del"), "mac": k, "action": v, "source": "Keyboard & Mouse window"})
    for s in sbar:
        if s.get("kind") == "toggle" and s.get("key"):
            out.append({"keys": s["key"], "mac": s["key"], "action": "Toggle " + s["title"], "command": s.get("setting", ""), "source": "status bar"})
    for b in chrome.get("rightButtons", []):
        m = re.search(r"\((Ctrl\+[^)]+)\)", b.get("help", ""))
        if m: out.append({"keys": m.group(1), "mac": "", "action": b["help"], "command": b.get("command", ""), "source": "ribbon tab bar"})
    # conflicts
    bykey = {}
    for s in out: bykey.setdefault(s["keys"], []).append(s)
    for s in out:
        conv = WIN_CONVENTIONS.get(s["mac"])
        if conv:
            s["windows"] = conv[0]; s["note"] = conv[1]
        others = {x["action"].split(" ▸ ")[-1].lower() for x in bykey.get(s["keys"], []) if x["mac"] != s["mac"] and x["mac"]}
        if others and s["mac"]:
            s.setdefault("note", "")
            s["note"] = (s["note"] + "; " if s["note"] else "") + "same Windows keys as: " + ", ".join(sorted(others))
    return out

# ----------------------------------------------------------------------------------------------------------------------
# Theme, render features, icons
# ----------------------------------------------------------------------------------------------------------------------
def hexs(v): return "#%06X" % v

def theme():
    colors, fonts = OrderedDict(), OrderedDict()
    for n, d in DECLS.get("Theme", {}).items():
        if d.kind not in ("expr", "computed") or not d.node: continue
        t = deep_text(d.node if d.kind == "expr" else d.node[2])
        m = re.search(r"pick\((\d+), (\d+)\)", t) or re.search(r"pick\(0x(\w+), 0x(\w+)\)", t)
        m = re.search(r"pick\((0x[0-9A-Fa-f]+|\d+), (0x[0-9A-Fa-f]+|\d+)\)", unparse(d.node) if d.kind == "expr" else t)
        if m:
            colors[n] = {"dark": hexs(int(m.group(1), 0)), "light": hexs(int(m.group(2), 0))}; continue
        m = re.search(r"Color\(hex: (0x[0-9A-Fa-f]+|\d+)", t)
        if m: colors[n] = {"dark": hexs(int(m.group(1), 0)), "light": hexs(int(m.group(1), 0))}; continue
        m = re.search(r"light \? Color\.black\.opacity\(([\d.]+)\) : Color\.white\.opacity\(([\d.]+)\)", t)
        if m: colors[n] = {"dark": "rgba(255,255,255,%s)" % m.group(2), "light": "rgba(0,0,0,%s)" % m.group(1)}; continue
        m = re.search(r"Color\(red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+)\)", t)
        if m:
            c = "#%02X%02X%02X" % tuple(round(float(x) * 255) for x in m.groups()); colors[n] = {"dark": c, "light": c}; continue
        if "ThemeColors.accentHex" in t: colors[n] = {"dark": hexs(static_value("AppPreferences", "defaultAccent")), "light": hexs(static_value("AppPreferences", "defaultAccent")), "preference": "accentHex"}; continue
        if "ThemeColors.canvasHex" in t and n == "canvas": colors[n] = {"dark": hexs(static_value("AppPreferences", "defaultCanvas")), "light": hexs(static_value("AppPreferences", "defaultCanvas")), "preference": "canvasHex"}; continue
        m = re.search(r"Font\.system\((.*)\)", t)
        if m:
            f = {}
            for part in m.group(1).split(","):
                if ":" in part:
                    k2, v = [x.strip() for x in part.split(":", 1)]; f[k2] = v.lstrip(".")
            if "size" in f: f["size"] = float(f["size"])
            f.setdefault("weight", "regular"); f["family"] = "SF Mono → Cascadia Mono/Consolas" if f.get("design") == "monospaced" else "SF Pro → Segoe UI Variable/Segoe UI"
            fonts[n] = f
    acc = static_value("AppPreferences", "accentPresets"); can = static_value("AppPreferences", "canvasPresets")
    sizes = OrderedDict()
    probes = [("ribbonHeight", "RibbonView.swift", r"\.frame\(height: (\d+)\)\s*\n\s*\}\s*\n\s*\.background\(Theme\.ribbon\)"),
              ("ribbonTabBarHeight", "RibbonView.swift", r"\.frame\(height: (\d+)\)\s*\n\s*\.background\(Theme\.ribbonTabBar\)"),
              ("ribbonTabFontSize", "RibbonView.swift", r"Text\(L10n\.t\(t\.rawValue, language\)\)\s*\n\s*\.font\(\.system\(size: ([\d.]+)"),
              ("ribbonTabPaddingX", "RibbonView.swift", r"\.padding\(\.horizontal, (\d+)\)\s*\n\s*\.frame\(height: 26\)"),
              ("ribbonActiveTabUnderline", "RibbonView.swift", r"Rectangle\(\)\.fill\(Theme\.accent\)\.frame\(height: (\d+)\)"),
              ("largeButtonWidth", "RibbonView.swift", r"\.frame\(width: (\d+), height: \d+, alignment: \.top\)"),
              ("largeButtonHeight", "RibbonView.swift", r"\.frame\(width: \d+, height: (\d+), alignment: \.top\)"),
              ("largeButtonIconSize", "RibbonView.swift", r"\.font\(\.system\(size: (\d+), weight: \.regular\)\)"),
              ("largeButtonLabelSize", "RibbonView.swift", r"Text\(title\)\s*\n\s*\.font\(\.system\(size: (\d+)\)\)"),
              ("smallButtonHeight", "RibbonView.swift", r"\.padding\(\.horizontal, 5\)\s*\n\s*\.frame\(height: (\d+)\)"),
              ("smallButtonMinWidth", "RibbonView.swift", r"\.frame\(minWidth: (\d+), alignment: \.leading\)"),
              ("smallButtonFontSize", "RibbonView.swift", r"Text\(title\)\.font\(\.system\(size: (\d+)\)\)\.lineLimit\(1\)"),
              ("ribbonGroupTitleSize", "RibbonView.swift", r"Text\(L10n\.t\(title, language\)\)\s*\n\s*\.font\(\.system\(size: ([\d.]+)\)\)"),
              ("buttonCornerRadius", "RibbonView.swift", r"RoundedRectangle\(cornerRadius: (\d+)\)\.fill\(active"),
              ("statusBarHeight", "StatusBarView.swift", r"\.frame\(height: (\d+)\)\s*\n\s*\.background\(Theme\.ribbonTabBar\)"),
              ("statusToggleFontSize", "StatusBarView.swift", r"Text\(title\)\s*\n\s*\.font\(\.system\(size: ([\d.]+)"),
              ("statusToggleHeight", "StatusBarView.swift", r"\.padding\(\.horizontal, 5\)\s*\n\s*\.frame\(height: (\d+)\)"),
              ("panelTabHeight", "PanelsView.swift", r"\.frame\(height: (\d+)\)\s*\n\s*\.background\(current == t"),
              ("panelTabIconSize", "PanelsView.swift", r"Image\(systemName: t\.symbol\)\.font\(\.system\(size: (\d+)\)\)"),
              ("panelTabLabelSize", "PanelsView.swift", r"Text\(t\.rawValue\)\.font\(\.system\(size: ([\d.]+)\)\)"),
              ("panelTabColumns", "PanelsView.swift", r"min\(tabs\.count, (\d+)\)"),
              ("panelHeaderFontSize", "Theme.swift", r"\.font\(\.system\(size: ([\d.]+), weight: \.semibold\)\)\s*\n\s*\.tracking"),
              ("iconButtonWidth", "Theme.swift", r"\.frame\(width: (\d+), height: \d+\)\s*\n\s*\.foregroundStyle\(active"),
              ("iconButtonHeight", "Theme.swift", r"\.frame\(width: \d+, height: (\d+)\)\s*\n\s*\.foregroundStyle\(active"),
              ("toolTileHeight", "ToolPalette.swift", r"\.frame\(height: (\d+)\)\s*\n\s*\.background\(RoundedRectangle\(cornerRadius: 6\)"),
              ("toolTileMinWidth", "ToolPalette.swift", r"GridItem\(\.adaptive\(minimum: (\d+)\)"),
              ("preferencesSidebarWidth", "Preferences.swift", r"\.padding\(10\)\s*\n\s*\.frame\(width: (\d+)\)")]
    cache = {}
    for key, f, rx in probes:
        if f not in cache: cache[f] = open(os.path.join(APP, f), encoding="utf-8").read()
        m = re.search(rx, cache[f])
        if m: sizes[key] = float(m.group(1)) if "." in m.group(1) else int(m.group(1))
        else: ERRORS.append("theme size probe failed: " + key)
    mw = open(os.path.join(APP, "MainWindow.swift"), encoding="utf-8").read()
    for m in re.finditer(r"(\w*[Ww]idth)\s*=\s*(\d+)", mw):
        sizes.setdefault("mainWindow." + m.group(1), int(m.group(2)))
    return {"mode": "dark (default); light available (Settings ▸ Display ▸ Theme)", "colors": colors, "fonts": fonts, "sizes": sizes,
            "accentPresets": [{"name": a, "hex": hexs(b)} for a, b in (acc if isinstance(acc, list) else [])],
            "canvasPresets": [{"name": a, "hex": hexs(b)} for a, b in (can if isinstance(can, list) else [])],
            "defaults": {"accent": hexs(static_value("AppPreferences", "defaultAccent")), "canvas": hexs(static_value("AppPreferences", "defaultCanvas"))}}

def render_features():
    looks = switch_map("BeautyPreset", "look")
    kw = static_value("BeautyPreset", "keywords")
    presets = []
    for i, (c, raw) in enumerate(ENUMS.get("BeautyPreset", [])):
        vals = OrderedDict()
        node = looks.get(c)
        if node and node[0] == "call":
            for lab, x in node[2]:
                if x[0] == "call" and core_name(x) == "SIMD3": vals[lab] = [ev(a, Env()) for _, a in x[2]]
                else:
                    v = ev(x, Env()); vals[lab] = str(v) if isinstance(v, Implicit) else v
        presets.append({"name": raw, "keyword": kw[i] if isinstance(kw, list) and i < len(kw) else raw, "look": vals})
    styles = static_value("Scene3DBuilder", "visualStyles")
    return {"presets": presets, "visualStyles": styles if isinstance(styles, list) else []}

def lucide_table():
    js = open(os.path.join(ROOT, "windows", "tools", "sf-to-lucide.mjs"), encoding="utf-8").read()
    explicit = dict(re.findall(r'"([\w.]+)":\s*"(\w+)"', js[js.index("explicit"):js.index("prefixRules")]))
    rules = re.findall(r'\["([\w.]*)",\s*"(\w+)"\]', js[js.index("prefixRules"):])
    def f(sf):
        if not sf: return "SquareTerminal"
        if sf in explicit: return explicit[sf]
        for p, n in rules:
            if sf.startswith(p): return n
        return "SquareTerminal"
    return f

# ----------------------------------------------------------------------------------------------------------------------
# Coverage, output
# ----------------------------------------------------------------------------------------------------------------------
def walk_commands(o, path, acc):
    """(command, path) for every command-bearing entry of the catalogue."""
    if isinstance(o, dict):
        c = o.get("command")
        t = o.get("title") or o.get("name") or o.get("label") or o.get("tab") or ""
        p = path + [t] if t else path
        if isinstance(c, str) and c and not c.startswith("@"): acc.append((c.split(" ")[0].upper(), " ▸ ".join(p)))
        for n in o.get("names", []) if isinstance(o.get("names"), list) else []:
            if n.upper() in ALIAS and ALIAS[n.upper()] != c: acc.append((n.upper(), " ▸ ".join(p)))
        for k, v in o.items():
            if k in ("names",): continue
            if isinstance(v, (list, dict)): walk_commands(v, p, acc)
    elif isinstance(o, list):
        for x in o: walk_commands(x, path, acc)
    return acc

def coverage(cat):
    """Mirror of CommandCatalog.coverage(_:) plus where each command appears in the generated catalogue."""
    curated = static_value("CommandCatalog", "curatedItems")
    covered_mac = set()
    for it in (curated if isinstance(curated, list) else []):
        if is_item(it):
            for n in it["names"]:
                if n.upper() in ALIAS: covered_mac.add(ALIAS[n.upper()])
    where = {}
    for c, p in walk_commands({"ribbon": cat["ribbon"], "contextualTabs": cat["contextualTabs"], "menus": cat["menus"], "palettes": cat["palettes"],
                               "statusBar": cat["statusBar"]}, [], []):
        if c in ALIAS: where.setdefault(ALIAS[c], []).append(p)
    cmds, missing, intentional = [], [], []
    for n, d in REG.items():
        sysvar = d["category"] == "Settings" and d["summary"].startswith("System variable")
        e = {"name": n, "aliases": d["aliases"], "category": d["category"], "summary": d["summary"], "appOnly": d["app"],
             "entries": sorted(set(where.get(n, [])))[:6], "entryCount": len(set(where.get(n, [])))}
        if sysvar: e["systemVariable"] = True
        if sysvar and n not in covered_mac: intentional.append(n)
        if n not in where and not sysvar: missing.append(n)
        cmds.append(e)
    return {"registered": len(REG), "macCatalogCovered": len(covered_mac & set(REG)), "withUiEntry": len(where),
            "systemVariablesByRule": len(intentional), "withoutUiEntry": missing,
            "macSelfTestReference": "Command coverage: 1044 commands, 50 system variables in palettes, 0 without UI entry",
            "notInMacCatalogs": sorted(set(REG) - covered_mac - set(intentional)),
            "subcommandsNotRegistered": SUBCOMMANDS,
            "note": "Static scan of CommandDef literals; the running Mac app reports 1044 (it also counts commands built at run time). "
                    "Refresh the list from engine.hello once archi-engine runs."}, cmds

def build():
    for f in sorted(os.listdir(APP)):
        if f.endswith(".swift"): index_file(os.path.join(APP, f))
    for dp, _, fs in os.walk(CORE):
        for f in fs:
            if f in ("SettingsCommands.swift", "ScheduleExporter.swift"): index_file(os.path.join(dp, f))
    for d in DECLS.values():
        for x in d.values():
            if x.kind == "func" and "CmdItem" in x.typtext and len(x.params) >= 3: HELPERS.add(x.name)
    PANEL_RAW.update(dict(ENUMS.get("PanelTab", [])))
    load_registry(); index_effects()
    cat = OrderedDict()
    cat["generated"] = {"by": "windows/tools/extract_parity.py", "from": "app/Sources/ArchiApp (+ CommandDef registrations in app/Sources)",
                        "conventions": {"command": "registered command name (run on the engine as a command line with args)",
                                        "@panel:<Panel>": "show the side panel", "@mode:2D|3D|Split|Sheet": "workspace mode",
                                        "@zoom:extents|in|out|window": "canvas zoom", "@export:<ext>[:kind]": "file.export with a save dialog",
                                        "@selectAll/@deselectAll/@cleanScreen/@scriptConsole/@runScript/@agent:toggle/@panels:toggle": "shell actions",
                                        "@newWindow:<kind>": "new document window (start, blankMetric, blankImperial, building, sample, template)",
                                        "@ui:<effect>": "Mac-only UI effect without a command; the Windows shell must implement it",
                                        "shortcut": "Windows keys (Cmd→Ctrl, Option→Alt, Control→Ctrl)", "macShortcut": "original Mac keys"}}
    cat["ribbon"] = ribbon()
    cat["ribbonChrome"] = ribbon_chrome()
    cat["contextualTabs"] = contextual_tabs()
    cat["menus"] = menubar()
    cat["palettes"] = palettes()
    cat["panels"] = panels()
    cat["dialogs"] = dialogs()
    cat["statusBar"] = status_bar()
    cat["shortcuts"] = collect_shortcuts(cat["menus"], cat["statusBar"], cat["ribbonChrome"])
    cat["theme"] = theme()
    cat["render"] = render_features()
    cov, cmds = coverage(cat)
    cat["coverage"] = cov
    cat["commands"] = cmds
    lucide = lucide_table()
    syms = set()
    def sw(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k == "symbol" and isinstance(v, str) and v and "{" not in v: syms.add(v)
                else: sw(v)
        elif isinstance(o, list):
            for x in o: sw(x)
    sw(cat)
    cat["symbolsToLucide"] = OrderedDict((s, lucide(s)) for s in sorted(syms))
    cat["parseWarnings"] = len([e for e in ERRORS if e.startswith("parse")])
    cat["errors"] = [e for e in ERRORS if not e.startswith("parse")]
    return cat

# ---- Markdown checklist ----------------------------------------------------------------------------------------------
def md_escape(s): return str(s).replace("|", "\\|").replace("\n", " ")

def previous_status(path):
    """Statuses already ticked in an existing checklist (Item column -> Status), kept across regenerations."""
    st = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            # Status cells may carry an audit note ("partial: …", "todo: …"); every non-plain cell is kept.
            m = re.match(r"\| (todo[^|]*|done[^|]*|partial[^|]*|n/a[^|]*|wip[^|]*) \| (.*?) \| ", line)
            if m and m.group(1).strip() != "todo": st[m.group(2)] = m.group(1).strip()
    return st

def checklist(cat, prev=None):
    prev = prev or {}
    L, counts, done = [], OrderedDict(), [0]
    kinds = OrderedDict((k, 0) for k in ("done", "partial", "todo", "n/a", "wip"))
    def row(section, path, detail=""):
        counts[section] = counts.get(section, 0) + 1
        st = prev.get(md_escape(path), "todo")
        if not st.startswith("todo"): done[0] += 1
        k = re.match(r"(done|partial|todo|n/a|wip)", st)
        kinds[k.group(1) if k else "todo"] += 1
        L.append("| %s | %s | %s |" % (st, md_escape(path), md_escape(detail)))
    def head(t):
        L.append(""); L.append(t); L.append(""); L.append("| Status | Item | Command / detail |"); L.append("| --- | --- | --- |")
    def cmdtxt(it):
        c = it.get("command", "")
        if it.get("args"): c += " " + it["args"]
        return ("`%s`" % c) if c else ""
    head("## Ribbon")
    for t in cat["ribbon"]:
        row("Ribbon tabs", "Tab " + t["tab"], "%d groups" % len(t["groups"]))
        for g in t["groups"]:
            row("Ribbon groups", "%s ▸ %s (group)" % (t["tab"], g["name"]), "")
            for it in g["items"]:
                kind = it.get("kind", "button")
                if kind == "menu":
                    row("Ribbon buttons", "%s ▸ %s ▸ %s (menu)" % (t["tab"], g["name"], it["title"]), it.get("help", ""))
                    for s in it["sections"]:
                        for x in s["items"]:
                            if x.get("separator") or x.get("header"): continue
                            row("Ribbon menu items", "%s ▸ %s ▸ %s ▸ %s%s" % (t["tab"], g["name"], it["title"], (s["name"] + " ▸ ") if s["name"] else "", x.get("title") or "{%s}" % x.get("dynamic", "")), cmdtxt(x))
                elif kind in ("label", "view"):
                    row("Ribbon buttons", "%s ▸ %s ▸ %s (%s)" % (t["tab"], g["name"], it.get("title", ""), kind), "")
                else:
                    row("Ribbon buttons", "%s ▸ %s ▸ %s%s" % (t["tab"], g["name"], it.get("title", ""), " (%s)" % kind if kind in ("dropdown",) else ""), cmdtxt(it))
    row("Ribbon chrome", "Tab bar ▸ app icon (About)", "`ABOUT`")
    row("Ribbon chrome", "Tab bar ▸ quick access toolbar", ", ".join(cat["ribbonChrome"]["quickAccessDefault"]) + " (customizable: " + ", ".join(cat["ribbonChrome"]["quickAccessChoices"]) + ")")
    for b in cat["ribbonChrome"]["rightButtons"]: row("Ribbon chrome", "Tab bar ▸ " + b["help"], cmdtxt(b))
    head("## Contextual ribbon tabs (selection)")
    for c in cat["contextualTabs"]:
        row("Contextual tabs", "Selection %s → tab \"%s\"" % (c["selection"], c["tab"]), ", ".join(x["command"] for x in c["items"]))
    head("## Menu bar")
    def mwalk(items, path):
        for it in items:
            if it.get("separator"): continue
            if it.get("header"): continue
            t = it.get("title") or ("{%s}" % it["dynamic"] if it.get("dynamic") else "")
            detail = cmdtxt(it) + ((" · " + it["shortcut"]) if it.get("shortcut") else "") + (" · system" if it.get("system") else "")
            row("Menu items", " ▸ ".join(path + [t]), detail.strip(" ·"))
            if it.get("submenu"): mwalk(it["submenu"], path + [t])
    for m in cat["menus"]:
        row("Menus", "Menu " + m["title"], "%d items" % len([i for i in m["items"] if not i.get("separator")]))
        mwalk(m["items"], [m["title"]])
    head("## Tool palettes")
    for p in cat["palettes"]:
        row("Palettes", "Palette " + p["name"], p.get("source", "") or ", ".join(p.get("default", [])))
        for x in p.get("items", []): row("Palette tiles", "%s ▸ %s" % (p["name"], x["title"]), cmdtxt(x))
    head("## Panels")
    for p in cat["panels"]:
        row("Panels", "Panel %s (%s)" % (p["name"], p.get("view", "")), "sections: " + ", ".join(p.get("sections", [])))
        for c in p.get("controls", []):
            row("Panel controls", "%s ▸ %s%s %s" % (p["name"], (c["tab"] + " ▸ ") if c.get("tab") else "", c["kind"], c.get("label", "")),
                (cmdtxt(c) + " " + (c.get("binding") or "") + (" (repeated)" if c.get("repeated") else "")).strip())
    head("## Dialogs and windows")
    for d in cat["dialogs"]:
        row("Dialogs", "%s (%s %s)" % (d["name"], d.get("kind", ""), d.get("view", "")), ("`%s`" % d["command"]) if d.get("command") else "")
        for c in d.get("controls", []):
            row("Dialog fields", "%s ▸ %s%s %s" % (d["name"], (c["tab"] + " ▸ ") if c.get("tab") else "", c["kind"], c.get("label", "")),
                (cmdtxt(c) + " " + (c.get("binding") or "")).strip())
    head("## Status bar")
    for s in cat["statusBar"]:
        if s["kind"] in ("spacer", "separator"): continue
        row("Status bar", "%s %s" % (s["kind"], s.get("title", s.get("symbol", ""))), (s.get("key") or "") + " " + (s.get("help") or ""))
    head("## Keyboard shortcuts (Windows keys; Mac in brackets)")
    for s in cat["shortcuts"]:
        row("Shortcuts", "%s [%s] %s" % (s["keys"], s["mac"], s["action"]), ((s.get("note") or "") + ((" → " + s["windows"]) if s.get("windows") else "")).strip())
    head("## Rendering and 3D")
    for p in cat["render"]["presets"]:
        row("Render features", "Lighting preset " + p["name"], ", ".join("%s=%s" % (k, v) for k, v in list(p["look"].items())[:8]) + " …")
    for v in cat["render"]["visualStyles"]: row("Render features", "Visual style " + v, "")
    for f in ["Photographic render (RENDER) with presets, supersampling, PNG output", "Walk mode (WASD + mouse)", "Section box", "Sun study (animated sun and shadows)",
              "View cube", "3D gizmo (move/rotate)", "Camera paths and walkthrough video", "Render queue", "360° panorama", "Measure 3D", "Split view (plan + 3D)"]:
        row("Render features", f, "")
    head("## Theme")
    for k, v in cat["theme"]["colors"].items(): row("Theme", "Color " + k, "dark %s · light %s" % (v["dark"], v["light"]))
    for k, v in cat["theme"]["fonts"].items(): row("Theme", "Font " + k, "%s pt %s %s" % (v.get("size"), v.get("weight"), v.get("design", "")))
    for k, v in cat["theme"]["sizes"].items(): row("Theme", "Size " + k, str(v))
    cov = cat["coverage"]
    hdr = ["# Windows parity checklist", "",
           "Generated by `windows/tools/extract_parity.py` from the Mac app's Swift sources; data in `docs/windows-parity.json`.",
           "Re-run `python3 windows/tools/extract_parity.py` after changing the Mac UI. Tick items by changing the Status cell from `todo`",
           "to `done`, `partial`, `wip` or `n/a (reason)`: the generator keeps every non-todo status whose Item text is unchanged.", "",
           "## Counts", "", "| Section | Items |", "| --- | ---: |"]
    for k, v in counts.items(): hdr.append("| %s | %d |" % (k, v))
    hdr += ["| **Total checklist lines** | **%d** |" % sum(counts.values()), "", "Items not `todo`: %d — **%s** (see docs/WINDOWS-GAPS.md)" % (done[0], " · ".join("%s %d" % kv for kv in kinds.items() if kv[0] != "wip" or kv[1])), "",
            "## Command coverage", "",
            "- Registered commands (CommandDef literals in app/Sources, incl. %d system-variable commands): **%d**; in the Mac curated ribbon/menu catalogs: %d (+ %d system variables by rule = %d)" % (sum(1 for c in cat["commands"] if c.get("systemVariable")), cov["registered"], cov["macCatalogCovered"], cov["systemVariablesByRule"], cov["macCatalogCovered"] + cov["systemVariablesByRule"]),
            "- Not registered (sub-steps of another command, excluded): %s" % ", ".join("`%s`" % x for x in cov["subcommandsNotRegistered"]),
            "- " + cov["note"],
            "- Mac self-test reference: `%s`" % cov["macSelfTestReference"],
            "- Commands reachable from a ribbon button, ribbon menu, menu-bar item, palette or status bar in this catalogue: **%d**" % cov["withUiEntry"],
            "- System variables reached by rule (Manage ▸ More ▸ Settings ▸ System Variables, Tools ▸ System Variables): %d" % cov["systemVariablesByRule"],
            "- Without any UI entry: **%d** %s" % (len(cov["withoutUiEntry"]), ", ".join("`%s`" % x for x in cov["withoutUiEntry"])),
            "- Registered but not in the Mac curated catalogs (CommandCatalog.coverage would report them): %d %s" % (len(cov["notInMacCatalogs"]), ", ".join("`%s`" % x for x in cov["notInMacCatalogs"][:40])),
            ""]
    if cat["errors"]: hdr += ["## Generator warnings", ""] + ["- " + md_escape(e) for e in cat["errors"]] + [""]
    return "\n".join(hdr + L) + "\n"

def main():
    cat = build()
    out_json = os.path.join(ROOT, "docs", "windows-parity.json")
    out_md = os.path.join(ROOT, "docs", "WINDOWS-PARITY.md")
    with open(out_json, "w", encoding="utf-8") as f: json.dump(cat, f, indent=1, ensure_ascii=False); f.write("\n")
    prev = previous_status(out_md)
    with open(out_md, "w", encoding="utf-8") as f: f.write(checklist(cat, prev))
    cov = cat["coverage"]
    nitems = sum(len(g["items"]) for t in cat["ribbon"] for g in t["groups"])
    print("ribbon: %d tabs, %d groups, %d items; menus: %d; panels: %d; dialogs: %d; shortcuts: %d; symbols: %d" % (
        len(cat["ribbon"]), sum(len(t["groups"]) for t in cat["ribbon"]), nitems, len(cat["menus"]), len(cat["panels"]), len(cat["dialogs"]),
        len(cat["shortcuts"]), len(cat["symbolsToLucide"])))
    print("commands: %d registered, %d with UI entry, %d system variables by rule, %d without UI entry %s" % (
        cov["registered"], cov["withUiEntry"], cov["systemVariablesByRule"], len(cov["withoutUiEntry"]), cov["withoutUiEntry"][:20]))
    print("parse warnings (non-UI Swift the mini-parser skips): %d; errors: %d" % (cat["parseWarnings"], len(cat["errors"])))
    for e in cat["errors"]: print("  " + e)
    print("wrote", out_json, "and", out_md)
    if CHECK and (cov["withoutUiEntry"] or cat["errors"]): sys.exit(1)

if __name__ == "__main__":
    main()
