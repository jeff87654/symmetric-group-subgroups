#!/usr/bin/env python3
"""
Verification pipeline for A174511(17) = 84,244 -- certificate v6 (2026-09-28).

Supersedes verify_a174511_17.py (v5, 84,246); see CORRECTION_A174511_17.md.  Evidence used:
  distinctness -- order, IdGroup, sigKey, element-order histogram, the label-free character-table
                  invariant `ctinv`; the 2 G-pairs (identical character tables) by the IdGroup profile
                  of their normal subgroups of one order, and independently by complete coset-action search.
                  NOT used: |Aut(G)|, crpfHash, or a `fail` from IsomorphismGroups.
  coverage     -- every isomorphism proof is checked against the ACTUAL class groups (generators
                  generate the duplicate's group, images lie in the representative's group, the map is
                  a bijective homomorphism); every IdGroup-map entry is recomputed.

Phases:
  0  decompress data files into work_v6/
  1  certificate consistency (Python)
  2  proof linkage, 389,891 proofs (GAP)
  3  order / sigKey / histogram of every type, IdGroup of every B-type (GAP)
  3b ctinv of every H/G type from its character table, plus relabelling self-tests (GAP + Python)
  4  G-pairs: stored normal-subgroup IdGroup profiles recomputed (they differ within each pair), and
     the complete coset-action search must prove non-isomorphism (GAP)
  5  IdGroup-map entries (GAP), class-to-type map, A174511(n) for n = 0..17 (Python)

Usage:
  python verify_a174511_17_v6.py --workers 2                    # everything (~10-12 h on 2 workers)
  python verify_a174511_17_v6.py --phases 1,4,5 --workers 2      # selected phases
  python verify_a174511_17_v6.py --reuse-tables audit/tables     # phase 3b from saved tables (faster)
Requires: GAP 4.15+ (Cygwin build on Windows), Python 3.9+.
"""
import argparse, gzip, json, queue, random, re, shutil, subprocess, sys, threading, time
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR = SCRIPT_DIR / "data"
WORK = SCRIPT_DIR / "work_v6"
GAPDIR = SCRIPT_DIR / "v6_gap"
sys.path.insert(0, str(GAPDIR))
import ctinv  # noqa: E402

GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
GAP_CMD = "/opt/gap-4.15.1/gap"
TOTAL_CLASSES, TOTAL_TYPES, TOTAL_PROOFS = 1466358, 84244, 389891
CERT, PROOFS = "s17_verification_certificate_v6.g", "s17_proofs_v6.g"
A000638 = {0: 1, 1: 1, 2: 2, 3: 4, 4: 11, 5: 19, 6: 56, 7: 96, 8: 296, 9: 554, 10: 1593, 11: 3094,
           12: 10723, 13: 20832, 14: 75154, 15: 159129, 16: 686165, 17: 1466358}
KNOWN_A174511 = {12: 2065, 13: 3845, 14: 7766}                  # independently established earlier
CERTIFIED_ELSEWHERE = {15: 16438, 16: 43626}                    # S15 / S16 certificates (consistency)


def cyg(p):
    p = str(Path(p).resolve()).replace("\\", "/")
    return f"/cygdrive/{p[0].lower()}{p[2:]}" if p[1] == ":" else p


def banner(s):
    print("\n" + "=" * 64 + f"\n{s}\n" + "=" * 64, flush=True)


# ------------------------------------------------------------------ GAP job runner
def run_gap_file(script, log, mem="8g", timeout=None):
    with open(log, "a") as fh:
        p = subprocess.Popen([GAP_BASH, "--login", "-c", f'{GAP_CMD} -q -o {mem} "{cyg(script)}"'],
                             stdout=fh, stderr=subprocess.STDOUT, creationflags=getattr(subprocess, "IDLE_PRIORITY_CLASS", 0))
        try:
            p.wait(timeout=timeout)
            return p.returncode, False
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(p.pid)], capture_output=True)
            p.wait()
            return None, True


