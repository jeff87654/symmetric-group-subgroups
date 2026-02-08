#!/usr/bin/env python3
"""
phase_a1_enumerate.py - Phase A-1: Enumerate recursion trees for S15

Launches GAP to call EnumerateAllLeaves() which:
1. For each maximal subgroup of S15 that is too large for direct computation,
   recursively enumerates maximal subgroups down to leaf groups.
2. Leaf groups (order <= MAX_DIRECT_ORDER) get their lattice computed in Phase A-2.
3. Non-leaf groups are S15 subgroups themselves - they go directly to Phase B.
4. Direct groups (small top-level maxsubs) are computed in Phase A-3.

Output:
  maxsub_output_s15/leaves.g       - leaf groups (for Phase A-2)
  maxsub_output_s15/nonleaves.g    - non-leaf S15 subgroups (for Phase B)
  maxsub_output_s15/direct.g       - small maxsubs (for Phase A-3)
  maxsub_output_s15/enumeration_summary.txt

Also creates leaf batch assignments for parallel computation:
  maxsub_output_s15/leaf_batch_1.g through leaf_batch_N.g

Prerequisites:
  - test_threshold.py must have determined MAX_DIRECT_ORDER
  - compute_s15_recursive.g must exist

Usage:
  python phase_a1_enumerate.py                  # Use default threshold
  python phase_a1_enumerate.py 87000000         # Specify MAX_DIRECT_ORDER
"""

import subprocess
import sys
import os
import re
import time
import math
from pathlib import Path
from datetime import datetime
from collections import defaultdict

GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
BASE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups")
OUTPUT_DIR = BASE_DIR / "maxsub_output_s15"
N = 15
MEMORY = "32g"
TIMEOUT = 4 * 3600  # 4 hours for enumeration

# Default threshold - update after running test_threshold.py
DEFAULT_MAX_DIRECT_ORDER = 50_000_000  # 50M - conservative default

# S14 calibration data: (order, classes, time_seconds)
S14_CALIBRATION = {
    29_030_400: (146_986, 8407),   # intrans_6x8
    87_091_200: (130_921, 6319),   # intrans_4x10
    25_401_600: (53_125, 3952),    # intrans_7x7
    645_120: (55_200, 1560),       # wreath_2wr7
    958_003_200: (76_083, 2961),   # intrans_2x12
}

# Number of parallel leaf workers
NUM_LEAF_WORKERS = 3  # 2-3 workers at 16-32g each fits in 64g


def windows_to_cygwin_path(win_path: str) -> str:
    path = str(win_path).replace('\\', '/')
    if len(path) >= 2 and path[1] == ':':
        drive = path[0].lower()
        path = f'/cygdrive/{drive}{path[2:]}'
    return path

BASE_CYGWIN = windows_to_cygwin_path(str(BASE_DIR))
OUTPUT_CYGWIN = windows_to_cygwin_path(str(OUTPUT_DIR))


def estimate_time(order: int) -> float:
    """Estimate computation time for a group of given order, based on S14 data."""
    if order <= 1000:
        return 1.0
    # Linear interpolation in log space
    known = sorted(S14_CALIBRATION.items())
    log_order = math.log(order)

    for i in range(len(known) - 1):
        o1, (c1, t1) = known[i]
        o2, (c2, t2) = known[i + 1]
        lo1, lo2 = math.log(o1), math.log(o2)
        if lo1 <= log_order <= lo2:
            frac = (log_order - lo1) / (lo2 - lo1)
            return t1 + frac * (t2 - t1)

    # Extrapolate from largest
    o_max, (c_max, t_max) = known[-1]
    ratio = order / o_max
    return t_max * ratio  # Linear extrapolation


