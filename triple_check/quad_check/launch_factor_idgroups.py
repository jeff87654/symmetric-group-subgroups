#!/usr/bin/env python3
"""
Phase 1A Launcher: Compute Factor IdGroups

Launches 4 parallel GAP workers to compute factor IdGroups for all DP groups.
Each worker processes a range of indices from s14_large_invariants_clean.g.
"""

import subprocess
import os
import sys
import json
import threading
import time
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
GAP_SCRIPT = "qc_factor_idgroups.g"

INPUT_FILE_WIN = os.path.join(SCRIPT_DIR, "..", "conjugacy_cache", "s14_large_invariants_clean.g")
INPUT_FILE_CYG = "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/triple_check/conjugacy_cache/s14_large_invariants_clean.g"

TOTAL_GROUPS = 10687
NUM_WORKERS = 4
MEMORY = "8g"


def get_cygwin_path(win_path):
    """Convert Windows path to Cygwin path."""
    path = os.path.abspath(win_path)
    drive = path[0].lower()
    rest = path[2:].replace("\\", "/")
    return f"/cygdrive/{drive}{rest}"


def create_worker_script(worker_id, start_idx, end_idx):
    """Create a GAP wrapper script for a worker."""
    output_file_win = os.path.join(SCRIPT_DIR, f"factor_results_{worker_id}.g")
    output_file_cyg = get_cygwin_path(output_file_win)
    gap_script_cyg = get_cygwin_path(os.path.join(SCRIPT_DIR, GAP_SCRIPT))

    wrapper_path = os.path.join(SCRIPT_DIR, f"_worker_1a_{worker_id}.g")
    with open(wrapper_path, "w") as f:
        f.write(f'S14_TC := "S14_TC";;\n')
        f.write(f'WORKER_ID := {worker_id};\n')
        f.write(f'START_INDEX := {start_idx};\n')
        f.write(f'END_INDEX := {end_idx};\n')
        f.write(f'INPUT_FILE := "{INPUT_FILE_CYG}";\n')
        f.write(f'OUTPUT_FILE := "{output_file_cyg}";\n')
        f.write(f'Read("{gap_script_cyg}");\n')

    return wrapper_path, output_file_win


def run_worker(worker_id, start_idx, end_idx):
    """Run a single GAP worker."""
    wrapper_path, output_file = create_worker_script(worker_id, start_idx, end_idx)
    wrapper_cyg = get_cygwin_path(wrapper_path)

    log_file = os.path.join(SCRIPT_DIR, f"log_1a_worker_{worker_id}.txt")

    cmd = [GAP_BASH, "--login", "-c",
           f'/opt/gap-4.15.1/gap -q -o {MEMORY} "{wrapper_cyg}"']

    print(f"[Worker {worker_id}] Starting: indices {start_idx}-{end_idx}")
    print(f"[Worker {worker_id}] Log: {log_file}")

    start_time = time.time()
    with open(log_file, "w") as log:
        log.write(f"# Worker {worker_id} started at {datetime.now()}\n")
        log.write(f"# Indices: {start_idx} to {end_idx}\n\n")
        log.flush()

        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, bufsize=1)
        for line in proc.stdout:
            log.write(line)
            log.flush()
            # Print progress lines
            if "processed" in line.lower() or "complete" in line.lower() or "error" in line.lower():
                print(f"[Worker {worker_id}] {line.rstrip()}")

        proc.wait()
        elapsed = time.time() - start_time
        log.write(f"\n# Finished at {datetime.now()}\n")
        log.write(f"# Exit code: {proc.returncode}\n")
        log.write(f"# Elapsed: {elapsed:.1f}s\n")

    print(f"[Worker {worker_id}] Done in {elapsed:.1f}s (exit code {proc.returncode})")
    return proc.returncode


def main():
    print("=" * 60)
    print("Phase 1A: Compute Factor IdGroups")
    print(f"Workers: {NUM_WORKERS}, Memory: {MEMORY} each")
    print(f"Total groups: {TOTAL_GROUPS}")
    print("=" * 60)
    print()

    # Divide work among workers
    chunk_size = (TOTAL_GROUPS + NUM_WORKERS - 1) // NUM_WORKERS
    ranges = []
    for w in range(NUM_WORKERS):
        start = w * chunk_size + 1
        end = min((w + 1) * chunk_size, TOTAL_GROUPS)
        ranges.append((w + 1, start, end))
        print(f"Worker {w+1}: indices {start} to {end} ({end - start + 1} groups)")

    print()
    start_time = time.time()

    # Launch workers in parallel
    threads = []
    results = {}

    def worker_thread(wid, s, e):
        results[wid] = run_worker(wid, s, e)

    for wid, s, e in ranges:
        t = threading.Thread(target=worker_thread, args=(wid, s, e))
        t.start()
        threads.append(t)

    # Wait for all
    for t in threads:
        t.join()

    elapsed = time.time() - start_time
    print()
    print("=" * 60)
    print(f"All workers complete in {elapsed:.1f}s")
    print()

    # Check results
    all_ok = True
    for wid in sorted(results.keys()):
        status = "OK" if results[wid] == 0 else f"FAILED (exit code {results[wid]})"
        print(f"Worker {wid}: {status}")
        if results[wid] != 0:
            all_ok = False

    if all_ok:
        print("\nAll workers succeeded. Run count_dp_reps.py for Phase 1B.")
    else:
        print("\nSome workers failed! Check log files.")

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
