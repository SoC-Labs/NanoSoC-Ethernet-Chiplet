#!/usr/bin/env python3
"""Resolve a VCS/Xcelium filelist into a flat Verilator command line.

Recursively expands `-f`, expands ${VAR}/$(VAR) from the environment, collects
+incdir+/+define+, dedups files by realpath, and reports duplicate MODULE
definitions across different files (which Verilator treats as a hard error).
"""
import os
import re
import sys
import json
import argparse

VAR_RE = re.compile(r"\$[({]([A-Za-z_][A-Za-z_0-9]*)[)}]")
MOD_RE = re.compile(r"^\s*(?:module|primitive)\s+([A-Za-z_][A-Za-z_0-9$]*)", re.M)


def expand(s, env):
    def sub(m):
        v = env.get(m.group(1))
        if v is None:
            raise SystemExit(f"flist_resolve: unset variable {m.group(0)}")
        return v
    prev = None
    while prev != s:
        prev, s = s, VAR_RE.sub(sub, s)
    return s


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    text = re.sub(r"//[^\n]*", "", text)
    return text


class Resolver:
    def __init__(self, env):
        self.env = env
        self.files = []          # ordered, deduped by realpath
        self.seen = set()
        self.incdirs = []
        self.defines = []
        self.libexts = []
        self.libdirs = []
        self.unknown = []
        self.missing = []
        self.flists = []

    def read(self, path, depth=0):
        path = os.path.realpath(path)
        if path in self.flists:
            return
        self.flists.append(path)
        with open(path) as f:
            raw = f.read()
        # flists use // comments; keep it line-based so a '//' inside a path
        # (there are none - all absolute) is not an issue.
        toks = []
        for line in raw.splitlines():
            line = line.split("//", 1)[0].strip()
            if not line or line.startswith("#"):
                continue
            toks.extend(line.split())
        i = 0
        while i < len(toks):
            t = toks[i]
            i += 1
            if t in ("-f", "-F"):
                nxt = expand(toks[i], self.env); i += 1
                if not os.path.exists(nxt):
                    self.missing.append(nxt)
                    continue
                self.read(nxt, depth + 1)
            elif t == "-y":
                self.libdirs.append(expand(toks[i], self.env)); i += 1
            elif t.startswith("+incdir+"):
                for d in expand(t[len("+incdir+"):], self.env).split("+"):
                    if d and d not in self.incdirs:
                        self.incdirs.append(d)
            elif t.startswith("+define+"):
                for d in expand(t[len("+define+"):], self.env).split("+"):
                    if d and d not in self.defines:
                        self.defines.append(d)
            elif t.startswith("+libext+"):
                for e in t[len("+libext+"):].split("+"):
                    if e and e not in self.libexts:
                        self.libexts.append(e)
            elif t.startswith("-") or t.startswith("+"):
                self.unknown.append(t)
            else:
                p = expand(t, self.env)
                rp = os.path.realpath(p)
                if not os.path.exists(rp):
                    self.missing.append(p)
                    continue
                if rp in self.seen:
                    continue
                self.seen.add(rp)
                self.files.append(rp)


def modules_in(path):
    try:
        with open(path, errors="replace") as f:
            return MOD_RE.findall(strip_comments(f.read()))
    except OSError:
        return []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("flist")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    r = Resolver(dict(os.environ))
    r.read(a.flist)

    # duplicate module definitions across distinct files
    owner = {}
    dups = []
    for f in r.files:
        for m in modules_in(f):
            if m in owner and owner[m] != f:
                dups.append((m, owner[m], f))
            owner.setdefault(m, f)
    # last-wins (VCS semantics): the LAST file defining a name is authoritative
    last = {}
    for f in r.files:
        for m in modules_in(f):
            last[m] = f

    out = {
        "files": r.files,
        "incdirs": r.incdirs,
        "defines": r.defines,
        "libexts": r.libexts,
        "libdirs": r.libdirs,
        "unknown": sorted(set(r.unknown)),
        "missing": r.missing,
        "flists": r.flists,
        "dup_modules": [{"module": m, "first": x, "later": y} for m, x, y in dups],
        "module_count": len(owner),
    }
    if a.json:
        json.dump(out, sys.stdout, indent=1)
        return
    print(f"flists read     : {len(r.flists)}")
    print(f"files           : {len(r.files)}")
    print(f"modules defined : {len(owner)}")
    print(f"incdirs         : {len(r.incdirs)}")
    print(f"defines         : {r.defines}")
    print(f"libexts         : {r.libexts}")
    print(f"unknown tokens  : {out['unknown']}")
    print(f"MISSING files   : {len(r.missing)}")
    for m in r.missing:
        print(f"   {m}")
    print(f"DUPLICATE module defs : {len(dups)}")
    for m, x, y in dups:
        print(f"   {m}\n      first: {x}\n      later: {y}")


if __name__ == "__main__":
    main()
