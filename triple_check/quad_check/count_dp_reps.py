#!/usr/bin/env python3
"""
Phase 1B: Count Unique Canonical Keys

Parses Phase 1A worker output files and:
1. Groups with allIdGroup=true: unique canonical key = unique isomorphism type
2. Groups with allIdGroup=false: group by invariant-based key, identify fallback buckets

Output: dp_result.json
"""

import re
import os
import json
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
NUM_WORKERS = 4


def parse_result_file(filepath):
    """Parse a Phase 1A worker result file."""
    with open(filepath, "r") as f:
        content = f.read()

    # Remove GAP line continuations (backslash + newline)
    content = content.replace("\\\n", "")

    records = []
    # Match rec(...) entries - use re.DOTALL since index may span lines
    for m in re.finditer(r'rec\(([^)]+)\)', content):
        rec_text = m.group(1)
        # Collapse any remaining whitespace runs to single space
        rec_text = re.sub(r'\s+', ' ', rec_text)

        idx_m = re.search(r'index:=\s*(\d+)', rec_text)
        key_m = re.search(r'canonKey:="([^"]*)"', rec_text)
        all_m = re.search(r'allIdGroup:=(true|false)', rec_text)
        nf_m = re.search(r'numFactors:=(\d+)', rec_text)

        if not all([idx_m, key_m, all_m]):
            continue

        records.append({
            "index": int(idx_m.group(1)),
            "canonKey": key_m.group(1),
            "allIdGroup": all_m.group(1) == "true",
            "numFactors": int(nf_m.group(1)) if nf_m else 0
        })

    return records


def main():
    print("Phase 1B: Count Unique Canonical Keys")
    print()

    all_records = []
    for w in range(1, NUM_WORKERS + 1):
        filepath = os.path.join(SCRIPT_DIR, f"factor_results_{w}.g")
        if not os.path.exists(filepath):
            print(f"ERROR: Missing {filepath}")
            return 1
        records = parse_result_file(filepath)
        print(f"Worker {w}: {len(records)} records")
        all_records.extend(records)

    print(f"\nTotal DP records: {len(all_records)}")

    # Split into definitive (all IdGroup) and fallback
    definitive = [r for r in all_records if r["allIdGroup"]]
    fallback = [r for r in all_records if not r["allIdGroup"]]

    print(f"  All-IdGroup (definitive): {len(definitive)}")
    print(f"  Needs fallback: {len(fallback)}")
    print()

    # Count unique canonical keys among definitive groups
    definitive_keys = {}
    for r in definitive:
        definitive_keys.setdefault(r["canonKey"], []).append(r["index"])

    unique_definitive = len(definitive_keys)
    print(f"Unique canonical keys (definitive): {unique_definitive}")

    # Show size distribution
    size_dist = {}
    for key, indices in definitive_keys.items():
        sz = len(indices)
        size_dist[sz] = size_dist.get(sz, 0) + 1
    print("  Bucket size distribution:")
    for sz in sorted(size_dist.keys()):
        print(f"    {sz} groups: {size_dist[sz]} buckets")
    print()

    # Count unique canonical keys among fallback groups
    fallback_keys = {}
    for r in fallback:
        fallback_keys.setdefault(r["canonKey"], []).append(r["index"])

    unique_fallback_keys = len(fallback_keys)
    print(f"Unique invariant keys (fallback): {unique_fallback_keys}")

    # How many fallback buckets have >1 group (need pairwise testing)?
    multi_fallback = {k: v for k, v in fallback_keys.items() if len(v) > 1}
    print(f"  Singleton fallback buckets: {unique_fallback_keys - len(multi_fallback)}")
    print(f"  Multi-group fallback buckets: {len(multi_fallback)}")

    if multi_fallback:
        print("\n  Multi-group fallback buckets (need Phase 1C):")
        total_pairs = 0
        for key, indices in sorted(multi_fallback.items(), key=lambda x: -len(x[1])):
            n = len(indices)
            pairs = n * (n - 1) // 2
            total_pairs += pairs
            print(f"    {n} groups, {pairs} pairs: indices {indices[:5]}{'...' if n > 5 else ''}")
            print(f"      key: {key[:100]}{'...' if len(key) > 100 else ''}")
        print(f"\n  Total pairwise tests needed: {total_pairs}")

    # Compute bounds
    min_dp_reps = unique_definitive + unique_fallback_keys  # if all multi-fallback collapse to 1
    max_dp_reps = unique_definitive + len(fallback)  # if no fallback groups are isomorphic

    print(f"\nDP rep count bounds:")
    print(f"  Minimum (all fallback collapse): {min_dp_reps}")
    print(f"  Maximum (no fallback collapse): {max_dp_reps}")
    print(f"  Expected (triple check): 2269")

    # Write output
    output = {
        "totalDP": len(all_records),
        "definitiveCount": len(definitive),
        "fallbackCount": len(fallback),
        "uniqueDefinitiveKeys": unique_definitive,
        "uniqueFallbackKeys": unique_fallback_keys,
        "multiFallbackBuckets": len(multi_fallback),
        "minDPReps": min_dp_reps,
        "maxDPReps": max_dp_reps,
        "expectedDPReps": 2269,
        "definitiveKeys": {k: v for k, v in definitive_keys.items()},
        "fallbackKeys": {k: v for k, v in fallback_keys.items()},
        "multiFallbackBuckets_detail": {k: v for k, v in multi_fallback.items()}
    }

    output_file = os.path.join(SCRIPT_DIR, "dp_result.json")
    with open(output_file, "w") as f:
        json.dump(output, f, indent=2)

    print(f"\nOutput: {output_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