def run_enumeration(max_direct_order: int) -> bool:
    """Launch GAP to enumerate all recursion tree leaves."""
    print(f"Launching GAP enumeration with MAX_DIRECT_ORDER = {max_direct_order:,}")

    script = f'''
Read("{BASE_CYGWIN}/compute_s15_recursive.g");

n := {N};
maxOrder := {max_direct_order};
outputDir := "{OUTPUT_CYGWIN}";

# Skip groups handled by compute_s15_maxsub.py (direct workers):
#   intrans_1x14: uses cached S14 data
#   wreath_*: small enough for direct computation
#   primitive_*: very small groups
skipLabels := ["intrans_1x14", "wreath_3wr5", "wreath_5wr3",
               "primitive_1", "primitive_2", "primitive_3", "primitive_4"];

startTime := Runtime();
results := EnumerateAllLeaves(maxOrder, n, skipLabels);

SaveEnumerationResults(results, outputDir, n);

elapsed := Runtime() - startTime;
Print("\\n=== Enumeration complete in ", Int(elapsed/1000), " seconds ===\\n");
Print("  Leaves: ", Length(results.leaves), "\\n");
Print("  Non-leaves: ", Length(results.nonleaves), "\\n");
Print("  Direct: ", Length(results.direct), "\\n");

# Print leaf order distribution
if Length(results.leaves) > 0 then
    Print("\\nLeaf order distribution:\\n");
    orders := List(results.leaves, x -> x.order);
    Sort(orders);
    prev := 0;
    for o in orders do
        if o <> prev then
            count := Number(orders, x -> x = o);
            Print("  Order ", o, ": ", count, " leaves\\n");
            prev := o;
        fi;
    od;
fi;

Print("\\nENUMERATION_COMPLETE\\n");
QUIT;
'''

    script_file = OUTPUT_DIR / "phase_a1_enumerate.g"
    log_file = OUTPUT_DIR / "phase_a1_enumerate.log"

    with open(script_file, 'w') as f:
        f.write(script)

    script_cygwin = windows_to_cygwin_path(str(script_file))
    cmd = f'/opt/gap-4.15.1/gap -q -o {MEMORY} "{script_cygwin}"'

    start_time = time.time()
    success = False

    with open(log_file, 'w') as log:
        log.write(f"# Phase A-1: Enumerate recursion trees\n")
        log.write(f"# MAX_DIRECT_ORDER = {max_direct_order}\n")
        log.write(f"# Started: {datetime.now()}\n\n")
        log.flush()

        try:
            proc = subprocess.Popen(
                [GAP_BASH, '--login', '-c', cmd],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )

            for line in proc.stdout:
                log.write(line)
                log.flush()
                line_s = line.strip()
                # Print important lines
                if any(kw in line_s for kw in [
                    "LEAF", "NON-LEAF", "SKIP", "DIRECT", "Found",
                    "Summary", "complete", "Saving", "ERROR",
                    "ENUMERATION_COMPLETE", "distribution", "Order",
                    "Enumerating", "maximal subgroup", "---"
                ]):
                    print(f"  {line_s}")

                if "ENUMERATION_COMPLETE" in line_s:
                    success = True

            proc.wait(timeout=TIMEOUT)

            log.write(f"\n# Finished: {datetime.now()}\n")
            log.write(f"# Exit code: {proc.returncode}\n")

        except subprocess.TimeoutExpired:
            proc.kill()
            print(f"TIMEOUT after {TIMEOUT // 3600}h!")
        except Exception as e:
            print(f"ERROR: {e}")

    elapsed = time.time() - start_time
    print(f"\nEnumeration completed in {elapsed:.0f}s ({'SUCCESS' if success else 'FAILED'})")

    return success


