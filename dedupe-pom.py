#!/usr/bin/env python3
"""Remove duplicate <dependency> entries from pom.xml, keeping the LAST one
(the declaration Maven 3.9 actually uses). Usage: python3 dedupe-pom.py pom.xml"""
import re, sys

path = sys.argv[1]
text = open(path, encoding='utf-8').read()
# each dependency block together with the indentation and line break before it
blocks = list(re.finditer(r'\n[ \t]*<dependency>.*?</dependency>', text, re.S))

def key(block):
    tag = lambda t, d='': (re.search(rf'<{t}>\s*(.*?)\s*</{t}>', block) or [None, d])[1]
    return (tag('groupId'), tag('artifactId'), tag('type', 'jar'), tag('classifier'))

last = {}
for m in blocks:
    last[key(m.group())] = m.start()
removed = [m for m in blocks if last[key(m.group())] != m.start()]
for m in reversed(removed):
    text = text[:m.start()] + text[m.end():]
open(path, 'w', encoding='utf-8').write(text)
for m in removed:
    k = key(m.group())
    v = re.search(r'<version>(.*?)</version>', m.group())
    print(f"removed {k[0]}:{k[1]} {v[1] if v else ''}")
