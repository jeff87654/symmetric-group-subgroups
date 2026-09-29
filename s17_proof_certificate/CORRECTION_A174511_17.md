# Correction: A174511(17) = 84,244 (not 84,246)

*Prepared 2026-09-28. Supersedes the value in `README.md` / `s17_verification_certificate_v5.g`.*

## Summary

The number of isomorphism types of subgroups of the symmetric group S₁₇ is **84,244**. The value
84,246 reported earlier counted two pairs of isomorphic groups as distinct types:

| Types (v5 certificate) | Class indices in `s17_subgroups_cycles.g` | Order | Structure |
|---|---|---:|---|
| 62511 ≅ 62512 | 1,375,569 ≅ 1,375,578 | 15,360 | non-solvable, fixed-point-free on 17 points |
| 76041 ≅ 76042 | 693,072 ≅ 693,109 | 92,160 | non-solvable, fixed-point-free on 17 points |

Explicit isomorphisms (images of generators) are given in `audit/search/pairs_w1.g` and
`audit/search/pairs_w2.g`. Each was checked in a fresh GAP session: `GroupHomomorphismByImages`
returns a homomorphism, and it is injective and surjective.

Both groups in each pair first occur in S₁₇, so the earlier terms are unaffected:

| n | 15 | 16 | 17 |
|---|---:|---:|---:|
| A174511(n) | 16,438 | 43,626 | **84,244** (was 84,246) |
| new at n (not isomorphic to a subgroup of S_{n−1}) | 8,672 | 27,188 | **40,618** (was 40,620) |

## Causes

The certificate separated types with a cascade of invariants (categories A–G in `README.md`). Two
steps in that cascade could wrongly declare two isomorphic groups distinct.

**Both errors began with the same GAP bug (cause 1).** The verification run of 2026-04-07
(`work/gpairs.log`) ran `IsomorphismGroups` on both pairs under GAP 4.15.1, and both returned `fail`:

```
Pair 10: 1375569 vs 1375578 order=15360
  NOT ISO (500015ms)
Pair 11: 693072 vs 693109 order=92160
  NOT ISO (1055500ms)
```

The order-92,160 pair kept that false `fail` as its only evidence (category G). The order-15,360 pair
was then moved from G to F on the strength of a differing `crpfHash` (cause 2). That fingerprint is not
an isomorphism invariant, so it only appeared to confirm the wrong `fail`, and it removed the pair from
the one category that was re-tested.

### 1. `IsomorphismGroups` returned `fail` for isomorphic groups (a GAP bug)

GAP's reference manual (§40.9-1) states that `IsomorphismGroups(G, H)` "computes an isomorphism
between the groups G and H if they are isomorphic and returns `fail` otherwise". The certificate's
category G used `fail` as the proof that two groups with identical invariants are distinct.

In GAP 4.15.1 this contract does not hold. For groups such as these, which are non-solvable with a
non-trivial solvable radical, `IsomorphismGroups` calls `PatheticIsomorphism` (`lib/autsr.gi`). That
function builds a constrained subgroup of Aut(G × H). If no element of it swaps the two factors, it
returns `fail` at the branch `Info(InfoMorph,1,"Shortorb test noniso")`. When the automorphism
computation misses automorphisms, which depends on the random state, the swap is lost and the
answer is a false `fail`.

- **GAP issue #6537**, "`IsomorphismGroups` still returns `fail` for isomorphic groups in some
  cases" (opened 2026-08-29, labelled *kind: bug: wrong result*):
  <https://github.com/gap-system/gap/issues/6537>. It depends on the random seed.
- **GAP PR #6544**, "Fix and enhancements to isomorphism test" (merged into the development branch
  2026-09-08; "This fixes the bug from #6537"; marked for backport to 4.16). No released version of
  GAP contains it yet: <https://github.com/gap-system/gap/pull/6544>.
