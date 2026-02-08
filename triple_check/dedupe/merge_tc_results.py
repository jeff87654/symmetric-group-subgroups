#!/usr/bin/env python3
"""
Merge Triple-Check Deduplication Results.

Collects results from all 12 workers + 1 difficult bucket representative,
verifies coverage and no overlaps, computes final A174511(14) count.
"""

import re
import json
from pathlib import Path
from datetime import datetime

# Configuration
DEDUPE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups\triple_check\dedupe")
RESULTS_DIR = DEDUPE_DIR / "results"
TRACKING_FILE = DEDUPE_DIR / "tracking.json"

# Expected counts
IDGROUP_TYPES = 4602
EXPECTED_TOTAL_A174511 = 7755
TOTAL_GROUPS = 10687


def parse_result_file(filepath):
    """Parse a GAP result file to extract representative indices."""
    if not filepath.exists():
        return None, f"File not found: {filepath}"

    content = filepath.read_text(encoding='utf-8')

    # Look for RESULT_REPS_* := [...]
    match = re.search(r'RESULT_REPS_\w+\s*:=\s*\[\s*(.*?)\s*\];', content, re.DOTALL)
    if not match:
        return None, f"Could not find RESULT_REPS in {filepath.name}"

    indices_str = match.group(1).strip()
    if not indices_str:
        return [], None

    indices = [int(x.strip()) for x in indices_str.split(',') if x.strip()]
    return indices, None


