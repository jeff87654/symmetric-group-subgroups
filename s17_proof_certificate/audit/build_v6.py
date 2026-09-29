#!/usr/bin/env python3
"""Build the corrected S17 certificate v6 from v5 + the 2026-09 audit (staged in audit/v6/).

Changes relative to v5:
  * types 62512 and 76042 are removed: proven isomorphic to 62511 and 76041 (maps from audit/search/),
    added to the proof file as two new proofs; types are renumbered contiguously 1..84244;
  * categories E, F, G of v5 are replaced, using only sound evidence (no |Aut|, crpfHash, or
    IsomorphismGroups = fail):
      D  unique (sigKey, histogram) among all types (10 former E-types, and 62511 / 76041 after merging)
      B  unique [order, IdGroup] (former E/F/G types whose order IdGroup identifies, e.g. 768)
      H  (new) unique label-free character-table invariant `ctinv` within the (sigKey, histogram) bucket
      G  (redefined) pair with identical ctinv; separated by the IdGroup profile `ns` of its normal
         subgroups of order `nsord` (gpair_ns.g -> gpair_ns.txt), and independently by complete
         coset-action search
  * the fields aut and crpfHash are dropped (not isomorphism evidence; crpfHash is not even invariant).
"""
import collections, json, re
from pathlib import Path

HERE = Path(__file__).resolve().parent
CERT = HERE.parent / "data" / "s17_verification_certificate_v5.g"
OUT = HERE / "v6"
OUT.mkdir(exist_ok=True)
MERGE = {62512: 62511, 76042: 76041}            # dropped type -> kept type (v5 numbers)

meta = json.load(open(HERE / "types.json"))
fp = {int(k): v for k, v in json.load(open(HERE / "invariant_results.json"))["fingerprint"].items()}
ids = {int(k): v for k, v in json.load(open(HERE / "type_idgroups.json")).items()}
nsp = {int(i): (int(o), p.replace(" ", "")) for i, o, p in
       (l.rstrip("\n").split("\t") for l in open(HERE / "gpair_ns.txt") if l.strip())}
audited = {r["t"] for r in meta["types"]}

v5 = []
for line in open(CERT):
    s = line.strip().rstrip(",")
    if not s.startswith("rec("): continue
    r = {"t": int(re.search(r"t:=(\d+)", s).group(1)), "i": int(re.search(r"i:=(\d+)", s).group(1)),
         "m": re.search(r'm:="(\w)"', s).group(1), "o": int(re.search(r"o:=(\d+)", s).group(1))}
    for k, pat in (("sk", r"sk:=(\[.*?\]\])"), ("h", r"h:=(\[\[.*?\]\])"), ("id", r"id:=(\[\d+,\d+\])")):
        m = re.search(pat, s)
        if m: r[k] = m.group(1).replace(" ", "")
    v5.append(r)
assert len(v5) == 84246

keep = [r for r in v5 if r["t"] not in MERGE]
new_t = {r["t"]: n for n, r in enumerate(keep, 1)}
by_skh = collections.defaultdict(list)
for r in keep:
    if r["t"] in audited: by_skh[(r["sk"], r["h"])].append(r)
all_skh = collections.Counter((r.get("sk"), r.get("h")) for r in keep if "sk" in r and "h" in r)

counts, notes = collections.Counter(), []
for key, rs in by_skh.items():
    if all_skh[key] == 1:                                   # alone among ALL types
        for r in rs: r["m"] = "D"
        continue
    assert all_skh[key] == len(rs), f"bucket {key} mixes audited and non-audited types"
    for r in rs:
        if ids[r["t"]]:
            r["m"] = "B"; r["id"] = ids[r["t"]]
        else:
            same = [x for x in rs if x is not r and fp[x["t"]] == fp[r["t"]]]
            r["ctinv"] = fp[r["t"]]
            if not same:
                r["m"] = "H"
            else:
                assert len(same) == 1, f"type {r['t']}: {len(same)} partners with equal ctinv"
                r["m"] = "G"; r["pair"] = new_t[same[0]["t"]]
                r["nsord"], r["ns"] = nsp[r["i"]]
    if any(ids[r["t"]] for r in rs) and not all(ids[r["t"]] for r in rs):
        notes.append(f"bucket {key}: IdGroup available for some but not all members")
for r in keep:
    counts[r["m"]] += 1
assert not notes, notes
g_pairs = sorted({tuple(sorted((new_t[r["t"]], r["pair"]))) for r in keep if r["m"] == "G"})
t2k = {new_t[r["t"]]: r for r in keep}
for a, b in g_pairs:                                        # the explicit invariant must separate each pair
    assert t2k[a]["nsord"] == t2k[b]["nsord"] and t2k[a]["ns"] != t2k[b]["ns"], (a, b)
