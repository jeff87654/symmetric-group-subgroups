#!/usr/bin/env python3
"""
Phase 2A: Parse Triple Check Bucket/Checkpoint/Result Files

Combines bucket assignments with checkpoint results to extract per-bucket:
- Full list of group indices
- List of representative indices
- List of non-representative indices

Also identifies which buckets contain the hard/difficult groups to exclude
from Phase 2B verification.

Output: tc_bucket_breakdown.json
"""

import re
import os
import json
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEDUPE_DIR = os.path.join(SCRIPT_DIR, "..", "dedupe")
BUCKETS_DIR = os.path.join(DEDUPE_DIR, "buckets")
CHECKPOINTS_DIR = os.path.join(DEDUPE_DIR, "checkpoints")
RESULTS_DIR = os.path.join(DEDUPE_DIR, "results")

# Hard bucket indices to exclude from Phase 2B
DIFFICULT_BUCKET_INDICES = {3943, 3944, 3945, 10687}  # order 2592
HARD_BUCKET_INDICES = {1824, 1825, 1826, 1827, 1828, 1829, 1830, 8999}  # order 10368
EXCLUDED_INDICES = DIFFICULT_BUCKET_INDICES | HARD_BUCKET_INDICES

WORKERS = [
    "dp",
    "2groups",
    "regular_1", "regular_2", "regular_3", "regular_4", "regular_5",
    "regular_6", "regular_7", "regular_8", "regular_9", "regular_10",
]


def parse_bucket_file(filepath):
    """Parse a bucket assignment file. Returns list of (key, indices)."""
    with open(filepath, "r") as f:
        content = f.read()

    buckets = []
    # Match rec(key := "...", indices := [...])
    for m in re.finditer(r'rec\(key\s*:=\s*"([^"]+)",\s*indices\s*:=\s*\[([^\]]+)\]\)', content):
        key = m.group(1)
        indices = [int(x.strip()) for x in m.group(2).split(",") if x.strip()]
        buckets.append({"key": key, "indices": indices})

    return buckets


def parse_checkpoint_file(filepath):
    """Parse a checkpoint file. Returns list of (bucket_num, input_size, output_size, reps)."""
    with open(filepath, "r") as f:
        content = f.read()

    checkpoints = []
    # Match: # Bucket N: M -> K reps: [ idx1, idx2, ... ]
    for m in re.finditer(r'# Bucket (\d+): (\d+) -> (\d+) reps: \[([^\]]*)\]', content):
        bucket_num = int(m.group(1))
        input_size = int(m.group(2))
        output_size = int(m.group(3))
        rep_text = m.group(4).strip()
        if rep_text:
            reps = [int(x.strip()) for x in rep_text.split(",") if x.strip()]
        else:
            reps = []
        checkpoints.append({
            "bucket_num": bucket_num,
            "input_size": input_size,
            "output_size": output_size,
            "reps": reps
        })

    return checkpoints


def parse_result_file(filepath):
    """Parse a result file. Returns list of representative indices."""
    with open(filepath, "r") as f:
        content = f.read()

    # Match RESULT_REPS_... := [ ... ];
    m = re.search(r'RESULT_REPS_\w+\s*:=\s*\[([\s\S]*?)\];', content)
    if not m:
        return []

    rep_text = m.group(1)
    reps = [int(x.strip()) for x in rep_text.split(",") if x.strip()]
    return reps


