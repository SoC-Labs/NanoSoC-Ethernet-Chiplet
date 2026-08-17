"""Ownership zoning for the full-chiplet lint.

Three tiers, because "who can fix this?" is the only question that decides
whether a lint finding is actionable:

  ARM_IP       Arm-licensed IP. Read-only lab tree or vendor-generated copies
               inside the submodules. Black-boxed: we neither may nor should
               edit it, and its findings are not evidence about this design.
  THIRD_PARTY  OpenCores / Wlink / vendor-generated RTL that IS compiled into
               the chip but is not authored here. Analysed and reported, never
               gated -- a finding is an upstream escalation, not a build break.
  AUTHORED     SoC Labs RTL. The gate applies here.

SYMLINKS ARE PART OF THE PROBLEM, NOT AN EDGE CASE
  Tiering is a path-prefix test, and a prefix test is only as good as the
  spelling of the path it is handed. Verilator canonicalises symlinks before it
  names a file in a message, and this repo's own resolved filelists carry
  canonicalised paths too, so a vendor file routinely arrives spelled as
  something that carries none of the prefixes below. It then tiers AUTHORED, is
  never black-boxed, is linted verbatim, and reddens the gate as if it were our
  RTL.

  The case this was built for: {REPO}/tidelink/deps/xhb500/generated was a
  symlink to a SECOND tidelink checkout (${TIDELINK_STANDALONE}, a
  different commit), so 28 Arm XHB500 sources arrived spelled as
  ${TIDELINK_STANDALONE}/deps/xhb500/... .

  As of 2026-08-17 18:44 that path is a REAL directory again (2626 files,
  identical content), so the scan below finds nothing to add and tiering is
  decided by the literal prefix. Keep it anyway: the symlink is still the
  TRACKED entry (mode 120000) at the submodule's HEAD and at the commit the
  parent pins -- the real directory is .gitignore'd content over a
  tracked-deleted link, one `git checkout` from reverting. Verified still
  functional against a sandbox tree carrying the link (arm-ip with the scan,
  authored without), and verified inert on the tree as it stands (tiering of
  every path in a full lint run is identical with the scan on and off).

  Note carefully why os.path.realpath on BOTH sides does not fix this. The
  symlink sits BELOW the prefix directory: realpath({REPO}/tidelink/deps/xhb500/)
  is itself, unchanged, while a file under it canonicalises into a different
  checkout entirely. The two never meet. The reachable set of a prefix is the
  prefix PLUS the canonical target of every symlink inside it that escapes it --
  so that is what _reachable_roots() computes, and it is applied to every prefix
  rather than special-casing the one that happens to be broken today.

  WHERE THE SCAN IS PAID. The in-repo prefixes sit on local disk and cost about
  10 ms to scan, so they are expanded at import -- which also keeps the exported
  ARM_IP list correct for consumers that iterate it (verilator_lint.py writes one
  `lint_off -file` glob per entry). The /research lab tree is NFS and costs 6 s
  warm and ~2 min cold, which is more than the lint it guards; it is therefore
  scanned only if some path matches no prefix at all -- the one situation where
  the answer is otherwise wrong. That split is not just cost: the lab tree is
  read-only vendor collateral whose layout changes only on a vendor drop, while
  the in-repo trees are the ones this project's own submodule wiring re-points,
  which is exactly how this broke.
"""

import os
import functools

# verif/lint/full/zones.py -> the repo root, four levels up.
REPO = os.environ.get(
    "NANOSOC_ETH_CHIPLET_HOME",
    os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))))))

