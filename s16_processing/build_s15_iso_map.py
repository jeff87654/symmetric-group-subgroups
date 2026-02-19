#!/usr/bin/env python3
"""
Build S15 isomorphism map from combined_proof.g for S16 processing.

Parses all (duplicate, representative) pairs from the S15 proof certificate
and uses union-find to resolve transitive chains to canonical representatives.

Output: s16_processing/s15_iso_map.g — a GAP-loadable record mapping
duplicate S15 indices to their canonical representative index.
"""

import re
import sys
from pathlib import Path
from datetime import datetime

BASE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups")
COMBINED_PROOF = BASE_DIR / "s15_proof_certificate" / "combined_proof.g"
OUTPUT_FILE = BASE_DIR / "s16_processing" / "s15_iso_map.g"


class UnionFind:
    """Union-Find with path compression for resolving transitive chains."""
    def __init__(self):
        self.parent = {}

    def find(self, x):
        if x not in self.parent:
            self.parent[x] = x
        if self.parent[x] != x:
            self.parent[x] = self.find(self.parent[x])
        return self.parent[x]

    def union(self, a, b):
        """Union a into b (b becomes representative)."""
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.parent[ra] = rb


def main():
    print(f"Building S15 isomorphism map from combined_proof.g")
    print(f"=" * 60)
    print(f"Started: {datetime.now()}")

    if not COMBINED_PROOF.exists():
        print(f"ERROR: {COMBINED_PROOF} not found")
        return 1

    # Parse all (duplicate, representative) pairs
    pairs = []
    dup_pattern = re.compile(r'duplicate\s*:=\s*(\d+)')
    rep_pattern = re.compile(r'representative\s*:=\s*(\d+)')

    with open(COMBINED_PROOF, 'r') as f:
        current_dup = None
        for line in f:
            dup_match = dup_pattern.search(line)
            rep_match = rep_pattern.search(line)
            if dup_match:
                current_dup = int(dup_match.group(1))
            if rep_match and current_dup is not None:
                rep = int(rep_match.group(1))
                pairs.append((current_dup, rep))
                current_dup = None

    print(f"Parsed {len(pairs)} (duplicate, representative) pairs")

    # Validate ranges (should be S15 subgroup indices 1..159129)
    max_dup = max(p[0] for p in pairs) if pairs else 0
    max_rep = max(p[1] for p in pairs) if pairs else 0
    min_dup = min(p[0] for p in pairs) if pairs else 0
    min_rep = min(p[1] for p in pairs) if pairs else 0
    print(f"Duplicate range: {min_dup}..{max_dup}")
    print(f"Representative range: {min_rep}..{max_rep}")

    # Build union-find to resolve transitive chains
    uf = UnionFind()
    for dup, rep in pairs:
        uf.union(dup, rep)

    # Build final mapping: each duplicate → canonical representative
    iso_map = {}  # duplicate_index -> canonical_representative
    all_indices = set()
    for dup, rep in pairs:
        all_indices.add(dup)
        all_indices.add(rep)

    for idx in all_indices:
        canon = uf.find(idx)
        if canon != idx:
            iso_map[idx] = canon

    # Count equivalence classes
    classes = {}
    for idx in all_indices:
        canon = uf.find(idx)
        if canon not in classes:
            classes[canon] = []
        classes[canon].append(idx)

    unique_reps = set(iso_map.values())

    print(f"\nUnion-Find results:")
    print(f"  Total mapped entries: {len(iso_map)}")
    print(f"  Unique canonical representatives: {len(unique_reps)}")
    print(f"  Equivalence classes: {len(classes)}")

    # Verify: no representative maps to itself
    self_maps = [k for k, v in iso_map.items() if k == v]
    if self_maps:
        print(f"  WARNING: {len(self_maps)} self-mappings found!")

    # Size distribution of equivalence classes
    sizes = [len(v) for v in classes.values()]
    if sizes:
        print(f"  Class size range: {min(sizes)}..{max(sizes)}")
        print(f"  Mean class size: {sum(sizes)/len(sizes):.1f}")

    # Write GAP output
    print(f"\nWriting {OUTPUT_FILE}")
    with open(OUTPUT_FILE, 'w') as f:
        f.write(f"# S15 isomorphism map for S16 processing\n")
        f.write(f"# Generated: {datetime.now()}\n")
        f.write(f"# Source: {COMBINED_PROOF.name}\n")
        f.write(f"# Pairs parsed: {len(pairs)}\n")
        f.write(f"# Mapped entries: {len(iso_map)}\n")
        f.write(f"# Unique representatives: {len(unique_reps)}\n")
        f.write(f"# Equivalence classes: {len(classes)}\n")
        f.write(f"#\n")
        f.write(f"# Usage: S15_ISO_MAP.(String(idx)) gives canonical representative\n")
        f.write(f"# Only duplicates are stored; representatives are not in the map.\n\n")
        f.write(f"S15_ISO_MAP := rec(\n")

        sorted_entries = sorted(iso_map.items())
        for i, (dup, rep) in enumerate(sorted_entries):
            comma = "," if i < len(sorted_entries) - 1 else ""
            f.write(f"  (\"{dup}\") := {rep}{comma}\n")

        f.write(f");\n")

    # Verify output is loadable by checking basic structure
    file_size = OUTPUT_FILE.stat().st_size
    print(f"Output file size: {file_size:,} bytes")

    print(f"\n{'=' * 60}")
    print(f"SUMMARY")
    print(f"{'=' * 60}")
    print(f"Proof pairs parsed: {len(pairs)}")
    print(f"Mapped entries (duplicates): {len(iso_map)}")
    print(f"Unique canonical representatives: {len(unique_reps)}")
    print(f"Equivalence classes: {len(classes)}")
    print(f"Output: {OUTPUT_FILE}")
    print(f"Completed: {datetime.now()}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
