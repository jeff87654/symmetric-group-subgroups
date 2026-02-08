#!/usr/bin/env python3
"""
Launcher script to generate test_groups_static.g with full invariants.

This script runs the GAP generator to create a test file with:
- Actual permutation generators (not DirectProduct calls)
- Full invariant fields matching combined_s13_s14_original.g format
  (sigKey, histogram, factors, factorOrders, etc.)

Usage:
    python run_generate_test_groups.py

Output:
    Creates test_groups_static_generated.g in the tests directory
    Review and rename to test_groups_static.g when ready
"""

import subprocess
import os
from datetime import datetime

# Configuration
GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPT_PATH = "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/Partition/tests/generate_test_groups_static.g"
OUTPUT_FILE = os.path.join(SCRIPT_DIR, "generate_test_groups_output.txt")

def main():
    print(f"Starting GAP to generate static test groups...")
    print(f"Script: {SCRIPT_PATH}")
    print(f"Log: {OUTPUT_FILE}")
    print()

    cmd = [GAP_BASH, "--login", "-c", f'/opt/gap-4.15.1/gap -q -o 2g "{SCRIPT_PATH}"']

    with open(OUTPUT_FILE, "w") as out:
        out.write(f"# Started at {datetime.now()}\n\n")

        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            cwd=SCRIPT_DIR
        )

        for line in proc.stdout:
            print(line, end='')
            out.write(line)
            out.flush()

        proc.wait()
        out.write(f"\n# Finished at {datetime.now()}\n")
        out.write(f"# Exit code: {proc.returncode}\n")

    print()
    if proc.returncode == 0:
        generated_file = os.path.join(SCRIPT_DIR, "test_groups_static_generated.g")
        if os.path.exists(generated_file):
            size = os.path.getsize(generated_file)
            print(f"SUCCESS: Generated {generated_file}")
            print(f"         File size: {size:,} bytes")
            print()
            print("Next steps:")
            print("  1. Review the generated file")
            print("  2. Rename to test_groups_static.g to replace the original")
        else:
            print("WARNING: GAP exited successfully but output file not found")
    else:
        print(f"ERROR: GAP exited with code {proc.returncode}")
        print(f"       Check {OUTPUT_FILE} for details")

if __name__ == "__main__":
    main()
