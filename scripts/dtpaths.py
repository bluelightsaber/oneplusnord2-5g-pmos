#!/usr/bin/env python3
# List node paths (with status/compatible) of a decompiled .dts. Usage: dtpaths.py file.dts
import re, sys
stack, out, cur = [], {}, None
for line in open(sys.argv[1]):
    s = line.strip()
    m = re.match(r'^(?:[\w-]+:\s*)?([\w@,.+-]+|/)\s*\{$', s)
    if m:
        stack.append(m.group(1)); cur = '/' + '/'.join(x for x in stack if x != '/'); out[cur] = {}; continue
    if s.startswith('};'):
        stack.pop(); cur = '/' + '/'.join(x for x in stack if x != '/') if stack else None; continue
    m = re.match(r'^(status|compatible) = (.*);$', s)
    if m and cur: out[cur][m.group(1)] = m.group(2)[:80]
for p in sorted(out):
    d = out[p]; print(p, '|', d.get('compatible', ''), '|', d.get('status', ''))
