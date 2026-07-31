#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# flist_to_sfl.py — turn a VCS filelist into a ProtoSynthesis source list.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright 2026, SoC Labs (www.soclabs.org)
# -----------------------------------------------------------------------------
# WHY THIS EXISTS
#
# The Pynq-Z2 flow hand-maintains pynq/filelist.tcl — ~400 lines of Vivado
# `read_verilog` calls that duplicate, by hand, what the repo's own flists
# already say. It drifts: it still carried a PL230 `include-inlining hack for a
# DMA that has since been replaced by the rendered DMA-250.
#
# We do not repeat that mistake. This repo already produces a single flat,
# fully-resolved, tool-independent filelist for VCS:
#
#     flist/flatten_soc_flist.py       SoC generated flist  -> absolute paths
#     flist/resolve_tidelink_flist.py  TideLink flist       -> one def per module
#     flist/nanosoc_eth_chiplet.flist  the three components + integration RTL
#
# This script consumes THAT and emits what ProtoSynthesis wants, so the HAPS-SX
# source list can never drift from the simulation source list. When a submodule
# rolls, `make -C fpga/haps-sx srclist` picks the change up with no edits here.
#
# EMITS
#   <out>.sfl        one `-vlog_std <std> <abs path>` per source file
#   <out>_inc.tcl    `option set include_path {a;b;c}`  (semicolon-delimited,
#                    which is what ProtoCompiler expects — NOT colon)
#
# LANGUAGE STANDARD
#   Default is `sysv` for every file, deliberately. The repo's own `make elab`
#   compiles this exact file set under `vcs -sverilog`, i.e. SystemVerilog
#   globally — so global SV is already proven not to break any of these
#   sources. Use --std-by-ext for per-extension (.sv -> sysv, .v -> v2001) if a
#   future source needs it.
#
# USAGE
#   flist_to_sfl.py <root.flist> --out <prefix> [--extra <file> ...]
#                   [--std-by-ext] [--define NAME=VAL ...]
# -----------------------------------------------------------------------------

import argparse
import os
import re
import sys

# Header extensions: their DIRECTORY becomes an include path; the file itself
# must never be compiled as a source.
_HEADER_EXTS = (".vh", ".svh", ".h")
_SOURCE_EXTS = (".v", ".sv", ".vlib")


def expand(tok):
    """$(VAR) -> ${VAR}, then expand ${VAR}/$VAR against the environment."""
    tok = re.sub(r"\$\(([A-Za-z_]\w*)\)", r"${\1}", tok)
    return os.path.expandvars(tok)


class Collector:
    def __init__(self, std_by_ext):
        self.sources = []          # ordered, deduped absolute paths
        self._seen_src = set()
        self.incdirs = []          # ordered, deduped absolute dirs
        self._seen_inc = set()
        self.defines = []
        self.unresolved = []       # tokens still containing '$' after expansion
        self.missing = []          # files that do not exist on disk
        self.std_by_ext = std_by_ext

    def add_source(self, path):
        ap = os.path.abspath(path)
        if ap in self._seen_src:
            return
        self._seen_src.add(ap)
        self.sources.append(ap)
        if not os.path.isfile(ap):
            self.missing.append(ap)

    def add_incdir(self, path):
        ap = os.path.abspath(path)
        if ap in self._seen_inc:
            return
        self._seen_inc.add(ap)
        self.incdirs.append(ap)

    def std_for(self, path):
        if not self.std_by_ext:
            return "sysv"
        return "sysv" if path.endswith(".sv") else "v2001"


def _resolve(tok, base_dir):
    """Expand vars, then make relative paths absolute against the flist dir."""
    p = expand(tok)
    if not os.path.isabs(p) and "$" not in p:
        p = os.path.join(base_dir, p)
    return p