def run_chunks(jobs, workers, label, cap_s=4 * 3600):
    """jobs: list of (name, header_text).  Each runs as one GAP process; results land where the header says."""
    q = queue.Queue()
    for j in jobs: q.put(j)
    timeouts = []

    def lane(k):
        while True:
            try: name, text = q.get_nowait()
            except queue.Empty: return
            hdr = WORK / f"_{label}_{name}.g"
            hdr.write_text(text, newline="\n")
            _, to = run_gap_file(hdr, WORK / f"{label}_lane{k}.log", timeout=cap_s)
            if to: timeouts.append(name)
    ts = [threading.Thread(target=lane, args=(k + 1,)) for k in range(workers)]
    for t in ts: t.start()
    for t in ts: t.join()
    return timeouts


def summaries(paths):
    ok = bad = missing = 0
    fails = []
    for p in paths:
        txt = p.read_text().splitlines() if p.exists() else []
        s = [l for l in txt if l.startswith("SUMMARY")]
        if not s: missing += 1; continue
        m = re.search(r"ok=(\d+)\tfail=(\d+)", s[-1]); ok += int(m.group(1)); bad += int(m.group(2))
        fails += [l for l in txt if l.startswith("FAIL")]
    return ok, bad, missing, fails


# ------------------------------------------------------------------ data
_CLASS = None
def classes():
    global _CLASS
    if _CLASS is None:
        _CLASS, started = [None], False
        for line in open(WORK / "s17_subgroups_cycles.g"):
            if not started:
                started = line.strip() == "return ["; continue
            s = line.strip()
            if s.startswith("["): _CLASS.append(s.rstrip(","))
        assert len(_CLASS) - 1 == TOTAL_CLASSES, len(_CLASS) - 1
    return _CLASS


def parse_certificate():
    recs = []
    for line in open(WORK / CERT):
        s = line.strip().rstrip(",")
        if not s.startswith("rec("): continue
        r = {"t": int(re.search(r"t:=(\d+)", s).group(1)), "i": int(re.search(r"i:=(\d+)", s).group(1)),
             "m": re.search(r'm:="(\w)"', s).group(1), "o": int(re.search(r"o:=(\d+)", s).group(1))}
        for k, pat in (("sk", r"sk:=(\[.*?\]\])"), ("h", r"h:=(\[\[.*?\]\])"), ("id", r"id:=(\[\d+,\d+\])"),
                       ("ctinv", r'ctinv:="(\w+)"'), ("pair", r"pair:=(\d+)")):
            m = re.search(pat, s)
            if m: r[k] = m.group(1).replace(" ", "")
        if "pair" in r: r["pair"] = int(r["pair"])
        m = re.search(r"nsord:=(\d+),ns:=(\[.*\])\)$", s)
        if m: r["nsord"], r["ns"] = int(m.group(1)), m.group(2).replace(" ", "")
        recs.append(r)
    return recs


def parse_proofs():
    text = open(WORK / PROOFS).read()
    out = []
    for body in re.findall(r"rec\((.*?)\)\s*[,\]]", text, re.S):
        out.append({"d": int(re.search(r"duplicate\s*:=\s*(\d+)", body).group(1)),
                    "r": int(re.search(r"representative\s*:=\s*(\d+)", body).group(1)),
                    "gens": re.sub(r"\s+", " ", re.search(r"gens\s*:=\s*(\[.*?\])", body, re.S).group(1)),
                    "images": re.sub(r"\s+", " ", re.search(r"images\s*:=\s*(\[.*?\])", body, re.S).group(1)),
                    "method": re.search(r'method\s*:=\s*"([^"]*)"', body).group(1)})
    return out


# ------------------------------------------------------------------ phases
def phase0():
    banner("PHASE 0: Setup")
    WORK.mkdir(exist_ok=True)
    for name, gz in (("s17_subgroups_cycles.g", True), (PROOFS, True), ("s17_idgroup_map.g", True), (CERT, False)):
        tgt = WORK / name
        if tgt.exists(): print(f"  {name}: present"); continue
        if gz:
            with gzip.open(DATA_DIR / f"{name}.gz", "rb") as a, open(tgt, "wb") as b: shutil.copyfileobj(a, b)
        else:
            shutil.copy2(DATA_DIR / name, tgt)
        print(f"  {name}: {tgt.stat().st_size / 1e6:.1f} MB")
    return True


