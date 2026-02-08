#!/usr/bin/env python3
"""
Phase 2B Launcher: Verify Non-DP Bucket Deduplication

Launches verification workers:
- 6 regular workers (Cygwin): verify regular non-DP buckets
- 1 2-group worker (WSL/ANUPQ): verify 2-group buckets

Each worker re-checks that:
1. Reps are mutually non-isomorphic
2. Non-reps each match some rep

Groups in the difficult bucket (3943,3944,3945,10687) and hard bucket
(1824-1830,8999) are excluded - verified separately in Phase 2C.
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
WSL_PATH = "wsl"
MEMORY = "8g"

# Excluded indices (handled by Phase 2C proof scripts)
DIFFICULT_INDICES = {3943, 3944, 3945, 10687}
HARD_INDICES = {1824, 1825, 1826, 1827, 1828, 1829, 1830, 8999}
EXCLUDED = DIFFICULT_INDICES | HARD_INDICES

NUM_REGULAR_WORKERS = 6

INPUT_FILE_CYG = "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/triple_check/conjugacy_cache/s14_large_invariants_clean.g"
INPUT_FILE_WSL = "/mnt/c/Users/jeffr/Downloads/Symmetric Groups/triple_check/conjugacy_cache/s14_large_invariants_clean.g"


def get_cygwin_path(win_path):
    path = os.path.abspath(win_path)
    drive = path[0].lower()
    rest = path[2:].replace("\\", "/")
    return f"/cygdrive/{drive}{rest}"


def get_wsl_path(win_path):
    path = os.path.abspath(win_path)
    drive = path[0].lower()
    rest = path[2:].replace("\\", "/")
    return f"/mnt/{drive}{rest}"


def load_bucket_breakdown():
    """Load the tc_bucket_breakdown.json from Phase 2A."""
    filepath = os.path.join(SCRIPT_DIR, "tc_bucket_breakdown.json")
    with open(filepath) as f:
        return json.load(f)


def get_verification_buckets(breakdown):
    """Extract non-DP multi-group buckets that need verification."""
    regular_buckets = []
    twogroup_buckets = []

    for worker_name, data in breakdown["workerData"].items():
        if worker_name == "dp":
            continue

        for bkt in data["buckets"]:
            indices = bkt["indices"]
            reps = bkt["reps"]

            # Remove excluded indices
            clean_indices = [i for i in indices if i not in EXCLUDED]
            clean_reps = [r for r in reps if r not in EXCLUDED]

            if len(clean_indices) <= 1:
                continue  # Singleton or empty after exclusion

            bucket_info = {
                "worker": worker_name,
                "bucket_num": bkt["bucket_num"],
                "key": bkt["key"],
                "indices": clean_indices,
                "reps": clean_reps,
                "size": len(clean_indices)
            }

            if worker_name == "2groups":
                twogroup_buckets.append(bucket_info)
            else:
                regular_buckets.append(bucket_info)

    return regular_buckets, twogroup_buckets


def create_verification_gap_script(buckets, worker_id, worker_type, path_func, input_path):
    """Create a GAP verification script for a set of buckets."""
    lib_path = path_func(os.path.join(SCRIPT_DIR, "qc_verify_common.g"))
    output_file = path_func(os.path.join(SCRIPT_DIR, f"verify_result_{worker_type}_{worker_id}.g"))

    lines = []
    lines.append(f'# QC Phase 2B Verification - {worker_type} worker {worker_id}')
    lines.append(f'# Buckets: {len(buckets)}')
    lines.append('')
    lines.append('SetInfoLevel(InfoWarning, 0);;')
    lines.append('')

    if worker_type == "2groups":
        lines.append('Print("Loading ANUPQ package...\\n");')
        lines.append('LoadPackage("anupq");;')
        lines.append('')

    lines.append('S14_TC := "S14_TC";;')
    lines.append('')
    lines.append(f'Print("Loading shared library...\\n");')
    lines.append(f'Read("{lib_path}");')
    lines.append('')
    lines.append(f'Print("Loading group data...\\n");')
    lines.append(f'Read("{input_path}");')
    lines.append('DATA := S14_TC_LARGE;;')
    lines.append('')
    lines.append('# Build index lookup')
    lines.append('DATA_BY_INDEX := rec();;')
    lines.append('for r in DATA do')
    lines.append('    DATA_BY_INDEX.(r.index) := r;')
    lines.append('od;')
    lines.append('Print("Built index lookup for ", Length(DATA), " records\\n\\n");')
    lines.append('')
    lines.append('totalErrors := 0;;')
    lines.append('totalBuckets := 0;;')
    lines.append(f'startTime := Runtime();;')
    lines.append('')

    # Initialize output file
    lines.append(f'PrintTo("{output_file}",')
    lines.append(f'    "# QC Phase 2B Verification - {worker_type} worker {worker_id}\\n",')
    lines.append(f'    "# Buckets: {len(buckets)}\\n\\n");')
    lines.append('')

    # Process each bucket
    verify_func = "VerifyBucket2Groups" if worker_type == "2groups" else "VerifyBucketRegular"

    for i, bkt in enumerate(buckets):
        bkt_num = i + 1
        indices_str = str(bkt["indices"])
        reps_str = str(bkt["reps"])
        key_escaped = bkt["key"][:60].replace('"', '\\"')

        lines.append(f'# Bucket {bkt_num}: {bkt["size"]} groups, {len(bkt["reps"])} reps')
        lines.append(f'Print("Bucket {bkt_num}/{len(buckets)}: {bkt["size"]} groups, '
                     f'{len(bkt["reps"])} reps, key={key_escaped}\\n");')
        lines.append(f'bktErrors := {verify_func}({indices_str}, {reps_str}, DATA_BY_INDEX);')
        lines.append(f'totalErrors := totalErrors + bktErrors;')
        lines.append(f'totalBuckets := totalBuckets + 1;')

        status_str = (
            f'"# Bucket {bkt_num}: {bkt["size"]} groups, {len(bkt["reps"])} reps, "'
        )
        lines.append(f'if bktErrors = 0 then')
        lines.append(f'    Print("  VERIFIED ({bkt["size"]} groups, {len(bkt["reps"])} reps)\\n");')
        lines.append(f'    AppendTo("{output_file}", {status_str}, "VERIFIED (0 errors)\\n");')
        lines.append(f'else')
        lines.append(f'    Print("  ERRORS: ", bktErrors, "\\n");')
        lines.append(f'    AppendTo("{output_file}", {status_str}, "ERRORS: ", bktErrors, "\\n");')
        lines.append(f'fi;')
        lines.append('')

    # Summary
    lines.append(f'elapsed := Runtime() - startTime;;')
    lines.append(f'Print("\\n=== {worker_type.upper()} Worker {worker_id} Complete ===\\n");')
    lines.append(f'Print("Buckets verified: ", totalBuckets, "\\n");')
    lines.append(f'Print("Total errors: ", totalErrors, "\\n");')
    lines.append(f'Print("Elapsed: ", elapsed, "ms\\n");')
    lines.append('')
    lines.append(f'AppendTo("{output_file}", "\\n# Total errors: ", totalErrors, "\\n");')
    lines.append(f'AppendTo("{output_file}", "# Elapsed: ", elapsed, "ms\\n");')
    lines.append(f'if totalErrors = 0 then')
    lines.append(f'    AppendTo("{output_file}", "# RESULT: PASS\\n");')
    lines.append(f'else')
    lines.append(f'    AppendTo("{output_file}", "# RESULT: FAIL\\n");')
    lines.append(f'fi;')
    lines.append('')
    lines.append(f'QuitGap(totalErrors);')

    script_path = os.path.join(SCRIPT_DIR, f"_verify_{worker_type}_{worker_id}.g")
    with open(script_path, "w") as f:
        f.write("\n".join(lines) + "\n")

    return script_path


def run_cygwin_worker(worker_id, script_path):
    """Run a GAP worker via Cygwin."""
    script_cyg = get_cygwin_path(script_path)
    log_file = os.path.join(SCRIPT_DIR, f"log_verify_regular_{worker_id}.txt")

    cmd = [GAP_BASH, "--login", "-c",
           f'/opt/gap-4.15.1/gap -q -o {MEMORY} "{script_cyg}"']

    start_time = time.time()
    with open(log_file, "w") as log:
        log.write(f"# Regular verify worker {worker_id} started at {datetime.now()}\n\n")
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, bufsize=1)
        for line in proc.stdout:
            log.write(line)
            log.flush()
            if "verified" in line.lower() or "error" in line.lower() or "complete" in line.lower():
                print(f"[Regular-{worker_id}] {line.rstrip()}")
        proc.wait()
        elapsed = time.time() - start_time
        log.write(f"\n# Finished at {datetime.now()}\n")
        log.write(f"# Exit code: {proc.returncode}\n")
        log.write(f"# Elapsed: {elapsed:.1f}s\n")

    print(f"[Regular-{worker_id}] Done in {elapsed:.1f}s (exit code {proc.returncode})")
    return proc.returncode


def run_wsl_worker(worker_id, script_path):
    """Run a GAP worker via WSL (for 2-groups with ANUPQ)."""
    script_wsl = get_wsl_path(script_path)
    log_file = os.path.join(SCRIPT_DIR, f"log_verify_2groups_{worker_id}.txt")

    cmd = [WSL_PATH, "bash", "-c",
           f'cd /tmp && gap -q -o {MEMORY} "{script_wsl}"']

    start_time = time.time()
    with open(log_file, "w") as log:
        log.write(f"# 2-group verify worker {worker_id} started at {datetime.now()}\n\n")
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, bufsize=1)
        for line in proc.stdout:
            log.write(line)
            log.flush()
            if "verified" in line.lower() or "error" in line.lower() or "complete" in line.lower():
                print(f"[2groups-{worker_id}] {line.rstrip()}")
        proc.wait()
        elapsed = time.time() - start_time
        log.write(f"\n# Finished at {datetime.now()}\n")
        log.write(f"# Exit code: {proc.returncode}\n")
        log.write(f"# Elapsed: {elapsed:.1f}s\n")

    print(f"[2groups-{worker_id}] Done in {elapsed:.1f}s (exit code {proc.returncode})")
    return proc.returncode


def distribute_buckets(buckets, num_workers):
    """Distribute buckets across workers using greedy bin packing by total group count."""
    workers = [[] for _ in range(num_workers)]
    worker_loads = [0] * num_workers

    # Sort buckets by size descending for better load balancing
    sorted_buckets = sorted(buckets, key=lambda b: b["size"], reverse=True)

    for bkt in sorted_buckets:
        # Assign to least loaded worker
        min_idx = worker_loads.index(min(worker_loads))
        workers[min_idx].append(bkt)
        worker_loads[min_idx] += bkt["size"]

    return workers, worker_loads


def main():
    print("=" * 60)
    print("Phase 2B: Verify Non-DP Bucket Deduplication")
    print("=" * 60)
    print()

    breakdown = load_bucket_breakdown()
    regular_buckets, twogroup_buckets = get_verification_buckets(breakdown)

    total_regular_groups = sum(b["size"] for b in regular_buckets)
    total_2group_groups = sum(b["size"] for b in twogroup_buckets)

    print(f"Regular buckets to verify: {len(regular_buckets)} ({total_regular_groups} groups)")
    print(f"2-group buckets to verify: {len(twogroup_buckets)} ({total_2group_groups} groups)")
    print(f"Excluded: {len(EXCLUDED)} indices (verified in Phase 2C)")
    print()

    # Distribute regular buckets across workers
    worker_buckets, worker_loads = distribute_buckets(regular_buckets, NUM_REGULAR_WORKERS)

    for i, (bkts, load) in enumerate(zip(worker_buckets, worker_loads)):
        print(f"Regular worker {i+1}: {len(bkts)} buckets, {load} groups")

    if twogroup_buckets:
        print(f"2-group worker 1: {len(twogroup_buckets)} buckets, {total_2group_groups} groups")
    print()

    # Create GAP scripts
    regular_scripts = []
    for i, bkts in enumerate(worker_buckets):
        if not bkts:
            continue
        script = create_verification_gap_script(
            bkts, i + 1, "regular", get_cygwin_path, INPUT_FILE_CYG)
        regular_scripts.append((i + 1, script))

    twogroup_scripts = []
    if twogroup_buckets:
        script = create_verification_gap_script(
            twogroup_buckets, 1, "2groups", get_wsl_path, INPUT_FILE_WSL)
        twogroup_scripts.append((1, script))

    start_time = time.time()

    # Launch all workers in parallel
    threads = []
    results = {}

    def regular_thread(wid, script):
        results[f"regular_{wid}"] = run_cygwin_worker(wid, script)

    def twogroup_thread(wid, script):
        results[f"2groups_{wid}"] = run_wsl_worker(wid, script)

    for wid, script in regular_scripts:
        t = threading.Thread(target=regular_thread, args=(wid, script))
        t.start()
        threads.append(t)

    for wid, script in twogroup_scripts:
        t = threading.Thread(target=twogroup_thread, args=(wid, script))
        t.start()
        threads.append(t)

    # Wait for all
    for t in threads:
        t.join()

    elapsed = time.time() - start_time
    print()
    print("=" * 60)
    print(f"All verification workers complete in {elapsed:.1f}s")
    print()

    all_ok = True
    for name in sorted(results.keys()):
        status = "PASS" if results[name] == 0 else f"FAIL (exit code {results[name]})"
        print(f"  {name}: {status}")
        if results[name] != 0:
            all_ok = False

    if all_ok:
        print("\nAll verification workers PASSED. No errors found.")
    else:
        print("\nSome workers FAILED! Check log and result files.")

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
