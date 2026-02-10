# Isomorphism Types of Subgroups of Symmetric Groups

Computation of [OEIS A174511](https://oeis.org/A174511): the number of isomorphism types of subgroups of the symmetric group S_n.

## Result

**A174511(14) = 7,766**

| n  | a(n)  | Ratio   |
|----|-------|---------|
| 1  | 1     | -       |
| 2  | 2     | 2.000   |
| 3  | 4     | 2.000   |
| 4  | 9     | 2.250   |
| 5  | 16    | 1.778   |
| 6  | 29    | 1.813   |
| 7  | 55    | 1.897   |
| 8  | 137   | 2.491   |
| 9  | 241   | 1.759   |
| 10 | 453   | 1.880   |
| 11 | 894   | 1.974   |
| 12 | 2,065 | 2.310   |
| 13 | 3,845 | 1.862   |
| 14 | **7,766** | **2.020** |

Values through a(13) were previously known. The value a(14) = 7,766 is new, computed and verified in January-February 2026.

## Method

### Stage 1: Conjugacy Class Enumeration
All A000638(14) = 75,154 conjugacy classes of subgroups of S_14 were enumerated via maximal subgroup decomposition using GAP 4.15.1. Each subgroup of S_14 is contained in at least one maximal subgroup (7 intransitive, 2 wreath products, primitive groups, and A_14).

### Stage 2: Isomorphism Classification
Each conjugacy class representative was classified:
- **64,467 groups** with IdGroup-compatible orders (< 2,000, excl. 512/768/1024/1536) yielded **4,602 unique types**
- **10,687 large groups** required isomorphism deduplication, yielding **3,164 unique types**

### Stage 3: Large Group Deduplication
The 10,687 large groups were deduplicated using:
- Invariant-based bucketing (order, derived subgroup, conjugacy classes, etc.)
- Direct product factor decomposition (7,431 groups)
- ANUPQ p-group testing (336 groups of order 512)
- Full `IsomorphismGroups` testing (remaining 2,920 groups)

## Verification

The result was verified through **four independent rounds**:

1. **Original computation** - Partition-based method
2. **Double check** - Independent 6-way parallel recomputation
3. **Triple check** - Fresh start from A000638(14) conjugacy classes
4. **Quadruple check** - Independent DP algorithm (factor IdGroup canonicalization) + exhaustive verification of all 514 isomorphism testing buckets (0 errors)

See [`oeis/A174511_14_computation_report.pdf`](oeis/A174511_14_computation_report.pdf) for the full report.

### Self-Contained Verification Script

A self-contained GAP script is provided that anyone can run to independently verify A174511(14) = 7,766. It requires only GAP 4.12+ and the two input files — no precomputed intermediate data is trusted.

```bash
cd s14_final/verification
python launch_verify.py        # Full verification (~1 hour, 20 GB RAM)
```

The script proves five things:
1. The 75,154 input groups are valid subgroups of S_14
2. They are **pairwise non-conjugate** in S_14 (Phase C)
3. They collapse to exactly **7,766 isomorphism types** via IdGroup + verified proof maps (Phase D)
4. These 7,766 types are **pairwise non-isomorphic** via an invariant cascade (Phase E)
5. Therefore A174511(14) = 7,766

Faster modes are available after a full run generates cached invariants:
```gap
TRUST_INVARIANTS := true;   # Trust Phase B invariants (~15 min)
SKIP_CONJUGACY := true;     # Also skip non-conjugacy checks (~10 min)
Read("verify_a174511_14.g");
```

See [`s14_final/verification/README.md`](s14_final/verification/README.md) for full documentation.

## Repository Structure

```
Partition/               - Original partition-based algorithm
  a174511.g              - Main GAP computation script
  tests/                 - Test suite (41-group validation, regression tests)
compute_s14_maxsub.g     - Maximal subgroup decomposition (GAP)
compute_s14_maxsub.py    - Parallel worker launcher
s14_final/               - Final verified data and proofs
  s14_subgroups.g          - 75,154 conjugacy class representatives
  proof_all_remapped.g     - 7,523 isomorphism proofs
  verification/            - Self-contained verification script
    verify_a174511_14.g    - GAP verification (Phases A-F)
    launch_verify.py       - Python launcher
triple_check/            - Triple check computation
  process_s14_subgroups.g  - Conjugacy class processing
  dedupe/                  - Isomorphism deduplication pipeline
  quad_check/              - Quadruple check verification
oeis/                    - OEIS submission materials
  b174511.txt              - Updated b-file (n=1..14)
  A174511_14_computation_report.pdf
  OEIS_SUBMISSION_GUIDE.txt
CLAUDE.md                - Project notes and computation history
```

## Software

- **GAP 4.15.1** (Groups, Algorithms, Programming) - core group theory computations
- **ANUPQ package** (via WSL) - 2-group isomorphism testing
- **Python 3.11** - orchestration, parallel workers, data processing

## Related OEIS Sequences

- [A000638](https://oeis.org/A000638) - Conjugacy classes of subgroups of S_n (verified: a(14) = 75,154)
- [A005432](https://oeis.org/A005432) - Total number of subgroups of S_n
- [A174511](https://oeis.org/A174511) - Isomorphism types of subgroups of S_n (**this computation**)

## Author

Jeffrey Ketchersid, February 2026
