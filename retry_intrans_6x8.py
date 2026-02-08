#!/usr/bin/env python3
"""Retry intrans_6x8 worker with 32GB memory and memory-optimized save phase."""

import subprocess
import sys
from datetime import datetime
from pathlib import Path

GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
BASE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups")
OUTPUT_DIR = BASE_DIR / "maxsub_output"

def main():
    script_path = "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/maxsub_output/retry_intrans_6x8.g"
    log_file = OUTPUT_DIR / "worker_intrans_6x8_retry.log"

    # Delete old truncated output file
    old_output = OUTPUT_DIR / "intrans_6x8.g"
    if old_output.exists():
        old_output.rename(OUTPUT_DIR / "intrans_6x8_old.g")
        print(f"Renamed old output to intrans_6x8_old.g")

    cmd = f'/opt/gap-4.15.1/gap -q -o 32g "{script_path}"'

    print("=" * 60)
    print("Retrying intrans_6x8 (S6 x S8) with 32GB memory")
    print("=" * 60)
    print(f"Started: {datetime.now()}")
    print(f"Command: {cmd}")
    print(f"Log: {log_file}")
    print()

    with open(log_file, 'w') as log:
        log.write(f"# Worker: intrans_6x8 (retry)\n")
        log.write(f"# Started: {datetime.now()}\n")
        log.write(f"# Memory: 32g\n")
        log.write(f"# Command: {cmd}\n\n")
        log.flush()

        proc = subprocess.Popen(
            [GAP_BASH, '--login', '-c', cmd],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

        for line in proc.stdout:
            print(line, end='')
            sys.stdout.flush()
            log.write(line)
            log.flush()

        proc.wait()

        elapsed_msg = f"\n# Finished: {datetime.now()}\n# Exit code: {proc.returncode}\n"
        log.write(elapsed_msg)
        print(elapsed_msg)

    # Verify output
    output_file = OUTPUT_DIR / "intrans_6x8.g"
    if output_file.exists():
        with open(output_file, 'r') as f:
            content = f.read()
            if "# Complete:" in content:
                print("\nSUCCESS: intrans_6x8 completed successfully!")
                return 0
            else:
                print("\nWARNING: Output file exists but no completion marker found")
                return 1
    else:
        print("\nFAILED: No output file created")
        return 2

if __name__ == "__main__":
    sys.exit(main())