def phase1(recs):
    banner("PHASE 1: Certificate consistency")
    err = []
    mc = Counter(r["m"] for r in recs)
    print("  method counts:", dict(sorted(mc.items())), " total", len(recs))
    if len(recs) != TOTAL_TYPES: err.append("type count")
    if sorted(r["t"] for r in recs) != list(range(1, TOTAL_TYPES + 1)): err.append("type numbers not contiguous")
    if len({r["i"] for r in recs}) != len(recs): err.append("duplicate representative index")
    if set(mc) - set("ABCDGH"): err.append(f"unknown methods {set(mc) - set('ABCDGH')}")
    by_o, by_sk, by_skh, by_id = Counter(r["o"] for r in recs), Counter(), defaultdict(list), Counter()
    for r in recs:
        if "sk" in r: by_sk[r["sk"]] += 1
        if "sk" in r and "h" in r: by_skh[(r["sk"], r["h"])].append(r)
        if "id" in r: by_id[r["id"]] += 1
    for r in recs:
        m = r["m"]
        if m == "A" and by_o[r["o"]] != 1: err.append(f"A t={r['t']}")
        if m == "B" and ("id" not in r or by_id[r["id"]] != 1 or int(r["id"][1:].split(",")[0]) != r["o"]):
            err.append(f"B t={r['t']}")
        if m == "C" and by_sk[r["sk"]] != 1: err.append(f"C t={r['t']}")
        if m == "D" and len(by_skh[(r["sk"], r["h"])]) != 1: err.append(f"D t={r['t']}")
        if m in ("H", "G") and "ctinv" not in r: err.append(f"{m} t={r['t']} without ctinv")
    t2r = {r["t"]: r for r in recs}
    for r in recs:
        if r["m"] == "G":
            q = t2r.get(r.get("pair"))
            if not q or q["m"] != "G" or q.get("pair") != r["t"] or q["ctinv"] != r["ctinv"]:
                err.append(f"G t={r['t']} pair broken")
            elif "ns" not in r or "ns" not in q or r["nsord"] != q["nsord"] or r["ns"] == q["ns"]:
                err.append(f"G t={r['t']}: no differing normal-subgroup profile (nsord/ns)")
    # every pair inside a (sigKey, histogram) bucket needs separating evidence
    pairs_checked = 0
    for key, rs in by_skh.items():
        for x in range(len(rs)):
            for y in range(x + 1, len(rs)):
                a, b = rs[x], rs[y]; pairs_checked += 1
                if "id" in a and "id" in b and a["id"] != b["id"]: continue
                if "ctinv" in a and "ctinv" in b and a["ctinv"] != b["ctinv"]: continue
                if a["m"] == "G" and a.get("pair") == b["t"]: continue          # ns differs; recomputed in phase 4
                err.append(f"bucket pair {a['t']}/{b['t']} has no separating evidence")
    print(f"  (sigKey, histogram) bucket pairs checked: {pairs_checked}")
    for e in err[:20]: print("  ERROR", e)
    print(f"\n  Phase 1: {'PASS' if not err else f'FAIL ({len(err)})'}")
    return not err


def phase2(workers):
    banner(f"PHASE 2: Proof linkage ({TOTAL_PROOFS} proofs)")
    C, proofs = classes(), parse_proofs()
    print(f"  proofs parsed: {len(proofs)}; distinct duplicates: {len({p['d'] for p in proofs})}")
    if len(proofs) != TOTAL_PROOFS: print("  ERROR: proof count"); return False
    jobs, outs = [], []
    for c in range(0, len(proofs), 5000):
        part = proofs[c:c + 5000]; n = f"{c // 5000 + 1:03d}"
        chunk, out = WORK / f"p2_chunk_{n}.g", WORK / f"p2_out_{n}.txt"
        out.unlink(missing_ok=True)
        with open(chunk, "w", newline="\n") as f:
            f.write("CLASS := [];;\n")
            for i in sorted({p["d"] for p in part} | {p["r"] for p in part}): f.write(f"CLASS[{i}] := {C[i]};;\n")
            f.write("PROOFS := [\n" + ",\n".join(f'[{p["d"]},{p["r"]},{p["gens"]},{p["images"]},"{p["method"]}"]'
                                                   for p in part) + "];;\n")
        jobs.append((n, f'CHUNK := "{cyg(chunk)}";; OUT := "{cyg(out)}";;\nRead("{cyg(GAPDIR / "check_proofs.g")}");\n'))
        outs.append(out)
    t0 = time.time(); run_chunks(jobs, workers, "p2")
    ok, bad, missing, fails = summaries(outs)
    print(f"  valid {ok}, invalid {bad}, chunks without result {missing}  ({time.time() - t0:.0f}s)")
    for l in fails[:10]: print("  ", l)
    good = bad == 0 and missing == 0 and ok == TOTAL_PROOFS
    print(f"\n  Phase 2: {'PASS' if good else 'FAIL'}")
    return good


