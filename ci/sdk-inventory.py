#!/usr/bin/env python3
"""Read package metadata without walking the runner's large NDK/sysroot trees."""
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve(strict=True)
paths = set()
for pattern in ['*/source.properties', '*/*/source.properties', 'system-images/*/*/*/source.properties']:
    paths.update(root.glob(pattern))
for path in sorted(paths):
    print('# ' + str(path.relative_to(root)))
    print(path.read_text())
