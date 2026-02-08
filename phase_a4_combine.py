#!/usr/bin/env python3
"""
phase_a4_combine.py - Phase A-4: Combine all Phase A results for Phase B

Merges output from:
  1. Leaf computation results (leaf_results_*.g from Phase A-2)
  2. Non-leaf groups (nonleaves.g from Phase A-1) - S15 subgroups from recursion tree
  3. Direct worker results (intrans_1x14.g, wreath_*.g, primitive_*.g from Phase A-3)

All are written to the standard maxsub_results format expected by Phase B-1.

The key insight: Phase B-1 (phase_b1_s15.py) expects worker output files in
OUTPUT_DIR/{label}.g with format:
    maxsub_results := [rec(gens := [...], inv := [...], source := "..."), ...]

This script converts all sources into that format, updating WORKER_FILES in
phase_b1_s15.py to include all source files.

Output:
  maxsub_output_s15/combined_leaves.g   - merged leaf results
  maxsub_output_s15/nonleaf_maxsub.g    - non-leaf groups in maxsub_results format

These files, together with the existing direct worker outputs (intrans_1x14.g,
wreath_3wr5.g, wreath_5wr3.g, primitive_*.g), provide all input for Phase B-1.

Usage:
  python phase_a4_combine.py
"""

import re
import sys
import time
from pathlib import Path
from datetime import datetime
from collections import defaultdict

BASE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups")
OUTPUT_DIR = BASE_DIR / "maxsub_output_s15"
N = 15


