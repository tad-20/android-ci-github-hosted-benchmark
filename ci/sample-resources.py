#!/usr/bin/env python3
"""Bounded read-only guest resource samples; no process arguments or credentials."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import sys
import time

directory = Path(sys.argv[1]).resolve(strict=True)
output = directory / 'guest-resources.jsonl'
deadline = time.monotonic() + 1790
with output.open('x', buffering=1) as writer:
    while time.monotonic() < deadline and not (directory / 'sampling.stop').exists():
        if output.stat().st_size > 4 * 1024**2:
            break
        memory = {}
        for line in Path('/proc/meminfo').read_text().splitlines():
            key, value = line.split(':', 1)
            if key in ['MemTotal', 'MemAvailable', 'Cached', 'SwapTotal', 'SwapFree',
                       'AnonPages', 'PageTables', 'HugePages_Total', 'HugePages_Free', 'Hugetlb']:
                memory[key] = value.strip()
        vmstat = {}
        for line in Path('/proc/vmstat').read_text().splitlines():
            key, value = line.split()
            if key in ['pswpin', 'pswpout', 'pgmajfault', 'oom_kill']:
                vmstat[key] = int(value)
        kvm = {}
        for key in ['pages_4k', 'pages_2m', 'pages_1g', 'pf_fixed', 'exits']:
            path = Path('/sys/kernel/debug/kvm') / key
            try:
                kvm[key] = int(path.read_text())
            except (OSError, ValueError):
                kvm[key] = None
        pressure = {}
        for key in ['cpu', 'memory', 'io']:
            path = Path('/proc/pressure') / key
            pressure[key] = path.read_text() if path.exists() else None
        usage = shutil.disk_usage(directory)
        cpu_ticks = list(map(int, Path('/proc/stat').read_text().splitlines()[0].split()[1:]))
        writer.write(json.dumps({'timestamp': datetime.now(timezone.utc).isoformat(),
                                'memory': memory, 'vmstat': vmstat, 'kvm': kvm,
                                'vm_cpu_ticks': cpu_ticks, 'clock_ticks_per_second': os.sysconf('SC_CLK_TCK'),
                                'logical_cpus': os.cpu_count(), 'cpu_scope': 'whole GitHub runner VM, including platform services',
                                'pressure': pressure, 'filesystem_free_bytes': usage.free}) + '\n')
        time.sleep(5)
