#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# scripts/ci/rom_cache.py -- build the mask-programmed boot ROM macros for ONE
# run, from a content-addressed cache, and materialise them INTO that run.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
# -----------------------------------------------------------------------------
# WHY THIS EXISTS
# ---------------
# Until now the ROM macros were a hand-fetched binary drop in ASIC/romlibs,
# gitignored, copied out of another user's tapeout tree by `romlibs-fetch`.
# Nothing connected a macro to the firmware it was supposed to contain, so a
# firmware change could reach the .bintxt and never reach the macro. That is not
# a hypothetical: it shipped. One macro held uniform random data, the other held
# a different firmware target, and both predated their own code files by seven
# weeks. They are MASK PROGRAMMED -- wrong bits are a dead die.
#
# ASIC/rom_gate.mk catches that failure. This file PREVENTS it: the ROM a run
# synthesises against is built by that run, from that run's firmware, and lives
# in that run's directory.
#
# THE THREE THINGS THIS GETS RIGHT, EACH OF WHICH COST SOMETHING TO LEARN
# -----------------------------------------------------------------------
# 1. NEVER RUN THE COMPILER'S `all` TARGET. `all` includes the `testcode`
#    generator, whose -code_file argument is its OUTPUT: it overwrites the
#    firmware you handed it with a synthetic pattern, and every generator
#    sequenced after it then reads the clobbered file. That is the whole reason
#    the five content views used to split into two families holding different
#    programs -- the Verilog model (which every simulation loads) was on the
#    wrong side of it. So: an explicit generator list, `testcode` refused by
#    name, and after EVERY generator the code file is re-hashed and the build
#    fails if it moved.
#
# 2. THE COMPILER MUST RUN FROM LOCAL DISK. It enumerates its own views/ through
#    a 32-bit helper whose non-LFS readdir() cannot represent an inode >= 2^32.
#    On the NFS tree that holds the shared install, inodes are ~1.8e10, so it
#    sees zero views, reports zero generators and emits nothing. ASIC/common.mk's
#    `rom-compiler-stage` mirrors it and guards the inode range; this file only
#    consumes the mirror, and refuses to start if it lists no generators.
#
# 3. PROVENANCE IS AN mtime ARGUMENT, AND A CACHE BREAKS IT IF YOU LET IT.
#    rom_verify.py proves a macro postdates its code file, using both filesystem
#    mtimes and the compiler's own internal creation stamp. A cache hit returns
#    files built at some earlier time; if the code file has been rewritten since
#    -- even with byte-identical content -- provenance fails on a macro that is
#    provably correct. Two measures, together:
#      * ASIC/common.mk regenerates the .bintxt files CONTENT-PRESERVINGLY, so
#        an unchanged program keeps its mtime, and mtime means what the checker
#        assumes it means: when the contents last changed.
#      * a cache entry older than its code file is treated as a MISS here (see
#        `_entry_is_fresh`) and rebuilt. Costs one rebuild; never reports a
#        false provenance failure, and never hides a real one.
#
# WHAT THE CACHE IS KEYED ON
# --------------------------
# sha256 over: the code file's CONTENTS, the code file's PATH, the spec's
# canonicalised key=value settings (comments excluded -- those specs carry long
# explanatory comments that must not invalidate a build), the compiler's version
# identity, and the generator list. Same inputs -> same bytes, reused. Any
# change -> a different key -> a rebuild. The path is in the key deliberately:
# the compiler records the -code_file it was handed inside the macro netlist,
# rom_verify.py compares that recording against the spec, and a build from a
# different path is therefore a genuinely different artefact.
#
# WHAT "INTO THE RUN" MEANS
# -------------------------
# HARDLINKS, not copies and not symlinks:
#   * a copy costs 32 MB per run for bytes that are already on the disk;
#   * a symlink into the cache leaves the run describing a file it does not own,
#     and a cache clean silently guts every run that pointed at it;
#   * a hardlink is genuinely present in the run directory, costs nothing, and
#     KEEPS THE DATA ALIVE if the cache entry is later replaced or deleted. It
#     is also why a rebuild at the same key is safe while other runs are open.
# Copy is the fallback when the cache and the run are on different filesystems.
#
# AND WHY THE RUN IS PINNED
# -------------------------
# Synthesis reads the .lib, P&R the .lef, stream-out the .gds2 -- three stages,
# hours apart, that MUST see one build. `stage` writes .rom_pin.json recording
# the key and every file's hash. Re-staging a run whose key has changed is
# refused, not silently honoured: a run whose ROM changed halfway through is a
# run whose netlist and whose mask disagree, and that is precisely the class of
# defect this whole exercise exists to end. Start a new run instead.
# -----------------------------------------------------------------------------

