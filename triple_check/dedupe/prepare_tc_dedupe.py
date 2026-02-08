#!/usr/bin/env python3
"""
Prepare Triple-Check Deduplication: Parse invariants, create buckets, assign workers.

Creates:
- Bucket assignment files for 12 workers (1 DP + 1 2-group + 10 regular)
- tracking.json with full coverage verification
- Worker GAP scripts from templates

Worker Distribution:
- DP worker: All-DP buckets (CompareByFactorsV3 fast path)
- 2-group worker: Non-all-DP buckets with power-of-2 orders (WSL + ANUPQ)
- Regular workers 1-10: Everything else (CompareByFactorsV3 + IsomorphismGroups)
- Difficult bucket [2592,162,42,3,[2,2,2,2]]: Skipped, 1 rep included in final count
"""

import re
import json
import os
from collections import defaultdict
from pathlib import Path
from datetime import datetime

# Paths
BASE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups\triple_check")
DEDUPE_DIR = BASE_DIR / "dedupe"
INVARIANTS_FILE = BASE_DIR / "conjugacy_cache" / "s14_large_invariants_clean.g"

# Output directories
BUCKETS_DIR = DEDUPE_DIR / "buckets"

# Number of regular workers
NUM_REGULAR_WORKERS = 10

# 2-group orders (powers of 2 requiring ANUPQ)
TWO_GROUP_ORDERS = {512, 1024, 2048}

# Difficult bucket sigKey+histogram (all isomorphic, skip with 1 rep)
DIFFICULT_SIGKEY = "[ 2592, 162, 42, 3, [ 2, 2, 2, 2 ] ]"
DIFFICULT_HISTOGRAM = "[ [ 1, 1 ], [ 2, 243 ], [ 3, 80 ], [ 4, 972 ], [ 6, 1296 ] ]"


def extract_bracket_expr(text, start_pos):
    """Extract a balanced bracket expression from text starting at start_pos.
    start_pos should point to the opening '['.
    Returns the full balanced expression including outer brackets."""
    if text[start_pos] != '[':
        return None
    depth = 0
    i = start_pos
    while i < len(text):
        if text[i] == '[':
            depth += 1
        elif text[i] == ']':
            depth -= 1
            if depth == 0:
                return text[start_pos:i + 1]
        i += 1
    return None


def parse_clean_file(filepath):
    """Parse s14_large_invariants_clean.g to extract all records."""
    print(f"Parsing {filepath}...")

    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    records = []

    # Split into individual records
    # Each record starts with "rec(" and ends with "),"  or the last one with ")\n];"
    rec_starts = [m.start() for m in re.finditer(r'^rec\(', content, re.MULTILINE)]

    for i, start in enumerate(rec_starts):
        if i + 1 < len(rec_starts):
            end = rec_starts[i + 1]
        else:
            end = len(content)

        rec_text = content[start:end]
        rec = {}

        # Extract index
        m = re.search(r'index\s*:=\s*(\d+)', rec_text)
        if m:
            rec['index'] = int(m.group(1))

        # Extract sigKey using bracket-aware extraction
        m = re.search(r'sigKey\s*:=\s*', rec_text)
        if m:
            bracket_start = m.end()
            sigkey_str = extract_bracket_expr(rec_text, bracket_start)
            if sigkey_str:
                rec['sigKey_str'] = sigkey_str
                # Also parse for order extraction
                parts = sigkey_str.strip('[] ').split(',')
                rec['order'] = int(parts[0].strip())

        # Extract order explicitly
        m = re.search(r'^\s*order\s*:=\s*(\d+)', rec_text, re.MULTILINE)
        if m:
            rec['order'] = int(m.group(1))

        # Extract isDirectProduct
        m = re.search(r'isDirectProduct\s*:=\s*(true|false)', rec_text)
        if m:
            rec['isDirectProduct'] = m.group(1) == 'true'

        # Extract histogram using bracket-aware extraction
        m = re.search(r'histogram\s*:=\s*', rec_text)
        if m:
            bracket_start = m.end()
            hist_str = extract_bracket_expr(rec_text, bracket_start)
            if hist_str:
                # Normalize: remove line continuations and extra whitespace
                hist_str = hist_str.replace('\\\n', '').replace('\n', ' ')
                hist_str = re.sub(r'\s+', ' ', hist_str).strip()
                rec['histogram_str'] = hist_str

        # Check for factorGens
        rec['hasFactorGens'] = 'factorGens' in rec_text

        if 'index' in rec:
            records.append(rec)

    print(f"  Parsed {len(records)} records")
    return records


