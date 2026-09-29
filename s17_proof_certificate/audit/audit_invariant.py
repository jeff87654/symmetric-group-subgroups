#!/usr/bin/env python3
"""Step 3 of the S17 certificate audit (2026-09-27): a label-free character-table invariant, and the
bucket analysis that decides which pairs of types are already proven distinct.

THE INVARIANT.  A character table is determined by the group only up to simultaneous re-ordering of
its rows (irreducible characters) and columns (classes); the power maps are stored as column
POSITIONS.  The certificate's crpfHash leaked both orderings into its value (and is therefore not an
isomorphism invariant).  Here nothing position-dependent is ever recorded:

  round 0   class colour = (element order, class size);   character colour = degree
  round r+1 class c:   (colour_r(c),  sorted multiset of (colour_r(chi), chi(c)) over all chi,
                        [colour_r(p-th power class of c) for each prime p | |G|, p ascending])
            char chi:  (colour_r(chi), sorted multiset of (colour_r(c), chi(c)) over all classes c)
  colours are SHA-256 digests of those descriptions, so they are comparable across groups;
  refinement stops when neither partition splits any further.
  fingerprint = SHA-256 of (order, primes, sorted final class colours, sorted final char colours).

Every ingredient is a sorted multiset or a colour looked up through a map, so relabelling classes or
characters cannot change the value: isomorphic groups ALWAYS get equal fingerprints, and different
fingerprints PROVE non-isomorphism.  (Equal fingerprints prove nothing.)  Cyclotomic values are
compared as GAP's printed normal form, which is canonical for a given value.  The self-test jobs
(relabelled copies) check this empirically.

Usage:  python audit_invariant.py [--tables DIR]
"""
import argparse, collections, hashlib, json, re
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _field(line, name):
    """Balanced-bracket value of `name:=` in a GAP record line (or the scalar up to the next comma)."""
    k = line.index(name + ":=") + len(name) + 2
    if line[k] != "[":
        e = k
        while line[e] not in ",)": e += 1
        return line[k:e]
    depth, e = 0, k
    while True:
        ch = line[e]
        if ch == "[": depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0: return line[k:e + 1]
        e += 1


def _split_top(s):
    """'[ a, b, [c,d] ]' -> ['a', 'b', '[c,d]'] (top-level items, stripped)."""
    s = s.strip()[1:-1]
    out, depth, cur = [], 0, []
    for ch in s:
        if ch in "[(": depth += 1
        elif ch in "])": depth -= 1
        if ch == "," and depth == 0:
            out.append("".join(cur).strip()); cur = []
        else:
            cur.append(ch)
    if "".join(cur).strip(): out.append("".join(cur).strip())
    return out


def parse_ct(line):
    r = {"job": int(_field(line, "job")), "t": int(_field(line, "t")),
         "selftest": _field(line, "selftest") == "true", "order": int(_field(line, "order")),
         "idgroup": _field(line, "idgroup").replace(" ", ""),
         "sk": _field(line, "sk").replace(" ", ""), "hist": _field(line, "hist").replace(" ", "")}
    r["sizes"] = [int(x) for x in _split_top(_field(line, "sizes"))]
    r["orders"] = [int(x) for x in _split_top(_field(line, "orders"))]
    r["powermaps"] = [(int(_split_top(pm)[0]), [int(x) for x in _split_top(_split_top(pm)[1])])
                      for pm in _split_top(_field(line, "powermaps"))]
    r["irr"] = [[v.replace(" ", "") for v in _split_top(row)] for row in _split_top(_field(line, "irr"))]
    return r


def _h(obj):
    return hashlib.sha256(repr(obj).encode()).hexdigest()


def fingerprint(r):
    k = len(r["sizes"])
    irr, pms = r["irr"], sorted(r["powermaps"])
    one = r["orders"].index(1)
    C = [_h(("c0", r["orders"][c], r["sizes"][c])) for c in range(k)]
    X = [_h(("x0", irr[x][one])) for x in range(len(irr))]
    nC, nX = len(set(C)), len(set(X))
    for _ in range(k + len(irr) + 2):
        C2 = [_h((C[c], sorted((X[x], irr[x][c]) for x in range(len(irr))),
                  [C[pm[c] - 1] for _, pm in pms])) for c in range(k)]
        X2 = [_h((X[x], sorted((C[c], irr[x][c]) for c in range(k)))) for x in range(len(irr))]
        C, X = C2, X2
        if len(set(C)) == nC and len(set(X)) == nX:
            break                                   # stable: no partition split this round
        nC, nX = len(set(C)), len(set(X))
    return _h((r["order"], [p for p, _ in pms], sorted(C), sorted(X)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tables", default=str(HERE / "tables"))
    a = ap.parse_args()
    meta = json.load(open(HERE / "types.json"))
    types = {r["t"]: r for r in meta["types"]}
    fp, recs, self_fp = {}, {}, {}
    for f in sorted(Path(a.tables).glob("ct*.g")):
        for line in open(f, encoding="latin-1"):
            if not line.startswith("CT["): continue
            r = parse_ct(line)
            v = fingerprint(r)
            if r["selftest"]: self_fp[r["t"]] = v
            else: fp[r["t"]] = v; recs[r["t"]] = {k: r[k] for k in ("order", "idgroup", "sk", "hist")}
    print(f"tables: {len(fp)} types, {len(self_fp)} self-test copies")
    bad_self = [t for t, v in self_fp.items() if t in fp and fp[t] != v]
    print(f"self-test: {sum(1 for t in self_fp if t in fp) - len(bad_self)} relabelled copies match, "
          f"{len(bad_self)} MISMATCH {bad_self[:10]}")
    # certificate cross-check of the stored sigKey / histogram
    skbad = [t for t, r in recs.items() if r["sk"] != types[t]["sk"] or r["hist"] != types[t]["h"]]
    print(f"certificate sigKey/histogram re-verified: {len(recs) - len(skbad)} ok, {len(skbad)} differ {skbad[:10]}")

    status, residual, idgroup_iso = collections.Counter(), [], []
    for key, ts in meta["buckets"].items():
        for x in range(len(ts)):
            for y in range(x + 1, len(ts)):
                a_, b_ = ts[x], ts[y]
                if a_ not in fp or b_ not in fp:
                    status["pending (table missing)"] += 1; continue
                ia, ib = recs[a_]["idgroup"], recs[b_]["idgroup"]
                if ia != "fail" and ib != "fail":
                    if ia != ib: status["distinct: IdGroup"] += 1
                    else: status["ISOMORPHIC: same IdGroup"] += 1; idgroup_iso.append([a_, b_, ia])
                elif fp[a_] != fp[b_]:
                    status["distinct: character-table invariant"] += 1
                else:
                    status["residual: needs complete search"] += 1; residual.append([a_, b_])
    for k, v in sorted(status.items()): print(f"   {k:40} {v:6}")
    json.dump({"fingerprint": fp, "selftest_mismatch": bad_self, "sk_mismatch": skbad,
               "residual": residual, "idgroup_iso": idgroup_iso, "status": status},
              open(HERE / "invariant_results.json", "w"), indent=1)


if __name__ == "__main__":
    main()