from __future__ import annotations

import argparse
import errno
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

CACHE_FORMAT = 1

# The generator that must never run. Its -code_file is an OUTPUT.
FORBIDDEN_GENERATORS = {"testcode", "all"}

# Default generator list: every generator this compiler offers EXCEPT testcode.
DEFAULT_GENERATORS = [
    "liberty", "lef-fp", "gds2", "verilog", "masis", "tmax", "fastscan",
    "ctl", "lvs", "bitmap", "apache_avm", "memorybist", "ascii", "postscript",
]


def die(msg: str, code: int = 1) -> None:
    sys.stderr.write("rom_cache: FAIL: %s\n" % msg)
    sys.exit(code)


def note(msg: str) -> None:
    sys.stdout.write("rom_cache: %s\n" % msg)
    sys.stdout.flush()


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def iso(epoch: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(epoch))


# -----------------------------------------------------------------------------
# Inputs: the spec, the code file, the compiler
# -----------------------------------------------------------------------------

def parse_spec(path: str) -> dict:
    """The spec's SETTINGS, without its prose.

    These specs carry long comment blocks arguing why `mode` and `words` are
    what they are. Those comments are the most valuable thing in the file and
    they get edited; they must not invalidate a cached build. Only `key = value`
    lines are read, and a line whose first non-blank character is '#' is a
    comment -- values are not comment-stripped, because `cust_comment` may
    legitimately contain a '#'.
    """
    if not os.path.isfile(path):
        die("no spec at %s" % path)
    out = {}
    with open(path, "r", errors="replace") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    if not out:
        die("spec %s has no key=value settings -- an empty spec is not a spec" % path)
    return out


def read_code_file(path: str):
    """Returns (lines, words, bits). Refuses anything the compiler would
    silently paper over: a missing, empty or ragged code file makes the compiler
    SUBSTITUTE contents rather than fail, and emit a perfectly well-formed macro
    full of something else."""
    if not os.path.isfile(path):
        die("no code file at %s\n"
            "      This is the defect, not a missing prerequisite: handed no code\n"
            "      file the ROM compiler substitutes contents and emits a valid macro."
            % path)
    with open(path, "r", errors="replace") as f:
        lines = [ln.strip() for ln in f if ln.strip()]
    if not lines:
        die("code file %s is empty" % path)
    widths = {len(ln) for ln in lines}
    if len(widths) != 1:
        die("code file %s is ragged: line widths %s -- every line must be one word"
            % (path, sorted(widths)))
    bits = widths.pop()
    bad = [i for i, ln in enumerate(lines) if not re.fullmatch(r"[01]+", ln)]
    if bad:
        die("code file %s is not binary text: line %d is %r"
            % (path, bad[0] + 1, lines[bad[0]][:32]))
    return lines, len(lines), bits


