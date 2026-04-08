# A174511(16) = 43,626 — Proof Certificate and Verification

**Result**: There are exactly **43,626** isomorphism types of subgroups of the
symmetric group S_16.

This directory contains a self-contained, reproducible verification pipeline.
Anyone with GAP 4.15+ and Python 3.8+ can independently verify the result.

## Quick Start

```bash
python verify_a174511_16.py              # Run full verification (~2-4 hours)
python verify_a174511_16.py --workers 6  # Use 6 parallel GAP workers (faster)
python verify_a174511_16.py --skip-gap   # Python-only checks (~10 seconds)
```

## Data Files

All data lives in `data/`. Compressed files are decompressed to `work/` at runtime.

| File | Compressed | Raw | Contents |
|------|-----------|-----|----------|
| `s16_subgroups.g.gz` | 6.2 MB | 254 MB | 686,165 conjugacy class representatives (generators as image lists) |
| `s16_proofs.g.gz` | 6.2 MB | 78 MB | 154,660 isomorphism proofs (generators + images defining a homomorphism) |
| `s16_idgroup_map.g.gz` | ~3 MB | ~30 MB | IdGroup lookups mapping class indices to [order, id] pairs |
| `s16_verification_certificate.g` | 4.2 MB | -- | 43,626 type records with method, invariants, and representative index |

Total compressed: ~20 MB.

## Certificate Structure

The certificate file (`s16_verification_certificate.g`) contains one record
per isomorphism type, derived from the verified S17 certificate. Each record:

```gap
rec(
  t := 42,              # Type number (1..43626)
  i := 105327,          # Index into s16_subgroups.g (representative)
  m := "D",             # Method used to distinguish this type (see below)
  o := 720,             # Group order
  sk := [720,360,22,3,[2]],   # sigKey (if method C or higher)
  h := [[1,1],[2,44],...],     # Element-order histogram (if method D or higher)
  aut := 1440,                 # |Aut(G)| (if method E or higher)
  crpfHash := "a3b2c1...",     # Character table fingerprint hash (if method F or higher)
  pair := 42001                # Paired type number (method G only)
)
```

### Classification Methods

| Method | Count | Meaning | Distinguishing invariant |
|--------|-------|---------|------------------------|
| **A** | 146 | Unique order | No other type has this group order |
| **B** | 14,202 | Unique IdGroup | Distinguished by GAP's SmallGroups library ID `[order, id]` |
| **C** | 8,773 | Unique sigKey | Distinguished by `[order, \|G'\|, nrCC, derivedLength, abelianInvariants]` |
| **D** | 14,073 | Unique (sigKey, histogram) | Same sigKey but unique element-order histogram |
| **E** | 3,245 | Unique (sigKey, histogram, \|Aut\|) | Same (sigKey, histogram) but unique automorphism group order |
| **F** | 3,173 | Unique crpfHash | Same (sigKey, histogram, \|Aut\|) but unique character table fingerprint |
| **G** | 14 | Non-isomorphic pair | All invariants identical; confirmed distinct by `IsomorphismGroups` returning `fail` |

**Total**: 146 + 14,202 + 8,773 + 14,073 + 3,245 + 3,173 + 14 = **43,626**

### Proof File Structure

Each proof in `s16_proofs.g` establishes that a duplicate conjugacy class
representative is isomorphic to a type representative:

```gap
rec(
  duplicate := 500123,
  representative := 105327,
  gens := ["(1,2,3)", "(1,2)"],       # Generators (cycle notation strings)
  images := ["(4,5,6)", "(4,5)"],     # Images under the isomorphism
  method := "projLift"
)
```

The proof is valid if `GroupHomomorphismByImages(G_dup, G_rep, gens, images)`
returns a non-`fail` homomorphism in GAP.

### Subgroups File Format

The subgroups file (`s16_subgroups.g`) uses GAP's `ReadAsFunction` format with
generators as image lists (not cycle notation):

```gap
return [
  [ [1,2,3,13,5,9,...,16], [1,9,12,13,...,16] ],  # Class 1: two generators
  [ [1,2,3,13,...], [1,5,6,4,...] ],                # Class 2: two generators
  ...
];
```

Each inner list is a permutation represented as its image list on {1..16}.
In GAP: `Group(List(generators, PermList))` constructs the group.

## Verification Pipeline

### Phase 0: Setup
Decompresses `.gz` files to `work/` (~340 MB total).

### Phase 1: Certificate Internal Consistency (Python, ~1 second)
- Verifies 43,626 type records with contiguous type numbers
- Checks all representative indices are unique
- Verifies uniqueness properties for each method level

### Phase 2: Proof Validation (GAP, parallel, ~5-10 minutes)
- Validates all 154,660 isomorphism proofs via GroupHomomorphismByImages
- Zero tolerance: any invalid proof fails the phase

### Phase 3: Invariant Verification (GAP, parallel, ~30-60 minutes)
- Recomputes invariants from actual groups for all types declaring them
- Compares order, sigKey, histogram, |Aut| against certificate values

### Phase 3b: crpfHash Verification (GAP, parallel, ~30-60 minutes)
- Recomputes character table fingerprint hashes for F/G-types
- Compares against certificate's `crpfHash` field

### Phase 4: G-pair Verification (GAP, ~5-30 minutes)
- Runs `IsomorphismGroups` on all 7 G-pairs (14 types)
- Confirms each pair returns `fail` (groups genuinely non-isomorphic)

### Phase 5: Class-to-Type Map (Python, ~10 seconds)
- Builds complete mapping from all 686,165 classes to 43,626 types
- Computes A174511(n) for n = 0..16
- Cross-checks known values at n = 12, 13, 14

## Results

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
```

## Requirements

- **GAP 4.15+** with Cygwin runtime (Windows) or native (Linux/Mac)
- **Python 3.8+**
- ~400 MB disk space for decompressed working files
- ~8 GB RAM per GAP worker

## Relationship to S17 Verification

This S16 certificate was derived from the verified S17 certificate
(`s17_proof_certificate/s17_verification_certificate_v5.g`). All 43,626 S16
types were matched to their corresponding S17 types by invariants, ensuring
consistency between the two verification pipelines. The S16 data files
(subgroups, proofs, IdGroup map) use S16-native indices and are independently
verifiable.