def phase3(recs, workers):
    banner(f"PHASE 3: Invariants of all {len(recs)} types")
    C = classes()
    lit = lambda r, k: r[k] if k in r else "false"
    jobs, outs = [], []
    # Interleave by group order so every chunk mixes small and very large groups (the largest types,
    # up to S17 itself, dominate the cost; in certificate order they all landed in the last chunk).
    by_order = sorted(recs, key=lambda r: -r["o"])
    nchunks = (len(recs) + 2999) // 3000
    for c in range(nchunks):
        part = by_order[c::nchunks]; n = f"{c + 1:03d}"
        chunk, out = WORK / f"p3_chunk_{n}.g", WORK / f"p3_out_{n}.txt"
        out.unlink(missing_ok=True)
        with open(chunk, "w", newline="\n") as f:
            f.write("CLASS := [];;\n")
            for r in part: f.write(f"CLASS[{r['i']}] := {C[r['i']]};;\n")
            f.write("TYPES := [\n" + ",\n".join(
                f"[{r['t']},{r['i']},{lit(r, 'sk')},{lit(r, 'h')},{r['id'] if r['m'] == 'B' else 'false'},{r['o']}]"
                for r in part) + "];;\n")
        jobs.append((n, f'CHUNK := "{cyg(chunk)}";; OUT := "{cyg(out)}";;\nRead("{cyg(GAPDIR / "check_invariants.g")}");\n'))
        outs.append(out)
    t0 = time.time(); run_chunks(jobs, workers, "p3")
    ok, bad, missing, fails = summaries(outs)
    print(f"  types verified {ok}, mismatches {bad}, chunks without result {missing}  ({time.time() - t0:.0f}s)")
    for l in fails[:10]: print("  ", l)
    good = bad == 0 and missing == 0 and ok == len(recs)
    print(f"\n  Phase 3: {'PASS' if good else 'FAIL'}")
    return good