def main():
    print("\n" + "=" * 60)
    print("MERGE TRIPLE-CHECK DEDUPLICATION RESULTS")
    print("=" * 60)
    print(f"Time: {datetime.now()}")
    print()

    # Load tracking info
    if TRACKING_FILE.exists():
        with open(TRACKING_FILE, 'r') as f:
            tracking = json.load(f)
        print(f"Loaded tracking: {tracking['total_groups']} total groups")
    else:
        print("WARNING: tracking.json not found")
        tracking = None

    # Collect results from all workers
    all_reps = {}
    total_reps = 0
    errors = []

    # DP worker
    reps, err = parse_result_file(RESULTS_DIR / "result_dp.g")
    if err:
        errors.append(f"DP worker: {err}")
    else:
        all_reps["dp"] = reps
        print(f"  DP worker:        {len(reps):>5} reps")
        total_reps += len(reps)

    # 2-groups worker
    reps, err = parse_result_file(RESULTS_DIR / "result_2groups.g")
    if err:
        errors.append(f"2-groups worker: {err}")
    else:
        all_reps["2groups"] = reps
        print(f"  2-groups worker:  {len(reps):>5} reps")
        total_reps += len(reps)

    # Regular workers 1-10
    for i in range(1, 11):
        reps, err = parse_result_file(RESULTS_DIR / f"result_regular_{i}.g")
        if err:
            errors.append(f"Regular worker {i}: {err}")
        else:
            all_reps[f"regular_{i}"] = reps
            print(f"  Regular worker {i:>2}: {len(reps):>5} reps")
            total_reps += len(reps)

    if errors:
        print(f"\nERRORS ({len(errors)}):")
        for e in errors:
            print(f"  - {e}")
        print("\nCannot compute final result with missing workers.")
        return 1

    # Add difficult bucket representative
    difficult_rep = None
    if tracking and tracking.get("difficult_bucket"):
        difficult_rep = tracking["difficult_bucket"]["representative"]
        print(f"\n  Difficult bucket: 1 rep (index {difficult_rep})")
        total_reps += 1

    print(f"\n  TOTAL worker reps: {total_reps - (1 if difficult_rep else 0)}")
    print(f"  + difficult rep:   {1 if difficult_rep else 0}")
    print(f"  = TOTAL large reps: {total_reps}")

    # Verification 1: No duplicate indices across workers
    print("\n--- Verification ---")
    all_indices = []
    for name, reps in all_reps.items():
        all_indices.extend(reps)
    if difficult_rep:
        all_indices.append(difficult_rep)

    unique_indices = set(all_indices)
    if len(unique_indices) != len(all_indices):
        dupes = [idx for idx in all_indices if all_indices.count(idx) > 1]
        print(f"  OVERLAP: {len(all_indices) - len(unique_indices)} duplicate indices!")
        print(f"    Duplicated: {sorted(set(dupes))[:20]}")
    else:
        print(f"  No overlaps: {len(unique_indices)} unique rep indices (good!)")

    # Verification 2: All rep indices are valid (1..10687)
    invalid = [idx for idx in unique_indices if idx < 1 or idx > TOTAL_GROUPS]
    if invalid:
        print(f"  INVALID indices: {sorted(invalid)[:20]}")
    else:
        print(f"  All indices in valid range 1..{TOTAL_GROUPS} (good!)")

    # Verification 3: Coverage check against tracking
    if tracking:
        all_assigned = set()
        all_assigned.update(tracking["dp_worker"]["indices"])
        all_assigned.update(tracking["two_group_worker"]["indices"])
        for w in tracking["regular_workers"]:
            all_assigned.update(w["indices"])
        if tracking.get("difficult_bucket", {}).get("indices"):
            all_assigned.update(tracking["difficult_bucket"]["indices"])

        worker_assigned = len(all_assigned) - len(tracking.get("difficult_bucket", {}).get("indices", []))
        print(f"  Tracking coverage: {len(all_assigned)}/{TOTAL_GROUPS} "
              f"({'COMPLETE' if len(all_assigned) == TOTAL_GROUPS else 'INCOMPLETE'})")

        # Check that every rep index was actually assigned to its worker
        for name, reps in all_reps.items():
            if name == "dp":
                expected = set(tracking["dp_worker"]["indices"])
            elif name == "2groups":
                expected = set(tracking["two_group_worker"]["indices"])
            else:
                worker_num = int(name.split("_")[1])
                expected = set(tracking["regular_workers"][worker_num - 1]["indices"])

            unexpected = set(reps) - expected
            if unexpected:
                print(f"  WARNING: {name} returned reps not in its assignment: {sorted(unexpected)[:5]}")

    # Final count
    large_reps = total_reps
    a174511 = IDGROUP_TYPES + large_reps

    print(f"\n" + "=" * 60)
    print(f"FINAL RESULT")
    print(f"=" * 60)
    print(f"  IdGroup types:       {IDGROUP_TYPES:>6}")
    print(f"  Large group reps:    {large_reps:>6}")
    print(f"  -------------------------")
    print(f"  A174511(14) =        {a174511:>6}")
    print()

    if a174511 == EXPECTED_TOTAL_A174511:
        print(f"  *** MATCHES EXPECTED VALUE {EXPECTED_TOTAL_A174511} ***")
    else:
        diff = a174511 - EXPECTED_TOTAL_A174511
        print(f"  *** MISMATCH: expected {EXPECTED_TOTAL_A174511}, got {a174511} (diff={diff:+d}) ***")
        print(f"  Expected large reps: {EXPECTED_TOTAL_A174511 - IDGROUP_TYPES}")
        print(f"  Actual large reps:   {large_reps}")

    # Write final summary
    summary = {
        "timestamp": datetime.now().isoformat(),
        "idgroup_types": IDGROUP_TYPES,
        "large_group_reps": large_reps,
        "a174511_14": a174511,
        "expected": EXPECTED_TOTAL_A174511,
        "matches_expected": a174511 == EXPECTED_TOTAL_A174511,
        "worker_counts": {name: len(reps) for name, reps in all_reps.items()},
        "difficult_bucket_rep": difficult_rep,
        "total_unique_indices": len(unique_indices),
        "all_rep_indices": sorted(unique_indices),
    }

    summary_path = DEDUPE_DIR / "final_result.json"
    with open(summary_path, 'w', encoding='utf-8') as f:
        json.dump(summary, f, indent=2)
    print(f"\nFull result written to: {summary_path}")

    return 0 if a174511 == EXPECTED_TOTAL_A174511 else 1


if __name__ == "__main__":
    exit(main())