def create_bucket_key(rec):
    """Create bucket key from sigKey + histogram (normalized)."""
    sigkey = rec.get('sigKey_str', '[]')
    hist = rec.get('histogram_str', '[]')
    return f"{sigkey}|{hist}"


def is_power_of_2(n):
    """Check if n is a power of 2."""
    return n > 0 and (n & (n - 1)) == 0


def assign_buckets(records):
    """Assign groups to buckets and categorize them."""
    print("\nAssigning groups to buckets...")

    # Group by bucket key
    buckets = defaultdict(list)
    rec_by_index = {}
    for rec in records:
        key = create_bucket_key(rec)
        buckets[key].append(rec['index'])
        rec_by_index[rec['index']] = rec

    print(f"  Total buckets: {len(buckets)}")

    # Count singletons
    singletons = sum(1 for v in buckets.values() if len(v) == 1)
    print(f"  Singletons (auto-representative): {singletons}")

    # Categorize buckets
    dp_buckets = {}
    two_group_buckets = {}
    regular_buckets = {}
    difficult_bucket_indices = None
    difficult_first_index = None

    for key, indices in buckets.items():
        sample = rec_by_index[indices[0]]

        # Check for difficult bucket
        is_difficult = (
            sample.get('sigKey_str', '') == DIFFICULT_SIGKEY and
            sample.get('histogram_str', '') == DIFFICULT_HISTOGRAM and
            not sample.get('isDirectProduct', True)
        )

        if is_difficult:
            difficult_bucket_indices = sorted(indices)
            difficult_first_index = difficult_bucket_indices[0]
            print(f"  DIFFICULT bucket found: {len(indices)} groups, indices={indices}")
            print(f"    Will use first index {difficult_first_index} as representative")
            continue

        # Check if ALL groups in bucket are direct products
        all_dp = all(rec_by_index[idx].get('isDirectProduct', False) for idx in indices)

        # Check if order is a power of 2
        order = sample.get('order', 0)
        is_2group = is_power_of_2(order) and order in TWO_GROUP_ORDERS

        if all_dp:
            dp_buckets[key] = indices
        elif is_2group:
            two_group_buckets[key] = indices
        else:
            regular_buckets[key] = indices

    dp_groups = sum(len(v) for v in dp_buckets.values())
    two_groups = sum(len(v) for v in two_group_buckets.values())
    reg_groups = sum(len(v) for v in regular_buckets.values())
    diff_groups = len(difficult_bucket_indices) if difficult_bucket_indices else 0

    print(f"\n  Category summary:")
    print(f"    DP buckets:        {len(dp_buckets):>5} buckets, {dp_groups:>6} groups")
    print(f"    2-group buckets:   {len(two_group_buckets):>5} buckets, {two_groups:>6} groups")
    print(f"    Regular buckets:   {len(regular_buckets):>5} buckets, {reg_groups:>6} groups")
    print(f"    Difficult (skip):  {'1':>5} bucket,  {diff_groups:>5} groups")
    print(f"    Total:             {len(buckets):>5} buckets, {dp_groups + two_groups + reg_groups + diff_groups:>6} groups")

    return dp_buckets, two_group_buckets, regular_buckets, difficult_bucket_indices, difficult_first_index, rec_by_index


def greedy_bin_pack(buckets, num_bins, rec_by_index):
    """Distribute buckets across bins using greedy bin packing.
    Difficulty = n (linear, since most groups in a bucket are isomorphic)."""
    print(f"\n  Distributing {len(buckets)} regular buckets across {num_bins} workers...")

    # Sort buckets by size (descending) for greedy packing
    bucket_items = [(key, indices, len(indices))
                    for key, indices in buckets.items()]
    bucket_items.sort(key=lambda x: x[2], reverse=True)

    # Initialize bins
    bins = [[] for _ in range(num_bins)]
    bin_sizes = [0] * num_bins

    # Greedy assignment - put largest bucket in least-full bin
    for key, indices, size in bucket_items:
        min_idx = bin_sizes.index(min(bin_sizes))
        bins[min_idx].append((key, indices))
        bin_sizes[min_idx] += size

    # Report distribution
    for i, (b, s) in enumerate(zip(bins, bin_sizes)):
        n_buckets = len(b)
        print(f"    Regular worker {i+1}: {n_buckets:>4} buckets, {s:>5} groups")

    return bins


