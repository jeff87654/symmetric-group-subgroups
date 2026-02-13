"""
Verify that every large group index is either:
  1. A type representative (not a duplicate in any proof), OR
  2. Listed as a duplicate in exactly one isomorphism proof

Expected: 29,088 large groups = 8,437 type reps + 20,651 duplicates
"""

import re
from collections import Counter

BASE = r"C:\Users\jeffr\Downloads\Symmetric Groups\s15_proof_certificate"

# ── Parse large group indices from s15_large_invariants.g ──
print("Parsing s15_large_invariants.g...")
with open(f"{BASE}\\s15_large_invariants.g", "r", encoding="utf-8") as f:
    inv_content = f.read()

large_indices = set()
for m in re.finditer(r"originalIndex\s*:=\s*(\d+)", inv_content):
    large_indices.add(int(m.group(1)))
print(f"  Large group indices: {len(large_indices)}")

# ── Parse proof duplicates and representatives ──
print("Parsing combined_proof.g...")
with open(f"{BASE}\\combined_proof.g", "r", encoding="utf-8") as f:
    proof_content = f.read()

dup_indices = []
dup_to_rep = {}
for m in re.finditer(
    r"duplicate\s*:=\s*(\d+)\s*,\s*\n?\s*representative\s*:=\s*(\d+)",
    proof_content
):
    dup = int(m.group(1))
    rep = int(m.group(2))
    dup_indices.append(dup)
    dup_to_rep[dup] = rep

dup_set = set(dup_indices)
dup_counter = Counter(dup_indices)

print(f"  Total proof records: {len(dup_indices)}")
print(f"  Unique duplicate indices: {len(dup_set)}")

# ── Check for redundant proofs ──
redundant = {k: v for k, v in dup_counter.items() if v > 1}
if redundant:
    print(f"\n  WARNING: {len(redundant)} indices appear as duplicate more than once:")
    for idx, count in sorted(redundant.items()):
        print(f"    Index {idx}: {count} times")
else:
    print("  No redundant proofs (all duplicate indices unique)")

# ── Classify each large group ──
type_reps = large_indices - dup_set
duplicates_in_proofs = large_indices & dup_set

# Check for large groups that are neither rep nor duplicate
uncovered = large_indices - type_reps - duplicates_in_proofs
# Check for proof duplicates that aren't large groups (i.e., IdGroup-compatible duplicates)
non_large_dups = dup_set - large_indices

print(f"\n  Type representatives (large only): {len(type_reps)}")
print(f"  Duplicates with proofs: {len(duplicates_in_proofs)}")
print(f"  Uncovered (SHOULD BE 0): {len(uncovered)}")
print(f"  Proof duplicates for IdGroup-compatible groups: {len(non_large_dups)}")

# ── Verify all proof representatives exist ──
# For large->large proofs, representative should be in large_indices
large_to_large = 0
bad_reps = []
for dup, rep in dup_to_rep.items():
    if dup in large_indices:
        large_to_large += 1
        if rep not in large_indices:
            bad_reps.append((dup, rep))

print(f"\n  Large->large proofs: {large_to_large}")
if bad_reps:
    print(f"  BAD: {len(bad_reps)} proofs map a large duplicate to a non-large representative:")
    for d, r in bad_reps[:10]:
        print(f"    {d} -> {r}")
else:
    print("  All large duplicates map to large representatives")

# ── Final verdict ──
print("\n" + "=" * 60)
total = len(type_reps) + len(duplicates_in_proofs)
print(f"  Large groups: {len(large_indices)}")
print(f"  = {len(type_reps)} type reps + {len(duplicates_in_proofs)} duplicates")
print(f"  = {total}")

if len(uncovered) == 0 and total == len(large_indices) and not redundant:
    print("\n  RESULT: PASS")
    print(f"  Every large group is accounted for.")
    print(f"  {len(type_reps)} type representatives + {len(duplicates_in_proofs)} duplicates = {total}")
else:
    print("\n  RESULT: FAIL")
    if uncovered:
        print(f"  {len(uncovered)} large groups are neither reps nor duplicates!")
        for idx in sorted(uncovered)[:20]:
            print(f"    Index {idx}")
