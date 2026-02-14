# S15 Proof Certificate

Self-contained proof that the symmetric group S\_15 has exactly **16,438 isomorphism types** of subgroups, and exactly **159,129 conjugacy classes** of subgroups.

## Input Files

| File | Description |
|------|-------------|
| `s15_subgroups.g` | 159,129 conjugacy class representatives (permutation generators on {1..15}) |
| `combined_proof.g` | 20,651 isomorphism proofs (explicit generator maps) |
| `type_fingerprints_s15.g` | 16,438 type records with minimal distinguishing invariants |
| `s15_idgroups.g` | 8,001 IdGroup type strings (for cross-check) |

## Running the Verification

### Prerequisites

- [GAP](https://www.gap-system.org/) 4.12+ with the SmallGroups library
- Python 3 (for the launcher)
- ~20 GB RAM recommended (`-o 20g`)

### Full Verification (~70 min)

```bash
python launch_verify.py
```

Or directly in GAP:
```gap
Read("verify_a174511_15.g");
```

### Standalone Class-to-Type Mapping (~10 min)

To produce only the class-to-type mapping without full verification:
```bash
python launch_build_class_to_type.py
```

## What the Verification Proves

The script establishes both an **upper bound** and a **lower bound** of 16,438 isomorphism types, proving A174511(15) = 16,438. It also verifies the completeness of the input conjugacy classes. Total runtime: ~70 minutes on a single core.

### Phase B: Verify proofs + build type mapping (~9 min)

**Upper bound**: at most 16,438 types.

1. **B1**: Computes `IdGroup` for all 130,041 groups with compatible orders (< 2000, excl. 512/768/1024/1536). Groups with the same IdGroup are unioned in a union-find structure, yielding **8,001** unique IdGroup types.

2. **B2**: Verifies all 20,651 isomorphism proofs as bijective homomorphisms:
   - Generators are in G, images are in H
   - Generators generate G
   - `GroupHomomorphismByImages` succeeds
   - The map is injective and surjective
   - Applies each verified proof to the union-find

3. **B3**: Counts distinct types from union-find = **16,438**

### Phase A: Verify fingerprint invariants (~24 min)

For each of the 8,437 large type representatives, rebuilds the group from raw generators and recomputes every invariant listed in its fingerprint record (derivedSize, nrCC, derivedLength, abelianInvariants, exponent, centerSize, element counts, etc.).

### Phase C: Verify non-isomorphism (~1 sec)

**Lower bound**: at least 16,438 types.

- **8,001 IdGroup types** are distinct by definition (different identifiers = non-isomorphic)
- **8,437 large types** are bucketed by order. Each pair sharing a bucket is distinguished by a verified invariant from Phase A.
- **No overlap** between IdGroup types and large types (disjoint order ranges verified)

### Phase D: Verify conjugacy class completeness (~43 min)

Given the known value A000638(15) = 159,129 (Holt), this phase verifies that our 159,129 representatives are in fact a complete list of conjugacy classes by showing they are pairwise non-conjugate in S15. Since there are exactly 159,129 conjugacy classes and our 159,129 groups are all distinct, no class is missing. Uses a 3-level cascade:

1. **L1 -- Orbit types**: Sub-buckets by `[orbit_size, TransitiveIdentification]` per orbit on {1..15}
2. **L2 -- Element histogram**: Sub-buckets by `(element_order, fixed_point_count)` histogram
3. **L3 -- IsConjugate**: Runs `IsConjugate(S15, G, H)` on remaining pairs

### Class-to-Type Mapping

After all phases pass, writes `class_to_type.g` mapping each of the 159,129 conjugacy class indices to its type index (1..16,438).

## Output Files

| File | Description |
|------|-------------|
| `class_to_type.g` | `CLASS_TO_TYPE[i]` = type index (1..16,438) for conjugacy class i |
| `build_class_to_type.g` | Standalone script to produce the mapping without full verification |

## Type Statistics

- **Total types**: 16,438 = 8,001 IdGroup + 8,437 large
- **Classes mapped**: 130,041 via IdGroup, 29,088 via proof chain
- **Type size distribution**: min=1, median=2, max=2,256 classes per type

## Proof Structure

The verification establishes:

1. The fingerprint invariants are correct (Phase A -- recomputed from raw generators)
2. The 159,129 groups collapse to exactly 16,438 isomorphism types via IdGroup + verified proofs (Phase B -- upper bound)
3. These 16,438 types are pairwise non-isomorphic via verified invariant differences (Phase C -- lower bound)
4. Therefore **A174511(15) = 16,438**
5. Given Holt's A000638(15) = 159,129, the 159,129 pairwise non-conjugate representatives (Phase D) form a complete list of conjugacy classes