def phase3b(recs, workers, reuse=None, n_selftest=40):
    hg = [r for r in recs if r["m"] in ("H", "G")]
    banner(f"PHASE 3b: ctinv of {len(hg)} H/G types" + (f"  [REUSING tables from {reuse}]" if reuse else ""))
    tables = Path(reuse) if reuse else WORK / "tables"
    rnd = random.Random(20260928)
    selftest = rnd.sample([r["t"] for r in hg], min(n_selftest, len(hg)))
    if not reuse:
        tables.mkdir(exist_ok=True)
        C = classes()
        with open(WORK / "hg_gens.g", "w", newline="\n") as f:
            f.write("AUDIT_GENS := [];;\n")
            for r in hg: f.write(f"AUDIT_GENS[{r['i']}] := {C[r['i']]};;\n")
        t2i = {r["t"]: r["i"] for r in hg}
        jobs = [[r["t"], r["t"], r["i"], False] for r in sorted(hg, key=lambda r: -r["o"])]
        jobs += [[200000 + t, t, t2i[t], True] for t in selftest]
        lanes = [jobs[k::workers] for k in range(workers)]

        def lane(k, js):
            out, log = tables / f"ct_w{k}.g", tables / f"log_w{k}.txt"
            launch = 0
            while True:
                done = set()
                if out.exists():
                    done = {int(m.group(1)) for m in re.finditer(r"^CT\[(\d+)\]", out.read_text(encoding="latin-1"), re.M)}
                failed = set()
                if log.exists():
                    failed = {int(l.split()[1]) for l in log.read_text().splitlines() if l.startswith(("ERROR", "SKIP"))}
                todo = [j for j in js if j[0] not in done | failed]
                if not todo: return
                launch += 1
                hdr = tables / f"_jobs_w{k}.g"
                hdr.write_text("JOBS := [" + ",".join(f"[{a},{b},{c},{'true' if d else 'false'}]" for a, b, c, d in todo) +
                               f'];;\nOUTFILE := "{cyg(out)}";;\nLOGFILE := "{cyg(log)}";;\nSELFTEST_SEED := {k * 1000 + launch};;\n'
                               f'Read("{cyg(WORK / "hg_gens.g")}");\nRead("{cyg(GAPDIR / "ctables.g")}");\n', newline="\n")
                with open(tables / f"gap_w{k}.txt", "a") as g:
                    p = subprocess.Popen([GAP_BASH, "--login", "-c", f'{GAP_CMD} -q -o 12g "{cyg(hdr)}"'], stdout=g,
                                         stderr=subprocess.STDOUT, creationflags=getattr(subprocess, "IDLE_PRIORITY_CLASS", 0))
                    while p.poll() is None:
                        time.sleep(10)
                        lines = log.read_text().splitlines() if log.exists() else []
                        if lines and lines[-1].startswith("BEGIN") and time.time() - log.stat().st_mtime > 3600:
                            subprocess.run(["taskkill", "/F", "/T", "/PID", str(p.pid)], capture_output=True); p.wait()
                            with open(log, "a") as fl: fl.write(f"SKIP {lines[-1].split()[1]} timeout\n")
        ts = [threading.Thread(target=lane, args=(k + 1, lanes[k])) for k in range(workers)]
        t0 = time.time()
        for t in ts: t.start()
        for t in ts: t.join()
        print(f"  tables computed ({time.time() - t0:.0f}s)")
    fp, self_fp = {}, {}
    for f in sorted(tables.glob("ct_w*.g")):
        for line in open(f, encoding="latin-1"):
            if not line.startswith("CT["): continue
            r = ctinv.parse_ct(line)
            (self_fp if r["selftest"] else fp)[r["t"]] = ctinv.fingerprint(r)
    t2r = {r["t"]: r for r in recs}
    if reuse:                                   # audit tables are keyed by v5 type numbers: map by class index
        i_of_v5 = {r["t"]: r["i"] for r in json.load(open(SCRIPT_DIR / "audit" / "types.json"))["types"]}
        v6_of_i = {r["i"]: r["t"] for r in recs}
        fp = {v6_of_i[i_of_v5[t]]: v for t, v in fp.items() if i_of_v5[t] in v6_of_i}
        self_fp = {v6_of_i[i_of_v5[t]]: v for t, v in self_fp.items() if i_of_v5[t] in v6_of_i}
    missing = [r["t"] for r in hg if r["t"] not in fp]
    wrong = [r["t"] for r in hg if r["t"] in fp and fp[r["t"]] != r["ctinv"]]
    bad_self = [t for t, v in self_fp.items() if fp.get(t) != v]
    print(f"  ctinv recomputed {len(hg) - len(missing)}/{len(hg)}; mismatches {len(wrong)} {wrong[:10]}; missing {len(missing)} {missing[:10]}")
    print(f"  relabelling self-tests: {len(self_fp) - len(bad_self)}/{len(self_fp)} reproduce their original's ctinv")
    good = not missing and not wrong and not bad_self and len(self_fp) > 0
    print(f"\n  Phase 3b: {'PASS' if good else 'FAIL'}")
    return good


