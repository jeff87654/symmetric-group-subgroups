#!/usr/bin/env python3
"""
Launch parallel GAP workers to verify S15 isomorphism proofs
against S16 conjugacy class data.

Each proof is verified by:
  1. Loading both groups from s16_subgroups.g
  2. Checking orders match
  3. Checking proof gens/images are valid group elements
  4. Checking the map extends to a surjective homomorphism (=> isomorphism)
"""

import subprocess
import sys
from datetime import datetime
from pathlib import Path
import threading
import time

# Configuration — 3 workers to leave headroom for main processing
NUM_WORKERS = 3
MEMORY_LIMIT = "15g"

# Paths
BASE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups")
S16_PROCESSING_DIR = BASE_DIR / "s16_processing"
CHECKPOINTS_DIR = S16_PROCESSING_DIR / "checkpoints"
GAP_SCRIPT = S16_PROCESSING_DIR / "verify_s15_proofs.g"
GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"

REQUIRED_FILES = [
    BASE_DIR / "conjugacy_cache" / "s16_subgroups.g",
    BASE_DIR / "s15_proof_certificate" / "combined_proof.g",
    GAP_SCRIPT,
]


def cygwin_path(windows_path):
    path_str = str(windows_path)
    if path_str[1] == ':':
        drive = path_str[0].lower()
        rest = path_str[2:].replace('\\', '/')
        return f"/cygdrive/{drive}{rest}"
    return path_str.replace('\\', '/')


def create_worker_script(worker_id):
    script_path = CHECKPOINTS_DIR / f"verify_worker_{worker_id}_script.g"
    cygwin_gap_script = cygwin_path(GAP_SCRIPT)
    content = f'''# Verification worker {worker_id}
WORKER_ID := {worker_id};
NUM_WORKERS := {NUM_WORKERS};
Read("{cygwin_gap_script}");
'''
    with open(script_path, 'w') as f:
        f.write(content)
    return script_path


def run_worker(worker_id):
    script_path = create_worker_script(worker_id)
    output_file = CHECKPOINTS_DIR / f"verify_worker_{worker_id}_output.txt"
    cygwin_script = cygwin_path(script_path)

    cmd = [
        GAP_BASH, "--login", "-c",
        f'/opt/gap-4.15.1/gap -q -o {MEMORY_LIMIT} "{cygwin_script}"'
    ]

    print(f"[{datetime.now().strftime('%H:%M:%S')}] Starting verification worker {worker_id}")

    with open(output_file, 'w') as out:
        out.write(f"# Verification worker {worker_id} started at {datetime.now()}\n\n")
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
            if 'COMPLETE' in line or 'FAIL' in line or 'VERIFIED' in line or line.startswith('Worker '):
                print(f"[V{worker_id}] {line.strip()}")

        proc.wait()
        out.write(f"\n# Finished at {datetime.now()}\n")
        out.write(f"# Exit code: {proc.returncode}\n")

    return worker_id, proc.returncode


def preflight_check():
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
        print("\nPre-flight FAILED.")
        return False
    print("Pre-flight PASSED\n")
    return True


def collect_results():
    """Parse and summarize results from all workers"""
    total_pass = 0
    total_fail = 0
    failures = []

    for wid in range(1, NUM_WORKERS + 1):
        results_file = CHECKPOINTS_DIR / f"verify_worker_{wid}_results.txt"
        if not results_file.exists():
            print(f"Warning: Missing results for worker {wid}")
            continue

        with open(results_file) as f:
            for line in f:
                if line.startswith("Passed:"):
                    total_pass += int(line.split(":")[1].strip())
                elif line.startswith("Failed:"):
                    total_fail += int(line.split(":")[1].strip())
                elif line.startswith("FAIL"):
                    failures.append(line.strip())

    return total_pass, total_fail, failures


def main():
    print(f"S15 Proof Verification against S16 data")
    print(f"=" * 60)
    print(f"Workers: {NUM_WORKERS}")
    print(f"Memory per worker: {MEMORY_LIMIT}")
    print(f"Started: {datetime.now()}")
    print(f"=" * 60)
    print()

    CHECKPOINTS_DIR.mkdir(parents=True, exist_ok=True)

    if not preflight_check():
        return 1

    threads = []
    results = {}

    def worker_thread(wid):
        results[wid] = run_worker(wid)

    for worker_id in range(1, NUM_WORKERS + 1):
        t = threading.Thread(target=worker_thread, args=(worker_id,))
        threads.append(t)
        t.start()
        time.sleep(1)  # Stagger for file loading

    for t in threads:
        t.join()

    # Summary
    print(f"\n{'=' * 60}")
    print(f"All verification workers completed at {datetime.now()}")
    print(f"{'=' * 60}")

    success = True
    for wid in range(1, NUM_WORKERS + 1):
        _, retcode = results.get(wid, (wid, -1))
        status = "OK" if retcode == 0 else f"FAILED ({retcode})"
        print(f"Worker {wid}: {status}")
        if retcode != 0:
            success = False

    if success:
        total_pass, total_fail, failures = collect_results()
        print(f"\nVerification Results:")
        print(f"  Passed: {total_pass:,}")
        print(f"  Failed: {total_fail}")
        print(f"  Total:  {total_pass + total_fail:,}")

        if total_fail > 0:
            print(f"\nFailures:")
            for f in failures[:20]:
                print(f"  {f}")
            if len(failures) > 20:
                print(f"  ... and {len(failures) - 20} more")
        else:
            print(f"\n*** ALL {total_pass:,} PROOFS VERIFIED ***")
    else:
        print(f"\nSome workers failed. Check output files for details.")

    return 0 if success and total_fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