- **GAP PR #6454**, "Fix a bug in automorphism group computations/isomorphism tests, that might have
  missed morphisms in larger groups (and e.g. incorrectly marked two groups as nonisomorphic when
  they really are isomorphic)" (merged 2026-07-08, in GAP 4.16.1; a regression present since GAP
  4.12): <https://github.com/gap-system/gap/pull/6454>.

We reproduced the failure independently. A fresh GAP 4.15.1 session re-ran the original computation
on a bucket of 16 groups of order 122,880 from the S₁₈ computation. `IsomorphismGroups`
returned `fail`, at the "Shortorb test noniso" exit, on a pair it had proved isomorphic in the
production run. Repeating the call on the same two groups found the isomorphism.

Both pairs were declared distinct this way (see above). The long running times (500 s and 1,055 s) are
consistent with the late "Shortorb test noniso" exit seen in our reproduction, but the exit taken in
those two April calls was not traced.

### 2. The character-table fingerprint (`crpfHash`) was not an isomorphism invariant

Category F separated types by a hash of the character table. Per conjugacy class *i*, it recorded
`[PowerMap(ct,1)[i], …, PowerMap(ct,n)[i]]` followed by `χ₁(i), …, χ_k(i)`, and then sorted these
per-class vectors. Sorting absorbs a reordering of the classes only if each vector stays the same,
and here it does not:

- the power-map entries are **class positions**, which change when the classes are ordered differently;
- the character values appear in **GAP's order of the irreducible characters**, which is not canonical.

So the hash depends on how GAP happens to order a particular table. The same group, conjugated by a
random permutation of 17 points and with its generators reversed, receives a different hash
(`audit/crpf_invariance_demo.g`).

The order-15,360 pair (types 62511/62512) was moved from category G to F in April 2026 because the
two hashes differed. The groups are in fact isomorphic.

The certificate's history shows how that happened. Version v4 (84,245) had this pair merged into one
type. Version v5 split it again with the note "These are NOT isomorphic despite identical sigKey,
histogram, and |Aut|. Distinguished by crpfHash (method F)", which raised the count to 84,246. The v4
merge was correct.

## Audit of the certificate

An audit re-established every separation that depended on |Aut(G)|, crpfHash or `IsomorphismGroups`,
using only sound evidence. That covers categories E, F and G: 11,345 types in 4,665 buckets with equal
(sigKey, element-order histogram), giving 11,819 pairs to separate. |Aut(G)| was not used as
evidence (see PR #6454).

1. **IdGroup**, where the SmallGroups library covers the order (this includes order 768): 752 pairs
   separated.
2. **A label-free character-table invariant**, computed from each type's full character table (all
   tables are saved in `audit/tables/`). Classes start coloured by (element order, class size) and
   characters by degree. The colours are then refined repeatedly:
   - a class's new colour combines its old colour, the sorted multiset of (character colour, value)
     over all characters, and the colours of its p-th power classes;
   - a character's new colour combines its old colour and the sorted multiset of (class colour,
     value) over all classes.

   Only sorted multisets and colour look-ups enter, never positions. So isomorphic groups always
   receive equal values, and different values prove non-isomorphism. 40 relabelled copies (random
   conjugation, permuted and redundant generators) all reproduced their original's value.
   11,063 pairs were separated this way.