def phase4(recs):
    gp = sorted({tuple(sorted((r["t"], r["pair"]))) for r in recs if r["m"] == "G"})
    banner(f"PHASE 4: {len(gp)} G-pairs: normal-subgroup profiles and complete coset-action search")
    C, t2i, t2r = classes(), {r["t"]: r["i"] for r in recs}, {r["t"]: r for r in recs}
    gt = [t for p in gp for t in p]
    out = WORK / "p4_out.txt"; out.unlink(missing_ok=True)
    hdr = WORK / "_p4.g"
    hdr.write_text("CLASS := [];;\n" + "".join(f"CLASS[{t2i[t]}] := {C[t2i[t]]};;\n" for p in gp for t in p) +
                   "GPAIRS := [" + ",".join(f"[{a},{b},{t2i[a]},{t2i[b]}]" for a, b in gp) + "];;\n"
                   "GNS := [" + ",".join(f"[{t},{t2i[t]},{t2r[t]['nsord']},{t2r[t]['ns']}]" for t in gt) + "];;\n"
                   f'OUT := "{cyg(out)}";;\nRead("{cyg(GAPDIR / "coset_engine.g")}");\nRead("{cyg(GAPDIR / "gpairs.g")}");\n',
                   newline="\n")
    run_gap_file(hdr, WORK / "p4.log", mem="12g")
    txt = out.read_text().splitlines() if out.exists() else []
    ns = {int(l.split("\t")[1]): l.split("\t")[2] for l in txt if l.startswith("NS")}
    lines = [l.split("\t") for l in txt if l.startswith("PAIR")]
    for a, b in gp:
        ra, rb = t2r[a], t2r[b]
        sep = ra["nsord"] == rb["nsord"] and ra["ns"] != rb["ns"]
        print(f"   {a}/{b}: normal subgroups of order {ra['nsord']}, [IdGroup(N), IdGroup(G/N)] "
              f"recomputed {ns.get(a)}/{ns.get(b)}, differ {sep}\n     {a}: {ra['ns']}\n     {b}: {rb['ns']}")
    for l in lines: print("  ", " ".join(l[1:]))
    good_ns = all(ns.get(t) == "true" for t in gt) and all(
        t2r[a]["nsord"] == t2r[b]["nsord"] and t2r[a]["ns"] != t2r[b]["ns"] for a, b in gp)
    good = good_ns and len(lines) == len(gp) and all(l[3] == "noniso" for l in lines)
    print(f"\n  Phase 4: {'PASS' if good else 'FAIL'}")
    return good


