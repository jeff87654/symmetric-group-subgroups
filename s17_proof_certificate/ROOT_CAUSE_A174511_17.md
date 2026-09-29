# Root cause of the A174511(17) overcount (84,246 → 84,244)

*Short version of [CORRECTION_A174511_17.md](CORRECTION_A174511_17.md). 2026-09-28.*

## The two pairs counted as distinct

The earlier S₁₇ certificate (v5) listed two pairs of isomorphic groups as separate types.
Both pairs are non-solvable and fixed-point-free on 17 points.

| v5 types | Classes in `s17_subgroups_cycles.g` | Order |
|---|---|---:|
| 62511 and 62512 | 1,375,569 and 1,375,578 | 15,360 |
| 76041 and 76042 | 693,072 and 693,109 | 92,160 |

Both groups in each pair first occur in S₁₇, so a(n) for n ≤ 16 is unaffected.

## Why they were counted as distinct

**1. A GAP bug.** The certificate treated `IsomorphismGroups(G, H) = fail` as a proof of
non-isomorphism, and GAP's manual says that is what `fail` means. In GAP 4.15.1 it is not
reliable. In the April 2026 run both pairs returned `fail` (500 s and 1,055 s), although both are
isomorphic.

- `IsomorphismGroups` reaches `PatheticIsomorphism` (`lib/autsr.gi`). That routine builds a
  constrained subgroup of Aut(G × H) and returns `fail` if no element of it swaps the two factors
  ("Shortorb test noniso").
- The automorphism computation can miss automorphisms, depending on the random state. The swap is
  then lost and the answer is a false `fail`. Repeating the call can find the isomorphism.
- Upstream reports:
  [issue #6537](https://github.com/gap-system/gap/issues/6537) (opened 2026-08-29, labelled
  "wrong result"), fixed on the development branch by
  [PR #6544](https://github.com/gap-system/gap/pull/6544) (merged 2026-09-08, not yet in a release);
  and [PR #6454](https://github.com/gap-system/gap/pull/6454) (merged 2026-07-08, in GAP 4.16.1; a
  regression present since 4.12), which fixes automorphism computations that missed morphisms.
- We reproduced the false `fail` in a fresh GAP 4.15.1 session. It came from a pair of order
  122,880 from our S₁₈ computation, which an earlier run had proved isomorphic, and a repeat call
  found the isomorphism.

**2. A fingerprint that is not an invariant.** The pair of order 15,360 had already been merged
correctly in an earlier certificate (v4). v5 split it again because a character-table hash
(`crpfHash`) differed. That hash stored power-map entries, which are class *positions*, and character
values in GAP's order of the irreducible characters. Neither ordering is canonical, so isomorphic
groups can get different hashes. The same group, conjugated by a random permutation of the 17 points,
gets a different hash (`audit/crpf_invariance_demo.g`). So the differing hash only appeared to
confirm the false `fail`.

## Proofs of isomorphism

Each pair now has an explicit isomorphism, found by a complete coset-action search.
`GroupHomomorphismByImages(Group(gens), R, gens, images)` returns a homomorphism that is injective and
surjective, which was checked in a fresh GAP session. The maps are in `audit/search/pairs_w2.g`
(order 15,360) and `audit/search/pairs_w1.g` (order 92,160), and are also stored as the last two
records of `data/s17_proofs_v6.g.gz`.

- **Order 15,360.** `gens` generate class 1,375,578 (v5 type 62512) and map into class 1,375,569
  (v5 type 62511):

  ```
  gens   = (1,7,3,5)(2,6,8,4), (1,4,2,5)(3,6,8,7)(12,13), (4,6)(5,7), (1,5)(2,6)(3,7)(4,8)(14,15,16,17),
           (14,16), (15,17), (9,10,13), (9,10)(11,12)
  images = (1,8,3,2)(4,5,6,7), (1,3)(4,5,6,7)(9,12), (1,2)(3,8)(4,7)(5,6), (1,4)(2,5)(3,6)(7,8)(14,15,16,17),
           (14,16), (15,17), (10,12,13), (9,11)(10,13)
  ```

- **Order 92,160.** `gens` generate class 693,109 (v5 type 76042) and map into class 693,072
  (v5 type 76041). The 11 generators and images are listed in `audit/search/pairs_w1.g`.

Result: **A174511(17) = 84,244**, with 40,618 new at n = 17.

## What the audit found beyond these two pairs

The audit re-examined every separation in v5 that rested on |Aut(G)|, `crpfHash` or a `fail` from
`IsomorphismGroups` (11,345 types). Only these two pairs were wrong. All other separations now rest on
`IdGroup`, on a label-free character-table invariant, or on a complete coset-action search. The
S₁₅ and S₁₆ counts are unchanged. Details are in `CORRECTION_A174511_17.md`.
