# A174511(16) = 43,626 — Independent Verification

Self-contained verification system for A174511(16) = 43,626, the number of
isomorphism types of subgroups of the symmetric group S₁₆.

## Quick Start

```bash
# Prerequisites: Python 3.6+, GAP 4.14+, 7-Zip, ~16 GB RAM
cd s16_final_results_reindexed/verification_script

# Full verification (~6 hrs)
python run_verification.py

# With conjugacy verification (~18-30 hrs)
python run_verification.py --conjugacy

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

## How It Works

The verification proves A174511(16) = 43,626 by establishing matching upper and lower bounds. Everything starts from a single 14 MB compressed archive (`s16_final_results.7z`) containing five data files: the 686,165 subgroup generator lists, a type certificate with 43,626 records, 154,656 isomorphism proofs, a class-to-type mapping, and extended invariant data. The orchestrator (`run_verification.py`) extracts these files, detects the local GAP installation, and runs five phases in sequence with automatic crash recovery.

The **upper bound** (at most 43,626 types) is proven by showing that every one of the 686,165 conjugacy classes maps to one of 43,626 type representatives. Phase 1 validates all 154,656 isomorphism proofs: for each proof claiming that class *d* is isomorphic to representative *r*, the verifier reconstructs both groups from their generators, confirms they have the same order, checks that the proof generators lie in the duplicate group, and verifies that the generator-to-image mapping extends to a valid group homomorphism via `GroupHomomorphismByImages`. Phase 4 then independently rebuilds the entire class-to-type mapping: for each of the 686,165 classes, it determines the type either by finding the class among the type representatives, following a validated proof chain to a representative, or computing `IdGroup` and matching against the certificate's B-type entries. The rebuilt mapping is compared entry-by-entry against the provided one, and the arithmetic identity 686,165 = 43,626 + 154,656 + 487,883 is confirmed.

The **lower bound** (at least 43,626 types) is proven by showing that all 43,626 type representatives are pairwise non-isomorphic. The certificate assigns each adjacent pair of types a discrimination method (A through H) and the verifier recomputes the distinguishing invariant from scratch. Methods A and B are trivial: types with unique group orders or unique `IdGroup` identifiers are obviously distinct. Method C uses the "sigKey" — a tuple of order, derived subgroup size, conjugacy class count, derived length, and abelian invariants — which the verifier recomputes from raw generators and checks against the certificate. Method D uses element order histograms (the distribution of element orders in the group), recomputed by iterating over all group elements. Method E applies a multi-level cascade of progressively more expensive invariants (Sylow subgroup structure, center size, Frattini subgroup, and more). Methods F and G use character table comparison via GAP's `CharacterTable`, and method H calls `IsomorphismGroups` directly and confirms it returns `fail`.

Phase 2 performs the heaviest lifting: it loads all 686,165 generator lists (254 MB) into a single GAP session and recomputes every invariant claimed in the certificate. This includes rebuilding sigKeys for all 29,278 types that use them, recomputing element order histograms for all 15,230 types that claim histogram discrimination, and verifying the E-type cascade for 5,294 types. Every recomputed value is compared against the certificate, and any mismatch is reported as a failure. Phase 3 handles the 1,194 type pairs that require character table comparison (methods F and G) or explicit `IsomorphismGroups` calls (method H, 96 pairs), independently confirming that GAP cannot find an isomorphism between them.

An optional **Phase 5** independently confirms A000638(16) = 686,165 by verifying that the 686,165 conjugacy class representatives are truly pairwise non-conjugate in S₁₆. Strictly speaking, the upper bound proof assumes the input list of 686,165 classes is correct — Phase 5 verifies this assumption. Classes are grouped into (type, orbit-type) buckets: two classes can only be conjugate if they have the same isomorphism type and the same orbit structure on 16 points. This reduces the problem from ~2.4×10¹¹ potential pairs to 70 million. Within large buckets, a second round of sub-bucketing uses conjugacy class histograms — for each conjugacy class of the group, the triple (element order, fixed point count, class size) — to further eliminate pairs. The remaining pairs are tested with GAP's `IsConjugate`. Eight parallel workers handle the 50,337 non-singleton buckets with interleaved assignment for load balancing.

The default run (Phases 0–4) takes approximately 6 hours. Adding `--conjugacy` for Phase 5 adds roughly 12–24 hours depending on hardware. For faster turnaround, `--skip-invariants` omits Phase 2 (saving ~3 hours) and `--skip-fgh` omits Phase 3 (saving ~30 minutes). Even with these flags, the upper bound is fully proven, and the lower bound is partially verified by the remaining phases. All GAP phases include automatic crash recovery: if a process is killed or runs out of memory, the orchestrator detects checkpoint files from prior progress and relaunches, resuming from where it left off.

## Verification Phases

| Phase | Description | Time | What It Checks |
|-------|-------------|------|----------------|
| 0 | Structural integrity | ~2 min | Python-only: certificate format, field presence, partition consistency, discrimination soundness (no cross-method collisions) |
| 1 | Proof validation | ~5 min | 4 parallel GAP workers validate all 154,656 proofs: each proof's generators define a group isomorphic to the duplicate, and the gen→image mapping is a valid homomorphism to the representative |
| 2 | Certificate invariant recomputation | ~3 hrs | Single GAP process loads all 686,165 subgroup generator lists, recomputes every invariant (order, IdGroup, sigKey, histogram, E7 cascade, E-type discriminants) from scratch, compares against certificate |
| 3 | F/G/H discrimination | ~30 min | Recomputes CharacterTable comparisons (F/G methods) and explicit `IsomorphismGroups` tests (H method) for 1,194 type pairs |
| 4 | Class-to-type mapping rebuild | ~3 min | 2 parallel workers independently rebuild the 686,165-entry class→type mapping by following proof chains and computing IdGroup, then compare against provided mapping |
| 5 | Conjugacy verification (optional) | ~12-24 hrs | 8 parallel workers verify all 686,165 classes are pairwise non-conjugate within (type, orbit-type) buckets, confirming A000638(16) = 686,165. Enable with `--conjugacy`. |

## Command-Line Options

```
python run_verification.py [OPTIONS]

  --skip-invariants    Skip Phase 2 (saves ~3 hrs)
  --skip-fgh           Skip Phase 3 (saves ~30 min)
  --conjugacy          Include Phase 5: conjugacy verification (~12-24 hrs)
  --conj-workers N     Number of workers for Phase 5 (default: 8)
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
| `build_conjugacy_buckets.py` | Python | Phase 5: build (type, orbit-type) buckets |
| `verify_smart_worker.g` | GAP | Phase 5: conjugacy verification worker |

## Sample Output

Default run (Phases 0–4):
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
  Phase 5: SKIPPED  — Conjugacy verification (686,165 classes non-conjugate)

  UPPER BOUND: 686,165 = 43,626 reps + 154,656 proofs + 487,883 IdGroup   [VERIFIED]
  A000638(16): 686,165 (not independently verified — use --conjugacy)
  LOWER BOUND: 43,626 types pairwise non-isomorphic (methods A-H)          [VERIFIED]

  >>> A174511(16) = 43,626   [INDEPENDENTLY VERIFIED] <<<

================================================================
```

With `--conjugacy` (Phases 0–5):
```
  Phase 5: PASS  — Conjugacy verification (686,165 classes non-conjugate)

  UPPER BOUND: 686,165 = 43,626 reps + 154,656 proofs + 487,883 IdGroup   [VERIFIED]
  A000638(16): 686,165 classes pairwise non-conjugate                      [VERIFIED]
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
