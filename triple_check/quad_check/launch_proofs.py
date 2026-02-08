#!/usr/bin/env python3
"""
Phase 2C: Re-verify Hard Bucket Proofs

Re-runs both proof scripts:
1. difficult_bucket_proof.g (4 groups, order 2592, 5 checks)
2. hard_bucket_10368_proof.g (8 groups, order 10368, 7 checks)

Both use explicit bijective homomorphisms verified by GAP.
"""

import subprocess
import os
import sys
import threading
import time
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
MEMORY = "8g"

PROOF_FILES = {
    "difficult": os.path.join(SCRIPT_DIR, "..", "difficult_bucket_proof.g"),
    "hard_10368": os.path.join(SCRIPT_DIR, "..", "hard_bucket_10368_proof.g"),
}


def get_cygwin_path(win_path):
    path = os.path.abspath(win_path)
    drive = path[0].lower()
    rest = path[2:].replace("\\", "/")
    return f"/cygdrive/{drive}{rest}"


def run_proof(name, proof_file):
    """Run a proof script and capture results."""
    proof_cyg = get_cygwin_path(proof_file)
    log_file = os.path.join(SCRIPT_DIR, f"log_proof_{name}.txt")

    cmd = [GAP_BASH, "--login", "-c",
           f'/opt/gap-4.15.1/gap -q -o {MEMORY} "{proof_cyg}"']

    print(f"[{name}] Starting proof verification...")

    start_time = time.time()
    with open(log_file, "w") as log:
        log.write(f"# Proof {name} started at {datetime.now()}\n\n")
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, bufsize=1)
        output_lines = []
        for line in proc.stdout:
            log.write(line)
            log.flush()
            output_lines.append(line.rstrip())
            if "pass" in line.lower() or "fail" in line.lower() or "result" in line.lower():
                print(f"[{name}] {line.rstrip()}")
        proc.wait()
        elapsed = time.time() - start_time
        log.write(f"\n# Finished at {datetime.now()}\n")
        log.write(f"# Exit code: {proc.returncode}\n")

    # Check for RESULT: PASS in output
    result_pass = any("RESULT: PASS" in line for line in output_lines)
    print(f"[{name}] Done in {elapsed:.1f}s (exit code {proc.returncode}, "
          f"{'PASS' if result_pass else 'FAIL'})")

    return proc.returncode, result_pass


def main():
    print("=" * 60)
    print("Phase 2C: Re-verify Hard Bucket Proofs")
    print("=" * 60)
    print()

    results = {}

    # Run both proofs in parallel
    threads = []

    def proof_thread(name, path):
        results[name] = run_proof(name, path)

    for name, path in PROOF_FILES.items():
        if not os.path.exists(path):
            print(f"ERROR: Missing proof file: {path}")
            return 1
        t = threading.Thread(target=proof_thread, args=(name, path))
        t.start()
        threads.append(t)

    for t in threads:
        t.join()

    print()
    print("=" * 60)
    all_ok = True
    for name in sorted(results.keys()):
        exit_code, passed = results[name]
        status = "PASS" if (exit_code == 0 and passed) else "FAIL"
        print(f"  {name}: {status}")
        if status != "PASS":
            all_ok = False

    if all_ok:
        print("\nBoth proofs PASSED.")
        print("  Difficult bucket (2592): 4 groups -> 1 rep")
        print("  Hard bucket (10368): 8 groups -> 1 rep")
    else:
        print("\nSome proofs FAILED!")

    # Write summary
    summary = {
        "difficult": {
            "exit_code": results["difficult"][0],
            "passed": results["difficult"][1],
            "groups": [3943, 3944, 3945, 10687],
            "reps": 1,
            "rep_index": 3943
        },
        "hard_10368": {
            "exit_code": results["hard_10368"][0],
            "passed": results["hard_10368"][1],
            "groups": [1824, 1825, 1826, 1827, 1828, 1829, 1830, 8999],
            "reps": 1,
            "rep_index": 1824
        }
    }

    summary_file = os.path.join(SCRIPT_DIR, "proof_results.json")
    import json
    with open(summary_file, "w") as f:
        json.dump(summary, f, indent=2)

    print(f"\nSummary: {summary_file}")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
