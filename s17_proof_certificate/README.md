# A174511(17) = 84,244 — Proof Certificate and Verification

**Result**: There are exactly **84,244** isomorphism types of subgroups of the symmetric group S₁₇.

> **Correction (2026-09-28).** An earlier version of this certificate (v5) reported 84,246. Two pairs
> of isomorphic groups had been counted as distinct types. Both errors started with a GAP bug:
> `IsomorphismGroups` returned `fail` for isomorphic groups (GAP issue
> [#6537](https://github.com/gap-system/gap/issues/6537)). One of them was then also "confirmed" by a
> character-table hash that is not an isomorphism invariant. See
> **[CORRECTION_A174511_17.md](CORRECTION_A174511_17.md)** for the causes, the evidence, and the audit
> that re-established every separation.

This directory contains a self-contained, reproducible verification pipeline. Anyone with GAP 4.15+
and Python 3.9+ can check the result independently.

## Quick start

```bash
python verify_a174511_17_v6.py --workers 2                              # full verification (~10-12 h on 2 workers)
python verify_a174511_17_v6.py --phases 0,1 --workers 2                 # Python-only consistency checks (~1 min)
python verify_a174511_17_v6.py --workers 2 --reuse-tables audit/tables  # reuse saved character tables (~4-6 h)
```

## Data files

| File | Contents |
|------|----------|
| `data/s17_subgroups_cycles.g.gz` | 1,466,358 conjugacy class representatives of subgroups of S₁₇ (generators in cycle notation) |
| `data/s17_verification_certificate_v6.g` | 84,244 type records: representative class index, method, invariants |
| `data/s17_proofs_v6.g.gz` | 389,891 isomorphism proofs (duplicate class → representative class, generators and images) |
| `data/s17_idgroup_map.g.gz` | [order, id] for the 1,015,460 classes whose order GAP's SmallGroups library identifies |
| `audit/tables/` | full character tables of all 11,345 types of v5's categories E/F/G (from the 2026-09 audit) |
| `v6_gap/` | GAP code used by the verifier, and `ctinv.py` (the character-table invariant) |

The v5 files (`s17_verification_certificate_v5.g`, `s17_proofs.g.gz`, `verify_a174511_17.py`) are
kept unchanged for the record.

## Certificate structure

One record per isomorphism type:

```gap
rec(t := 42, i := 105327, m := "D", o := 720, sk := [...], h := [...])
```

Here `t` is the type number (1..84244), `i` the index of the representative class in
`s17_subgroups_cycles.g`, and `m` the method that distinguishes this type from all others:

| Method | Count | Distinguished from every other type by |
|--------|------:|----------------------------------------|
| **A** | 176 | its order |
| **B** | 24,068 | its SmallGroups identifier `id := [order, IdGroup]` |
| **C** | 16,880 | its sigKey `sk := [order, \|G'\|, #classes, derived length (−1 if non-solvable), abelian invariants]` |
| **D** | 32,658 | its (sigKey, element-order histogram `h`) |
| **H** | 10,458 | its label-free character-table invariant `ctinv`, within its (sigKey, histogram) bucket |
| **G** | 4 (2 pairs) | its pair partner has an identical character table; separated by `ns`, the `IdGroup`s of the normal subgroups of order `nsord`, and independently by complete coset-action search |

**The character-table invariant `ctinv`.** A character table is determined by the group only up to the
order of its rows (irreducible characters) and columns (classes), and its power maps refer to column
positions. `ctinv` records nothing that depends on those orderings:

- Classes start coloured by (element order, class size) and characters by degree.
- Each round, a class's colour is refined by the sorted multiset of (character colour, value) and by
  the colours of its p-th power classes. A character's colour is refined by the sorted multiset of
  (class colour, value).
- Refinement stops when the partitions no longer split. The result is the SHA-256 hash of the final
  sorted colour multisets (`v6_gap/ctinv.py`).

Isomorphic groups therefore always get equal `ctinv`, and different values prove non-isomorphism. The
verifier also recomputes it on randomly relabelled copies, which must reproduce the original value.

**The complete coset-action search.** For permutation groups D and R of equal order, where D has
orbits O₁,…,O_k: D ≅ R if and only if R, acting on the disjoint union of the coset spaces R/H_j for
some conjugacy classes of subgroups H_j with [R:H_j] = |O_j|, is conjugate to D in Sym(O₁)×…×Sym(O_k).
Searching all such tuples either finds an isomorphism or proves there is none (`v6_gap/coset_engine.g`).

**The G-pairs.** Only one pair of groups needs more than the invariants above, and it appears twice:
- types 43999/44000, order 4,000 on 15 points;
- types 54779/54780, the same two groups times C₂.

The two character tables are identical, power maps included. The pair is separated by its normal
subgroups of order 2,000, which for the order-4,000 groups are exactly the three index-2 subgroups:

| | `ns` = sorted [IdGroup(N), IdGroup(G/N)] over normal N with \|N\| = 2000 |
|---|---|
| type 43999 | [2000, 902], [2000, 912], [2000, 924], each with quotient C₂ |
| type 44000 | [2000, 901], [2000, 913], [2000, 924], each with quotient C₂ |

The certificate stores `nsord := 2000` and `ns` for each G-type. The verifier recomputes both from
the class groups and checks that they differ within each pair. The complete coset-action search is a
second, independent proof.

Not used as evidence anywhere: |Aut(G)|, a `fail` from `IsomorphismGroups`, or v5's `crpfHash`.

**Proofs** (`s17_proofs_v6.g`) each have the form
`rec(duplicate := N, representative := M, gens := [...], images := [...], method := "...")`.
A proof is valid when `gens` generate class N's group, `images` lie in class M's group, and
gens ↦ images extends to a bijective homomorphism.

## Verification pipeline (`verify_a174511_17_v6.py`)

| Phase | Check |
|------:|-------|
| 0 | decompress the data files into `work_v6/` |
| 1 | certificate consistency: counts, contiguous numbering, each category's uniqueness claim, and separating evidence for every pair of types sharing (sigKey, histogram) |
| 2 | all 389,891 proofs, against the *actual* class groups |
| 3 | order, sigKey and histogram of every type, and IdGroup of every B-type, recomputed |
| 3b | `ctinv` of every H/G type recomputed from its character table, plus 40 relabelling self-tests |
| 4 | every G-pair: `ns` recomputed and different within the pair; complete coset-action search must prove non-isomorphism |
| 5 | every IdGroup-map entry recomputed; class-to-type map (all 1,466,358 classes); A174511(n) for n ≤ 17 |

## Results

The verification run of 2026-09-28 (`verify_run_v6.log`) passed every phase. The G-pairs' `ns`
fields were added afterwards, and phases 1 and 4 were re-run on the final file
(`verify_run_v6_gpairs.log`). The run reproduces the known values for n = 12..14 and the S₁₅ and S₁₆
certificates:

```
   n   A000638(n)   A174511(n)      New
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
  17    1,466,358       84,244   40,618
```

A000638(n) is the number of conjugacy classes of subgroups of S_n. "New" counts the types first
appearing in S_n, i.e. not isomorphic to any subgroup of S_{n−1}.

## Requirements

- GAP 4.15+ (Cygwin build on Windows, or native Linux/macOS; adjust `GAP_BASH`/`GAP_CMD` in the script)
- Python 3.9+
- about 2 GB of disk space for the decompressed working files and recomputed character tables
- about 12 GB of RAM per GAP worker for the largest character tables
