#!/usr/bin/env python3
"""Run verification of static test groups."""

import subprocess
from datetime import datetime

GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
SCRIPT = "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/Partition/tests/verify_static_groups.g"

print(f"Verifying test_groups_static.g...")
print()

cmd = [GAP_BASH, "--login", "-c", f'/opt/gap-4.15.1/gap -q -o 2g "{SCRIPT}"']

proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
for line in proc.stdout:
    print(line, end='')
proc.wait()

print()
print(f"Exit code: {proc.returncode}")
