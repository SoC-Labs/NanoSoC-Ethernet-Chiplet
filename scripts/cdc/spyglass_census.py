#!/usr/bin/env python3
"""Parse a SpyGlass moresimple.rpt into a rule x severity census, split by
provenance (authored / generated / vendor).

Usage: census.py <moresimple.rpt> [--csv out.csv] [--quiet]

Assert-on-artefact: prints a PARSE MISMATCH banner (and exits 2) if the number
of rows parsed does not equal the header's own "Number of Reported Messages".
A census that silently drops rows is the failure mode this guard exists for.
"""
import os, re, sys, collections, subprocess

SEVS = {'Fatal', 'Error', 'Warning', 'Info', 'SynthesisWarning',
        'SyntaxError', 'Notice'}


def _repo_root():
    """Repository root, discovered — never hardcoded. This repository is
    public and the pre-commit vendor gate rejects absolute site paths."""
    r = os.environ.get('CHIPLET_HOME') or os.environ.get('CHIPLET')
    if not r:
        try:
            r = subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                               capture_output=True, text=True,
                               cwd=os.path.dirname(os.path.abspath(__file__))
                               ).stdout.strip()
        except Exception:
            r = ''
    return (r.rstrip('/') + '/') if r else ''


ROOT = _repo_root()
# Shared, lab-wide, read-only vendor IP tree (OpenCores EthMAC and friends).
# Its mount point is site configuration, so it is taken from the environment
# rather than written down here.
VENDOR_ROOT = (os.environ.get('LAB_IP_LIBRARY_ROOT')
               or os.environ.get('ARM_IP_LIBRARY_PATH') or '')


def provenance(path):
    if path in ('N.A.', 'N/A', ''):
        return 'no-file'
    if not ROOT or not path.startswith(ROOT):
        # Outside the repository: either the lab IP tree, or an unknown mount.
        # Both are third-party as far as this census is concerned.
        return 'vendor' if path.startswith('/') else 'no-file'
    p = path[len(ROOT):]
    if p.startswith('build/') or '/build_soc/' in p or p.startswith('build_soc/') \
       or '/nanosoc_gen/' in p:
        return 'generated'
    # Third-party / foundry-facing collateral, matched by DIRECTORY ROLE rather
    # than by process name — this repository is public and the pre-commit vendor
    # gate rejects revision-coded foundry names in tracked content.
    vendor_marks = ('/deps/', 'nanosoc_arch_tech/', 'coresight_soc400/',
                    '/logical/', '/cache_models/', 'asic_lib/',
                    'tech_wrappers/', '/ethmac_patches/', '/opencores')
    if any(m in p for m in vendor_marks):
        return 'vendor'
    return 'authored'


def owner(path):
    if not ROOT or not path.startswith(ROOT):
        return 'lab-vendor-ip (path redacted)' if path.startswith('/') else 'n-a'
    p = path[len(ROOT):]
    for pre in ('nanosoc-multicore-system/ethernet-subsystem-ahb/ethernet-mac-ahb',
                'nanosoc-multicore-system/ethernet-subsystem-ahb',
                'nanosoc-multicore-system', 'tidelink/deps', 'tidelink',
                'tidechart', 'build', 'src'):
        if p.startswith(pre):
            return pre
    return p.split('/')[0]


def parse(rpt):
    txt = open(rpt, errors='replace').read()
    def hdr(k):
        m = re.search(k + r'\s*:\s*(\d+)', txt)
        return int(m.group(1)) if m else -1
    meta = dict(total=hdr('Total Number of Generated Messages'),
                waived=hdr('Number of Waived Messages'),
                reported=hdr('Number of Reported Messages'),
                overlimit=hdr('Number of Overlimit Messages'))
    rows, bad = [], []
    for line in txt.splitlines():
        if not line.startswith('['):
            continue
        f = re.split(r'\s{2,}', line.strip())
        if len(f) < 6:
            bad.append(line)
            continue
        # locate the severity column (index 2 = no alias, 3 = alias present)
        si = None
        for i in (2, 3):
            if i < len(f) and f[i] in SEVS:
                si = i
                break
        if si is None:
            bad.append(line)
            continue
        try:
            path, ln, wt = f[si + 1], int(f[si + 2]), int(f[si + 3])
        except (IndexError, ValueError):
            bad.append(line)
            continue
        rows.append(dict(id=f[0].strip('[]'), rule=f[1],
                         alias=(f[2] if si == 3 else ''), sev=f[si],
                         file=path, line=ln, wt=wt,
                         msg='  '.join(f[si + 4:]),
                         prov=provenance(path), owner=owner(path)))
    return meta, rows, bad


def main():
    rpt = sys.argv[1]
    meta, rows, bad = parse(rpt)
    print(f'report      : {rpt}')
    print("header      : generated={total} waived={waived} reported={reported} "
          "overlimit={overlimit}".format(**meta))
    print(f'parsed rows : {len(rows)}   unparsed: {len(bad)}')
    ok = (meta['reported'] < 0) or (len(rows) == meta['reported'])
    if not ok:
        print(f"*** PARSE MISMATCH: parsed {len(rows)} != reported "
              f"{meta['reported']} — census NOT trustworthy ***")
        for b in bad[:10]:
            print('   unparsed:', b[:200])
    else:
        print('parse check : OK (rows == header reported count)')

    if '--quiet' not in sys.argv:
        print('\n== by severity ==')
        for s, n in collections.Counter(r['sev'] for r in rows).most_common():
            print(f'  {n:6d}  {s}')

        print('\n== by provenance ==')
        for s, n in collections.Counter(r['prov'] for r in rows).most_common():
            print(f'  {n:6d}  {s}')

        print('\n== by rule x severity, split authored/generated/vendor ==')
        pc = collections.defaultdict(collections.Counter)
        sv = {}
        for r in rows:
            pc[r['rule']][r['prov']] += 1
            sv.setdefault(r['rule'], collections.Counter())[r['sev']] += 1
        hdr = (f"{'rule':26s} {'severity':17s} {'n':>5s}  "
               f"{'auth':>5s} {'gen':>4s} {'vend':>5s} {'n/a':>4s}")
        print(hdr); print('-' * len(hdr))
        tot = collections.Counter()
        for rule in sorted(pc, key=lambda k: -sum(pc[k].values())):
            n = sum(pc[rule].values())
            sevs = '+'.join(sorted(sv[rule]))
            c = pc[rule]
            tot.update(c)
            print(f"{rule:26s} {sevs:17s} {n:5d}  {c['authored']:5d} "
                  f"{c['generated']:4d} {c['vendor']:5d} {c['no-file']:4d}")
        print('-' * len(hdr))
        print(f"{'TOTAL':26s} {'':17s} {len(rows):5d}  {tot['authored']:5d} "
              f"{tot['generated']:4d} {tot['vendor']:5d} {tot['no-file']:4d}")

        print('\n== unsynchronised crossings (Ac_unsync01/02, Ar_unsync01) by owner ==')
        u = [r for r in rows if r['rule'] in ('Ac_unsync01', 'Ac_unsync02', 'Ar_unsync01')]
        print(f'  total crossings reported: {len(u)}')
        for k, n in collections.Counter(r['owner'] for r in u).most_common():
            print(f'  {n:6d}  {k}')

    if '--csv' in sys.argv:
        import csv
        out = sys.argv[sys.argv.index('--csv') + 1]
        with open(out, 'w', newline='') as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
            w.writeheader(); w.writerows(rows)
        print(f'\ncsv -> {out}')
    sys.exit(0 if ok else 2)


if __name__ == '__main__':
    main()