def compiler_identity(compiler: str) -> dict:
    """Version identity plus the generators the install can actually run.

    The banner also carries the hostname and the running kernel, which vary run
    to run and must NOT enter the cache key -- only the two version lines do.

    The generator list is on the lines AFTER 'Available generators are:', not on
    that line. Parsing it as a same-line value yields an empty list on a
    perfectly working compiler, which reads as the NFS-inode failure and sends
    you to fix an install that is fine.
    """
    if not (os.path.isfile(compiler) and os.access(compiler, os.X_OK)):
        die("ROM compiler missing or not executable: %s\n"
            "      Mirror it to local disk first: make -f ASIC/common.mk rom-compiler-stage"
            % compiler)
    with open(os.devnull, "rb") as devnull:
        p = subprocess.run([compiler, "-help"], stdin=devnull,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    text = p.stdout.decode("utf-8", "replace")

    versions = [ln.strip() for ln in text.splitlines()
                if re.match(r"^\s*(Compiler|GUI) version\b", ln)]
    if not versions:
        die("%s printed no version banner -- it is not the compiler, or it did "
            "not start" % compiler)

    gens = []
    started = False
    for ln in text.splitlines():
        if "Available generators are:" in ln:
            started = True
            tail = ln.split("Available generators are:", 1)[1].strip()
            if tail:
                gens.extend(tail.split())
            continue
        if started:
            s = ln.strip()
            if not s or s.startswith("You can also") or s.startswith("Options"):
                break
            if re.fullmatch(r"[A-Za-z0-9_.-]+", s):
                gens.append(s)
            else:
                break
    if not gens:
        die("%s starts but lists NO generators.\n"
            "      Almost always the FILESYSTEM, not the install: the compiler scans\n"
            "      its own views/ from a 32-bit helper whose readdir() cannot represent\n"
            "      an inode >= 2^32, so from NFS it sees no views and no generators.\n"
            "      Run it from a LOCAL-DISK mirror: make -f ASIC/common.mk rom-compiler-stage"
            % compiler)

    return {"path": compiler,
            "versions": versions,
            "wrapper_sha256": sha256_file(compiler),
            "generators_available": sorted(gens)}


# -----------------------------------------------------------------------------
# The cache key
# -----------------------------------------------------------------------------

def compute_key(rom: str, spec_path: str, code_path: str, generators: list,
                ident: dict) -> tuple:
    spec = parse_spec(spec_path)
    code_sha = sha256_file(code_path)
    canon = {
        "cache_format": CACHE_FORMAT,
        "rom": rom,
        "spec_settings": spec,
        "code_sha256": code_sha,
        "code_path": os.path.abspath(code_path),
        "compiler_versions": ident["versions"],
        "compiler_wrapper_sha256": ident["wrapper_sha256"],
        "generators": sorted(generators),
    }
    blob = json.dumps(canon, sort_keys=True, separators=(",", ":")).encode()
    return sha256_bytes(blob)[:16], canon, spec, code_sha


# -----------------------------------------------------------------------------
# Cache entries
# -----------------------------------------------------------------------------

def entry_dir(cache_root: str, rom: str, key: str) -> str:
    return os.path.join(cache_root, rom, key)


def load_manifest(edir: str):
    mpath = os.path.join(edir, "build.json")
    if not os.path.isfile(mpath):
        return None
    try:
        with open(mpath) as f:
            return json.load(f)
    except Exception:
        return None


def entry_is_sound(edir: str) -> bool:
    """A cache entry is only usable if it is COMPLETE. A half-written entry that
    still has files in it is the worst possible cache hit, so the manifest is
    written last and its absence condemns the entry."""
    man = load_manifest(edir)
    if not man:
        return False
    macro = os.path.join(edir, "macro")
    for name in man.get("files", {}):
        p = os.path.join(macro, name)
        if not (os.path.isfile(p) and os.path.getsize(p) > 0):
            return False
    return True


def entry_is_fresh(man: dict, code_path: str) -> tuple:
    """Provenance freshness -- see the header.

    A cache hit whose files predate the code file makes rom_verify.py's
    provenance check fail on a macro that is byte-for-byte correct. Rather than
    teach the checker to ignore that (it is the check that caught a macro seven
    weeks older than its firmware), treat such an entry as a miss and rebuild.
    """
    built = man.get("built_at_epoch")
    if not built:
        return False, "manifest records no build time"
    try:
        cm = os.path.getmtime(code_path)
    except OSError as e:
        return False, "cannot stat the code file: %s" % e
    if cm > built + 1:
        return False, ("the code file was rewritten %s, after this entry was built %s "
                       "-- rebuilding so provenance holds"
                       % (iso(cm), iso(built)))
    return True, ""


# -----------------------------------------------------------------------------
# The build
# -----------------------------------------------------------------------------

def build_entry(cache_root: str, rom: str, key: str, canon: dict, spec: dict,
                spec_path: str, code_path: str, code_sha: str,
                generators: list, ident: dict, compiler: str,
                expect_words: int) -> str:
    """Compile one ROM into the cache, atomically.

    Built in a temporary directory and moved into place with a single rename, so
    a killed build cannot leave a partial entry that a later run would treat as
    a hit. The manifest is written before the rename and is what marks the entry
    complete.
    """
    final = entry_dir(cache_root, rom, key)
    tmp = os.path.join(cache_root, rom, ".tmp-%s-%d" % (key, os.getpid()))
    macro = os.path.join(tmp, "macro")
    logs = os.path.join(tmp, "logs")
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(macro)
    os.makedirs(logs)
    # A failed build leaves its tmp directory behind ON PURPOSE -- the generator
    # logs in it are the only evidence of what went wrong. Sweep the ones older
    # than a day here rather than deleting on failure.
    parent = os.path.join(cache_root, rom)
    for name in os.listdir(parent):
        if not name.startswith(".tmp-"):
            continue
        p = os.path.join(parent, name)
        if p != tmp and os.path.isdir(p) and \
                time.time() - os.path.getmtime(p) > 86400:
            shutil.rmtree(p, ignore_errors=True)

    # The geometry trap, checked BEFORE three minutes of compiler time and, more
    # to the point, before an 11-bit-address macro is baked. The specs were
    # corrected to words=512 after both macros on disk were found to be 512 deep
    # while the specs said 2048; a rebuild from the wrong spec produces a macro
    # that matches neither the RTL wrapper's A[8:0] nor the HADDR[10:2] decode.
    lines, words, bits = read_code_file(code_path)
    spec_words = spec.get("words")
    spec_bits = spec.get("bits")
    problems = []
    if spec_words is None or int(spec_words) != words:
        problems.append("spec says words=%s, the code file has %d words"
                        % (spec_words, words))
    if spec_bits is None or int(spec_bits) != bits:
        problems.append("spec says bits=%s, the code file is %d bits wide"
                        % (spec_bits, bits))
    if expect_words and words != expect_words:
        problems.append("this design's ROMs are %d words deep (A[%d:0]); this "
                        "code file is %d words -- an 11-bit-address macro matches "
                        "neither the RTL wrapper nor the HADDR region decode"
                        % (expect_words, (expect_words - 1).bit_length() - 1, words))
    if problems:
        shutil.rmtree(tmp, ignore_errors=True)
        die("[%s] GEOMETRY DISAGREEMENT before compile:\n      - %s"
            % (rom, "\n      - ".join(problems)))

    bad = sorted(set(generators) & FORBIDDEN_GENERATORS)
    if bad:
        shutil.rmtree(tmp, ignore_errors=True)
        die("refusing to run generator(s) %s. `testcode` treats -code_file as its "
            "OUTPUT and overwrites the firmware; `all` runs it. See this file's header."
            % ", ".join(bad))
    unknown = sorted(set(generators) - set(ident["generators_available"]))
    if unknown:
        shutil.rmtree(tmp, ignore_errors=True)
        die("[%s] generator(s) %s are not offered by this compiler (it offers: %s)"
            % (rom, ", ".join(unknown), " ".join(ident["generators_available"])))

    note("[%s] building %d generators (key %s)" % (rom, len(generators), key))
    timings = {}
    t_all = time.time()
    for g in generators:
        t0 = time.time()
        with open(os.path.join(logs, "gen_%s.log" % g), "wb") as lf, \
                open(os.devnull, "rb") as devnull:
            p = subprocess.run([compiler, g, "-spec", spec_path,
                                "-code_file", code_path],
                               cwd=macro, stdin=devnull, stdout=lf,
                               stderr=subprocess.STDOUT)
        timings[g] = round(time.time() - t0, 2)

        # THE GUARD. Exit status is not the verdict -- the compiler exits 0 after
        # substituting contents. What matters is whether the firmware moved.
        after = sha256_file(code_path) if os.path.isfile(code_path) else None
        if after != code_sha:
            shutil.rmtree(tmp, ignore_errors=True)
            die("[%s] generator '%s' MODIFIED THE CODE FILE %s.\n"
                "      Its -code_file is an output, not an input. Remove it from the\n"
                "      generator list and restore the firmware: make -f ASIC/common.mk rom-bintxt"
                % (rom, g, code_path))
        if p.returncode != 0:
            die("[%s] generator '%s' failed (rc=%d); see %s/gen_%s.log"
                % (rom, g, p.returncode, logs, g))
        note("  [%s] %-12s %6.1fs" % (rom, g, timings[g]))
    total = round(time.time() - t_all, 2)

    produced = sorted(os.listdir(macro))
    if not produced:
        shutil.rmtree(tmp, ignore_errors=True)
        die("[%s] every generator reported success and NOTHING was written to %s"
            % (rom, macro))

    files = {}
    for name in produced:
        p = os.path.join(macro, name)
        if not os.path.isfile(p):
            continue
        files[name] = {"size": os.path.getsize(p), "sha256": sha256_file(p)}
        os.chmod(p, 0o444)   # a cache entry is immutable; runs hardlink to it

    inst = spec.get("instname", rom)
    required = ["%s.lef" % inst, "%s.gds2" % inst, "%s.v" % inst, "%s.cdl" % inst]
    corners = [c.strip() for c in spec.get("corners", "").split(",") if c.strip()]
    required += ["%s_%s.lib" % (inst, c) for c in corners]
    missing = [r for r in required if r not in files]
    if missing:
        shutil.rmtree(tmp, ignore_errors=True)
        die("[%s] the compiler exited 0 but did not write: %s"
            % (rom, ", ".join(missing)))

    man = {
        "cache_format": CACHE_FORMAT,
        "rom": rom,
        "key": key,
        "key_inputs": canon,
        "origin": "compiled",
        "built_at_epoch": time.time(),
        "built_at": iso(time.time()),
        "host": os.uname().nodename,
        "user": os.environ.get("USER", "?"),
        "compiler": {"versions": ident["versions"],
                     "wrapper_sha256": ident["wrapper_sha256"]},
        "spec_path": os.path.abspath(spec_path),
        "code_file": {"path": os.path.abspath(code_path),
                      "sha256": code_sha,
                      "mtime_epoch": os.path.getmtime(code_path),
                      "mtime": iso(os.path.getmtime(code_path)),
                      "words": words, "bits": bits},
        "instname": inst,
        "generators": generators,
        "generator_seconds": timings,
        "total_seconds": total,
        "files": files,
    }
    with open(os.path.join(tmp, "build.json"), "w") as f:
        json.dump(man, f, indent=2, sort_keys=True)
        f.write("\n")

    os.makedirs(os.path.dirname(final), exist_ok=True)
    # INSTALLING OVER AN EXISTING ENTRY, and when not to.
    #
    # Two runs that start together with the same firmware both miss and both
    # build; the loser must not tear the winner's entry out from under a run
    # that is at that moment hardlinking from it. So an entry that is already
    # sound AND provenance-fresh is left alone and this build is discarded --
    # the two are equivalent by construction, since the key covers every input.
    #
    # The entry IS replaced when it is unsound (a partial write) or stale (older
    # than its code file), because those are the cases a rebuild exists to fix.
    # Even then, runs already hardlinked to the old files keep them: removing a
    # directory entry does not remove the data. That is the whole reason this
    # materialises by hardlink rather than by symlink.
    if os.path.exists(final):
        keep = entry_is_sound(final) and entry_is_fresh(load_manifest(final),
                                                        code_path)[0]
        if keep:
            shutil.rmtree(tmp, ignore_errors=True)
            note("[%s] another build installed this key first and it is sound; "
                 "keeping it (%.1fs of work discarded)" % (rom, total))
            return final
        stale = final + ".stale-%d" % os.getpid()
        os.rename(final, stale)
        shutil.rmtree(stale, ignore_errors=True)
    try:
        os.rename(tmp, final)
    except OSError as e:
        if e.errno != errno.ENOTEMPTY:
            raise
        shutil.rmtree(tmp, ignore_errors=True)   # lost a race; the winner is sound
    note("[%s] built in %.1fs -> %s" % (rom, total, final))
    return final


def import_entry(cache_root: str, rom: str, key: str, canon: dict, spec: dict,
                 spec_path: str, code_path: str, code_sha: str,
                 generators: list, src: str) -> str:
    """Adopt an already-compiled macro tree into the cache.

    For hosts with no working compiler, replacing `romlibs-fetch`. The imported
    entry is labelled origin=imported and carries the tree it came from, so a
    run staged from it can never be mistaken for one this repository built. It
    still has to pass rom_gate.mk afterwards -- importing asserts nothing about
    contents, and the tree this project imported for months held the wrong bits.
    """
    if not os.path.isdir(src):
        die("no macro tree to import at %s" % src)
    final = entry_dir(cache_root, rom, key)
    tmp = os.path.join(cache_root, rom, ".tmp-%s-%d" % (key, os.getpid()))
    macro = os.path.join(tmp, "macro")
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(macro)
    files = {}
    for name in sorted(os.listdir(src)):
        sp = os.path.join(src, name)
        if not os.path.isfile(sp):
            continue
        # Skip dotfiles. The compiler emits none, so anything hidden here is
        # BOOKKEEPING, not macro content -- and the tree being imported is very
        # often another RUN's romlibs, which carries this tool's own
        # .rom_build.json. Importing that as if it were a view then hardlinks a
        # read-only metadata file into the new run at the exact path the new
        # metadata has to be written to, and staging dies with EACCES.
        if name.startswith("."):
            continue
        dp = os.path.join(macro, name)
        shutil.copy2(sp, dp)
        files[name] = {"size": os.path.getsize(dp), "sha256": sha256_file(dp)}
        os.chmod(dp, 0o444)
    if not files:
        shutil.rmtree(tmp, ignore_errors=True)
        die("%s holds no files to import" % src)
    man = {
        "cache_format": CACHE_FORMAT, "rom": rom, "key": key, "key_inputs": canon,
        "origin": "imported", "imported_from": os.path.abspath(src),
        "built_at_epoch": time.time(), "built_at": iso(time.time()),
        "host": os.uname().nodename, "user": os.environ.get("USER", "?"),
        "spec_path": os.path.abspath(spec_path),
        "code_file": {"path": os.path.abspath(code_path), "sha256": code_sha,
                      "mtime_epoch": os.path.getmtime(code_path),
                      "mtime": iso(os.path.getmtime(code_path))},
        "instname": spec.get("instname", rom),
        "generators": generators, "files": files,
    }
    with open(os.path.join(tmp, "build.json"), "w") as f:
        json.dump(man, f, indent=2, sort_keys=True)
        f.write("\n")
    os.makedirs(os.path.dirname(final), exist_ok=True)
    if os.path.exists(final):
        stale = final + ".stale-%d" % os.getpid()
        os.rename(final, stale)
        shutil.rmtree(stale, ignore_errors=True)
    os.rename(tmp, final)
    note("[%s] imported %d files from %s -> %s" % (rom, len(files), src, final))
    return final


# -----------------------------------------------------------------------------
# Materialising into a run
# -----------------------------------------------------------------------------

def link_or_copy(src: str, dst: str) -> str:
    if os.path.lexists(dst):
        os.unlink(dst)
    try:
        os.link(src, dst)
        return "link"
    except OSError as e:
        if e.errno not in (errno.EXDEV, errno.EPERM, errno.EMLINK):
            raise
        shutil.copy2(src, dst)
        return "copy"


def stage_into_run(edir: str, run_romlibs: str, rom: str, label: str,
                   repin: bool) -> dict:
    """Materialise one cache entry into <run>/romlibs/<label>/, and pin it."""
    man = load_manifest(edir)
    if not man:
        die("[%s] cache entry %s has no manifest" % (rom, edir))
    key = man["key"]
    pin_path = os.path.join(run_romlibs, ".rom_pin.json")
    pin = {}
    if os.path.isfile(pin_path):
        try:
            with open(pin_path) as f:
                pin = json.load(f)
        except Exception:
            pin = {}
    prev = pin.get("roms", {}).get(label)

    if prev and prev.get("key") != key and not repin:
        die("[%s] THIS RUN IS ALREADY PINNED TO A DIFFERENT ROM BUILD.\n"
            "      run      : %s\n"
            "      pinned   : %s (staged %s)\n"
            "      requested: %s\n"
            "      Synthesis reads the .lib, P&R the .lef and stream-out the .gds2 --\n"
            "      hours apart, and they must be ONE build. Re-staging this run would\n"
            "      leave its netlist and its mask describing different programs.\n"
            "      Start a new run instead (a new RUN_TAG / a new output directory).\n"
            "      ROM_RUN_REPIN=1 overrides, and is only ever right on a run whose\n"
            "      results are being discarded."
            % (label, run_romlibs, prev.get("key"), prev.get("staged_at"), key))

    dest = os.path.join(run_romlibs, label)
    macro = os.path.join(edir, "macro")
    fresh_needed = True
    if prev and prev.get("key") == key and os.path.isdir(dest):
        # Already staged. Verify rather than trust: this is the assertion that
        # makes "one build per run" a fact instead of a convention.
        bad = []
        for name, meta in man["files"].items():
            p = os.path.join(dest, name)
            if not os.path.isfile(p) or os.path.getsize(p) != meta["size"]:
                bad.append(name)
        if not bad:
            fresh_needed = False
        else:
            note("[%s] re-materialising: %d staged file(s) missing or resized"
                 % (label, len(bad)))

    modes = set()
    if fresh_needed:
        if os.path.isdir(dest):
            shutil.rmtree(dest)
        os.makedirs(dest)
        for name in sorted(man["files"]):
            modes.add(link_or_copy(os.path.join(macro, name),
                                   os.path.join(dest, name)))
        # Unlink first: the macro files are staged as hardlinks to an immutable
        # (0444) cache entry, and if a previous stage ever left one at this name
        # copy2 would try to write through it and fail with EACCES.
        bj = os.path.join(dest, ".rom_build.json")
        if os.path.lexists(bj):
            os.unlink(bj)
        shutil.copy2(os.path.join(edir, "build.json"), bj)
        os.chmod(bj, 0o644)

    ent = {"key": key, "cache_entry": os.path.abspath(edir),
           "origin": man.get("origin"), "instname": man.get("instname"),
           "built_at": man.get("built_at"),
           "built_at_epoch": man.get("built_at_epoch"),
           "code_file": man.get("code_file", {}).get("path"),
           "code_sha256": man.get("code_file", {}).get("sha256"),
           "staged_at": iso(time.time()),
           "materialised_by": "+".join(sorted(modes)) if modes else "already-staged",
           "file_count": len(man["files"])}
    pin.setdefault("roms", {})[label] = ent
    pin["pin_format"] = CACHE_FORMAT
    pin["run_romlibs"] = os.path.abspath(run_romlibs)
    with open(pin_path, "w") as f:
        json.dump(pin, f, indent=2, sort_keys=True)
        f.write("\n")
    note("[%s] %s in %s (key %s)"
         % (label, "already staged" if not fresh_needed else "staged " +
            ent["materialised_by"], dest, key))
    return ent


# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------

def add_common(ap):
    ap.add_argument("--rom", required=True,
                    help="ROM identity, e.g. eth_rom / cc_rom")
    ap.add_argument("--label", help="directory name inside the run (default: --rom)")
    ap.add_argument("--spec", required=True)
    ap.add_argument("--code-file", required=True)
    ap.add_argument("--compiler", help="path to the LOCAL-DISK compiler mirror")
    ap.add_argument("--cache-root", required=True)
    ap.add_argument("--generators", default=" ".join(DEFAULT_GENERATORS))
    ap.add_argument("--expect-words", type=int, default=512,
                    help="depth this design's ROMs must be (0 disables)")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    for name in ("key", "build", "stage", "status"):
        s = sub.add_parser(name)
        add_common(s)
        if name in ("build", "stage"):
            s.add_argument("--import-from",
                           help="adopt an already-compiled macro tree instead of "
                                "compiling (for hosts with no compiler)")
        if name == "stage":
            s.add_argument("--run-romlibs", required=True,
                           help="<run>/romlibs -- where the macros are materialised")
            s.add_argument("--repin", action="store_true",
                           help="allow this run's ROM build to change. Almost never right.")
        s.add_argument("--json", help="write the resulting record here")

    a = ap.parse_args(argv)
    label = a.label or a.rom
    gens = a.generators.split()

    # EVERY PATH IS ABSOLUTISED HERE, and this is not tidiness. The compiler is
    # invoked with its working directory INSIDE the macro output directory --
    # that is how it is made to write there -- so a relative --spec or
    # --code-file resolves against the wrong directory and the compiler reports
    # "spec file does not exist" one second into what looks like a real build.
    for attr in ("spec", "code_file", "compiler", "cache_root", "run_romlibs",
                 "import_from"):
        v = getattr(a, attr, None)
        if v:
            setattr(a, attr, os.path.abspath(v))

    if a.cmd in ("build", "stage") and a.import_from:
        ident = {"versions": ["imported"], "wrapper_sha256": "imported",
                 "generators_available": gens}
    else:
        if not a.compiler:
            die("--compiler is required (the local-disk mirror; see "
                "`make -f ASIC/common.mk rom-compiler-stage`)")
        ident = compiler_identity(a.compiler)

    key, canon, spec, code_sha = compute_key(a.rom, a.spec, a.code_file, gens, ident)

    if a.cmd == "key":
        print(key)
        return 0

    edir = entry_dir(a.cache_root, a.rom, key)

    if a.cmd == "status":
        man = load_manifest(edir)
        rec = {"rom": a.rom, "key": key, "entry": edir,
               "hit": bool(man) and entry_is_sound(edir)}
        if man:
            rec["fresh"], rec["why"] = entry_is_fresh(man, a.code_file)
            rec["built_at"] = man.get("built_at")
            rec["origin"] = man.get("origin")
            rec["total_seconds"] = man.get("total_seconds")
        print(json.dumps(rec, indent=2, sort_keys=True))
        if a.json:
            os.makedirs(os.path.dirname(os.path.abspath(a.json)), exist_ok=True)
            with open(a.json, "w") as f:
                json.dump(rec, f, indent=2, sort_keys=True)
        return 0

    # build / stage: ensure the entry exists, is complete, and is provenance-fresh
    hit = entry_is_sound(edir)
    reason = "miss"
    if hit:
        man = load_manifest(edir)
        fresh, why = entry_is_fresh(man, a.code_file)
        if fresh:
            reason = "hit"
            note("[%s] cache HIT %s (built %s in %ss)"
                 % (label, key, man.get("built_at"), man.get("total_seconds")))
        else:
            hit = False
            reason = "stale: " + why
            note("[%s] cache entry %s is not usable -- %s" % (label, key, why))
    if not hit:
        if reason == "miss":
            note("[%s] cache MISS %s" % (label, key))
        if a.import_from:
            import_entry(a.cache_root, a.rom, key, canon, spec, a.spec,
                         a.code_file, code_sha, gens, a.import_from)
        else:
            build_entry(a.cache_root, a.rom, key, canon, spec, a.spec,
                        a.code_file, code_sha, gens, ident, a.compiler,
                        a.expect_words)
        if not entry_is_sound(edir):
            die("[%s] built an entry at %s that does not verify as complete"
                % (label, edir))

    rec = {"rom": a.rom, "label": label, "key": key, "entry": edir,
           "cache": "hit" if reason == "hit" else "miss", "reason": reason}

    if a.cmd == "stage":
        os.makedirs(a.run_romlibs, exist_ok=True)
        repin = a.repin or os.environ.get("ROM_RUN_REPIN") == "1"
        rec["pin"] = stage_into_run(edir, a.run_romlibs, a.rom, label, repin)
        rec["run_dir"] = os.path.join(os.path.abspath(a.run_romlibs), label)

    if a.json:
        os.makedirs(os.path.dirname(os.path.abspath(a.json)), exist_ok=True)
        with open(a.json, "w") as f:
            json.dump(rec, f, indent=2, sort_keys=True)
            f.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
