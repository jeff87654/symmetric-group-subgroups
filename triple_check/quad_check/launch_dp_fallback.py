#!/usr/bin/env python3
"""
Phase 1C Launcher: DP Fallback for Non-IdGroup Factors

Only runs if Phase 1B identifies multi-group fallback buckets.
Reads dp_result.json to find buckets, creates a GAP-readable bucket file,
and launches a single GAP worker.
"""

import subprocess
import os
import sys
import json
import time
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
MEMORY = "8g"


def get_cygwin_path(win_path):
    path = os.path.abspath(win_path)
    drive = path[0].lower()
    rest = path[2:].replace("\\", "/")
    return f"/cygdrive/{drive}{rest}"


def main():
    print("Phase 1C: DP Fallback for Non-IdGroup Factors")
    print()

    # Load Phase 1B results
    dp_result_file = os.path.join(SCRIPT_DIR, "dp_result.json")
    if not os.path.exists(dp_result_file):
        print("ERROR: dp_result.json not found. Run count_dp_reps.py first.")
        return 1

    with open(dp_result_file) as f:
        dp_result = json.load(f)

    multi_buckets = dp_result.get("multiFallbackBuckets_detail", {})
    if not multi_buckets:
        print("No multi-group fallback buckets found. Phase 1C not needed.")
        print("All fallback buckets are singletons - no pairwise testing required.")

        # Write trivial result
        result = {"fallbackReps": dp_result["uniqueFallbackKeys"], "buckets": []}
        with open(os.path.join(SCRIPT_DIR, "fallback_result.json"), "w") as f:
            json.dump(result, f, indent=2)
        return 0

    total_groups = sum(len(v) for v in multi_buckets.values())
    print(f"Multi-group fallback buckets: {len(multi_buckets)}")
    print(f"Total groups in fallback buckets: {total_groups}")
    print()

    # Create GAP-readable bucket file
    bucket_file = os.path.join(SCRIPT_DIR, "fallback_buckets.g")
    with open(bucket_file, "w") as f:
        f.write("# Fallback buckets for Phase 1C\n")
        f.write(f"# {len(multi_buckets)} buckets, {total_groups} groups\n\n")
        f.write("FALLBACK_BUCKETS := [\n")
        first = True
        for key, indices in multi_buckets.items():
            if not first:
                f.write(",\n")
            first = False
            # Escape the key for GAP string
            escaped_key = key.replace("\\", "\\\\").replace('"', '\\"')
            f.write(f'  rec(key := "{escaped_key}", indices := {indices})')
        f.write("\n];\n")

    print(f"Bucket file: {bucket_file}")

    # Create wrapper script
    input_cyg = get_cygwin_path(os.path.join(SCRIPT_DIR, "..", "conjugacy_cache", "s14_large_invariants_clean.g"))
    fallback_cyg = get_cygwin_path(bucket_file)
    output_cyg = get_cygwin_path(os.path.join(SCRIPT_DIR, "fallback_results.g"))
    gap_script_cyg = get_cygwin_path(os.path.join(SCRIPT_DIR, "qc_dp_fallback.g"))

    wrapper_path = os.path.join(SCRIPT_DIR, "_worker_1c.g")
    with open(wrapper_path, "w") as f:
        f.write(f'S14_TC := "S14_TC";;\n')
        f.write(f'INPUT_FILE := "{input_cyg}";\n')
        f.write(f'FALLBACK_FILE := "{fallback_cyg}";\n')
        f.write(f'OUTPUT_FILE := "{output_cyg}";\n')
        f.write(f'Read("{gap_script_cyg}");\n')

    wrapper_cyg = get_cygwin_path(wrapper_path)
    log_file = os.path.join(SCRIPT_DIR, "log_1c_fallback.txt")

    cmd = [GAP_BASH, "--login", "-c",
           f'/opt/gap-4.15.1/gap -q -o {MEMORY} "{wrapper_cyg}"']

    print(f"Launching GAP worker...")
    print(f"Log: {log_file}")
    print()

    start_time = time.time()
    with open(log_file, "w") as log:
        log.write(f"# Phase 1C started at {datetime.now()}\n\n")
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, bufsize=1)
        for line in proc.stdout:
            print(line, end='')
            log.write(line)
            log.flush()
        proc.wait()
        elapsed = time.time() - start_time
        log.write(f"\n# Finished at {datetime.now()}\n")
        log.write(f"# Exit code: {proc.returncode}\n")
        log.write(f"# Elapsed: {elapsed:.1f}s\n")

    print(f"\nDone in {elapsed:.1f}s (exit code {proc.returncode})")

    if proc.returncode == 0:
        print("Phase 1C complete. Run merge_qc_results.py for Phase 3.")
    else:
        print("Phase 1C FAILED. Check log file.")

    return proc.returncode


if __name__ == "__main__":
    sys.exit(main())
