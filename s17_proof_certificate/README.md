# A174511(17) = 84,246 — Proof Certificate and Verification

**Result**: There are exactly **84,246** isomorphism types of subgroups of the
symmetric group S_17.

This directory contains a self-contained, reproducible verification pipeline.
Anyone with GAP 4.15+ and Python 3.8+ can independently verify the result.

## Quick Start

```bash
python verify_a174511_17.py              # Run full verification (~2-3 hours)
python verify_a174511_17.py --workers 6  # Use 6 parallel GAP workers (faster)
python verify_a174511_17.py --skip-gap   # Python-only checks (~10 seconds)
```

## Data Files

All data lives in `data/`. Compressed files are decompressed to `work/` at runtime.

| File | Compressed | Raw | Contents |
|------|-----------|-----|----------|
| `s17_subgroups_cycles.g.gz` | 7.7 MB | 191 MB | 1,466,358 conjugacy class representatives (generators as permutations) |
| `s17_proofs.g.gz` | 14 MB | 176 MB | 389,889 isomorphism proofs (generators + images defining a homomorphism) |
| `s17_idgroup_map.g.gz` | 3.7 MB | 42 MB | IdGroup lookups mapping 1,015,460 class indices to [order, id] pairs |
| `s17_verification_certificate_v5.g` | 8.7 MB | — | 84,246 type records with method, invariants, and representative index |

Total compressed: ~34 MB.

## Certificate Structure

The certificate file (`s17_verification_certificate_v5.g`) contains one record
per isomorphism type. Each record has the form:

```gap
rec(
  t := 42,              # Type number (1..84246)
  i := 105327,          # Index into s17_subgroups_cycles.g (representative)
  m := "D",             # Method used to distinguish this type (see below)
  o := 720,             # Group order
  sk := "[720,360,22,3,[2]]",  # sigKey (if method C or higher)
  h := "[1,44,...]",    # Element-order histogram (if method D or higher)
  aut := 1440,          # |Aut(G)| (if method E or higher)
  crpf := "a3b2c1...",  # Character table fingerprint hash (if method F or higher)
  pair := 42001         # Paired type number (method G only)
)
```

### Classification Methods

Every type is assigned a **method** indicating how it is distinguished from all
other types. The methods form a cascade of increasingly expensive invariants:

| Method | Count | Meaning | Distinguishing invariant |
|--------|-------|---------|------------------------|
| **A** | 176 | Unique order | No other type has this group order |
| **B** | 23,199 | Unique IdGroup | Distinguished by GAP's SmallGroups library ID `[order, id]` |
| **C** | 16,880 | Unique sigKey | Distinguished by `[order, |G'|, nrCC, derivedLength, abelianInvariants]` |
| **D** | 32,646 | Unique (sigKey, histogram) | Same sigKey but unique element-order histogram |
| **E** | 5,963 | Unique (sigKey, histogram, \|Aut\|) | Same (sigKey, histogram) but unique automorphism group order |
| **F** | 5,360 | Unique crpfHash | Same (sigKey, histogram, \|Aut\|) but unique character table fingerprint |
| **G** | 22 | Non-isomorphic pair | All invariants identical; confirmed distinct by `IsomorphismGroups` returning `fail` |

**Total**: 176 + 23,199 + 16,880 + 32,646 + 5,963 + 5,360 + 22 = **84,246**

### Invariant Details

- **sigKey**: `[order, derivedSubgroupSize, nrConjugacyClasses, derivedLength, abelianInvariants]`
  - `derivedLength = -1` for non-solvable groups
- **histogram**: Element-order histogram — for each element order `d` dividing `|G|`,
  the number of elements of order `d`, formatted as a sorted list
- **crpfHash**: Canonical Row-Power Fingerprint — a hash of the character table that
  is invariant under permutation of conjugacy classes. Computed as a SHA-256 digest
  of sorted (power map + character value) fingerprints per conjugacy class.

### Proof File Structure

Each proof in `s17_proofs.g` establishes that a duplicate conjugacy class
representative is isomorphic to a type representative:

```gap
rec(
  duplicate := 500123,          # Index of the duplicate class
  representative := 105327,     # Index of the type representative
  gens := [(1,2,3), (1,2)],    # Generators of the duplicate's group
  images := [(4,5,6), (4,5)],  # Images under the isomorphism
  method := "projLift"          # Method used to find the isomorphism
)
```

The proof is valid if `GroupHomomorphismByImages(G_dup, G_rep, gens, images)`
returns a non-`fail` homomorphism in GAP (i.e., the mapping on generators
extends to a genuine group homomorphism).

### IdGroup Map Structure

The IdGroup map (`s17_idgroup_map.g`) provides `[order, id]` pairs for all
conjugacy classes whose groups are small enough for GAP's SmallGroups library
(order < 2000, excluding orders 512, 768, 1024, 1536):