def main():
    print("Phase 2A: Parse Triple Check Bucket/Checkpoint/Result Files")
    print()

    all_worker_data = {}
    total_buckets = 0
    total_groups = 0
    total_reps = 0
    total_non_reps = 0

    # Track which worker/bucket contains the hard/difficult groups
    excluded_bucket_info = {}

    for worker in WORKERS:
        bucket_file = os.path.join(BUCKETS_DIR, f"buckets_{worker}.g")
        checkpoint_file = os.path.join(CHECKPOINTS_DIR, f"checkpoint_{worker}.g")
        result_file = os.path.join(RESULTS_DIR, f"result_{worker}.g")

        if not os.path.exists(bucket_file):
            print(f"WARNING: Missing {bucket_file}")
            continue

        buckets = parse_bucket_file(bucket_file)
        checkpoints = parse_checkpoint_file(checkpoint_file)
        result_reps = parse_result_file(result_file)

        # Match buckets with checkpoints by position
        worker_buckets = []
        for i, bucket in enumerate(buckets):
            checkpoint = checkpoints[i] if i < len(checkpoints) else None

            reps = checkpoint["reps"] if checkpoint else []
            non_reps = [idx for idx in bucket["indices"] if idx not in set(reps)]

            # Check if this bucket contains any excluded groups
            bucket_excluded = set(bucket["indices"]) & EXCLUDED_INDICES
            has_excluded = len(bucket_excluded) > 0

            bkt_data = {
                "bucket_num": i + 1,
                "key": bucket["key"],
                "indices": bucket["indices"],
                "size": len(bucket["indices"]),
                "reps": reps,
                "non_reps": non_reps,
                "num_reps": len(reps),
                "has_excluded": has_excluded,
                "excluded_indices": sorted(bucket_excluded) if has_excluded else []
            }
            worker_buckets.append(bkt_data)

            if has_excluded:
                excluded_bucket_info[f"{worker}_bucket_{i+1}"] = {
                    "worker": worker,
                    "bucket_num": i + 1,
                    "key": bucket["key"],
                    "all_indices": bucket["indices"],
                    "excluded_indices": sorted(bucket_excluded),
                    "reps": reps
                }

            total_groups += len(bucket["indices"])
            total_reps += len(reps)
            total_non_reps += len(non_reps)

        total_buckets += len(worker_buckets)

        # Verify result reps match checkpoint reps
        checkpoint_all_reps = []
        for c in checkpoints:
            checkpoint_all_reps.extend(c["reps"])

        if sorted(checkpoint_all_reps) != sorted(result_reps):
            print(f"WARNING: {worker} - checkpoint reps ({len(checkpoint_all_reps)}) "
                  f"!= result reps ({len(result_reps)})")
        else:
            print(f"{worker}: {len(buckets)} buckets, {sum(len(b['indices']) for b in buckets)} groups, "
                  f"{len(result_reps)} reps - MATCH")

        all_worker_data[worker] = {
            "num_buckets": len(worker_buckets),
            "num_groups": sum(len(b["indices"]) for b in buckets),
            "num_reps": len(result_reps),
            "buckets": worker_buckets
        }

    print()
    print(f"Total: {total_buckets} buckets, {total_groups} groups, {total_reps} reps, {total_non_reps} non-reps")
    print()

    # Categorize for Phase 2B
    # Non-DP buckets = all regular_* + 2groups (excluding DP)
    non_dp_buckets = []
    dp_buckets = []
    for worker, data in all_worker_data.items():
        for bkt in data["buckets"]:
            if worker == "dp":
                dp_buckets.append({**bkt, "worker": worker})
            else:
                non_dp_buckets.append({**bkt, "worker": worker})

    # Separate excluded vs verifiable non-DP buckets
    verifiable_non_dp = [b for b in non_dp_buckets if not b["has_excluded"]]
    excluded_non_dp = [b for b in non_dp_buckets if b["has_excluded"]]

    print(f"DP buckets: {len(dp_buckets)} ({sum(b['size'] for b in dp_buckets)} groups, "
          f"{sum(b['num_reps'] for b in dp_buckets)} reps)")
    print(f"Non-DP buckets (verifiable): {len(verifiable_non_dp)} "
          f"({sum(b['size'] for b in verifiable_non_dp)} groups, "
          f"{sum(b['num_reps'] for b in verifiable_non_dp)} reps)")
    print(f"Non-DP buckets (excluded/hard): {len(excluded_non_dp)} "
          f"({sum(b['size'] for b in excluded_non_dp)} groups)")

    if excluded_bucket_info:
        print("\nExcluded bucket details:")
        for name, info in excluded_bucket_info.items():
            print(f"  {name}: {info['key'][:80]}...")
            print(f"    All indices: {info['all_indices']}")
            print(f"    Excluded indices: {info['excluded_indices']}")
            print(f"    Reps: {info['reps']}")

    # Split verifiable non-DP buckets for Phase 2B workers
    # regular buckets go to 6 workers, 2group buckets to 1 WSL worker
    regular_verify = [b for b in verifiable_non_dp if b["worker"].startswith("regular")]
    twogroup_verify = [b for b in verifiable_non_dp if b["worker"] == "2groups"]

    # Multi-group regular buckets (need actual verification, not just singletons)
    multi_regular = [b for b in regular_verify if b["size"] > 1]
    singleton_regular = [b for b in regular_verify if b["size"] == 1]
    multi_2group = [b for b in twogroup_verify if b["size"] > 1]
    singleton_2group = [b for b in twogroup_verify if b["size"] == 1]

    print(f"\nPhase 2B verification needed:")
    print(f"  Regular multi-group buckets: {len(multi_regular)} "
          f"({sum(b['size'] for b in multi_regular)} groups, "
          f"{sum(b['num_reps'] for b in multi_regular)} reps)")
    print(f"  Regular singletons (trivial): {len(singleton_regular)}")
    print(f"  2-group multi-group buckets: {len(multi_2group)} "
          f"({sum(b['size'] for b in multi_2group)} groups, "
          f"{sum(b['num_reps'] for b in multi_2group)} reps)")
    print(f"  2-group singletons (trivial): {len(singleton_2group)}")

    # Summary of expected rep counts
    dp_reps = sum(b['num_reps'] for b in dp_buckets)
    regular_reps = sum(b['num_reps'] for b in non_dp_buckets if b['worker'].startswith('regular'))
    twogroup_reps = sum(b['num_reps'] for b in non_dp_buckets if b['worker'] == '2groups')

    # Count excluded bucket reps
    excluded_reps = 0
    for info in excluded_bucket_info.values():
        excluded_reps += len(info["reps"])

    print(f"\nExpected rep breakdown:")
    print(f"  DP: {dp_reps}")
    print(f"  Regular (all): {regular_reps}")
    print(f"  2-groups: {twogroup_reps}")
    print(f"  Sum: {dp_reps + regular_reps + twogroup_reps}")
    print(f"  Expected total: 3164")

    # Write output
    output = {
        "totalBuckets": total_buckets,
        "totalGroups": total_groups,
        "totalReps": total_reps,
        "workerData": all_worker_data,
        "excludedBucketInfo": excluded_bucket_info,
        "summary": {
            "dpReps": dp_reps,
            "regularReps": regular_reps,
            "twogroupReps": twogroup_reps,
            "total": dp_reps + regular_reps + twogroup_reps,
            "numVerifiableRegularMulti": len(multi_regular),
            "numVerifiable2groupMulti": len(multi_2group),
            "numSingletonRegular": len(singleton_regular),
            "numSingleton2group": len(singleton_2group)
        }
    }

    output_file = os.path.join(SCRIPT_DIR, "tc_bucket_breakdown.json")
    with open(output_file, "w") as f:
        json.dump(output, f, indent=2)

    print(f"\nOutput: {output_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
