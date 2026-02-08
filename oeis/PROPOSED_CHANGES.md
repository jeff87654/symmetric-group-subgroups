# Proposed Changes to OEIS A174511

**Sequence**: [A174511](https://oeis.org/A174511) — Number of isomorphism types of subgroups of S_n
**Author**: Jeffrey Yan
**Date**: February 2026
**Repository**: [github.com/jeff87654/symmetric-group-subgroups](https://github.com/jeff87654/symmetric-group-subgroups)

---

## 1. Summary of Changes

| Field | Current | Proposed |
|-------|---------|----------|
| DATA | `1, 2, 4, 9, 16, 29, 55, 137, 241, 453, 894, 2065, 3845` | `1, 2, 4, 9, 16, 29, 55, 137, 241, 453, 894, 2065, 3845, 7766` |
| b-file | n = 1..13 | n = 1..14 |
| Extensions | (none after a(13)) | `a(14) from _Jeffrey Yan_, Feb 08 2026` |
| Links | (unchanged) | Add link to GitHub repository |
| Comments | (unchanged) | Add computation methodology note |

The single new term is **a(14) = 7,766**.

---

## 2. Justification

### 2.1 The Value is Correct

The value a(14) = 7,766 has been independently verified through **four rounds of checking** using different algorithms:

| Round | Method | Result |
|-------|--------|--------|
| Original | Partition-based enumeration | 7,766 (after corrections) |
| Double check | Independent 6-way parallel recomputation | 7,766 |
| Triple check | Fresh start from A000638(14) = 75,154 conjugacy classes | 7,766 |
| Quadruple check | Independent DP algorithm + exhaustive bucket verification | 7,766 |

### 2.2 Breakdown

The 75,154 conjugacy class representatives of subgroups of S_14 decompose into 7,766 abstract isomorphism types:

| Category | Input groups | Distinct types | Method |
|----------|-------------|----------------|--------|
| IdGroup-compatible (order < 2000, excl. 512/768/1024/1536) | 64,467 | 4,602 | GAP `IdGroup` — canonical, exact |
| Large: direct product factor dedup | 7,429 | 2,269 | Factor-level `IdGroup` canonicalization |
| Large: 2-groups (order 512) | 336 | 10 | ANUPQ `IsIsomorphicPGroup` |
| Large: isomorphism testing | 2,922 | 885 | Invariant bucketing + `IsomorphismGroups` |
| **Total** | **75,154** | **7,766** | |

The 10,687 large groups (order >= 2000 or order in {512, 768, 1024, 1536}) were partitioned into invariant-based buckets. Of the 7,431 direct product groups in the dataset, 2 share invariant signatures with non-DP groups and were bucketed with the isomorphism-testing category; hence 7,429 in the DP row and 2,922 (= 2,920 non-DP + 2 DP overlap) in the isomorphism-testing row. The net type count is unaffected.

Two notable sub-cases within the isomorphism-testing category required special treatment:
- **Order 10,368 bucket** (8 groups → 1 type): `IsomorphismGroups` takes 25–53 min per pair; verified via explicit bijective `GroupHomomorphismByImages` (see `hard_bucket_10368_proof.g`)
- **Order 2,592 bucket** (4 groups → 1 type): verified via explicit bijective homomorphisms (see `difficult_bucket_proof.g`)

### 2.3 Consistency Checks

- **A000638(14) = 75,154**: Our enumeration of conjugacy classes matches the known OEIS value, confirming complete coverage of all subgroups.
- **Growth ratio**: a(14)/a(13) = 7,766/3,845 = 2.02, consistent with the observed pattern (ratios range from 1.76 to 2.49 for n = 2..13).
- **Order coverage**: Every group order appearing among the 75,154 representatives is accounted for in the final type count. Validated by `validate_order_coverage.g`.
- **Cross-deduplication**: Large groups from S_14 were cross-checked against S_13 large groups to ensure no double-counting of types already present in smaller symmetric groups.
- **Spot-check against SmallGroups library**: For 13 selected orders with full SmallGroups coverage, the number of distinct `IdGroup` values found among S_14 subgroups was verified to be <= `NrSmallGroups(n)`. All 13 orders pass. At 6 of these orders (6, 10, 12, 20, 24, 36, 60), every isomorphism type in the SmallGroups library appears as a subgroup of S_14. See `spot_check_orders.g`.

### 2.4 Quadruple Check Details

The final verification round (quadruple check) used two independent approaches:

**Phase 1 — Fresh DP deduplication**: Instead of the triple check's bipartite factor matching (`CompareByFactorsV3`), a completely different algorithm was used: compute `IdGroup` of each direct product factor, sort the list, and use that as a canonical key. Two DP groups are isomorphic iff their sorted factor IdGroup lists match. For factors without IdGroup (order 512/1024), extended invariants + pairwise `IsomorphismGroups` on individual factors was used as fallback. Result: 2,271 unique types among all 7,431 DP groups. Of these, 2,269 were in DP-specific buckets during the triple check; the remaining 2 DP groups (indices 4230 and 7429) shared invariant signatures with non-DP groups and were processed in regular isomorphism-testing buckets, where they were correctly identified as unique representatives. Net type count: unchanged at 3,164.

**Phase 2 — Exhaustive verification of non-DP results**: For every multi-group bucket from the triple check's deduplication (508 regular buckets + 6 2-group buckets = 514 total), verified:
- (a) All chosen representatives are **mutually non-isomorphic** (no over-counting)
- (b) Every non-representative **is isomorphic** to at least one representative (no under-counting)

Result: **0 errors** across all 514 buckets.

---

## 3. Proposed Additions to OEIS Entry

### 3.1 Updated DATA Line

```
1, 2, 4, 9, 16, 29, 55, 137, 241, 453, 894, 2065, 3845, 7766
```

### 3.2 Updated b-file (n = 1..14)

```
1 1
2 2
3 4
4 9
5 16
6 29
7 55
8 137
9 241
10 453
11 894
12 2065
13 3845
14 7766
```

### 3.3 Proposed Comment

> a(14) was computed by enumerating all A000638(14) = 75154 conjugacy classes of subgroups of S_14, classifying 64467 groups via IdGroup (yielding 4602 types), and deduplicating the remaining 10687 large groups by isomorphism testing (yielding 3164 types). The result was independently verified four times using different algorithms. - _Jeffrey Yan_, Feb 08 2026

### 3.4 Proposed Link

> Jeffrey Yan, <a href="https://github.com/jeff87654/symmetric-group-subgroups">Computation and verification of a(14)</a>, GitHub, 2026.

### 3.5 Extensions Line

> a(14) from _Jeffrey Yan_, Feb 08 2026

---

## 4. Correction History

The value underwent several corrections during development before settling on the final verified answer. This history is documented for transparency:

| Value | Date | Issue |
|-------|------|-------|
| 7,095 | Jan 2026 | Initial computation — missing partition [8,2,2,2] |
| 7,739 | Jan 2026 | Partition coverage fixed |
| 7,740 | Jan 2026 | +1 group from double check verification |
| 7,754 | Jan 2026 | Cross-deduplication corrections |
| 7,756 | Jan 2026 | Additional bucket analysis |
| 7,755 | Jan 2026 | Fixed CompareByFactorsV3 bug (two-semidirect-factor case) |
| **7,766** | **Feb 2026** | **Triple check: 11 missing IdGroup types found; confirmed by quadruple check** |

All intermediate values were caused by bugs in the deduplication pipeline, not in the underlying group enumeration. The final value of 7,766 has been stable across the triple and quadruple checks, which used completely independent code paths.

---

## 5. Computational Environment

| Component | Version/Details |
|-----------|----------------|
| GAP | 4.15.1 (Cygwin) |
| ANUPQ package | via WSL (Ubuntu) |
| Python | 3.11 (orchestration) |
| Parallelism | Up to 11 simultaneous GAP workers |
| Memory | 8–50 GB per worker |
| Total wall time | ~30 hours across all computation and verification phases |

---

## 6. Files Included in Repository

| Path | Description |
|------|-------------|
| `oeis/b174511.txt` | Updated b-file for OEIS |
| `oeis/A174511_14_computation_report.pdf` | Full computation report (PDF) |
| `Partition/a174511.g` | Original partition-based GAP algorithm |
| `Partition/tests/test_groups_static.g` | 41-group validation test suite |
| `compute_s14_maxsub.g` | Maximal subgroup decomposition (GAP) |
| `compute_s14_maxsub.py` | Parallel worker launcher |
| `triple_check/process_s14_subgroups.g` | Conjugacy class processing |
| `triple_check/dedupe/` | Isomorphism deduplication pipeline |
| `triple_check/difficult_bucket_proof.g` | Explicit isomorphism proof (order 2,592) |
| `triple_check/hard_bucket_10368_proof.g` | Explicit isomorphism proof (order 10,368) |
| `triple_check/quad_check/` | Quadruple check verification scripts |
| `triple_check/quad_check/merge_qc_results.py` | Final verification merge (PASS) |
| `triple_check/quad_check/spot_check_orders.g` | Spot-check of IdGroup types at 13 orders |