def generate_bucket_file(filepath, bucket_assignments, rec_by_index):
    """Generate a GAP file with bucket assignments."""
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(f"# Bucket assignments for TC dedupe\n")
        f.write(f"# Generated: {datetime.now().isoformat()}\n")
        f.write(f"# Buckets: {len(bucket_assignments)}\n")
        total_groups = sum(len(indices) for _, indices in bucket_assignments)
        f.write(f"# Groups: {total_groups}\n\n")

        f.write("BUCKET_ASSIGNMENTS := [\n")

        for key, indices in bucket_assignments:
            sample = rec_by_index.get(indices[0], {})
            order = sample.get('order', '?')
            sigkey = sample.get('sigKey_str', '?')
            is_dp = sample.get('isDirectProduct', False)

            f.write(f"  # Order {order}, sigKey={sigkey}, {len(indices)} groups, DP={is_dp}\n")
            f.write(f"  rec(key := \"{key}\", indices := {indices}),\n")

        f.write("];\n")


def generate_worker_script(worker_type, worker_num, bucket_file_name, result_var_name):
    """Generate a worker GAP script that loads common library and processes buckets."""
    base_cygwin = "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/triple_check"
    base_wsl = "/mnt/c/Users/jeffr/Downloads/Symmetric Groups/triple_check"

    if worker_type == "2groups":
        base = base_wsl
        dedup_func = "DeduplicateBucket2Groups"
    else:
        base = base_cygwin
        dedup_func = "DeduplicateBucketDP" if worker_type == "dp" else "DeduplicateBucket"

    common_path = f"{base}/dedupe/tc_dedupe_common.g"
    data_path = f"{base}/conjugacy_cache/s14_large_invariants_clean.g"
    bucket_path = f"{base}/dedupe/buckets/{bucket_file_name}"
    result_path = f"{base}/dedupe/results/result_{worker_type}"
    if worker_type == "regular":
        result_path += f"_{worker_num}"
    result_path += ".g"
    checkpoint_path = f"{base}/dedupe/checkpoints/checkpoint_{worker_type}"
    if worker_type == "regular":
        checkpoint_path += f"_{worker_num}"
    checkpoint_path += ".g"

    worker_name = worker_type
    if worker_type == "regular":
        worker_name = f"regular_{worker_num}"

    script = f'''# Triple-Check Dedupe - Worker {worker_name}
# Auto-generated by prepare_tc_dedupe.py
# Type: {worker_type}

SetInfoLevel(InfoWarning, 0);;
'''

    if worker_type == "2groups":
        script += '''
Print("Loading ANUPQ package...\\n");
LoadPackage("anupq");;
'''

    script += f'''
# Define S14_TC before loading data
S14_TC := "S14_TC";;

Print("Loading shared library...\\n");
Read("{common_path}");

Print("Loading group data...\\n");
Read("{data_path}");
DATA := S14_TC_LARGE;;

Print("Loading bucket assignments...\\n");
Read("{bucket_path}");

# Build index lookup for data records
DATA_BY_INDEX := rec();;
for r in DATA do
    DATA_BY_INDEX.(r.index) := r;
od;
Print("Built index lookup for ", Length(DATA), " records\\n");

# Initialize checkpoint file
PrintTo("{checkpoint_path}",
        "# Worker {worker_name} checkpoint file\\n",
        "# Started: ", String(Runtime()), "\\n\\n");

totalReps := [];;
totalGroupsProcessed := 0;;
startTime := Runtime();;

Print("Starting deduplication ({worker_type})...\\n");
Print("Processing ", Length(BUCKET_ASSIGNMENTS), " buckets\\n\\n");

for bucketNum in [1..Length(BUCKET_ASSIGNMENTS)] do
    bucket := BUCKET_ASSIGNMENTS[bucketNum];
    LogProgress(Concatenation("Bucket ", String(bucketNum), "/",
        String(Length(BUCKET_ASSIGNMENTS)), ": ",
        String(Length(bucket.indices)), " groups, key=",
        bucket.key{{[1..Minimum(60, Length(bucket.key))]}}));

    reps := {dedup_func}(bucket.indices, DATA_BY_INDEX);

    totalGroupsProcessed := totalGroupsProcessed + Length(bucket.indices);
    Append(totalReps, reps);

    LogProgress(Concatenation("  Bucket ", String(bucketNum), " complete: ",
        String(Length(bucket.indices)), " -> ", String(Length(reps)), " reps"));
    LogProgress(Concatenation("  Running total: ", String(Length(totalReps)),
        " reps from ", String(bucketNum), " buckets (",
        String(totalGroupsProcessed), " groups processed)"));

    # Checkpoint after each bucket
    AppendTo("{checkpoint_path}",
             "# Bucket ", bucketNum, ": ", Length(bucket.indices), " -> ",
             Length(reps), " reps: ", reps, "\\n");
od;

# Write final results
elapsed := Runtime() - startTime;;
PrintTo("{result_path}",
        "# Worker {worker_name} results\\n",
        "# Completed: ", String(Runtime()), "ms\\n",
        "# Elapsed: ", String(elapsed), "ms\\n",
        "# Total representatives: ", Length(totalReps), "\\n\\n",
        "{result_var_name} := ", totalReps, ";\\n");

Print("\\n=== COMPLETE === Worker {worker_name}: ",
      Length(totalReps), " unique representatives from ",
      totalGroupsProcessed, " groups in ",
      Length(BUCKET_ASSIGNMENTS), " buckets (",
      String(Int(elapsed/1000)), "s)\\n");
QUIT;
'''
    return script