def phase5(recs, workers, skip_idgroup=False):
    banner("PHASE 5: IdGroup map, class-to-type map, A174511(n)")
    idmap = {int(a): (int(b), int(c)) for a, b, c in
             re.findall(r"S17_IDGROUP_MAP\[(\d+)\] := \[(\d+), (\d+)\];", open(WORK / "s17_idgroup_map.g").read())}
    good = True
    if not skip_idgroup:
        C, items = classes(), sorted(idmap.items())
        jobs, outs = [], []
        for c in range(0, len(items), 20000):
            part = items[c:c + 20000]; n = f"{c // 20000 + 1:03d}"
            chunk, out = WORK / f"p5_chunk_{n}.g", WORK / f"p5_out_{n}.txt"
            out.unlink(missing_ok=True)
            with open(chunk, "w", newline="\n") as f:
                f.write("CLASS := [];;\n" + "".join(f"CLASS[{i}] := {C[i]};;\n" for i, _ in part))
                f.write("IDS := [" + ",".join(f"[{i},{o},{d}]" for i, (o, d) in part) + "];;\n")
            jobs.append((n, f'CHUNK := "{cyg(chunk)}";; OUT := "{cyg(out)}";;\nRead("{cyg(GAPDIR / "check_idgroup.g")}");\n'))
            outs.append(out)
        t0 = time.time(); run_chunks(jobs, workers, "p5")
        ok, bad, missing, fails = summaries(outs)
        print(f"  IdGroup-map entries verified {ok}/{len(idmap)}, wrong {bad}, chunks without result {missing}  ({time.time() - t0:.0f}s)")
        for l in fails[:10]: print("  ", l)
        good = bad == 0 and missing == 0 and ok == len(idmap)
    rep_to_type = {r["i"]: r["t"] for r in recs}
    id_to_type = {idmap[i]: t for i, t in rep_to_type.items() if i in idmap}
    dup_to_rep = {p["d"]: p["r"] for p in parse_proofs()}
    c2t = [0] * (TOTAL_CLASSES + 1)
    via = Counter()
    for idx in range(1, TOTAL_CLASSES + 1):
        cur, hops = idx, 0
        while hops < 20:
            if cur in rep_to_type: c2t[idx] = rep_to_type[cur]; via["rep" if hops == 0 else "proof"] += 1; break
            if cur in idmap and idmap[cur] in id_to_type:
                c2t[idx] = id_to_type[idmap[cur]]; via["idgroup" if hops == 0 else "proof"] += 1; break
            if cur not in dup_to_rep: break
            cur, hops = dup_to_rep[cur], hops + 1
    missing = [i for i in range(1, TOTAL_CLASSES + 1) if c2t[i] == 0]
    print(f"  classes mapped {TOTAL_CLASSES - len(missing):,}/{TOTAL_CLASSES:,}  {dict(via)}  missing {len(missing)}")
    first = {}
    for idx in range(1, TOTAL_CLASSES + 1):
        t = c2t[idx]
        if t and t not in first: first[t] = idx
    print(f"\n  {'n':>3} {'A000638(n)':>11} {'A174511(n)':>11} {'new':>7}")
    prev, a = 0, {}
    for n in range(18):
        a[n] = sum(1 for v in first.values() if v <= A000638[n])
        note = ""
        if n in KNOWN_A174511: note = " OK" if a[n] == KNOWN_A174511[n] else f" MISMATCH (expected {KNOWN_A174511[n]})"
        if n in CERTIFIED_ELSEWHERE: note = " = S%d certificate" % n if a[n] == CERTIFIED_ELSEWHERE[n] else f" differs from S{n} certificate ({CERTIFIED_ELSEWHERE[n]})"
        print(f"  {n:>3} {A000638[n]:>11,} {a[n]:>11,} {a[n] - prev:>7,}{note}")
        prev = a[n]
    with open(WORK / "s17_class_to_type_map_v6.g", "w", newline="\n") as f:
        f.write("# S17 class -> type (certificate v6)\nS17_CLASS_TO_TYPE := [\n" + ",\n".join(map(str, c2t[1:])) + "\n];\n")
    good = good and not missing and a[17] == TOTAL_TYPES and all(a[n] == v for n, v in KNOWN_A174511.items())
    print(f"\n  Phase 5: {'PASS' if good else 'FAIL'}")
    return good


def main():
    ap = argparse.ArgumentParser(description="Verify A174511(17) = 84,244 (certificate v6)")
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--phases", default="0,1,2,3,3b,4,5")
    ap.add_argument("--reuse-tables", default=None, help="phase 3b: read character tables from this directory")
    ap.add_argument("--skip-idgroup-map", action="store_true", help="phase 5: skip re-verifying the IdGroup map")
    a = ap.parse_args()
    ph = a.phases.split(",")
    print(f"A174511(17) verification, certificate v6 -- started {datetime.now()}  workers={a.workers}  phases={ph}")
    res = {}
    if "0" in ph: res["0"] = phase0()
    recs = parse_certificate()
    if "1" in ph: res["1"] = phase1(recs)
    if "2" in ph: res["2"] = phase2(a.workers)
    if "3" in ph: res["3"] = phase3(recs, a.workers)
    if "3b" in ph: res["3b"] = phase3b(recs, a.workers, a.reuse_tables)
    if "4" in ph: res["4"] = phase4(recs)
    if "5" in ph: res["5"] = phase5(recs, a.workers, a.skip_idgroup_map)
    banner("SUMMARY")
    for k, v in res.items(): print(f"  phase {k}: {'PASS' if v else 'FAIL'}")
    full = set(res) == {"0", "1", "2", "3", "3b", "4", "5"} and all(res.values()) and not a.reuse_tables and not a.skip_idgroup_map
    if all(res.values()):
        print(f"\n  *** A174511(17) = {TOTAL_TYPES:,} VERIFIED ***" if full else
              "\n  all selected phases passed (a complete verification runs every phase with fresh tables)")
    print(f"\nFinished {datetime.now()}")
    return 0 if all(res.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
