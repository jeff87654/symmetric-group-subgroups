#!/usr/bin/env python3
"""
Merge worker outputs into final S16 result files.

Produces:
  - conjugacy_cache/s16_idgroup_map.g  (index → [order, id] for IdGroup-compatible groups)
  - conjugacy_cache/s16_large_invariants.g  (large group records with invariants)
"""

import re
import sys
from pathlib import Path
from datetime import datetime
from collections import defaultdict

# Paths
BASE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups")
S16_PROCESSING_DIR = BASE_DIR / "s16_processing"
CHECKPOINTS_DIR = S16_PROCESSING_DIR / "checkpoints"

# Output files
IDGROUPS_OUTPUT = BASE_DIR / "conjugacy_cache" / "s16_idgroup_map.g"
LARGE_OUTPUT = BASE_DIR / "conjugacy_cache" / "s16_large_invariants.g"

NUM_WORKERS = 8
EXPECTED_TOTAL = 686165


def parse_idgroups_file(filepath):
    """Parse IdGroup map entries from a worker file.
    Format: S16_IDGROUP_MAP[index] := [order, id];
    """
    entries = []
    pattern = re.compile(r'S16_IDGROUP_MAP\[(\d+)\]\s*:=\s*\[(\d+),\s*(\d+)\];')
    with open(filepath, 'r') as f:
        for line in f:
            match = pattern.search(line)
            if match:
                idx = int(match.group(1))
                order = int(match.group(2))
                id_num = int(match.group(3))
                entries.append({
                    'index': idx,
                    'order': order,
                    'id': id_num,
                })
    return entries


def parse_large_groups_file(filepath):
    """Parse large group records from a worker file"""
    content = open(filepath, 'r').read()

    # Find the list content
    match = re.search(r'S16_LARGE_W\d+ := \[(.*?)\];', content, re.DOTALL)
    if not match:
        print(f"Warning: Could not find records in {filepath}")
        return []

    list_content = match.group(1)

    # Parse individual records using parenthesis depth tracking
    records = []
    lines = list_content.split('\n')
    current_record = []
    depth = 0
    in_record = False

    for line in lines:
        stripped = line.strip()
        if stripped.startswith('rec(') and depth == 0:
            in_record = True
            current_record = [line]
            depth = line.count('(') - line.count(')')
        elif in_record:
            current_record.append(line)
            depth += line.count('(') - line.count(')')
            if depth <= 0:
                rec_str = '\n'.join(current_record)
                rec_str = rec_str.rstrip().rstrip(',')
                records.append(rec_str)
                current_record = []
                in_record = False
                depth = 0

    return records


def extract_index(rec_str):
    """Extract index from a record string"""
    match = re.search(r'\bindex\s*:=\s*(\d+)', rec_str)
    return int(match.group(1)) if match else None


def extract_isomorphic_to(rec_str):
    """Extract isomorphicTo field if present"""
    match = re.search(r'isomorphicTo\s*:=\s*(\d+)', rec_str)
    return int(match.group(1)) if match else None


