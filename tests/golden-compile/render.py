#!/usr/bin/env python3
"""Decode the `Compute golden_lines.` display (coq/tests/GoldenCompile.v) into C source.

Display format measured on Rocq 9.1.1: a list displays as `[ "e1"; "e2"; ... ]`;
entry quotes double INSIDE an entry (`""`); backslashes in Coq strings are
literal and display literal (no escaping round-trip to undo).  A display
truncated by the pretty-printer shows a `..` marker — treated as a hard error,
same vacuity rule as every other lane (DESIGN-NOTES sec. 8.3).
"""
import sys

text = sys.stdin.read()
# The Compute display line starts `= [` — anchoring there keeps warning noise
# (whose bracketed tags like [deprecated-...] would otherwise look like lists)
# out of the parser.
anchor = text.find('= [')
if anchor < 0:
    sys.stderr.write("FAIL: no `= [` Compute display found in rocq output\n")
    sys.exit(1)
start = text.find('[', anchor)
if start < 0:
    sys.stderr.write("FAIL: no list display found in rocq output\n")
    sys.exit(1)
if ']' not in text[start:]:
    sys.stderr.write("FAIL: list display unterminated (truncated?)\n")
    sys.exit(1)

n = len(text)
i = start + 1
entries = []
closed = False
while i < n:
    c = text[i]
    if c == ']':
        closed = True
        break
    if c == '"':
        buf = []
        i += 1
        while i < n:
            c = text[i]
            if c == '"':
                if i + 1 < n and text[i + 1] == '"':
                    buf.append('"')
                    i += 2
                    continue
                i += 1  # entry closed by delimiter context
                break
            buf.append(c)
            i += 1
        entries.append(''.join(buf))
    elif c in ' \t\n;,':
        i += 1
    else:
        sys.stderr.write("FAIL: unexpected char %r outside entries\n" % c)
        sys.exit(1)

if not closed:
    sys.stderr.write("FAIL: unterminated list display\n")
    sys.exit(1)
if any(e.strip() == '..' for e in entries):
    sys.stderr.write("FAIL: '..' truncation marker inside the display\n")
    sys.exit(1)
# shape gates (vacuity defense): recognizable harness ends
if len(entries) < 40:
    sys.stderr.write("FAIL: golden_lines has only %d entries\n" % len(entries))
    sys.exit(1)
if entries[0] != '#include <stdio.h>' or entries[-1] != '}':
    sys.stderr.write("FAIL: golden_lines does not start/end with the harness shape\n")
    sys.exit(1)

sys.stdout.write('\n'.join(entries) + '\n')
