# A174511(16) = 43,626 — Independent Verification

Self-contained verification system for A174511(16) = 43,626, the number of
isomorphism types of subgroups of the symmetric group S₁₆.

## Quick Start

```bash
# Prerequisites: Python 3.6+, GAP 4.14+, 7-Zip, ~16 GB RAM
cd s16_final_results_reindexed/verification_script

# Full verification (~6 hrs)
python run_verification.py

# Faster run, skipping invariant recomputation (~3 hrs)
python run_verification.py --skip-invariants

# Fastest run, skipping invariants + F/G/H discrimination (~2.5 hrs)
python run_verification.py --skip-invariants --skip-fgh
```

The script automatically extracts data from `s16_final_results.7z` (14 MB),
detects GAP, and runs all phases with crash recovery.

## What It Proves

The verification establishes A174511(16) = 43,626 by proving two independent bounds:

**Upper bound (≤ 43,626):** All 686,165 conjugacy classes of subgroups of S₁₆
collapse to at most 43,626 isomorphism types:
- 43,626 type representatives
- 154,656 explicit isomorphism proofs (duplicate → representative)
- 487,883 classes identified via GAP's `IdGroup`

**Lower bound (≥ 43,626):** All 43,626 type representatives are pairwise
non-isomorphic, proven by invariant discrimination using 8 methods (A–H):

| Method | Description | Types Distinguished |
|--------|-------------|---------------------|
| A | Unique group order | 14,348 |
| B | `IdGroup` identification | 14,170 |
| C | Unique sigKey (order, |G'|, #CC, derived length, abelian invariants) | 6,458 |
| D | Element order histogram | 5,406 |
| E | Multi-level invariant cascade (T1–T8) | 2,050 |
| F | Character table comparison | 998 |
| G | Character table + Sylow subgroup analysis | 100 |
| H | Explicit `IsomorphismGroups` (returns `fail`) | 96 |

## Verification Phases

| Phase | Description | Time | What It Checks |
|-------|-------------|------|----------------|
| 0 | Structural integrity | ~2 min | Python-only: certificate format, field presence, partition consistency, discrimination soundness (no cross-method collisions) |
| 1 | Proof validation | ~5 min | 4 parallel GAP workers validate all 154,656 proofs: each proof's generators define a group isomorphic to the duplicate, and the gen→image mapping is a valid homomorphism to the representative |
| 2 | Certificate invariant recomputation | ~3 hrs | Single GAP process loads all 686,165 subgroup generator lists, recomputes every invariant (order, IdGroup, sigKey, histogram, E7 cascade, E-type discriminants) from scratch, compares against certificate |
| 3 | F/G/H discrimination | ~30 min | Recomputes CharacterTable comparisons (F/G methods) and explicit `IsomorphismGroups` tests (H method) for 1,194 type pairs |
| 4 | Class-to-type mapping rebuild | ~3 min | 2 parallel workers independently rebuild the 686,165-entry class→type mapping by following proof chains and computing IdGroup, then compare against provided mapping |

## Command-Line Options

```
python run_verification.py [OPTIONS]

  --skip-invariants    Skip Phase 2 (saves ~3 hrs)
  --skip-fgh           Skip Phase 3 (saves ~30 min)
  --phase 0,1,4        Run only specific phases
  --resume             Skip phases whose results are already complete
  --gap-path PATH      Path to GAP binary (or Cygwin bash.exe on Windows)
  --memory 16g         GAP memory per worker (default: 16g)
  --cert-memory 50g    GAP memory for Phase 2 (default: 50g)
```

## Data Files

All data is contained in `s16_final_results.7z` (14 MB, auto-extracted):

| File | Size | Description |
|------|------|-------------|
| `s16_subgroups.g` | 254 MB | 686,165 generator lists (one per conjugacy class of subgroups of S₁₆) |
| `s16_verification_certificate_v7.g` | 3.6 MB | 43,626 type records with distinguishing invariants |
| `s16_master_proofs_repaired_v2.g` | 84 MB | 154,656 isomorphism proofs |
| `s16_class_to_type.g` | 3.5 MB | 686,165-entry class-to-type mapping |
| `s16_large_invariants.g` | 7.3 MB | Extended invariants for large groups |

## Verification Scripts

Core scripts (all in `verification_script/`):

| Script | Language | Description |
|--------|----------|-------------|
| `run_verification.py` | Python | Master orchestrator — single entry point |
| `verify_cert_structural.py` | Python | Phase 0: structural integrity |
| `verify_discrimination_soundness.py` | Python | Phase 0: discrimination collision detection |
| `verify_proofs_worker.g` | GAP | Phase 1: proof validation worker |
| `verify_proof_coverage.py` | Python | Phase 1: arithmetic coverage check |
| `verify_cert_from_subgroups.g` | GAP | Phase 2: invariant recomputation |
| `verify_cert_phase78.g` | GAP | Phase 3: F/G/H discrimination |
| `verify_class_to_type_worker.g` | GAP | Phase 4: class-to-type rebuild |

## Sample Output

```
================================================================
  A174511(16) VERIFICATION RESULTS
  Total elapsed: 5h 42m 18s
================================================================

  Phase 0: PASS  — Structural integrity
  Phase 1: PASS  — Proof validation (154,656 proofs)
  Phase 2: PASS  — Certificate invariants (43,626 types)
  Phase 3: PASS  — F/G/H discrimination (1,098 F/G + 96 H pairs)
  Phase 4: PASS  — Class-to-type rebuild (686,165 classes)

  UPPER BOUND: 686,165 = 43,626 reps + 154,656 proofs + 487,883 IdGroup   [VERIFIED]
  LOWER BOUND: 43,626 types pairwise non-isomorphic (methods A-H)          [VERIFIED]

  >>> A174511(16) = 43,626   [INDEPENDENTLY VERIFIED] <<<

================================================================
```

## Requirements

- **Python 3.6+**
- **GAP 4.14+** (Cygwin distribution on Windows, native on Linux/macOS)
- **7-Zip** (Windows) or **p7zip** (Linux/macOS) for archive extraction
- **~16 GB RAM** (Phase 2 uses 50 GB GAP workspace but actual usage is ~12 GB)
- **~500 MB disk** for extracted data files

## Platform Notes

- **Windows**: Uses GAP's Cygwin bash (`C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe`). Paths are auto-converted to Cygwin format.
- **Linux/macOS**: Uses system `gap` binary. Pass `--gap-path` if not on PATH.
- All phases include automatic crash recovery with checkpoint resume (up to 30 retries for GAP phases, 50 for Phase 2).
