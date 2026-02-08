#!/usr/bin/env python3
"""
Merge worker outputs into final result files.
"""

import re
import sys
from pathlib import Path
from datetime import datetime
from collections import defaultdict

# Paths
BASE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups")
TRIPLE_CHECK_DIR = BASE_DIR / "triple_check"
CHECKPOINTS_DIR = TRIPLE_CHECK_DIR / "checkpoints"

# Output files
IDGROUPS_OUTPUT = BASE_DIR / "conjugacy_cache" / "s14_idgroups.g"
LARGE_OUTPUT = BASE_DIR / "conjugacy_cache" / "s14_large_invariants.g"

NUM_WORKERS = 8


def parse_idgroups_file(filepath):
    """Parse IdGroup entries from a worker file"""
    idgroups = []
    with open(filepath, 'r') as f:
        for line in f:
            # Match entries like: "  \"[720, 409]\",  # idx=123"
            match = re.search(r'"(\[(\d+),\s*(\d+)\])"', line)
            if match:
                idgroup_str = match.group(1)
                order = int(match.group(2))
                id_num = int(match.group(3))
                # Extract original index if present
                idx_match = re.search(r'idx=(\d+)', line)
                orig_idx = int(idx_match.group(1)) if idx_match else None
                idgroups.append({
                    'string': idgroup_str,
                    'order': order,
                    'id': id_num,
                    'originalIndex': orig_idx
                })
    return idgroups


def parse_large_groups_file(filepath):
    """Parse large group records from a worker file"""
    content = open(filepath, 'r').read()

    # Find the list content
    match = re.search(r'S14_LARGE_W\d+ := \[(.*?)\];', content, re.DOTALL)
    if not match:
        print(f"Warning: Could not find records in {filepath}")
        return []

    list_content = match.group(1)

    # Parse individual records - only match top-level rec(
    # Look for "rec(" at the start of a line (after whitespace)
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
                # End of record
                rec_str = '\n'.join(current_record)
                # Remove trailing comma if present
                rec_str = rec_str.rstrip().rstrip(',')
                records.append(rec_str)
                current_record = []
                in_record = False
                depth = 0

    return records


def extract_original_index(rec_str):
    """Extract originalIndex from a record string"""
    match = re.search(r'originalIndex\s*:=\s*(\d+)', rec_str)
    return int(match.group(1)) if match else None


def main():
    print(f"S14 Triple Check - Merging results")
    print(f"=" * 50)
    print(f"Started: {datetime.now()}")

    # Collect all IdGroups
    all_idgroups = []
    idgroup_counts = {}

    for worker_id in range(1, NUM_WORKERS + 1):
        filepath = CHECKPOINTS_DIR / f"worker_{worker_id}_idgroups.g"
        if not filepath.exists():
            print(f"Warning: Missing {filepath}")
            continue
        idgroups = parse_idgroups_file(filepath)
        idgroup_counts[worker_id] = len(idgroups)
        all_idgroups.extend(idgroups)
        print(f"Worker {worker_id}: {len(idgroups)} IdGroups")

    # Deduplicate IdGroups (keep unique [order, id] pairs)
    seen = set()
    unique_idgroups = []
    for idg in all_idgroups:
        key = (idg['order'], idg['id'])
        if key not in seen:
            seen.add(key)
            unique_idgroups.append(idg)

    print(f"\nTotal IdGroups: {len(all_idgroups)}")
    print(f"Unique IdGroups: {len(unique_idgroups)}")
    print(f"Duplicates removed: {len(all_idgroups) - len(unique_idgroups)}")

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

    # Sort large groups by originalIndex for consistency
    large_with_idx = [(extract_original_index(r), r) for r in all_large]
    large_with_idx.sort(key=lambda x: x[0] if x[0] else 0)

    # Write IdGroups output
    print(f"\nWriting IdGroups to {IDGROUPS_OUTPUT}")
    with open(IDGROUPS_OUTPUT, 'w') as f:
        f.write(f"# S14 IdGroups from Triple Check\n")
        f.write(f"# Generated: {datetime.now()}\n")
        f.write(f"# Total unique types: {len(unique_idgroups)}\n")
        f.write(f"S14_TC_IDGROUPS := [\n")

        # Sort by order then id for cleaner output
        unique_idgroups.sort(key=lambda x: (x['order'], x['id']))

        for i, idg in enumerate(unique_idgroups):
            comma = "," if i < len(unique_idgroups) - 1 else ""
            f.write(f"  \"{idg['string']}\"{comma}\n")

        f.write(f"];\n")

    # Write large groups output
    print(f"Writing large groups to {LARGE_OUTPUT}")
    with open(LARGE_OUTPUT, 'w') as f:
        f.write(f"# S14 Large Groups with Invariants from Triple Check\n")
        f.write(f"# Generated: {datetime.now()}\n")
        f.write(f"# Total groups: {len(all_large)}\n")
        f.write(f"S14_TC_LARGE := [\n")

        for i, (orig_idx, rec_str) in enumerate(large_with_idx):
            # Update combinedIndex and index to be sequential
            rec_str = re.sub(r'combinedIndex := \d+', f'combinedIndex := {i+1}', rec_str)
            rec_str = re.sub(r'index := \d+', f'index := {i+1}', rec_str)
            comma = "," if i < len(large_with_idx) - 1 else ""
            f.write(f"{rec_str}{comma}\n")

        f.write(f"];\n")

    # Summary
    print(f"\n{'=' * 50}")
    print(f"SUMMARY")
    print(f"{'=' * 50}")
    print(f"Unique IdGroup types: {len(unique_idgroups)}")
    print(f"Large groups: {len(all_large)}")
    print(f"TOTAL: {len(unique_idgroups) + len(all_large)}")
    print(f"\nExpected A174511(14) = 7,755")

    # Verify worker coverage
    total_processed = sum(idgroup_counts.values()) + sum(large_counts.values())
    print(f"\nTotal groups processed: {total_processed}")
    print(f"Expected: 75,154")

    if total_processed != 75154:
        print(f"WARNING: Count mismatch! Missing {75154 - total_processed} groups")
    else:
        print(f"Coverage check: PASSED")

    return 0


if __name__ == "__main__":
    sys.exit(main())