def main():
    print(f"S16 Processing - Merging results")
    print(f"=" * 60)
    print(f"Started: {datetime.now()}")

    # Collect all IdGroups
    all_idgroups = []
    idgroup_counts = {}

    for worker_id in range(1, NUM_WORKERS + 1):
        filepath = CHECKPOINTS_DIR / f"worker_{worker_id}_idgroups.g"
        if not filepath.exists():
            print(f"Warning: Missing {filepath}")
            continue
        entries = parse_idgroups_file(filepath)
        idgroup_counts[worker_id] = len(entries)
        all_idgroups.extend(entries)
        print(f"Worker {worker_id}: {len(entries)} IdGroups")

    # Check for duplicate indices
    idx_set = set()
    dup_indices = []
    for entry in all_idgroups:
        if entry['index'] in idx_set:
            dup_indices.append(entry['index'])
        idx_set.add(entry['index'])

    if dup_indices:
        print(f"WARNING: {len(dup_indices)} duplicate indices found!")
    else:
        print(f"No duplicate IdGroup indices (good)")

    # Count unique [order, id] types
    unique_types = set()
    for entry in all_idgroups:
        unique_types.add((entry['order'], entry['id']))

    print(f"\nTotal IdGroup entries: {len(all_idgroups)}")
    print(f"Unique IdGroup types: {len(unique_types)}")

    # Collect all large groups
    all_large = []
    large_counts = {}

    for worker_id in range(1, NUM_WORKERS + 1):
        filepath = CHECKPOINTS_DIR / f"worker_{worker_id}_large.g"
        if not filepath.exists():
            print(f"Warning: Missing {filepath}")
            continue
        records = parse_large_groups_file(filepath)
        large_counts[worker_id] = len(records)
        all_large.extend(records)
        print(f"Worker {worker_id}: {len(records)} large groups")

    print(f"\nTotal large groups: {len(all_large)}")

    # Check for duplicate indices in large groups
    large_idx_set = set()
    large_dup_indices = []
    for rec_str in all_large:
        idx = extract_index(rec_str)
        if idx is not None:
            if idx in large_idx_set:
                large_dup_indices.append(idx)
            large_idx_set.add(idx)

    if large_dup_indices:
        print(f"WARNING: {len(large_dup_indices)} duplicate large group indices!")
    else:
        print(f"No duplicate large group indices (good)")

    # Check no index appears in both idgroup and large
    overlap = idx_set & large_idx_set
    if overlap:
        print(f"WARNING: {len(overlap)} indices appear in BOTH idgroup and large!")
    else:
        print(f"No overlap between idgroup and large indices (good)")

    # Count isomorphicTo entries
    iso_count = 0
    for rec_str in all_large:
        if extract_isomorphic_to(rec_str) is not None:
            iso_count += 1
    print(f"Large groups with isomorphicTo: {iso_count}")

    # Sort large groups by index
    large_with_idx = [(extract_index(r), r) for r in all_large]
    large_with_idx.sort(key=lambda x: x[0] if x[0] else 0)

    # Write IdGroup map output
    print(f"\nWriting IdGroup map to {IDGROUPS_OUTPUT}")
    # Sort by index for writing
    all_idgroups.sort(key=lambda x: x['index'])

    with open(IDGROUPS_OUTPUT, 'w') as f:
        f.write(f"# S16 IdGroup Map\n")
        f.write(f"# Generated: {datetime.now()}\n")
        f.write(f"# Total entries: {len(all_idgroups)}\n")
        f.write(f"# Unique [order, id] types: {len(unique_types)}\n")
        f.write(f"S16_IDGROUP_MAP := [];\n")

        for entry in all_idgroups:
            f.write(f"S16_IDGROUP_MAP[{entry['index']}] := [{entry['order']}, {entry['id']}];\n")

    # Write large groups output
    print(f"Writing large groups to {LARGE_OUTPUT}")
    with open(LARGE_OUTPUT, 'w') as f:
        f.write(f"# S16 Large Groups with Invariants\n")
        f.write(f"# Generated: {datetime.now()}\n")
        f.write(f"# Total groups: {len(all_large)}\n")
        f.write(f"# Groups with isomorphicTo: {iso_count}\n")
        f.write(f"S16_LARGE := [\n")

        for i, (idx, rec_str) in enumerate(large_with_idx):
            comma = "," if i < len(large_with_idx) - 1 else ""
            f.write(f"{rec_str}{comma}\n")

        f.write(f"];\n")

    # Summary
    total_processed = len(all_idgroups) + len(all_large)
    print(f"\n{'=' * 60}")
    print(f"SUMMARY")
    print(f"{'=' * 60}")
    print(f"IdGroup entries: {len(all_idgroups)}")
    print(f"Unique IdGroup types: {len(unique_types)}")
    print(f"Large groups: {len(all_large)}")
    print(f"Large with isomorphicTo: {iso_count}")
    print(f"Total processed: {total_processed}")
    print(f"Expected: {EXPECTED_TOTAL:,}")

    if total_processed != EXPECTED_TOTAL:
        print(f"WARNING: Count mismatch! Expected {EXPECTED_TOTAL}, got {total_processed} (diff={EXPECTED_TOTAL - total_processed})")
    else:
        print(f"Coverage check: PASSED")

    # Worker breakdown
    print(f"\nWorker breakdown:")
    print(f"  {'Worker':<8} {'IdGroup':<10} {'Large':<10} {'Total':<10}")
    for wid in range(1, NUM_WORKERS + 1):
        idg = idgroup_counts.get(wid, 0)
        lg = large_counts.get(wid, 0)
        print(f"  {wid:<8} {idg:<10} {lg:<10} {idg+lg:<10}")

    print(f"\nOutput files:")
    print(f"  {IDGROUPS_OUTPUT}")
    print(f"  {LARGE_OUTPUT}")
    print(f"\nCompleted: {datetime.now()}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