def main():
    # Create directories
    for d in [BUCKETS_DIR, DEDUPE_DIR / "checkpoints", DEDUPE_DIR / "results",
              DEDUPE_DIR / "logs"]:
        d.mkdir(parents=True, exist_ok=True)

    # Parse input
    records = parse_clean_file(INVARIANTS_FILE)

    # Verify record count
    assert len(records) == 10687, f"Expected 10687 records, got {len(records)}"
    print(f"  Verified: {len(records)} records")

    # Verify indices are 1..10687
    indices = sorted(r['index'] for r in records)
    expected_indices = list(range(1, 10688))
    if indices != expected_indices:
        missing = set(expected_indices) - set(indices)
        extra = set(indices) - set(expected_indices)
        print(f"  WARNING: Index mismatch! Missing: {sorted(missing)[:10]}, Extra: {sorted(extra)[:10]}")
    else:
        print(f"  Verified: indices are 1..10687")

    # Assign buckets
    (dp_buckets, two_group_buckets, regular_buckets,
     difficult_indices, difficult_first_index, rec_by_index) = assign_buckets(records)

    # Bin-pack regular buckets across workers
    regular_assignments = greedy_bin_pack(regular_buckets, NUM_REGULAR_WORKERS, rec_by_index)

    # Generate bucket files
    print("\nGenerating bucket files...")

    # DP bucket file
    dp_items = list(dp_buckets.items())
    generate_bucket_file(BUCKETS_DIR / "buckets_dp.g", dp_items, rec_by_index)
    print(f"  Written: buckets_dp.g ({len(dp_items)} buckets)")

    # 2-groups bucket file
    two_group_items = list(two_group_buckets.items())
    generate_bucket_file(BUCKETS_DIR / "buckets_2groups.g", two_group_items, rec_by_index)
    print(f"  Written: buckets_2groups.g ({len(two_group_items)} buckets)")

    # Regular worker bucket files
    for i, assignments in enumerate(regular_assignments):
        generate_bucket_file(
            BUCKETS_DIR / f"buckets_regular_{i+1}.g",
            assignments,
            rec_by_index
        )
        n_groups = sum(len(indices) for _, indices in assignments)
        print(f"  Written: buckets_regular_{i+1}.g ({len(assignments)} buckets, {n_groups} groups)")

    # Generate worker scripts
    print("\nGenerating worker scripts...")

    # DP worker
    script = generate_worker_script("dp", 0, "buckets_dp.g", "RESULT_REPS_DP")
    with open(DEDUPE_DIR / "worker_dp.g", 'w', encoding='utf-8') as f:
        f.write(script)
    print(f"  Written: worker_dp.g")

    # 2-groups worker
    script = generate_worker_script("2groups", 0, "buckets_2groups.g", "RESULT_REPS_2GROUPS")
    with open(DEDUPE_DIR / "worker_2groups.g", 'w', encoding='utf-8') as f:
        f.write(script)
    print(f"  Written: worker_2groups.g")

    # Regular workers
    for i in range(1, NUM_REGULAR_WORKERS + 1):
        script = generate_worker_script("regular", i, f"buckets_regular_{i}.g",
                                        f"RESULT_REPS_REGULAR_{i}")
        with open(DEDUPE_DIR / f"worker_regular_{i}.g", 'w', encoding='utf-8') as f:
            f.write(script)
        print(f"  Written: worker_regular_{i}.g")

    # Generate tracking JSON
    print("\nGenerating tracking file...")

    tracking = {
        "generated": datetime.now().isoformat(),
        "input_file": str(INVARIANTS_FILE),
        "total_groups": len(records),
        "difficult_bucket": {
            "sigKey": DIFFICULT_SIGKEY,
            "indices": difficult_indices,
            "representative": difficult_first_index,
            "count": len(difficult_indices) if difficult_indices else 0,
            "note": "All 4 groups are isomorphic. Include 1 rep in final count."
        },
        "dp_worker": {
            "buckets": len(dp_buckets),
            "groups": sum(len(v) for v in dp_buckets.values()),
            "indices": sorted([idx for indices in dp_buckets.values() for idx in indices])
        },
        "two_group_worker": {
            "buckets": len(two_group_buckets),
            "groups": sum(len(v) for v in two_group_buckets.values()),
            "indices": sorted([idx for indices in two_group_buckets.values() for idx in indices])
        },
        "regular_workers": []
    }

    for i, assignments in enumerate(regular_assignments):
        worker_indices = sorted([idx for _, indices in assignments for idx in indices])
        tracking["regular_workers"].append({
            "worker": i + 1,
            "buckets": len(assignments),
            "groups": sum(len(indices) for _, indices in assignments),
            "indices": worker_indices
        })

    # Verify coverage
    all_assigned = set(tracking["dp_worker"]["indices"])
    all_assigned.update(tracking["two_group_worker"]["indices"])
    for w in tracking["regular_workers"]:
        all_assigned.update(w["indices"])
    if difficult_indices:
        all_assigned.update(difficult_indices)

    tracking["coverage"] = {
        "assigned": len(all_assigned),
        "expected": len(records),
        "complete": len(all_assigned) == len(records),
        "missing": sorted(set(range(1, len(records) + 1)) - all_assigned),
        "worker_assigned": len(all_assigned) - (len(difficult_indices) if difficult_indices else 0),
        "note": f"{len(all_assigned) - (len(difficult_indices) if difficult_indices else 0)} worker-assigned + {len(difficult_indices) if difficult_indices else 0} difficult = {len(all_assigned)} total"
    }

    # Check for overlaps between workers
    dp_set = set(tracking["dp_worker"]["indices"])
    two_set = set(tracking["two_group_worker"]["indices"])
    reg_sets = [set(w["indices"]) for w in tracking["regular_workers"]]
    diff_set = set(difficult_indices) if difficult_indices else set()

    all_sets = [("dp", dp_set), ("2groups", two_set)] + \
               [(f"regular_{i+1}", s) for i, s in enumerate(reg_sets)] + \
               [("difficult", diff_set)]

    overlaps = []
    for i in range(len(all_sets)):
        for j in range(i + 1, len(all_sets)):
            overlap = all_sets[i][1] & all_sets[j][1]
            if overlap:
                overlaps.append(f"{all_sets[i][0]} & {all_sets[j][0]}: {sorted(overlap)[:5]}")

    tracking["overlaps"] = overlaps if overlaps else "NONE (good!)"

    tracking_path = DEDUPE_DIR / "tracking.json"
    with open(tracking_path, 'w', encoding='utf-8') as f:
        json.dump(tracking, f, indent=2)
    print(f"  Written: tracking.json")

    # Summary
    print("\n" + "=" * 60)
    print("PREPARATION COMPLETE")
    print("=" * 60)
    print(f"Total groups: {len(records)}")
    print(f"  DP worker:        {tracking['dp_worker']['groups']:>6} groups in {tracking['dp_worker']['buckets']} buckets")
    print(f"  2-group worker:   {tracking['two_group_worker']['groups']:>6} groups in {tracking['two_group_worker']['buckets']} buckets")
    for w in tracking['regular_workers']:
        print(f"  Regular worker {w['worker']:>2}: {w['groups']:>6} groups in {w['buckets']} buckets")
    if difficult_indices:
        print(f"  Difficult (skip): {len(difficult_indices):>6} groups (1 rep = index {difficult_first_index})")
    print(f"Coverage: {'COMPLETE' if tracking['coverage']['complete'] else 'INCOMPLETE!'}")
    if overlaps:
        print(f"OVERLAP WARNING: {overlaps}")
    else:
        print(f"Overlaps: NONE")
    print()
    print("Next steps:")
    print("  1. Review tc_dedupe_common.g (shared library)")
    print("  2. Run tc_test_validation.g (must pass)")
    print("  3. Run launch_tc_dedupe.py (12 parallel workers)")
    print("  4. Run merge_tc_results.py (collect results)")


if __name__ == "__main__":
    main()