print("categories:", dict(sorted(counts.items())), " total", sum(counts.values()), " G-pairs (v6 numbers):", g_pairs)

def fmt(r):
    parts = [f"t:={new_t[r['t']]}", f"i:={r['i']}", f'm:="{r["m"]}"', f"o:={r['o']}"]
    if "sk" in r: parts.append(f"sk:={r['sk']}")
    if "h" in r: parts.append(f"h:={r['h']}")
    if r["m"] == "B" and "id" in r: parts.append(f"id:={r['id']}")
    if r["m"] in ("H", "G"): parts.append(f'ctinv:="{r["ctinv"]}"')
    if r["m"] == "G": parts += [f"pair:={r['pair']}", f"nsord:={r['nsord']}", f"ns:={r['ns']}"]
    return "rec(" + ",".join(parts) + ")"

hdr = f"""# S17 Verification Certificate v6
# A174511(17) = {len(keep)}
# Generated: 2026-09-28 from v5 and the 2026-09 audit (see ../CORRECTION_A174511_17.md)
# Corrected from v5 (84,246): v5 types 62512 and 76042 are isomorphic to 62511 and 76041
# (explicit maps, added to the proof file). v5's separation of 62511/62512 rested on crpfHash, which
# is not an isomorphism invariant; 76041/76042 on IsomorphismGroups returning fail (GAP issue #6537).
#
# Method counts:
""" + "".join(f"#   {m}: {counts[m]}\n" for m in sorted(counts)) + f"""#   Total: {len(keep)}
#
# Method descriptions:
#   A: Unique order.
#   B: Unique [order, IdGroup] pair.
#   C: Unique sigKey = [order, |G'|, nrCC, derivedLength, abelInv].
#   D: Unique (sigKey, element-order histogram) pair.
#   H: Unique label-free character-table invariant `ctinv` within its (sigKey, histogram) bucket.
#   G: Pair with identical ctinv (the two character tables are equivalent, power maps included).
#      Separated by ns = sorted list of [IdGroup(N), IdGroup(G/N)] over the normal subgroups N of
#      order nsord, which differs within the pair; independently, a complete coset-action search
#      proves the pair non-isomorphic.
# (v5's E / F categories used |Aut| and crpfHash; neither is used as evidence in v6.)
S17_CERTIFICATE := [
"""
with open(OUT / "s17_verification_certificate_v6.g", "w", newline="\n") as f:
    f.write(hdr + ",\n".join(fmt(r) for r in keep) + "\n];\n")
json.dump({str(k): v for k, v in new_t.items()} | {str(k): f"merged into v5 type {v}" for k, v in MERGE.items()},
          open(OUT / "v5_to_v6_types.json", "w"), indent=0)

# proof file v6 = v5 proofs + the two merge proofs (duplicate = dropped type's rep, representative = kept rep)
rep_of = {r["t"]: r["i"] for r in v5}
extra = []
for k in (1, 2):
    for line in open(HERE / "search" / f"pairs_w{k}.g", encoding="latin-1"):
        m = re.match(r'PAIR\[(\d+),(\d+)\] := rec\(.*?status:="iso",valid:=true', line)
        if not m: continue
        a, b = int(m.group(1)), int(m.group(2))
        assert MERGE.get(b) == a, (a, b)
        gens = re.search(r"gens:=\[(.*?)\],images:=", line).group(1)
        imgs = re.search(r"images:=\[(.*?)\]\);", line).group(1)
        split = lambda s: [p.strip() for p in re.findall(r"(?:\([^()]*\))+|\(\)", s)]
        extra.append((rep_of[b], rep_of[a], split(gens), split(imgs)))
assert len(extra) == 2
src = open(HERE.parent / "work" / "s17_proofs.g").read().rstrip()
assert src.endswith("];") or src.endswith("]; "), src[-40:]
body = src[: src.rstrip().rfind("]")].rstrip().rstrip(",")   # v5's last record ends "),": drop that comma
recs = ",\n".join(f'  rec(\n  duplicate := {d},\n  gens := [ ' + ", ".join(f'"{g}"' for g in gs) +
                  ' ],\n  images := [ ' + ", ".join(f'"{g}"' for g in im) +
                  f' ],\n  method := "cosetAction",\n  representative := {r} )' for d, r, gs, im in extra)
with open(OUT / "s17_proofs_v6.g", "w", newline="\n") as f:
    f.write(body.replace("# Total proofs: 389857", "# Total proofs: 389891 (v6: +2 cosetAction merge proofs, 2026-09-28)", 1))
    f.write(",\n" + recs + "\n];\n")
print("proof file v6 written with", len(extra), "extra proofs:", [(d, r) for d, r, _, _ in extra])
