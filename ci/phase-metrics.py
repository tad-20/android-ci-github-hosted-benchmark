#!/usr/bin/env python3
"""Record one command phase. Callers supply GNU timeout for bounded execution."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import resource
import subprocess
import sys
import time

p=argparse.ArgumentParser()
p.add_argument('--output',type=Path,required=True)
p.add_argument('phase')
p.add_argument('command',nargs=argparse.REMAINDER)
a=p.parse_args()
command=a.command[1:] if a.command[:1]==['--'] else a.command
if not command:
    p.error('command required')
a.output.parent.mkdir(parents=True,exist_ok=True)
start=datetime.now(timezone.utc);clock=time.monotonic()
identity=f'{a.phase}:{time.monotonic_ns()}'
def emit(event):
    with a.output.open('a') as f:
        f.write(json.dumps(event,separators=(',',':'))+'\n')
emit({'phase':a.phase,'id':identity,'event':'start','timestamp':start.isoformat(),'executable':Path(command[0]).name})
try:
    rc=subprocess.run(command).returncode
except OSError as exc:
    rc=127
    print(str(exc),file=sys.stderr)
usage=resource.getrusage(resource.RUSAGE_CHILDREN)
emit({'phase':a.phase,'id':identity,'event':'end','started_at':start.isoformat(),
      'timestamp':datetime.now(timezone.utc).isoformat(),'wall_seconds':time.monotonic()-clock,
      'exit_code':rc,'timeout_or_forced_exit':rc in (124,137),
      'child_user_cpu_seconds':usage.ru_utime,'child_system_cpu_seconds':usage.ru_stime,
      'largest_child_peak_rss_bytes':usage.ru_maxrss*1024,
      'child_block_inputs':usage.ru_inblock,'child_block_outputs':usage.ru_oublock,
      'rss_scope':'largest waited child process; not aggregate job memory peak'})
sys.exit(rc if rc>=0 else 128-rc)
