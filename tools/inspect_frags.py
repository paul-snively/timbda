#!/usr/bin/env python3
import re

src = open('dialect/TimbdaRules.td').read()
segs = src.split(';let ')
print('segments:', len(segs))
for i, s in enumerate(segs):
    ctor = re.search(r'ctor = "([^"]*)"', s)
    tag = re.search(r'kernelTag = "([^"]*)"', s)
    semn = re.search(r'semName = "([^"]*)"', s)
    cpp = re.search(r'cppDecl = "([^"]*)"', s)
    fields = sorted(set(re.findall(r'([A-Za-z_][A-Za-z_0-9]*)\s*=', s)))
    print(i,
          'ctor=' + (ctor.group(1) if ctor else '-'),
          'tag=' + (tag.group(1) if tag else '-'),
          'sem=' + (semn.group(1) if semn else '-'),
          'cpp=' + (cpp.group(1)[:40] if cpp else '-'),
          'nfields=' + str(len(fields)))