# ── The read-only Arm IP tree, NAMED ONCE AND NOT SPELLED ──────────────────
# This repository is PUBLIC, and an absolute path to this site's IP mount is
# site-layout disclosure. set_env.sh exports ARM_IP_LIBRARY_PATH (and ASIC/
# common.mk exports the same value); verif/lint/full/run.sh sources set_env.sh
# before importing this module, so it is set in every real run.
#
# UNSET IS FATAL, NOT DEFAULTED. Tiering is a path-prefix test: with the wrong
# root, every Arm source stops matching, tiers AUTHORED, is linted verbatim and
# reddens the gate as if it were our RTL. That is precisely the "SILENT SCOPE
# COLLAPSE" verif/lint/run.sh:38 already warns about, and a quietly wrong tier
# map is worse than no run. So this raises instead of falling back to a literal.
_ARM_IP_ROOT = os.environ.get("ARM_IP_LIBRARY_PATH", "").rstrip("/")
if not _ARM_IP_ROOT:
    raise RuntimeError(
        "ARM_IP_LIBRARY_PATH is not set, so the Arm-IP tier prefixes cannot be\n"
        "built. Source set_env.sh (verif/lint/full/run.sh does this for you) or\n"
        "export ARM_IP_LIBRARY_PATH yourself.\n"
        "This is deliberately fatal rather than defaulted: with the wrong root\n"
        "every Arm source tiers AUTHORED and the gate reddens on vendor RTL --\n"
        "the silent scope collapse verif/lint/run.sh:38 describes.")


def _arm_ip(*parts):
    """A prefix under the read-only Arm IP tree. Product names are public; the
    mount point is not, so only the leaf names appear in this file."""
    return "/".join((_ARM_IP_ROOT,) + parts) + "/"


# Set to 1 to tier on literal prefixes only. An escape hatch for a dead NFS
# mount, not a normal mode -- the gate is wrong without the scan wherever a
# source tree is reached through a link.
_NO_SCAN = os.environ.get("LINT_ZONES_NO_SYMLINK_SCAN") == "1"

# A canonical root shallower than this many components is refused: a stray link
# to / or /home would otherwise swallow the whole design into a vendor tier.
_MIN_ROOT_DEPTH = 3


def _norm(p):
    return p.rstrip(os.sep) + os.sep


def _under_repo(prefix):
    """Cheap to scan: local disk, and re-pointed by our own checkout wiring."""
    return prefix.startswith(_norm(REPO))


@functools.lru_cache(maxsize=None)
def _reachable_roots(prefix, deep):
    """Every canonical directory prefix under which a file inside `prefix` can
    legitimately be reported.

    Always: `prefix` itself and its own realpath (the prefix may be reached
    through a link). With deep=True, additionally the realpath of every symlink
    inside it whose target escapes it.

    Symlinks are NOT followed while walking, so a self-referential link -- xhb500
    has one, generated/generated -> generated -- cannot loop us.

    Broken links count. A dangling vendor link (Corstone-101 has two) costs
    nothing to cover now and silently mis-tiers the day its target appears.
    """
    roots = {_norm(prefix), _norm(os.path.realpath(prefix))}
    if not deep or _NO_SCAN or not os.path.isdir(prefix):
        return frozenset(roots)
    base = _norm(os.path.realpath(prefix))
    try:
        for parent, dirs, files in os.walk(prefix, followlinks=False):
            # A symlink to a directory lands in `dirs`; a BROKEN one is not a
            # directory to os.walk and lands in `files`. Both matter, so check
            # every entry rather than only `dirs`.
            for name in dirs + files:
                link = os.path.join(parent, name)
                if not os.path.islink(link):
                    continue
                target = _norm(os.path.realpath(link))
                if target.startswith(base):
                    continue                  # stays inside; already covered
                if target.strip(os.sep).count(os.sep) + 1 < _MIN_ROOT_DEPTH:
                    continue                  # implausibly shallow; refuse it
                roots.add(target)
    except OSError:
        pass                                  # unreadable tree: literal only
    return frozenset(roots)


def _expand(prefixes, deep):
    """Prefix list -> the same list plus every canonical root it can be reached
    through. `deep` forces the walk even for the expensive NFS prefixes."""
    out = []
    for p in prefixes:
        for r in sorted(_reachable_roots(p, deep or _under_repo(p))):
            if r not in out:
                out.append(r)
    return out


_ARM_IP = [
    # Read-only shared lab tree
    _arm_ip("BP210"),
    _arm_ip("Corstone-101"),
    _arm_ip("CG092"),                               # flash cache
    _arm_ip("Cortex-M0-plus"),
    _arm_ip("PL022"),                               # SSP
    _arm_ip("SoC-400"),                             # CoreSight DAP
    # Arm IP that lives INSIDE the submodules, vendor-generated
    f"{REPO}/tidelink/deps/xhb500/",                       # XHB500 AHB bridge
    f"{REPO}/nanosoc-multicore-system/build_soc/rtl/dma250/rendered_CFG_MIN/",
]

