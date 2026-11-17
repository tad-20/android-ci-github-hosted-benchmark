#!/usr/bin/env python3
"""Reject absent, partial, skipped, failed, stale, or duplicate instrumentation results."""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

p = argparse.ArgumentParser()
p.add_argument('workload', choices=['espresso', 'todo'])
p.add_argument('results', type=Path)
p.add_argument('--expectations', type=Path, default=Path(__file__).with_name('expectations.json'))
a = p.parse_args()
expected = {tuple(x) for x in json.loads(a.expectations.read_text())[a.workload]}
actual = set()
files = list(a.results.rglob('TEST-*.xml'))
if not files:
    raise SystemExit('FAIL: no instrumentation XML results')
for f in files:
    root = ET.parse(f).getroot()
    for suite in root.iter('testsuite'):
        for attr in ('failures', 'errors', 'skipped', 'disabled'):
            if float(suite.get(attr, '0')) != 0:
                raise SystemExit(f'FAIL: {f.name} has {attr}')
    for case in root.iter('testcase'):
        key = (case.get('classname', ''), case.get('name', ''))
        if any(case.find(tag) is not None for tag in ('failure', 'error', 'skipped')):
            raise SystemExit(f'FAIL: unsuccessful test {key}')
        if key in actual:
            raise SystemExit(f'FAIL: duplicate test {key}')
        actual.add(key)
if actual != expected:
    raise SystemExit(f'FAIL: missing={sorted(expected-actual)} unexpected={sorted(actual-expected)}')
print(json.dumps({'instrumentation_results': 'pass', 'tests': len(actual), 'xml_files': len(files)}))
