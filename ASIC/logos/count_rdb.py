#!/usr/bin/env python3
"""Count markers in a KLayout .lyrdb BY CATEGORY.

Do NOT count with a regex on <category>. The RDB nests <name> INSIDE
<category>, so `grep '<category>AP.W.1</category>'` matches nothing and
reports a confident zero. That mis-read cost a full round of wrong advice
on 2026-08-21 -- a logo was declared clean when it had 20 real violations.

Always read CTRL.* first: a control of 0 means the layer was never read,
which is a broken measurement, not a clean result.
"""
import sys, xml.etree.ElementTree as ET
from collections import Counter
c = Counter()
for it in ET.parse(sys.argv[1]).getroot().iter('item'):
    c[it.findtext('category', '?').strip().strip("'")] += 1
if not any(k.startswith('CTRL') for k in c):
    print("WARNING: no CTRL.* category - this deck cannot prove it read anything")
for k in sorted(c):
    print(f"{c[k]:>8}  {k}")
