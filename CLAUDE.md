# OEIS A174511 Computation - Project Notes

## Project Overview

Computing A174511: the number of isomorphism types of subgroups of the symmetric group S_n.

## Key Files

- **Partition/a174511.g** - Main GAP algorithm for computing subgroups via partitions
- **Partition/cache/s*_cache.g** - Cached results for each S_n
- **Partition/batch_*_large.g** - Large groups (too big for IdGroup) from S13 computation
- **Partition/batch_*_types.g** - IdGroup types from S13 computation
- **Partition/validate_order_coverage.g** - Validation test for deduplication coverage

## Known Values

| n  | a(n)  | IdGroup types | Large groups |
|----|-------|---------------|--------------|
| 12 | 2065  | 1543          | 522          |
| 13 | 3845  | 2692          | 1153         |
| 14 | 7766  | 4602          | 3164         |

Note: a(14) was corrected from 7095 → 7739 → 7740 → 7754 → 7756 → 7755 → **7766** after multiple verification rounds (January-February 2026). The final correction from 7755 to 7766 came from the Triple Check (February 2026), which found 11 missing IdGroup types (1 of order 128 + 10 of order 256, all 2-groups lost in original merge).

The DC verification found:
- Original V3 computation was missing partition [8,2,2,2]
- Complete 6-way parallel run covered all 34 partitions (3,878 combinations)
- Cross-deduplication against S13: 2,768 S14 reps → 758 duplicates → 2,010 new S14 large (initial count)

**Bug in DC deduplication (discovered January 2026):**
- DC's `CompareByFactorsV3` algorithm had a bug when groups have TWO semidirect factors (in the old `ambiguousFactorGens` format)
- The algorithm only compared ONE factor (whichever `RecNames()` returned first), ignoring the other
- This caused an undercount of 1 group
- See `/isomorphism-testing` skill for details on the bug and fix

**Difficult bucket** (sigKey `[2592, 162, 42, 3, [2,2,2,2]]`):
- These groups do NOT decompose as direct products (`isDirectProduct=false`)
- Cannot use factor-level optimization - requires full `IsomorphismGroups` testing
- This is what makes them computationally expensive

Final (original Partition method): 4,591 IdGroup + 1,153 S13 large + 2,011 S14 new = 7,755
Final (Triple Check from conjugacy classes): 4,602 IdGroup + 3,164 large = **7,766**

See `Partition/Partion Double Check/dedupe_independent_v2/` for DC verification files.

## Deduplication Result Files

After S13 deduplication:
- `dedupe_result_1.g` through `dedupe_result_8.g` - Main 8-way results
- `dedupe_order_*.g` - Individual large order results
- `invariant_dedupe_p*.g` - Precomputed invariant-based deduplication results
- `missing_dedupe_p*.g` - Previously missed orders (55 orders, 280 groups)

## sigKey Format

The sigKey is an invariant signature used for bucketing groups during deduplication:

```
[ order, derived_size, conjugacy_classes, derived_length, abelian_invariants ]
```

- **order**: Size of the group
- **derived_size**: Size of the derived subgroup G'
- **conjugacy_classes**: Number of conjugacy classes
- **derived_length**: Length of derived series (positive for solvable groups, -1 for non-solvable)
- **abelian_invariants**: Abelian invariants of G/G'

**Historical Note**: The original merge scripts (`merge_s14_large.g`, `merge_s14_v2.g`) incorrectly used NilpotencyClass instead of DerivedLength for the 4th field. This was corrected in January 2026 by `compute_all_derivedlength.g` and `fix_all_sigkeys.py`, which updated all 12,421 S14 large groups with correct DerivedLength values. 739 groups had mismatched values (NilpotencyClass ≠ DerivedLength) that were fixed.

## Cross-Deduplication

**CRITICAL**: Within-Sn deduplication is NOT sufficient. New Sn large groups must also be compared against S(n-1) large groups.

Cross-deduplication uses multi-level filtering:
1. Order filter - groups with unique orders are guaranteed new
2. Basic sigKey filter - groups with unique signatures are guaranteed new
3. Extended fingerprint filter - groups with unique fingerprints are guaranteed new
4. Isomorphism testing - only for groups with matching fingerprints

**Extended Fingerprint** includes: order, derived size, center size, conjugacy classes, exponent, Frattini size, derived length, nilpotency class, abelian invariants, order profile (element order histogram).

See `Partition/cross_dedupe/` for implementation files.

## Verification Scripts

- `verify_bucket_coverage.py` - Analyzes output files to detect missing/overlapping buckets
- `count_results.py` - Counts groups in result files and checks for duplicate sigKeys
- `fix_result_files.py` - Identifies and reports double-counting issues
- `Partition/tests/run_all_tests.py` - Test suite for verifying deduplication implementations (see `/test-verification`)
- **`Partition/tests/test_groups_static.g`** - MANDATORY correctness test for any isomorphism testing script (41 groups with pre-computed invariants, 6 isomorphic pairs, 12 non-isomorphic pairs)