def parse_flist(path, col):
    """Walk a VCS filelist, following `-f` includes (one or two tokens)."""
    seen = set()

    def walk(fp):
        ap = os.path.abspath(fp)
        if ap in seen:
            return
        seen.add(ap)
        if not os.path.isfile(ap):
            sys.stderr.write("flist_to_sfl: MISSING filelist %s\n" % ap)
            col.missing.append(ap)
            return
        d = os.path.dirname(ap)
        with open(ap) as fh:
            text = fh.read()
        # Drop comments line-by-line, then tokenise the whole file so a
        # `-f` and its argument can span whitespace or newlines.
        clean = []
        for raw in text.splitlines():
            line = raw.split("//", 1)[0]
            line = re.sub(r"(^|\s)#.*$", "", line)
            clean.append(line)
        toks = " ".join(clean).split()

        i = 0
        while i < len(toks):
            tok = toks[i]
            if tok in ("-f", "-F") and i + 1 < len(toks):
                walk(_resolve(toks[i + 1], d))
                i += 2
                continue
            m = re.match(r"^-[fF](.+)$", tok)
            if m:
                walk(_resolve(m.group(1), d))
                i += 1
                continue
            if tok.startswith("+incdir+"):
                for x in tok[len("+incdir+"):].split("+"):
                    if x:
                        col.add_incdir(_resolve(x, d))
                i += 1
                continue
            if tok.startswith("+define+"):
                for x in tok[len("+define+"):].split("+"):
                    if x:
                        col.defines.append(x)
                i += 1
                continue
            if tok.startswith("-") or tok.startswith("+"):
                i += 1
                continue
            p = _resolve(tok, d)
            if "$" in p:
                col.unresolved.append(tok)
            elif p.endswith(_HEADER_EXTS):
                col.add_incdir(os.path.dirname(p))
            elif p.endswith(_SOURCE_EXTS):
                col.add_source(p)
            i += 1

    walk(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("flist", help="root VCS filelist")
    ap.add_argument("--out", required=True,
                    help="output prefix; writes <prefix>.sfl and <prefix>_inc.tcl")
    ap.add_argument("--extra", action="append", default=[],
                    help="extra source appended AFTER the flist (e.g. the board top)")
    ap.add_argument("--define", action="append", default=[],
                    help="extra `define passed to run compile -hdl_define")
    ap.add_argument("--std-by-ext", action="store_true",
                    help="per-extension language standard instead of sysv everywhere")
    ap.add_argument("--allow-missing", action="store_true",
                    help="warn instead of failing when a listed file is absent")
    args = ap.parse_args()

    col = Collector(args.std_by_ext)
    parse_flist(os.path.abspath(args.flist), col)

    for e in args.extra:
        col.add_source(os.path.abspath(os.path.expandvars(e)))

    # --- report problems loudly; a silently short source list is the worst
    # --- failure mode here (it shows up as a black box 40 minutes later).
    rc = 0
    if col.unresolved:
        sys.stderr.write(
            "flist_to_sfl: %d token(s) still contain '$' after expansion — "
            "an environment variable is unset. Source set_env.sh first.\n"
            % len(col.unresolved))
        for t in sorted(set(col.unresolved))[:20]:
            sys.stderr.write("    %s\n" % t)
        rc = 1
    if col.missing:
        sys.stderr.write("flist_to_sfl: %d listed file(s) do not exist:\n"
                         % len(col.missing))
        for t in col.missing[:20]:
            sys.stderr.write("    %s\n" % t)
        if not args.allow_missing:
            rc = 1

    sfl_path = args.out + ".sfl"
    inc_path = args.out + "_inc.tcl"
    viv_path = args.out + "_vivado.tcl"

    with open(sfl_path, "w") as fh:
        fh.write("# Generated by flist_to_sfl.py — DO NOT EDIT.\n")
        fh.write("# Source: %s\n" % os.path.abspath(args.flist))
        fh.write("# %d source files\n" % len(col.sources))
        for s in col.sources:
            fh.write("-vlog_std %s %s\n" % (col.std_for(s), s))

    with open(inc_path, "w") as fh:
        fh.write("# Generated by flist_to_sfl.py — DO NOT EDIT.\n")
        fh.write("# %d include directories\n" % len(col.incdirs))
        # ProtoCompiler wants a SEMICOLON-delimited list, not colon.
        fh.write("option set include_path {%s}\n" % ";".join(col.incdirs))
        defines = col.defines + args.define
        if defines:
            fh.write("# Defines collected from the flist and the command line.\n")
            fh.write("set HAPS_SX_HDL_DEFINES {%s}\n" % " ".join(defines))
        else:
            fh.write("set HAPS_SX_HDL_DEFINES {}\n")

    # --- Vivado form -------------------------------------------------------
    # Same source set, spelled for `read_verilog`. Emitted from the SAME walk
    # so the ProtoSynthesis and Vivado flows can never diverge on which files
    # are in the design.
    defines = col.defines + args.define
    with open(viv_path, "w") as fh:
        fh.write("#" * 78 + "\n")
        fh.write("# Generated by flist_to_sfl.py — DO NOT EDIT.\n")
        fh.write("# Source: %s\n" % os.path.abspath(args.flist))
        fh.write("# %d source files, %d include dirs\n"
                 % (len(col.sources), len(col.incdirs)))
        fh.write("#" * 78 + "\n\n")

        fh.write("set_property include_dirs [list \\\n")
        for d in col.incdirs:
            fh.write("    %s \\\n" % d)
        fh.write("] [current_fileset]\n\n")

        if defines:
            fh.write("set_property verilog_define {%s} [current_fileset]\n\n"
                     % " ".join(defines))

        for s in col.sources:
            # -sv for .sv; plain read_verilog otherwise. Unlike the
            # ProtoSynthesis side (where global sysv is proven by `make elab`
            # running vcs -sverilog), Vivado's SV parser is stricter about
            # legacy Verilog, so stay per-extension here.
            if s.endswith(".sv"):
                fh.write("read_verilog -sv %s\n" % s)
            else:
                fh.write("read_verilog %s\n" % s)

    sys.stderr.write("flist_to_sfl: %d sources, %d include dirs -> %s, %s\n"
                     % (len(col.sources), len(col.incdirs), sfl_path, viv_path))
    return rc


if __name__ == "__main__":
    sys.exit(main())