def create_leaf_batches():
    """Read leaves.g and create batch assignment files for parallel workers."""
    leaves_file = OUTPUT_DIR / "leaves.g"
    if not leaves_file.exists():
        print("ERROR: leaves.g not found!")
        return False

    print(f"\nCreating leaf batch assignments for {NUM_LEAF_WORKERS} workers...")

    # Parse leaves.g to extract leaf metadata
    content = leaves_file.read_text()

    # Extract order and label for each leaf
    leaf_pattern = re.compile(
        r'rec\(\s*genImages\s*:=\s*(.*?),\s*order\s*:=\s*(\d+)'
        r',\s*label\s*:=\s*"([^"]+)"\s*,\s*depth\s*:=\s*(\d+)\s*\)',
        re.DOTALL
    )

    leaves = []
    for match in leaf_pattern.finditer(content):
        gen_images_str = match.group(1).strip()
        order = int(match.group(2))
        label = match.group(3)
        depth = int(match.group(4))
        est_time = estimate_time(order)
        leaves.append({
            "gen_images_str": gen_images_str,
            "order": order,
            "label": label,
            "depth": depth,
            "est_time": est_time,
        })

    print(f"  Found {len(leaves)} leaves")

    if not leaves:
        print("  No leaves to assign!")
        return True

    # Report order distribution
    order_counts = defaultdict(int)
    for leaf in leaves:
        order_counts[leaf["order"]] += 1
    print(f"\n  Order distribution:")
    for order in sorted(order_counts.keys()):
        est = estimate_time(order)
        print(f"    Order {order:>15,d}: {order_counts[order]:>4d} leaves "
              f"(est ~{est:.0f}s each)")

    total_est = sum(leaf["est_time"] for leaf in leaves)
    print(f"\n  Total estimated time: {total_est:,.0f}s ({total_est/3600:.1f}h)")
    print(f"  With {NUM_LEAF_WORKERS} workers: ~{total_est/NUM_LEAF_WORKERS/3600:.1f}h")

    # Sort leaves by estimated time (largest first) for greedy bin packing
    leaves.sort(key=lambda x: x["est_time"], reverse=True)

    # Greedy bin packing: assign each leaf to the worker with least total time
    worker_times = [0.0] * NUM_LEAF_WORKERS
    worker_leaves = [[] for _ in range(NUM_LEAF_WORKERS)]

    for leaf in leaves:
        # Find worker with minimum total estimated time
        min_idx = worker_times.index(min(worker_times))
        worker_leaves[min_idx].append(leaf)
        worker_times[min_idx] += leaf["est_time"]

    # Report assignments
    print(f"\n  Worker assignments:")
    for w in range(NUM_LEAF_WORKERS):
        n_leaves = len(worker_leaves[w])
        est = worker_times[w]
        if n_leaves > 0:
            max_order = max(l["order"] for l in worker_leaves[w])
            print(f"    Worker {w+1}: {n_leaves} leaves, est {est:.0f}s ({est/3600:.1f}h), "
                  f"max order {max_order:,}")

    # Write batch files
    for w in range(NUM_LEAF_WORKERS):
        batch_file = OUTPUT_DIR / f"leaf_batch_{w+1}.g"
        with open(batch_file, 'w') as f:
            f.write(f"# Leaf batch {w+1} for S{N} Phase A-2\n")
            f.write(f"# Leaves: {len(worker_leaves[w])}\n")
            f.write(f"# Estimated time: {worker_times[w]:.0f}s\n")
            f.write(f"leaf_batch := [\n")
            first = True
            for leaf in worker_leaves[w]:
                if not first:
                    f.write(",\n")
                first = False
                f.write(f"  rec(genImages := {leaf['gen_images_str']}, "
                        f"order := {leaf['order']}, "
                        f"label := \"{leaf['label']}\")")
            f.write(f"\n];\n")
        print(f"  Written {batch_file.name}")

    # Also write a summary file
    summary_file = OUTPUT_DIR / "enumeration_summary.txt"
    with open(summary_file, 'w') as f:
        f.write(f"# S15 Recursive Enumeration Summary\n")
        f.write(f"# {datetime.now()}\n\n")
        f.write(f"Total leaves: {len(leaves)}\n")
        f.write(f"Leaf workers: {NUM_LEAF_WORKERS}\n")
        f.write(f"Total estimated time: {total_est:.0f}s ({total_est/3600:.1f}h)\n")
        f.write(f"Parallel estimated time: {max(worker_times):.0f}s "
                f"({max(worker_times)/3600:.1f}h)\n\n")
        for w in range(NUM_LEAF_WORKERS):
            f.write(f"Worker {w+1}: {len(worker_leaves[w])} leaves, "
                    f"est {worker_times[w]:.0f}s\n")
            for leaf in worker_leaves[w]:
                f.write(f"  {leaf['label']} (order {leaf['order']:,}, "
                        f"est {leaf['est_time']:.0f}s)\n")
            f.write("\n")

    print(f"\n  Summary saved to {summary_file.name}")
    return True


def main():
    print("=" * 60)
    print("Phase A-1: Enumerate Recursion Trees for S15")
    print("=" * 60)
    print(f"Started: {datetime.now()}")
    print()

    # Determine MAX_DIRECT_ORDER
    max_direct_order = DEFAULT_MAX_DIRECT_ORDER
    if len(sys.argv) > 1:
        max_direct_order = int(sys.argv[1])

    # Check if threshold test results exist
    threshold_file = OUTPUT_DIR / "threshold_summary.txt"
    if threshold_file.exists():
        content = threshold_file.read_text()
        m = re.search(r'MAX_DIRECT_ORDER\s*=\s*(\d+)', content)
        if m:
            detected = int(m.group(1))
            if len(sys.argv) <= 1:
                max_direct_order = detected
                print(f"Using threshold from test_threshold.py: {max_direct_order:,}")
            else:
                print(f"Threshold test detected {detected:,}, but using override: {max_direct_order:,}")
    else:
        print(f"No threshold test results found. Using default: {max_direct_order:,}")

    print(f"MAX_DIRECT_ORDER = {max_direct_order:,}")
    print()

    OUTPUT_DIR.mkdir(exist_ok=True)

    # Check if enumeration already completed
    leaves_file = OUTPUT_DIR / "leaves.g"
    nonleaves_file = OUTPUT_DIR / "nonleaves.g"
    if leaves_file.exists() and nonleaves_file.exists():
        print("Enumeration files already exist. Skipping GAP enumeration.")
        print("Delete leaves.g and nonleaves.g to re-run enumeration.")
    else:
        # Run GAP enumeration
        if not run_enumeration(max_direct_order):
            print("\nERROR: Enumeration failed!")
            return 1

    # Create batch assignments
    if not create_leaf_batches():
        print("\nERROR: Batch creation failed!")
        return 1

    print(f"\n{'='*60}")
    print("Phase A-1 complete!")
    print(f"{'='*60}")
    print(f"  Next steps:")
    print(f"    1. python phase_a2_compute_leaves.py    (leaf lattice computation)")
    print(f"    2. python compute_s15_maxsub.py         (direct workers)")
    print(f"    3. python phase_a4_combine.py           (combine all results)")
    print(f"    4. python phase_b1_s15.py               (bucketing)")
    print(f"    5. python rerun_phase_b2b3_s15.py       (dedup + collection)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
