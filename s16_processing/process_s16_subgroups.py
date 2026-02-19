#!/usr/bin/env python3
"""
Launch parallel GAP workers to process S16 subgroups.
Each worker processes indices [worker_id, worker_id+num_workers, ...]

Pre-flight: verifies s16_subgroups.g, s15_iso_map.g, and process_s16_subgroups.g exist.
"""

import subprocess
import sys
import os
from datetime import datetime
from pathlib import Path
import threading
import time

# Configuration
NUM_WORKERS = 8
MEMORY_LIMIT = "25g"
CHECKPOINT_INTERVAL = 200
EXPECTED_TOTAL = 686165

# Paths
BASE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups")
S16_PROCESSING_DIR = BASE_DIR / "s16_processing"
CHECKPOINTS_DIR = S16_PROCESSING_DIR / "checkpoints"
GAP_SCRIPT = S16_PROCESSING_DIR / "process_s16_subgroups.g"
GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"

# Required input files
REQUIRED_FILES = [
    BASE_DIR / "conjugacy_cache" / "s16_subgroups.g",
    S16_PROCESSING_DIR / "s15_iso_map.g",
    GAP_SCRIPT,
]


def cygwin_path(windows_path):
    """Convert Windows path to Cygwin path"""
    path_str = str(windows_path)
    if path_str[1] == ':':
        drive = path_str[0].lower()
        rest = path_str[2:].replace('\\', '/')
        return f"/cygdrive/{drive}{rest}"
    return path_str.replace('\\', '/')


def create_worker_script(worker_id):
    """Create a temporary GAP script for this worker"""
    script_path = CHECKPOINTS_DIR / f"worker_{worker_id}_script.g"
    cygwin_gap_script = cygwin_path(GAP_SCRIPT)

    content = f'''# Worker {worker_id} configuration
WORKER_ID := {worker_id};
NUM_WORKERS := {NUM_WORKERS};
CHECKPOINT_INTERVAL := {CHECKPOINT_INTERVAL};
Read("{cygwin_gap_script}");
'''
    with open(script_path, 'w') as f:
        f.write(content)
    return script_path


def run_worker(worker_id):
    """Run a single GAP worker"""
    script_path = create_worker_script(worker_id)
    output_file = CHECKPOINTS_DIR / f"worker_{worker_id}_output.txt"
    cygwin_script = cygwin_path(script_path)

    cmd = [
        GAP_BASH, "--login", "-c",
        f'/opt/gap-4.15.1/gap -q -o {MEMORY_LIMIT} "{cygwin_script}"'
    ]

    print(f"[{datetime.now().strftime('%H:%M:%S')}] Starting worker {worker_id}")

    with open(output_file, 'w') as out:
        out.write(f"# Worker {worker_id} started at {datetime.now()}\n\n")
        out.flush()

        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )

        for line in proc.stdout:
            out.write(line)
            out.flush()
            # Print progress lines to console
            if 'COMPLETE' in line or 'Error' in line or line.startswith('Worker '):
                print(f"[W{worker_id}] {line.strip()}")

        proc.wait()
        out.write(f"\n# Finished at {datetime.now()}\n")
        out.write(f"# Exit code: {proc.returncode}\n")

    return worker_id, proc.returncode


def preflight_check():
    """Verify all required files exist before launching workers"""
    print("Pre-flight checks:")
    all_ok = True
    for filepath in REQUIRED_FILES:
        if filepath.exists():
            size = filepath.stat().st_size
            print(f"  OK: {filepath.name} ({size:,} bytes)")
        else:
            print(f"  MISSING: {filepath}")
            all_ok = False

    if not all_ok:
        print("\nPre-flight FAILED. Missing required files.")
        print("Run build_s15_iso_map.py first if s15_iso_map.g is missing.")
        return False

    print("Pre-flight PASSED\n")
    return True


def main():
    """Launch all workers in parallel"""
    print(f"S16 Processing - Computing IdGroups and large group invariants")
    print(f"=" * 60)
    print(f"Workers: {NUM_WORKERS}")
    print(f"Memory per worker: {MEMORY_LIMIT}")
    print(f"Checkpoint interval: {CHECKPOINT_INTERVAL}")
    print(f"Expected total: {EXPECTED_TOTAL:,}")
    print(f"Started: {datetime.now()}")
    print(f"=" * 60)
    print()

    # Ensure directories exist
    CHECKPOINTS_DIR.mkdir(parents=True, exist_ok=True)

    # Pre-flight checks
    if not preflight_check():
        return 1

    # Launch workers
    threads = []
    results = {}

    def worker_thread(wid):
        results[wid] = run_worker(wid)

    for worker_id in range(1, NUM_WORKERS + 1):
        t = threading.Thread(target=worker_thread, args=(worker_id,))
        threads.append(t)
        t.start()
        time.sleep(0.5)  # Stagger starts slightly

    # Wait for all workers
    for t in threads:
        t.join()

    # Summary
    print(f"\n{'=' * 60}")
    print(f"All workers completed at {datetime.now()}")
    print(f"{'=' * 60}")

    success = True
    for wid in range(1, NUM_WORKERS + 1):
        _, retcode = results.get(wid, (wid, -1))
        status = "OK" if retcode == 0 else f"FAILED ({retcode})"
        print(f"Worker {wid}: {status}")
        if retcode != 0:
            success = False

    if success:
        print(f"\nAll workers succeeded. Run merge_s16_results.py to combine outputs.")
    else:
        print(f"\nSome workers failed. Check output files in {CHECKPOINTS_DIR} for details.")

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
