# Verification of A174511(14) = 7,766

Self-contained proof that the symmetric group S\_14 has exactly **7,766 isomorphism types** of subgroups.

## Input Files

| File | Size | Description |
|------|------|-------------|
| `s14_subgroups.g` | 24 MB | 75,154 conjugacy class representatives (permutation generators on {1..14}) |
| `proof_all_remapped.g` | 4 MB | 7,523 isomorphism proofs (explicit generator maps) |
| `type_fingerprints.g` | 2.2 MB | 7,766 type records with minimal distinguishing invariants |

The first two are in the parent directory (`s14_final/`). The fingerprint file is in this directory.

## Running the Verification

### Prerequisites

- [GAP](https://www.gap-system.org/) 4.12+ with the SmallGroups library
- Python 3 (for the launcher)
- ~20 GB RAM recommended (`-o 20g`)

### Run

```bash
python launch_verify.py
```

Or directly in GAP:
```gap
Read("verify_a174511_14.g");
```

## What the Script Proves

The script establishes both an **upper bound** and a **lower bound** of 7,766 isomorphism types, proving A174511(14) = 7,766. It has three phases:

### Phase A: Verify fingerprint invariants

For each of the 7,766 type representatives, rebuilds the group from raw generators and recomputes every invariant listed in its fingerprint record:

- **4,602 IdGroup types**: verifies `IdGroup(G)` matches the recorded value
- **3,164 large types**: verifies only the fields needed to distinguish each type from all same-order types

Each large type stores a minimal set of fields from this cost-ordered cascade:

| Field | GAP Computation | Types Using |
|-------|----------------|-------------|
| `derivedSize` | `Size(DerivedSubgroup(G))` | 3,071 |
| `nrCC` | `Length(ConjugacyClasses(G))` | 2,835 |
| `derivedLength` | `DerivedLength(G)` or -1 | 274 |
| `abelianInvariants` | `AbelianInvariants(G/G')` | 650 |
| `exponent` | `Exponent(G)` | 410 |
| `centerSize` | `Size(Centre(G))` | 104 |
| `nrInvolutions` | elements of order 2 | 832 |
| `nrElementsOfOrder4` | elements of order 4 | 110 |
| `nrElementsOfOrder6` | elements of order 6 | 4 |
| `classSizes` | sorted conjugacy class sizes | 8 |
| `derivedSeriesSizes` | derived series sizes | 8 |
| `nilpotencyClass` | nilpotency class or -1 | 3 |
| `numNormalSubs` | `Length(NormalSubgroups(G))` | 4 |
| `autGroupOrder` | `Size(AutomorphismGroup(G))` | 72 |
| `subgroupOrderProfile` | subgroup conjugacy class profile | 26 |

Shared computation ensures expensive GAP objects (DerivedSubgroup, ConjugacyClasses, DerivedSeriesOfGroup) are computed at most once per type and reused across multiple fields.

### Phase B: Verify proofs + build type mapping (~10-15 min)

**Upper bound**: at most 7,766 types.

1. **B1**: Computes `IdGroup` for all 64,467 groups with compatible orders (< 2000, excl. 512/768/1024/1536). Groups with the same IdGroup are unioned in a union-find structure, yielding **4,602** unique IdGroup types.

2. **B2**: Verifies all 7,523 isomorphism proofs as bijective homomorphisms:
   - Generators are in G, images are in H
   - Generators generate G
   - `GroupHomomorphismByImages` succeeds
   - The map is injective and surjective
   - Applies each verified proof to the union-find

3. **B3**: Counts distinct types from union-find = **7,766**

### Phase C: Verify non-isomorphism (~1 sec)

**Lower bound**: at least 7,766 types.

- **4,602 IdGroup types** are distinct by definition (different identifiers = non-isomorphic)
- **3,164 large types** are bucketed by order. Each pair sharing a bucket is distinguished by a verified invariant from Phase A, walking the cost-ordered cascade:

| Invariant | Pairs Distinguished |
|-----------|---------------------|
| derivedSize | 74,679 |
| nrCC | 18,554 |
| derivedLength | 297 |
| abelianInvariants | 562 |
| exponent | 292 |
| centerSize | 86 |
| nrInvolutions | 713 |
| nrElementsOfOrder4 | 60 |
| nrElementsOfOrder6 | 2 |
| classSizes | 4 |
| derivedSeriesSizes | 4 |
| nilpotencyClass | 2 |
| numNormalSubs | 2 |
| autGroupOrder | 36 |
| subgroupOrderProfile | 13 |

- **No overlap** between IdGroup types and large types (disjoint order ranges verified)

### Phase D: Verify conjugacy class completeness (optional, ~16 min)

Confirms **A000638(14) = 75,154** by verifying that all 75,154 representatives are pairwise non-conjugate in S14. Uses a 3-level cascade to reduce ~6.6 million potential pairs to only 4,833 actual `IsConjugate` tests:

1. Buckets all 75,154 classes by isomorphism type (from Phase B union-find), yielding 7,766 type buckets
2. **L1 — Orbit types**: Sub-buckets by `[orbit_size, TransitiveIdentification]` per orbit on {1..14} (precomputed in Phase B1). Eliminates **5,541,698 pairs** (83.6%)
3. **L2 — Element histogram**: Sub-buckets by `(element_order, fixed_point_count)` histogram via `ConjugacyClasses(G)`. Eliminates **1,077,206 pairs** (16.3%)
4. **L3 — IsConjugate**: Runs `IsConjugate(S14, G, H)` on the remaining **4,833 pairs** (0.07%)
5. If any pair is conjugate → FATAL (would mean two "distinct" classes are actually the same)

Controlled by `RUN_PHASE_D := true;` near the top of the script. Default: enabled.

### Mapping output

After all phases pass, writes `class_to_type.g` mapping each of the 75,154 conjugacy class indices to its type index (1..7,766). Type size distribution: min=1, median=2, max=1,318 classes per type.

## Data Files

| File | Description |
|------|-------------|
| `type_fingerprints.g` | 7,766 type records with minimal invariant fields (input to script) |
| `type_fingerprints_full.g` | Original version with full invariant cascades (backup) |
| `analyze_minimal_fingerprints.py` | Script that produced the minimal fingerprints from the full version |
| `phase_b_invariants.g` | 75,154 group invariants (optional, for reference) |
| `class_to_type.g` | Maps each of 75,154 classes to one of 7,766 type indices (output) |
| `verify_output_phaseD_v2.txt` | Full verification output log including Phase D statistics |

## Fingerprint Format

### IdGroup types (4,602 records)
```gap
rec(typeIndex:=4, representative:=4, order:=72, idGroup:=[ 72, 44 ])
```

### Large types in singleton-order groups (62 records)
```gap
rec(typeIndex:=1, representative:=1, order:=5616, idGroup:=fail)
```
No additional fields needed — the unique order alone distinguishes.

### Large types needing distinction (3,102 records)
```gap
rec(typeIndex:=64, representative:=64, order:=2592, idGroup:=fail,
    derivedSize:=162, nrCC:=90, nrInvolutions:=391)
```
Only fields that actually differ from some same-order type are stored.

## Proof Structure

The verification establishes:

1. The fingerprint invariants are correct (Phase A — recomputed from raw generators)
2. The 75,154 groups collapse to exactly 7,766 isomorphism types via IdGroup + verified proofs (Phase B — upper bound)
3. These 7,766 types are pairwise non-isomorphic via verified invariant differences (Phase C — lower bound)
4. Therefore **A174511(14) = 7,766**
5. (Optional) All 75,154 representatives are pairwise non-conjugate in S14 (Phase D), therefore **A000638(14) = 75,154**
