#!/usr/bin/env python3
# =============================================================================
# tl042_v2_report.py — stratify a TL-042 v2 NO-HARM campaign RUNS.tsv on the
# ANCHOR PAIR and print the NO-HARM verdict.
#
# It is deliberately standalone: re-run it on a finished RUNS.tsv any time to
# regenerate the table without re-touching the rig.
#
#   usage: tl042_v2_report.py RUNS.tsv
#
# STRATIFICATION (plan §2 — the make-or-break variable)
#   * The die_a=YES / die_b=NO anchor pair is expected to deliver 0/N. It is
#     EXCLUDED from the per-arm delivery rate and REPORTED SEPARATELY.
#   * The per-arm NO-HARM comparison is made over the ANCHOR-GOOD population
#     (linkup, anchor pair known, and NOT the YES/NO cell).
#   * Runs whose link never came up, or whose LOCALMEM verify was unreadable,
#     are VOID (excluded from every denominator). Runs whose anchor pair could
#     not be parsed are INDETERMINATE (excluded from the anchor-good rate).
#   * We do NOT stratify on SWI_LANE_STATUS (plan §2: it misleads).
#
# ACCEPTANCE (plan §0): NO-HARM = v2's anchor-good byte-exact delivery rate is
# NOT below baseline's. This is not "does v2 stop the wedge" — no inject is run.
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
# =============================================================================
import sys


def load(path):
    with open(path) as f:
        lines = [l.rstrip("\n") for l in f if l.strip()]
    if not lines:
        return []
    hdr = lines[0].split("\t")
    rows = []
    for l in lines[1:]:
        parts = l.split("\t")
        if len(parts) != len(hdr):
            continue
        rows.append(dict(zip(hdr, parts)))
    return rows


def pair(r):
    return "%s/%s" % (r.get("anchor_a", "?"), r.get("anchor_b", "?"))


def is_void(r):
    return r.get("linkup") != "1" or r.get("delivery_pass") == "VOID"


def is_yes_no(r):
    return r.get("anchor_a") == "YES" and r.get("anchor_b") == "NO"


def is_indeterminate(r):
    return "?" in (r.get("anchor_a"), r.get("anchor_b"))


def delivered(r):
    return r.get("delivery_pass") == "1"


def rate(rows):
    n = len(rows)
    d = sum(1 for r in rows if delivered(r))
    return d, n, (100.0 * d / n if n else float("nan"))


def main():
    if len(sys.argv) != 2:
        print("usage: tl042_v2_report.py RUNS.tsv", file=sys.stderr)
        return 2
    rows = load(sys.argv[1])
    if not rows:
        print("no rows in %s" % sys.argv[1], file=sys.stderr)
        return 2

    arms = sorted({r["arm"] for r in rows})
    N = rows[0].get("delivery_n", "N")

    # 1. raw cross-tab: arm x anchor-pair -> delivered/n --------------------
    print("\n1. CROSS-TAB  (delivered / runs, by arm x anchor pair)")
    pairs = sorted({pair(r) for r in rows if r.get("linkup") == "1"})
    w = max([10] + [len(p) for p in pairs])
    print("   %-9s | %s" % ("arm", " | ".join(p.center(w) for p in pairs)))
    print("   " + "-" * (11 + (w + 3) * len(pairs)))
    for arm in arms:
        cells = []
        for p in pairs:
            sub = [r for r in rows if r["arm"] == arm and r.get("linkup") == "1"
                   and pair(r) == p]
            d, n, _ = rate(sub)
            cells.append(("%d/%d" % (d, n) if n else "-").center(w))
        print("   %-9s | %s" % (arm, " | ".join(cells)))

    # 2. per-arm ANCHOR-GOOD delivery rate (the NO-HARM population) ---------
    print("\n2. ANCHOR-GOOD delivery rate  (linkup, anchor known, NOT die_a=YES/die_b=NO)")
    good_rate = {}
    for arm in arms:
        good = [r for r in rows if r["arm"] == arm and not is_void(r)
                and not is_yes_no(r) and not is_indeterminate(r)]
        d, n, pct = rate(good)
        good_rate[arm] = (d, n, pct)
        print("   %-9s : %2d/%2d byte-exact  (%.1f%%)"
              % (arm, d, n, pct) if n else "   %-9s : no anchor-good runs" % arm)

    # 3. the die_a=YES / die_b=NO cell — reported SEPARATELY ----------------
    print("\n3. die_a=YES / die_b=NO cell  (expected 0/%s — reported separately)" % N)
    any_yn = False
    for arm in arms:
        yn = [r for r in rows if r["arm"] == arm and is_yes_no(r)]
        if not yn:
            continue
        any_yn = True
        d, n, _ = rate(yn)
        flag = "" if d == 0 else "  <-- UNEXPECTED: a YES/NO run DELIVERED"
        print("   %-9s : delivered %d/%d%s" % (arm, d, n, flag))
    if not any_yn:
        print("   (no die_a=YES/die_b=NO runs occurred this campaign)")

    # 4. excluded buckets ---------------------------------------------------
    void = [r for r in rows if is_void(r)]
    indet = [r for r in rows if not is_void(r) and is_indeterminate(r)]
    print("\n4. EXCLUDED")
    print("   void (no link-up / unreadable verify) : %d" % len(void))
    for r in void:
        print("      run %s arm=%s linkup=%s delivery_pass=%s"
              % (r.get("run"), r.get("arm"), r.get("linkup"), r.get("delivery_pass")))
    print("   indeterminate anchor pair             : %d" % len(indet))
    for r in indet:
        print("      run %s arm=%s pair=%s" % (r.get("run"), r.get("arm"), pair(r)))

    # 5. NO-HARM verdict ----------------------------------------------------
    print("\n5. NO-HARM VERDICT  (v2 must NOT deliver below baseline on anchor-good)")
    b = good_rate.get("baseline")
    v = good_rate.get("v2")
    if not b or not v or b[1] == 0 or v[1] == 0:
        print("   INSUFFICIENT DATA: need anchor-good runs in BOTH arms "
              "(baseline n=%s, v2 n=%s)."
              % (b[1] if b else 0, v[1] if v else 0))
        print("   (Small-n caveat: plan §1 wants n>=6/arm; a thin anchor-good")
        print("    population after exclusions means re-run, do not conclude.)")
        return 0
    print("   baseline anchor-good : %d/%d (%.1f%%)" % b)
    print("   v2       anchor-good : %d/%d (%.1f%%)" % v)
    delta = v[2] - b[2]
    if v[2] + 1e-9 >= b[2]:
        print("   => NO HARM: v2 delivery rate is not below baseline (delta %+.1f pts)." % delta)
    else:
        print("   => POSSIBLE REGRESSION: v2 %.1f%% < baseline %.1f%% (delta %+.1f pts)."
              % (v[2], b[2], delta))
        print("      Investigate before accepting v2. Confirm n is adequate and that")
        print("      the failures are not the anchor lottery leaking past the stratifier.")
    print("\n   NOTE: this is NO-HARM only. v2 still wedges on an errinject by design")
    print("   (second XHB500-internal hold beneath wr_hold_r); that is NOT measured here.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