## Verification Checklist

Before finalizing any a(n) calculation:
- [ ] Run `validate_order_coverage.g` - must show "VALIDATION PASSED"
- [ ] Run `verify_bucket_coverage.py` - check for missing/duplicate buckets
- [ ] Run `count_results.py` - verify result file counts match output file counts
- [ ] Sum all IdGroup types from batch_*_types.g files
- [ ] Sum all deduplicated large groups from all result files
- [ ] **Cross-deduplicate Sn large groups against S(n-1) large groups**
- [ ] Cross-check: a(n) should be significantly larger than a(n-1)
- [ ] For n >= 12, expect a(n) ~ 1.5-2x * a(n-1)

When developing or modifying deduplication code:
- [ ] Run `python Partition/tests/validate_implementation.py <impl_dir>` - pre-flight validation must pass
- [ ] Run `python Partition/tests/run_all_tests.py --quick` - critical tests pass
- [ ] Run `python Partition/tests/run_all_tests.py --cygwin-only` - all Cygwin tests must pass
- [ ] Verify multi-factor regression test passes (multiple semidirect factors - difficult bucket pattern)
- [ ] **Validate isomorphism functions against `test_groups_static.g`** - ALL expected pairs must pass

## Skills - MUST Load When Relevant

These skills contain detailed workflows. **You MUST use the Skill tool** (e.g., `/crash-recovery`) when working on tasks matching these triggers:

| Skill | MUST Load When Task Involves | Command |
|-------|------------------------------|---------|
| crash-recovery | GAP crash, error, worker failed, "Action not well-defined", out of memory | `/crash-recovery` |
| deduplication | dedupe, deduplication, bucket assignment, order coverage, cross-dedupe | `/deduplication` |
| isomorphism-testing | IsomorphismGroups, compare groups, ANUPQ, 2-groups, PcGroupCode | `/isomorphism-testing` |
| resume-scripts | resume, continue interrupted worker, restart | `/resume-scripts` |
| bucket-tracking | tracking file, bucket assignment, master file, audit | `/bucket-tracking` |
| verification | verify results, failed isomorphism test, incomplete | `/verification` |
| s14-computation | S14 specifically, a(14), 7766, 7755, lessons learned | `/s14-computation` |
| test-verification | test suite, verify implementation, pre-flight validation, regression test, ground truth, bucket 54 test, validate before running | `/test-verification` |

## Critical Warnings

These are the most important lessons from prior computations:

1. **Cross-deduplication is MANDATORY**: Within-Sn deduplication is NOT sufficient. Every new Sn computation must cross-dedupe against S(n-1) large groups. (Details: `/deduplication`)

2. **ANUPQ crashes on Cygwin**: The ANUPQ package for 2-group isomorphism testing fails with "iostream dead" on Cygwin. Use WSL with `/mnt/c/...` paths instead. (Details: `/isomorphism-testing`)

3. **Verify completion BEFORE creating resume scripts**: Creating resume scripts for already-completed workers causes massive double-counting. Always check output file for "Complete" message AND exit code 0 before creating any resume script. (Details: `/resume-scripts`)

4. **Do NOT use PcGroupCode**: PcGroupCode is not canonical. Matching codes happen to indicate isomorphism, but different codes do NOT indicate non-isomorphism. Avoid PcGroupCode entirely — use IdGroup, ANUPQ's IsIsomorphicPGroup (for 2-groups), or IsomorphismGroups instead.

5. **Order coverage validation is mandatory**: Run `validate_order_coverage.g` BEFORE and AFTER any deduplication. 55 orders (280 groups) were silently dropped during S13 due to missing this check. (Details: `/deduplication`)

6. **Check ALL factorGens entries**: When using factor-level isomorphism testing, `factorGens` stores generators for ALL direct product factors (not just semidirect ones). The bipartite matching in `CompareByFactorsV3` must match every factor. The old `ambiguousFactorGens` field only stored semidirect factors, which caused DC to undercount a(14) by 1 group. (Details: `/isomorphism-testing`)

7. **Run pre-flight validation before ANY new deduplication**: Use `python Partition/tests/validate_implementation.py <impl_dir>` before running any computation. This catches critical bugs like the multi-factor comparison issue. (Details: `/test-verification`)

8. **Validate isomorphism scripts against test_groups_static.g**: ANY new script that performs group isomorphism testing MUST be validated against `Partition/tests/test_groups_static.g` before production use. This file contains 41 test groups with 6 expected isomorphic pairs and 12 expected non-isomorphic pairs. All pairs must pass. (Details: `/test-verification`)

9. **Use `factorGens` (not `ambiguousFactorGens`)**: The `factorGens` field stores generators for ALL direct product factors, positionally aligned with `factors` and `factorOrders`. This replaces the old `ambiguousFactorGens` which only stored semidirect factors and had name-collision bugs. The three arrays are co-sorted by `(order, name)` for canonical ordering. See `triple_check/process_s14_subgroups.g` for the implementation and `tc_test_validation.g` Part 5 for regression tests.
