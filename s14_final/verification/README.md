# Verification of A174511(14) = 7,766

Self-contained proof that the symmetric group S\_14 has exactly **7,766 isomorphism types** of subgroups.

## Input Files

| File | Size | Description |
|------|------|-------------|
| `s14_subgroups.g` | 24 MB | 75,154 conjugacy class representatives (permutation generators on {1..14}) |
| `proof_all_remapped.g` | 4 MB | 7,523 isomorphism proofs (explicit generator maps) |

These are in the parent directory (`s14_final/`).

## Running the Verification

### Prerequisites

- [GAP](https://www.gap-system.org/) 4.12+ with the SmallGroups library
- Python 3 (for the launcher)
- ~20 GB RAM recommended (`-o 20g`)

### Full Verification (~1 hour)

Recomputes everything from scratch. No precomputed data is trusted.

```bash
python launch_verify.py
```

Or directly in GAP:
```gap
Read("verify_a174511_14.g");
```

### Faster Modes

After a full run generates `phase_b_invariants.g`, subsequent runs can trust
the precomputed invariants:

```gap
# Trust Phase B invariants, still verify proofs + non-isomorphism (~15 min)
TRUST_INVARIANTS := true;
Read("verify_a174511_14.g");

# Also skip conjugacy checks (~10 min)
TRUST_INVARIANTS := true;
SKIP_CONJUGACY := true;
Read("verify_a174511_14.g");
```

## What the Script Proves

### Phase A: Load and validate input data (~5 sec)

- Loads 75,154 generator lists and 7,523 proof records
- Validates all indices are in range, no self-links

### Phase B: Compute group invariants (~30-45 min, or seconds if trusted)

For each of the 75,154 groups, computes:
- **sigKey**: `[order, |G'|, #conjugacy_classes, derived_length, abelian_invariants]`
- **Exponent**
- **IdGroup** (for orders < 2000, excluding {512, 768, 1024, 1536})

Result: 64,467 groups get IdGroup identifiers, 10,687 are "large" groups.

### Phase C: Verify non-conjugacy (~10-30 min, skippable)

Proves all 75,154 groups are pairwise non-conjugate in S\_14:
1. Buckets groups by S\_14-conjugacy invariants (orbit profile + element-fixedpoint histogram)
2. ~60,000 singleton buckets are automatically non-conjugate
3. Tests `IsConjugate(S_14, G_i, G_j)` for all pairs in multi-group buckets (~70,000 pairs)
4. All must return `false`

### Phase D: Verify isomorphism proofs (~1-2 min)

**Upper bound**: at most 7,766 types.

For each of the 7,523 proofs (mapping duplicate -> representative):
1. Verifies generators are in G, images are in H
2. Verifies generators generate G
3. Constructs `GroupHomomorphismByImages` and verifies it is a valid homomorphism
4. Checks `IsInjective` (trivial kernel) and `IsSurjective` (image = H)

Builds a union-find structure:
- Groups with the same IdGroup are unioned -> **4,602** unique IdGroup types
- Verified proof maps union duplicates with representatives -> **3,164** large group types
- Total: 4,602 + 3,164 = **7,766**

### Phase E: Verify non-isomorphism (~10-20 min)

**Lower bound**: at least 7,766 types.

- 4,602 IdGroup types are distinct by definition (different identifiers = non-isomorphic)
- 3,164 large group representatives are proved pairwise non-isomorphic via an invariant cascade:

| Level | Invariant | Cost |
|-------|-----------|------|
| 1 | Center size | Cheap |
| 2 | Element order profile | Moderate |
| 3 | Conjugacy class sizes | Moderate |
| 4 | Chief factor sizes | Moderate |
| 5 | Derived series sizes | Moderate |
| 6 | Nilpotency class | Cheap |
| 7 | Number of normal subgroups | Moderate |
| 8 | Frattini subgroup size | Moderate |
| 9 | Automorphism group order | Expensive |
| 10 | Subgroup order profile | Expensive |
| 11 | Power map structure | Expensive |
| 12 | `IsomorphismGroups` (must return `fail`) | Very expensive |

Each pair is distinguished by the cheapest sufficient invariant. The cascade stops
as soon as a difference is found.

- No overlap between IdGroup types and large types (verified by disjoint order ranges)

### Phase F: Output

| Output File | Description |
|-------------|-------------|
| `class_to_type_mapping.g` | Maps each of 75,154 classes to one of 7,766 type indices |
| `type_fingerprints.g` | For each type: representative index, order, IdGroup/sigKey, distinguishing invariant |
| `verification_summary.txt` | Human-readable proof narrative with statistics |
| `phase_b_invariants.g` | Precomputed invariants (reusable with `TRUST_INVARIANTS`) |
| `phase_c_nonconjugacy.txt` | Non-conjugacy proof log |
| `phase_d_proof_verification.txt` | Isomorphism proof verification log |
| `phase_e_noniso.txt` | Non-isomorphism proof log |

## Proof Structure

The verification establishes:

1. The 75,154 input groups are valid degree-14 permutation groups
2. They are pairwise non-conjugate in S\_14 (Phase C) — so they represent distinct conjugacy classes
3. They collapse to exactly 7,766 isomorphism types (Phase D) — upper bound
4. These 7,766 types are pairwise non-isomorphic (Phase E) — lower bound
5. Therefore **A174511(14) = 7,766**
