#!/usr/bin/env python3
"""Observe the official runner's memory policy without imposing Celesto settings."""
import json
from pathlib import Path

memory = {}
for line in Path('/proc/meminfo').read_text().splitlines():
    key, value = line.split(':', 1)
    if key in ['MemTotal', 'MemAvailable', 'AnonHugePages', 'HugePages_Total', 'HugePages_Free', 'Hugepagesize']:
        memory[key] = value.strip()
values = {}
for key in ['pages_4k', 'pages_2m', 'pages_1g', 'pf_fixed', 'exits']:
    try:
        values[key] = int((Path('/sys/kernel/debug/kvm') / key).read_text())
    except (OSError, ValueError):
        values[key] = None
policy = Path('/sys/kernel/mm/transparent_hugepage/enabled')
print(json.dumps({'platform': 'github-hosted', 'memory': memory, 'kvm': values,
                  'transparent_hugepage_policy': policy.read_text().strip() if policy.exists() else None}))