3. **Complete coset-action search** on the 4 pairs that remained, using the following theorem. For
   permutation groups D and R of equal order, where D has orbits O₁,…,O_k:

   D ≅ R if and only if R, acting on the disjoint union of the coset spaces R/H_j for some
   conjugacy classes of subgroups H_j with [R:H_j] = |O_j|, is conjugate to D in Sym(O₁) × … × Sym(O_k).

   The search runs over all such tuples, so it either finds an isomorphism or proves there is none.

   - 62511/62512 and 76041/76042: **isomorphic** (validated maps).
   - 43999/44000 (order 4,000) and 54779/54780 (order 8,000): **not isomorphic**.

   These two G-pairs are really one pair. Types 54779/54780 are types 43999/44000 times a direct factor
   C₂: the same generators plus the transposition (16,17). By Krull–Schmidt, G₁ × C₂ ≅ G₂ × C₂ only if
   G₁ ≅ G₂. The two character tables are identical, power maps included:
   `TransformingPermutationsCharacterTables` finds an exact correspondence. So no invariant derived
   from the character table can separate them, and their equal character-table invariants are correct.

   After the audit we looked for an explicit invariant anyway (`audit/gpair_invariants.g`, output in
   `audit/gpair_invariants_out.txt`). The pair agrees on many invariants:
   - orbits and orbit actions;
   - centre, derived series, Frattini and Fitting subgroups;
   - Sylow subgroups and their normalizers;
   - the number of conjugacy classes of subgroups (144);
   - the multiset of (index, core order, coset-action type) over those classes.

   It is separated by its **subgroups of index 2**. Each group has exactly three, all normal, and
   SmallGroups identifies them as:

   | | index-2 subgroups (`IdGroup`) |
   |---|---|
   | G₁ (class 77,238, type 43999) | [2000, 902], [2000, 912], [2000, 924] |
   | G₂ (class 77,239, type 44000) | [2000, 901], [2000, 913], [2000, 924] |

   An isomorphism maps index-2 subgroups onto index-2 subgroups, so the pair is not isomorphic. The
   order-8,000 pair shows the same difference among its normal subgroups of order 2,000 (902 and 912
   against 901 and 913, twice each).

   The certificate now records this invariant for all four G-types (fields `nsord` and `ns`; see below).
   So each G-pair has two independent proofs of distinctness: the invariant and the complete search.

The audit also found the following, none of which changes a count:

- The stored sigKeys and histograms of all 11,345 types were recomputed and all match.
- Ten types labelled E are in fact unique in (sigKey, histogram) among all types, so they are
  distinct without |Aut|.

**Coverage (every conjugacy class really belongs to its type).**

- All 389,891 isomorphism proofs of v6 (the 389,889 of v5 plus the 2 merges) were re-checked against
  the *actual* class groups, with **no failures**: the generators generate the duplicate class's group,
  the images lie in the representative's group, and the map is a bijective homomorphism. The original
  verifier's Phase 2 checked only Group(gens) ≅ Group(images).
- All 1,015,460 IdGroup-map entries were recomputed from the class groups, **with no errors**.
- As a result, every one of the 1,466,358 conjugacy classes maps to one of the 84,244 types:
  84,244 as representatives, 992,223 through IdGroup, and 389,891 through validated proofs.

## Other certificates

**S₁₆** (`../s16_proof_certificate`, A174511(16) = 43,626):

- The same category G depends on `IsomorphismGroups`. All 7 of its G-pairs are now proven
  non-isomorphic by complete search.
- Its E/F types are covered by the S₁₇ audit. Every S₁₆ conjugacy class is also an S₁₇ class. On
  665,334 classes matched between the two class files by generating set, the two certificates'
  classifications correspond one-to-one: 43,602 types, with no split and no merge.
- Its stored |Aut| values disagree with recomputation for about a third of the types that record
  them. |Aut| is not used as evidence here.

**S₁₅** (`../s15_proof_certificate`): three pairs were distinguished only by `IsomorphismGroups`.
All three are now proven non-isomorphic:

- (140996, 141229): IdGroup [768, 364874] vs [768, 364880];
- (77179, 77180): IdGroup [2000, 912] vs [2000, 913];
- (97021, 97022): complete coset-action search.

## What the corrected result relies on

The corrected result relies on GAP 4.15.1's `Size`, `ConjugacyClasses`, `CharacterTable`/`Irr`,
`IdGroup`, `NormalSubgroups`, `MaximalSubgroupClassReps`/`LowIndexSubgroups`, `RepresentativeAction`
and `GroupHomomorphismByImages`. It does **not** rely on `AutomorphismGroup`, on a `fail` from
`IsomorphismGroups`, or on crpfHash.