def _match_bracket(text, start):
    """Find the matching ] for [ at position start. Returns index of ] or -1."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == '[':
            depth += 1
        elif text[i] == ']':
            depth -= 1
            if depth == 0:
                return i
    return -1


def count_entries(filepath: Path) -> int:
    """Quick count of rec() entries in a maxsub_results file."""
    if not filepath.exists():
        return 0
    content = filepath.read_text(encoding='utf-8', errors='replace')
    return content.count("rec(gens :=")


def merge_leaf_results() -> tuple:
    """Merge all leaf_results_*.g files into combined_leaves.g.

    Returns (success, total_count).
    """
    # Find all leaf result files
    leaf_files = sorted(OUTPUT_DIR.glob("leaf_results_*.g"))
    if not leaf_files:
        print("  No leaf_results_*.g files found - skipping leaf merge")
        return True, 0

    print(f"  Found {len(leaf_files)} leaf result files:")
    total_entries = 0
    for f in leaf_files:
        count = count_entries(f)
        total_entries += count
        # Check completeness
        content = f.read_text(encoding='utf-8', errors='replace')
        complete = "# Complete:" in content
        status = "OK" if complete else "INCOMPLETE"
        print(f"    {f.name}: {count} entries ({status})")

    # Parse and merge all entries into a single file
    output_file = OUTPUT_DIR / "combined_leaves.g"
    print(f"\n  Merging into {output_file.name}...")

    entry_count = 0
    with open(output_file, 'w') as out:
        out.write(f"# Combined leaf results for S{N}\n")
        out.write(f"# Source files: {len(leaf_files)}\n")
        out.write(f"# Combined: {datetime.now()}\n")
        out.write("maxsub_results := [\n")

        for leaf_file in leaf_files:
            content = leaf_file.read_text(encoding='utf-8', errors='replace')

            # Extract individual rec() entries using bracket-matching
            pos = 0
            file_count = 0
            while pos < len(content):
                rec_start = content.find("rec(gens :=", pos)
                if rec_start == -1:
                    break

                gens_start = content.find("[", rec_start + 11)
                if gens_start == -1:
                    break
                gens_end = _match_bracket(content, gens_start)
                if gens_end == -1:
                    pos = rec_start + 11
                    continue
                gens_str = content[gens_start:gens_end + 1].strip()

                inv_marker = content.find("inv :=", gens_end)
                if inv_marker == -1:
                    break
                inv_start = content.find("[", inv_marker + 6)
                if inv_start == -1:
                    break
                inv_end = _match_bracket(content, inv_start)
                if inv_end == -1:
                    pos = inv_marker + 6
                    continue
                inv_str = content[inv_start:inv_end + 1].strip()

                source_marker = content.find('source :=', inv_end)
                if source_marker == -1:
                    break
                quote1 = content.find('"', source_marker + 9)
                if quote1 == -1:
                    break
                quote2 = content.find('"', quote1 + 1)
                if quote2 == -1:
                    break
                source = content[quote1 + 1:quote2]

                if entry_count > 0:
                    out.write(",\n")
                out.write(f'  rec(gens := {gens_str}, inv := {inv_str}, '
                          f'source := "{source}")')
                entry_count += 1
                file_count += 1
                pos = quote2 + 1

            print(f"    Processed {leaf_file.name}: {file_count} entries")

        out.write("\n];\n")
        out.write(f"# Complete: {entry_count} entries from {len(leaf_files)} files\n")

    print(f"  Combined {entry_count} entries into {output_file.name}")
    return True, entry_count


def convert_nonleaves() -> tuple:
    """Convert nonleaves.g to maxsub_results format.

    nonleaves.g has format: nonleaf_groups := [rec(gens := ..., inv := ..., source := "..."), ...]
    We need: maxsub_results := [rec(gens := ..., inv := ..., source := "..."), ...]

    Returns (success, count).
    """
    nonleaves_file = OUTPUT_DIR / "nonleaves.g"
    if not nonleaves_file.exists():
        print("  No nonleaves.g found - skipping non-leaf conversion")
        return True, 0

    content = nonleaves_file.read_text(encoding='utf-8', errors='replace')
    count = content.count("rec(gens :=")

    if count == 0:
        print("  nonleaves.g has 0 entries - skipping")
        return True, 0

    # Convert: just rename the variable from nonleaf_groups to maxsub_results
    output_file = OUTPUT_DIR / "nonleaf_maxsub.g"
    output_content = content.replace("nonleaf_groups :=", "maxsub_results :=")

    # Add Complete marker if not present
    if "# Complete:" not in output_content:
        output_content += f"\n# Complete: {count} non-leaf groups\n"

    with open(output_file, 'w') as f:
        f.write(output_content)

    print(f"  Converted {count} non-leaf groups -> {output_file.name}")
    return True, count


def verify_direct_workers() -> dict:
    """Verify all direct worker outputs exist and are complete."""
    direct_files = [
        "intrans_1x14",
        "wreath_3wr5", "wreath_5wr3",
        "primitive_1", "primitive_2", "primitive_3", "primitive_4",
    ]

    results = {}
    for label in direct_files:
        filepath = OUTPUT_DIR / f"{label}.g"
        if filepath.exists():
            count = count_entries(filepath)
            content = filepath.read_text(encoding='utf-8', errors='replace')
            complete = "# Complete:" in content
            results[label] = {"exists": True, "count": count, "complete": complete}
        else:
            results[label] = {"exists": False, "count": 0, "complete": False}

    return results


def update_phase_b1_worker_list():
    """Print the updated WORKER_FILES list for phase_b1_s15.py."""
    all_sources = []

    # Direct workers
    for label in ["intrans_1x14", "wreath_3wr5", "wreath_5wr3",
                   "primitive_1", "primitive_2", "primitive_3", "primitive_4"]:
        filepath = OUTPUT_DIR / f"{label}.g"
        if filepath.exists() and count_entries(filepath) > 0:
            all_sources.append(label)

    # Leaf results (combined)
    combined = OUTPUT_DIR / "combined_leaves.g"
    if combined.exists() and count_entries(combined) > 0:
        all_sources.append("combined_leaves")

    # Non-leaf groups
    nonleaf = OUTPUT_DIR / "nonleaf_maxsub.g"
    if nonleaf.exists() and count_entries(nonleaf) > 0:
        all_sources.append("nonleaf_maxsub")

    return all_sources


def main():
    print("=" * 60)
    print("Phase A-4: Combine Results for S15 Deduplication")
    print("=" * 60)
    print(f"Started: {datetime.now()}")
    print()

    start_time = time.time()

    # Step 1: Verify direct workers
    print("Checking direct worker outputs...")
    direct = verify_direct_workers()
    total_direct = 0
    missing = []
    for label, info in direct.items():
        if info["exists"] and info["complete"]:
            print(f"  {label}: {info['count']} entries (OK)")
            total_direct += info["count"]
        elif info["exists"]:
            print(f"  {label}: {info['count']} entries (INCOMPLETE)")
            total_direct += info["count"]
        else:
            print(f"  {label}: MISSING")
            missing.append(label)

    if missing:
        print(f"\n  WARNING: Missing direct worker outputs: {missing}")
        print(f"  Run compute_s15_maxsub.py to generate these.")

    # Step 2: Merge leaf results
    print(f"\nMerging leaf computation results...")
    leaf_ok, leaf_count = merge_leaf_results()

    # Step 3: Convert non-leaf groups
    print(f"\nConverting non-leaf groups...")
    nonleaf_ok, nonleaf_count = convert_nonleaves()

    # Step 4: Summary
    total = total_direct + leaf_count + nonleaf_count

    print(f"\n{'='*60}")
    print("Combination Summary")
    print(f"{'='*60}")
    print(f"  Direct workers:  {total_direct:>10,} entries")
    print(f"  Leaf results:    {leaf_count:>10,} entries")
    print(f"  Non-leaf groups: {nonleaf_count:>10,} entries")
    print(f"  {'':─<30}")
    print(f"  Total:           {total:>10,} entries (before dedup)")

    # Build the file list for Phase B-1
    all_sources = update_phase_b1_worker_list()
    print(f"\n  Worker files for Phase B-1 ({len(all_sources)} files):")
    for src in all_sources:
        filepath = OUTPUT_DIR / f"{src}.g"
        count = count_entries(filepath)
        print(f"    \"{src}\",  # {count:,} entries")

    print(f"\n  UPDATE phase_b1_s15.py WORKER_FILES to:")
    print(f"  WORKER_FILES = {all_sources}")

    elapsed = time.time() - start_time
    print(f"\n  Time: {elapsed:.1f}s")
    print(f"\n  Next step: python phase_b1_s15.py")

    return 0


if __name__ == "__main__":
    sys.exit(main())