_THIRD_PARTY = [
    _arm_ip("OpenCores-EthMAC"),
    _arm_ip("OpenCores-HA1588"),
    f"{REPO}/nanosoc-multicore-system/ethernet-subsystem-ahb/ethernet-mac-ahb/src/rtl/ethmac_patches/",
    f"{REPO}/nanosoc-multicore-system/ethernet-subsystem-ahb/ethernet-mac-ahb/src/rtl/ha1588_patches/",
    f"{REPO}/tidelink/deps/axi-chiplet-controller/",       # Wlink, Bluespec-generated
    f"{REPO}/tidelink/deps/tidelink-phy/",
    f"{REPO}/tidelink/src/rtl/local_overrides/",           # vendor copies + local fixes
]

# Exported already-expanded over the cheap (in-repo) prefixes, so that a consumer
# iterating these lists sees the symlinked spellings too.
ARM_IP = _expand(_ARM_IP, deep=False)
THIRD_PARTY = _expand(_THIRD_PARTY, deep=False)

# Finer labels inside AUTHORED, for a report that says WHERE, not just "ours".
# Order is precedence: build_soc before its parent, tidelink before soc.
AUTHORED_ZONES = [
    ("integration",  f"{REPO}/src/rtl/"),
    ("chip-wrapper", f"{REPO}/build/chip/rtl/"),
    ("tidechart",    f"{REPO}/tidechart/"),
    ("tidelink",     f"{REPO}/tidelink/"),
    ("soc-generated", f"{REPO}/nanosoc-multicore-system/build_soc/"),
    ("soc",          f"{REPO}/nanosoc-multicore-system/"),
]

_deep_cache = None


def _deep_prefixes():
    """The fully-scanned prefix sets, built at most once per process and only
    when some path matched nothing -- see the module docstring on where the scan
    is paid."""
    global _deep_cache
    if _deep_cache is None:
        _deep_cache = (
            _expand(_ARM_IP, deep=True),
            _expand(_THIRD_PARTY, deep=True),
            [(label, _expand([pref], deep=True)) for label, pref in AUTHORED_ZONES],
        )
    return _deep_cache


@functools.lru_cache(maxsize=None)
def _spellings(path):
    """The path as given, and its canonical form. Prefix tests run against both:
    the caller may hand us either, and they are not interchangeable."""
    real = os.path.realpath(path)
    return (path,) if real == path else (path, real)


def _matches(prefixes, path):
    return any(p in s for p in prefixes for s in _spellings(path))


def _authored_label(zones, path):
    for label, pref in zones:
        if isinstance(pref, str):
            if any(pref in s for s in _spellings(path)):
                return label
        elif _matches(pref, path):
            return label
    return None


def tier(path):
    # Generated black boxes (build/lint/full/**/armbb|bbox) stand in for the IP
    # they replace, so a finding against one is a finding against that IP.
    if "/armbb/" in path or "/bbox/" in path:
        return "arm-ip"
    if _matches(ARM_IP, path):
        return "arm-ip"
    if _matches(THIRD_PARTY, path):
        return "third-party"
    # Recognised as one of ours: cheap exit, no scan.
    if _authored_label(AUTHORED_ZONES, path):
        return "authored"
    # Matched nothing at all. Before calling it authored -- which is what the
    # ratchet gates on -- pay for the deep scan once and ask whether it is vendor
    # IP reached through a link.
    arm, third, _ = _deep_prefixes()
    if _matches(arm, path):
        return "arm-ip"
    if _matches(third, path):
        return "third-party"
    return "authored"


def zone(path):
    t = tier(path)
    if t != "authored":
        return t
    label = _authored_label(AUTHORED_ZONES, path)
    if label:
        return label
    # Unrecognised authored path: the deep sets are already built by tier().
    return _authored_label(_deep_prefixes()[2], path) or "other"