Every isomorphism is an explicit map. Every separation is either a difference in a proven invariant
or the result of a complete search.

## Corrected certificate (v6)

`data/s17_verification_certificate_v6.g` has 84,244 records. `data/s17_proofs_v6.g.gz` holds the
389,889 proofs of v5 plus the 2 merge proofs.

| Category | Meaning | Count |
|---|---|---:|
| A | unique order | 176 |
| B | unique [order, IdGroup] | 24,068 |
| C | unique sigKey | 16,880 |
| D | unique (sigKey, element-order histogram) | 32,658 |
| H | unique label-free character-table invariant within its (sigKey, histogram) bucket | 10,458 |
| G | identical character tables; distinct by the `IdGroup`s of the normal subgroups of order `nsord` (field `ns`), and independently by complete coset-action search | 4 (2 pairs) |

v5's categories E (|Aut|) and F (crpfHash) are gone. Types are renumbered contiguously; the
v5 → v6 number map is `audit/v6/v5_to_v6_types.json`. The verifier `verify_a174511_17_v6.py`
checks every step, and uses `v6_gap/` for its GAP code:

1. certificate consistency, including separating evidence for every pair sharing (sigKey, histogram);
2. linkage of all 389,891 proofs to the actual class groups;
3. order, sigKey, histogram and IdGroup of every type;
4. the character-table invariant of every H/G type, with relabelling self-tests;
5. for the G-pairs, the normal-subgroup `IdGroup` lists (recomputed; they differ within each pair)
   and the complete searches;
6. the IdGroup map;
7. the class-to-type map and A174511(n).

Verification run of 2026-09-28 (`verify_run_v6.log`): **every phase passed.**

| Phase | Result |
|---|---|
| 1 | 11,817 same-(sigKey, histogram) pairs, each with separating evidence |
| 2 | 389,891 / 389,891 proofs linked to the actual class groups |
| 3 | 84,244 / 84,244 types: order, sigKey, histogram and IdGroup recomputed, 0 mismatches |
| 3b | 10,462 / 10,462 character-table invariants match; 40 / 40 relabelling self-tests |
| 4 | both G-pairs non-isomorphic: normal-subgroup `IdGroup` lists recomputed and different; complete search |
| 5 | 1,015,460 / 1,015,460 IdGroup-map entries; all 1,466,358 classes mapped |

The run reproduces A174511(12..14) = 2,065, 3,845, 7,766 and the S₁₅ and S₁₆ certificates (16,438 and
43,626), and gives **A174511(17) = 84,244** (40,618 new at n = 17). In this run, phase 3b used the
character tables saved by the audit. A run that recomputes them (`--workers N` without
`--reuse-tables`, about 10–12 hours on 2 workers) is the from-scratch confirmation.

The `nsord`/`ns` fields of the four G-types were added after that run. Rebuilding with
`audit/build_v6.py` changed only those four records and the header's description of category G;
the proof file and type numbering are byte-identical. Phases 1 and 4 were re-run on the final file
(`verify_run_v6_gpairs.log`) and passed. The other phases check fields that did not change.

## Files

- `audit/`: the audit scripts, the saved character tables (`tables/`), the invariant results
  (`invariant_results.json`), and the complete searches and maps (`search/`).
- `audit/coverage/`: the proof-linkage and IdGroup-map re-verification.
- `audit/gpair_invariants.g`, `audit/gpair_invariants_8000.g`: the invariant comparison of the G-pair
  (outputs in `*_out.txt`). `audit/gpair_ns.g` → `audit/gpair_ns.txt`: the `ns` values written into
  the certificate.
- `data/s17_verification_certificate_v6.g`, `data/s17_proofs_v6.g.gz`, `verify_a174511_17_v6.py` and
  `v6_gap/`: the corrected certificate and its verifier.
