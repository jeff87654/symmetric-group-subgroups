# Isomorphism Types of Subgroups of Symmetric Groups

Computation of [OEIS A174511](https://oeis.org/A174511): the number of isomorphism types of subgroups of the symmetric group S_n.

## Results

**A174511(16) = 43,626**

| n  | a(n)   | Ratio   |
|----|--------|---------|
| 1  | 1      | -       |
| 2  | 2      | 2.000   |
| 3  | 4      | 2.000   |
| 4  | 9      | 2.250   |
| 5  | 16     | 1.778   |
| 6  | 29     | 1.813   |
| 7  | 55     | 1.897   |
| 8  | 137    | 2.491   |
| 9  | 241    | 1.759   |
| 10 | 453    | 1.880   |
| 11 | 894    | 1.974   |
| 12 | 2,065  | 2.310   |
| 13 | 3,845  | 1.862   |
| 14 | 7,766  | 2.020   |
| 15 | 16,438 | 2.117   |
| 16 | **43,626** | **2.654** |

Values through a(13) were previously known. The values a(14) = 7,766 and a(15) = 16,438 were computed and verified in January-February 2026. The value a(16) = 43,626 was computed and independently verified in February-March 2026.

## Method

The computation follows a three-stage pipeline, applied to S₁₄, S₁₅, and S₁₆.

### Stage 1: Conjugacy Class Enumeration (A000638)

All conjugacy classes of subgroups are enumerated via **maximal subgroup decomposition**: every subgroup of S_n is contained in at least one maximal subgroup, so we compute the subgroup lattice of each maximal subgroup and collect conjugacy class representatives, deduplicating via invariant bucketing and `IsConjugate` testing.

| n  | A000638(n) | Maximal subgroups | Method |
|----|------------|-------------------|--------|
| 14 | 75,154     | 7 intransitive + 2 wreath + primitives + A₁₄ | Direct lattice computation |
| 15 | 159,129    | 7 intransitive + 2 wreath + 4 primitive + A₁₅ | Recursive decomposition (S₇×S₈ too large for direct) |
| 16 | 686,165    | 8 intransitive + 3 wreath + primitives + A₁₆ | Recursive decomposition |

### Stage 2: Isomorphism Classification

Each conjugacy class representative is classified by isomorphism type:

|  | S₁₄ | S₁₅ | S₁₆ |
|--|------|------|------|
| IdGroup-compatible groups | 64,467 → 4,602 types | 130,041 → 8,001 types | 502,115 → 14,233 types |
| Large groups (need dedup) | 10,687 → 3,164 types | 29,088 → 8,437 types | 184,050 → 29,393 types |
| **Total types** | **7,766** | **16,438** | **43,626** |

Groups with IdGroup-compatible orders (< 2,000, excl. 512/768/1024/1536) are classified by GAP's `IdGroup`. The remaining "large" groups require explicit isomorphism deduplication.

### Stage 3: Large Group Deduplication

Large groups are deduplicated using a cascade of increasingly expensive methods:
- Invariant-based bucketing (order, derived subgroup size, conjugacy class count, derived length, abelian invariants)
- Direct product factor decomposition with bipartite matching
- Projection-lift cascade for 2-groups (projLift + combinedOrbit + pcGroupIso)
- GQuotients for solvable difficult groups
- Full `IsomorphismGroups` testing (remaining groups)

## Verification

Self-contained verification scripts are provided that anyone can run to independently verify these results. Each requires only GAP 4.14+ and the input data files — no precomputed intermediate results are trusted.

### S₁₆ Verification

```bash
cd s16_final_results_reindexed/verification_script
python run_verification.py              # Full verification (~6 hrs, 16 GB RAM)
python run_verification.py --skip-invariants   # Faster (~3 hrs)
```

Starting from a single 14 MB archive (`s16_final_results.7z`), the script runs 5 phases:
- **Phase 0**: Structural integrity (Python, ~2 min)
- **Phase 1**: Validates 154,656 isomorphism proofs (4 GAP workers, ~5 min)
- **Phase 2**: Recomputes all certificate invariants from raw generators (1 GAP worker, ~3 hrs)
- **Phase 3**: Verifies F/G/H discrimination via CharacterTable / IsomorphismGroups (~30 min)
- **Phase 4**: Independently rebuilds the 686,165-entry class-to-type mapping (~3 min)

See [`s16_final_results_reindexed/verification_script/README.md`](s16_final_results_reindexed/verification_script/README.md) for full details.

### S₁₄ Verification

```bash
cd s14_final/verification
python launch_verify.py        # ~38 min, 20 GB RAM
```

See [`s14_final/verification/README.md`](s14_final/verification/README.md) for details.

### S₁₅ Verification

```bash
cd s15_proof_certificate
python launch_verify.py         # Full verification (~70 min, 20 GB RAM)
```

All verification scripts establish an **upper bound** and **lower bound** that match:
- **Upper bound**: Every conjugacy class is accounted for (type representative, proof duplicate, or IdGroup-collapsed)
- **Lower bound**: All type representatives are pairwise non-isomorphic (proven by invariant discrimination or explicit non-isomorphism)

## Repository Structure

```
s16_final_results_reindexed/ - Final verified data and proofs for S16
  s16_final_results.7z         - 14 MB compressed archive (all data)
  verification_script/         - Self-contained verification system
    run_verification.py          - Master orchestrator (single entry point)
    README.md                    - Verification documentation
    verify_*.py / verify_*.g     - Individual verification phases
s14_final/                   - Final verified data and proofs for S14
  s14_subgroups.g              - 75,154 conjugacy class representatives
  proof_all_remapped.g         - 7,523 isomorphism proofs
  verification/                - Self-contained verification script
    verify_a174511_14.g          - GAP verification (Phases A-D)
    class_to_type.g              - 75,154 -> 7,766 class-to-type mapping
s15_proof_certificate/       - Proof certificate for S15
  s15_subgroups.g              - 159,129 conjugacy class representatives
  combined_proof.g             - 20,651 isomorphism proofs
  type_fingerprints_s15.g      - 16,438 type records with minimal invariants
  verify_a174511_15.g          - GAP verification (Phases A-D + mapping)
  build_class_to_type.g        - Standalone class-to-type mapping script
  class_to_type.g              - 159,129 -> 16,438 class-to-type mapping
conjugacy_cache/             - Cached conjugacy class data for S13-S15
compute_s14_maxsub.g         - Maximal subgroup decomposition for S14
compute_s15_recursive.g      - Recursive decomposition library for S15
maxsub_output_s15/           - S15 maximal subgroup computation output
Partition/                   - Original partition-based algorithm
  a174511.g                    - Main GAP computation script
  tests/                       - Test suite (41-group validation, regression tests)
triple_check/                - Triple check computation for S14
oeis/                        - OEIS submission materials
CLAUDE.md                    - Project notes and computation history
```

## Software

- **GAP 4.15.1** (Groups, Algorithms, Programming) — core group theory computations
- **Python 3.11** — orchestration, parallel workers, data processing

## Related OEIS Sequences

- [A000638](https://oeis.org/A000638) — Conjugacy classes of subgroups of S_n (verified: a(14) = 75,154, a(15) = 159,129, a(16) = 686,165)
- [A005432](https://oeis.org/A005432) — Total number of subgroups of S_n
- [A174511](https://oeis.org/A174511) — Isomorphism types of subgroups of S_n (**this computation**)

## Author

Jeffrey Ketchersid, February–March 2026