```gap
S17_IDGROUP_MAP := [
  [index1, order1, id1],
  [index2, order2, id2],
  ...
];
```

Two groups with the same `[order, id]` are isomorphic by definition.

## Verification Pipeline

The verification script runs 6 phases:

### Phase 0: Setup
Decompresses `.gz` files to `work/` (~409 MB total).

### Phase 1: Certificate Internal Consistency (Python, ~1 second)
- Verifies 84,246 type records with contiguous type numbers 1..84,246
- Checks all representative indices are unique
- Verifies A-types have unique orders
- Verifies C-types have unique sigKeys within their invariant bucket
- Verifies D-types have unique (sigKey, histogram) pairs
- Verifies E-types have unique (sigKey, histogram, |Aut|) triples
- Verifies F-types have unique crpfHash within their bucket
- Verifies G-types form valid pairs with identical invariants

### Phase 2: Proof Validation (GAP, parallel, ~7 minutes)
- Validates all 389,889 isomorphism proofs
- For each proof: constructs `GroupHomomorphismByImages(G, H, gens, images)`
  and verifies it returns a valid homomorphism (not `fail`)
- Zero tolerance: any invalid proof is a pipeline failure

### Phase 3: Invariant Verification (GAP, parallel, ~40 minutes)
- Recomputes invariants from actual group generators for all types that declare them:
  - **Order**: recomputed for all 84,246 types
  - **sigKey**: recomputed for all types with `sk` field
  - **Histogram**: recomputed for all types with `h` field
  - **|Aut|**: recomputed for all types with `aut` field
- Compares each recomputed value against the certificate

### Phase 3b: crpfHash Verification (GAP, parallel, ~1 hour)
- Recomputes character table fingerprint hashes for all 5,358 F/G-types
- Uses canonical Row-Power Fingerprint: for each conjugacy class, compute
  power map signature + character values, sort, hash
- Compares against certificate's `crpf` field

### Phase 4: G-pair Verification (GAP, ~30 minutes)
- Runs `IsomorphismGroups` on all 11 G-pairs (22 types)
- Confirms each pair returns `fail` (groups are genuinely non-isomorphic)
- These are the hardest cases: all computable invariants are identical

### Phase 5: Class-to-Type Map (Python, ~10 seconds)
- Builds a complete mapping from all 1,466,358 conjugacy class indices to
  their type number (1..84,246), using three sources:
  - 84,246 type representative indices (direct from certificate)
  - 1,015,460 IdGroup lookups (matching `[order, id]` to B-type representatives)
  - 389,889 proof chain resolutions (following duplicate -> representative chains)
- Verifies 100% coverage (every class index assigned to exactly one type)
- Computes A174511(n) for n = 0..17 by finding the minimum class index per type
  and checking which S_n each type first appears in
- Cross-checks against known values: A174511(12) = 2,065; A174511(13) = 3,845;
  A174511(14) = 7,766

## Results

The full verification produces:

```
A174511(n):
   n   A000638(n)   A174511(n)      New
----------------------------------------
   0            1            1        1
   1            1            1        0
   2            2            2        1
   3            4            4        2
   4           11            9        5
   5           19           16        7
   6           56           29       13
   7           96           55       26
   8          296          137       82
   9          554          241      104
  10        1,593          453      212
  11        3,094          894      441
  12       10,723        2,065    1,171
  13       20,832        3,845    1,780
  14       75,154        7,766    3,921
  15      159,129       16,438    8,672
  16      686,165       43,626   27,188
  17    1,466,358       84,246   40,620
```

Where:
- **A000638(n)** = number of conjugacy classes of subgroups of S_n
- **A174511(n)** = number of isomorphism types of subgroups of S_n
- **New** = types appearing for the first time at this n (not isomorphic to
  any subgroup of S_{n-1})

## Requirements

- **GAP 4.15+** with Cygwin runtime (Windows) or native (Linux/Mac)
- **Python 3.8+**
- ~500 MB disk space for decompressed working files
- ~8 GB RAM per GAP worker (configurable via script)

## Verification Output

A successful run of the included `verify_run.log` shows:

```
Phase 0: PASS  — Data decompressed
Phase 1: PASS  — Certificate internally consistent
Phase 2: PASS  — 389,889/389,889 proofs valid
Phase 3: PASS  — All invariants match (orders, sigKeys, histograms, |Aut|)
Phase 3b: PASS — 5,358/5,358 crpfHash values match
Phase 4: PASS  — 11/11 G-pairs confirmed non-isomorphic
Phase 5: PASS  — 1,466,358/1,466,358 classes mapped, A174511(12..14) cross-checked

*** A174511(17) = 84,246 VERIFIED ***
```
