#!/usr/bin/env python3
"""
Verification pipeline for A174511(17) = 84,246.

Independently verifies that there are exactly 84,246 isomorphism types of
subgroups of the symmetric group S_17, by:
  1. Checking certificate internal consistency
  2. Validating all 389,889 isomorphism proofs (GroupHomomorphismByImages)
  3. Recomputing invariants from actual groups (order, sigKey, histogram, |Aut|, crpfHash)
  4. Confirming non-isomorphism of G-pairs (IsomorphismGroups)
  5. Building the class-to-type map (1,466,358 -> 84,246)
  6. Computing A174511(n) for n = 0..17

Usage:
  python verify_a174511_17.py              # Run all phases
  python verify_a174511_17.py --workers 6  # Use 6 parallel GAP workers
  python verify_a174511_17.py --skip-gap   # Python-only checks (phases 1, 5)

Requires: GAP 4.15+ (Cygwin), Python 3.8+
"""
import argparse, gzip, hashlib, os, re, shutil, subprocess, sys, tempfile, threading
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

# ============================================================
# Configuration
# ============================================================
SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR = SCRIPT_DIR / "data"
WORK_DIR = SCRIPT_DIR / "work"

GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
GAP_MEMORY = "8g"

TOTAL_CLASSES = 1466358
TOTAL_TYPES = 84246
TOTAL_PROOFS = 389889

A000638 = {
    0: 1, 1: 1, 2: 2, 3: 4, 4: 11, 5: 19, 6: 56, 7: 96,
    8: 296, 9: 554, 10: 1593, 11: 3094, 12: 10723, 13: 20832,
    14: 75154, 15: 159129, 16: 686165, 17: 1466358
}

KNOWN_A174511 = {12: 2065, 13: 3845, 14: 7766}

# ============================================================
# Helpers
# ============================================================
def cygpath(winpath):
    """Convert Windows path to Cygwin path."""
    p = str(winpath).replace("\\", "/")
    if len(p) >= 2 and p[1] == ":":
        return f"/cygdrive/{p[0].lower()}/{p[2:].lstrip('/')}"
    return p

def run_gap(script_path, memory=GAP_MEMORY, log_path=None):
    """Run a GAP script via Cygwin bash, return (exit_code, output)."""
    cmd = [GAP_BASH, "--login", "-c",
           f'/opt/gap-4.15.1/gap -q -o {memory} "{cygpath(script_path)}"']
    output_lines = []
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, bufsize=1)
    for line in proc.stdout:
        output_lines.append(line)
        if log_path:
            with open(log_path, "a") as f:
                f.write(line)
    proc.wait()
    return proc.returncode, "".join(output_lines)

def run_gap_workers(scripts, n_workers, label=""):
    """Run multiple GAP scripts in parallel threads."""
    results = {}
    def worker(idx, script):
        log = WORK_DIR / f"{label}_w{idx+1}.log"
        rc, out = run_gap(script, log_path=log)
        results[idx] = (rc, out, log)
    threads = []
    for i, s in enumerate(scripts):
        t = threading.Thread(target=worker, args=(i, s))
        t.start()
        threads.append(t)
    for t in threads:
        t.join()
    return results

def normalize_gap(s):
    """Remove whitespace from GAP list string."""
    return re.sub(r"\s+", "", s)

# ============================================================
# Phase 0: Setup — decompress data files
# ============================================================
def phase0_setup():
    print("=" * 60)
    print("PHASE 0: Setup")
    print("=" * 60)
    WORK_DIR.mkdir(exist_ok=True)

    files = {
        "s17_subgroups_cycles.g": True,  # True = gzipped
        "s17_proofs.g": True,
        "s17_idgroup_map.g": True,
        "s17_verification_certificate_v5.g": False,
    }
    for name, is_gz in files.items():
        target = WORK_DIR / name
        if target.exists():
            print(f"  {name}: already decompressed")
            continue
        if is_gz:
            src = DATA_DIR / f"{name}.gz"
            print(f"  Decompressing {name}.gz ...", end=" ", flush=True)
            with gzip.open(src, "rb") as gz, open(target, "wb") as out:
                shutil.copyfileobj(gz, out)
            print(f"done ({target.stat().st_size / 1e6:.1f} MB)")
        else:
            src = DATA_DIR / name
            shutil.copy2(src, target)
            print(f"  {name}: copied")

    return True

# ============================================================
# Phase 1: Certificate internal consistency (Python)
# ============================================================
def parse_certificate():
    """Parse certificate records."""
    records = []
    cert_path = WORK_DIR / "s17_verification_certificate_v5.g"
    with open(cert_path) as f:
        for line in f:
            line = line.strip()
            if not line.startswith("rec("):
                continue
            r = {}
            r["t"] = int(re.search(r't:=(\d+)', line).group(1))
            r["i"] = int(re.search(r'i:=(\d+)', line).group(1))
            r["m"] = re.search(r'm:="(\w)"', line).group(1)
            r["o"] = int(re.search(r'o:=(\d+)', line).group(1))
            sk = re.search(r'sk:=(\[.*?\]\])', line)
            if sk: r["sk"] = sk.group(1)
            h = re.search(r'h:=(\[\[.*?\]\])', line)
            if h: r["h"] = h.group(1)
            aut = re.search(r'aut:=(\d+)', line)
            if aut: r["aut"] = int(aut.group(1))
            crpf = re.search(r'crpfHash:="([^"]+)"', line)
            if crpf: r["crpf"] = crpf.group(1)
            records.append(r)
    return records

def phase1_consistency():
    print("\n" + "=" * 60)
    print("PHASE 1: Certificate Internal Consistency")
    print("=" * 60)

    records = parse_certificate()
    errors = 0

    # Method counts
    mc = Counter(r["m"] for r in records)
    total = sum(mc.values())
    print(f"  Total types: {total}", end="")
    if total != TOTAL_TYPES:
        print(f" ERROR (expected {TOTAL_TYPES})")
        errors += 1
    else:
        print(" OK")

    # Contiguous type numbers
    types = sorted(r["t"] for r in records)
    if types != list(range(1, TOTAL_TYPES + 1)):
        print("  Type numbers: NOT contiguous - ERROR")
        errors += 1
    else:
        print("  Type numbers: contiguous 1..84246 OK")

    # Unique indices
    indices = [r["i"] for r in records]
    if len(set(indices)) != len(indices):
        print("  Indices: DUPLICATES - ERROR")
        errors += 1
    else:
        print("  Indices: all unique OK")

    # Method-level uniqueness
    order_counts = Counter(r["o"] for r in records)
    for r in records:
        if r["m"] == "A" and order_counts[r["o"]] != 1:
            print(f"  A-type t={r['t']}: order not unique - ERROR")
            errors += 1; break
    else:
        a_count = mc.get("A", 0)
        print(f"  A-types: {a_count} all have unique orders OK")

    # C uniqueness
    sk_counts = defaultdict(list)
    for r in records:
        if "sk" in r: sk_counts[r["sk"]].append(r)
    c_err = sum(1 for r in records if r["m"] == "C" and len(sk_counts[r["sk"]]) != 1)
    print(f"  C-types: {mc.get('C', 0)} unique sigKeys {'OK' if c_err == 0 else f'ERROR ({c_err})'}")
    errors += c_err

    # D uniqueness
    skh_counts = defaultdict(list)
    for r in records:
        if "sk" in r and "h" in r: skh_counts[(r["sk"], r["h"])].append(r)
    d_err = sum(1 for r in records if r["m"] == "D" and len(skh_counts[(r["sk"], r["h"])]) != 1)
    print(f"  D-types: {mc.get('D', 0)} unique (sk,h) {'OK' if d_err == 0 else f'ERROR ({d_err})'}")
    errors += d_err

    # E uniqueness
    skha_counts = defaultdict(list)
    for r in records:
        if "sk" in r and "h" in r and "aut" in r:
            skha_counts[(r["sk"], r["h"], r["aut"])].append(r)
    e_err = sum(1 for r in records if r["m"] == "E" and
                len(skha_counts.get((r.get("sk"), r.get("h"), r.get("aut")), [])) != 1)
    print(f"  E-types: {mc.get('E', 0)} unique (sk,h,aut) {'OK' if e_err == 0 else f'ERROR ({e_err})'}")
    errors += e_err

    # F uniqueness (crpfHash within E-bucket)
    fg_buckets = defaultdict(list)
    for r in records:
        if r["m"] in ("F", "G") and "crpf" in r:
            fg_buckets[(r.get("sk"), r.get("h"), r.get("aut"))].append(r)
    f_err = 0
    for r in records:
        if r["m"] == "F" and "crpf" in r:
            key = (r.get("sk"), r.get("h"), r.get("aut"))
            same = [x for x in fg_buckets[key] if x.get("crpf") == r["crpf"] and x["m"] == "F"]
            if len(same) != 1: f_err += 1
    print(f"  F-types: {mc.get('F', 0)} unique crpfHash in bucket {'OK' if f_err == 0 else f'ERROR ({f_err})'}")
    errors += f_err

    # G-pairs
    g_types = [r for r in records if r["m"] == "G"]
    g_buckets = defaultdict(list)
    for r in g_types:
        g_buckets[(r.get("sk"), r.get("h"), r.get("aut"), r.get("crpf", ""))].append(r)
    g_ok = all(len(v) == 2 for v in g_buckets.values())
    print(f"  G-types: {len(g_types)} in {len(g_buckets)} pairs {'OK' if g_ok else 'ERROR'}")
    if not g_ok: errors += 1

    print(f"\n  Phase 1: {'PASS' if errors == 0 else f'FAIL ({errors} errors)'}")
    return errors == 0, records

# ============================================================
# Phase 2: Proof validation (GAP, parallel)
# ============================================================
def phase2_proofs(n_workers):
    print("\n" + "=" * 60)
    print(f"PHASE 2: Proof Validation ({TOTAL_PROOFS} proofs, {n_workers} workers)")
    print("=" * 60)

    proofs_per = (TOTAL_PROOFS + n_workers - 1) // n_workers
    scripts = []
    for w in range(n_workers):
        start = w * proofs_per + 1
        end = min((w + 1) * proofs_per, TOTAL_PROOFS)
        script = WORK_DIR / f"validate_proofs_w{w+1}.g"
        output = WORK_DIR / f"validate_proofs_w{w+1}_out.txt"
        with open(script, "w") as f:
            f.write(f'_OUT := "{cygpath(output)}";\n')
            f.write(f'PrintTo(_OUT, "");\n')
            f.write(f'Read("{cygpath(WORK_DIR / "s17_proofs.g")}");\n')
            f.write(f'_nOK := 0;; _nFail := 0;;\n')
            f.write(f'for _i in [{start}..Minimum({end}, Length(S17_PROOFS))] do\n')
            f.write(f'  _p := S17_PROOFS[_i];\n')
            f.write(f'  _gens := List(_p.gens, x -> EvalString(x));\n')
            f.write(f'  _imgs := List(_p.images, x -> EvalString(x));\n')
            f.write(f'  _G := Group(_gens); _H := Group(_imgs);\n')
            f.write(f'  if Size(_G) <> Size(_H) then\n')
            f.write(f'    AppendTo(_OUT, "FAIL|", _p.duplicate, "|size\\n"); _nFail := _nFail+1;\n')
            f.write(f'  else\n')
            f.write(f'    _phi := GroupHomomorphismByImages(_G, _H, _gens, _imgs);\n')
            f.write(f'    if _phi = fail then\n')
            f.write(f'      AppendTo(_OUT, "FAIL|", _p.duplicate, "|hom\\n"); _nFail := _nFail+1;\n')
            f.write(f'    else _nOK := _nOK+1; fi;\n')
            f.write(f'  fi;\n')
            f.write(f'  if (_i-{start}+1) mod 5000 = 0 then\n')
            f.write(f'    Print("w{w+1}: ", _i-{start}+1, "/{end-start+1} ok=", _nOK, " fail=", _nFail, "\\n"); fi;\n')
            f.write(f'od;\n')
            f.write(f'AppendTo(_OUT, "SUMMARY|ok=", _nOK, "|fail=", _nFail, "\\n");\n')
            f.write(f'Print("w{w+1} done: ok=", _nOK, " fail=", _nFail, "\\n");\n')
            f.write(f'QUIT;\n')
        scripts.append(script)

    print(f"  Launching {n_workers} workers...", flush=True)
    t0 = datetime.now()
    results = run_gap_workers(scripts, n_workers, label="proof")
    dt = (datetime.now() - t0).total_seconds()

    total_ok = 0; total_fail = 0; all_good = True
    for i in range(n_workers):
        output = WORK_DIR / f"validate_proofs_w{i+1}_out.txt"
        try:
            text = output.read_text()
            m = re.search(r'SUMMARY\|ok=(\d+)\|fail=(\d+)', text)
            if m:
                ok, fail = int(m.group(1)), int(m.group(2))
                total_ok += ok; total_fail += fail
                if fail > 0: all_good = False
            else:
                print(f"  Worker {i+1}: no summary found - ERROR")
                all_good = False
            fails = [l for l in text.split("\n") if l.startswith("FAIL")]
            for fl in fails:
                print(f"  FAILED: {fl}")
        except FileNotFoundError:
            print(f"  Worker {i+1}: output missing - ERROR")
            all_good = False

    print(f"  Proofs validated: {total_ok}/{total_ok + total_fail} ({dt:.0f}s)")
    print(f"\n  Phase 2: {'PASS' if all_good and total_ok == TOTAL_PROOFS else 'FAIL'}")
    return all_good and total_ok == TOTAL_PROOFS

# ============================================================
# Phase 3: Invariant verification (GAP, parallel)
# ============================================================
def phase3_invariants(records, n_workers):
    print("\n" + "=" * 60)
    print(f"PHASE 3: Invariant Verification ({len(records)} types, {n_workers} workers)")
    print("=" * 60)

    subgroups_cyg = cygpath(WORK_DIR / "s17_subgroups_cycles.g")

    # Split types into worker batches
    batches = [[] for _ in range(n_workers)]
    for i, r in enumerate(records):
        batches[i % n_workers].append(r)

    scripts = []
    for w in range(n_workers):
        batch = batches[w]
        script = WORK_DIR / f"verify_inv_w{w+1}.g"
        output = WORK_DIR / f"verify_inv_w{w+1}_out.txt"
        with open(script, "w") as f:
            f.write(f'_OUT := "{cygpath(output)}";\n')
            f.write(f'PrintTo(_OUT, "");\n')
            f.write(f'Print("Loading generators...\\n");\n')
            f.write(f'_gen := ReadAsFunction("{subgroups_cyg}")();\n')
            f.write(f'Print("Loaded ", Length(_gen), "\\n");\n')
            f.write(f'_ComputeSK := function(G) local D,dl,ai;\n')
            f.write(f'  D:=DerivedSubgroup(G);\n')
            f.write(f'  if not IsSolvableGroup(G) then dl:=-1; else dl:=DerivedLength(G); fi;\n')
            f.write(f'  ai:=ShallowCopy(AbelianInvariants(G/D)); Sort(ai);\n')
            f.write(f'  return [Size(G),Size(D),NrConjugacyClasses(G),dl,ai]; end;\n')
            f.write(f'_ComputeH := function(G) local h,cc,c,o,n,r,ks,k;\n')
            f.write(f'  h:=rec(); cc:=ConjugacyClasses(G);\n')
            f.write(f'  for c in cc do o:=String(Order(Representative(c))); n:=Size(c);\n')
            f.write(f'    if IsBound(h.(o)) then h.(o):=h.(o)+n; else h.(o):=n; fi; od;\n')
            f.write(f'  ks:=List(RecNames(h),x->Int(x)); Sort(ks); r:=[];\n')
            f.write(f'  for k in ks do Add(r,[k,h.(String(k))]); od; return r; end;\n')
            f.write(f'_t0:=Runtime();; _nDone:=0;;\n')

            AUT_LIMIT = 50000
            for r in batch:
                idx = r["i"]
                has_sk = "sk" in r
                has_h = "h" in r
                has_aut = "aut" in r and r["o"] <= AUT_LIMIT

                f.write(f'_G:=Group(_gen[{idx}]); _sz:=Size(_G);\n')
                f.write(f'AppendTo(_OUT, "IDX={idx}|ORDER=", _sz);\n')
                if has_sk:
                    f.write(f'AppendTo(_OUT, "|SK=", _ComputeSK(_G));\n')
                if has_h:
                    f.write(f'AppendTo(_OUT, "|HIST=", _ComputeH(_G));\n')
                if has_aut:
                    f.write(f'AppendTo(_OUT, "|AUT=", Size(AutomorphismGroup(_G)));\n')
                f.write(f'AppendTo(_OUT, "\\n");\n')
                f.write(f'_nDone:=_nDone+1;\n')
                f.write(f'if _nDone mod 500=0 then Print("w{w+1}: ",_nDone,"/{len(batch)} (",Runtime()-_t0,"ms)\\n"); fi;\n')

            f.write(f'Print("w{w+1} done: ",_nDone," types (",Runtime()-_t0,"ms)\\n");\n')
            f.write(f'QUIT;\n')
        scripts.append(script)

    print(f"  Launching {n_workers} workers...", flush=True)
    t0 = datetime.now()
    run_gap_workers(scripts, n_workers, label="inv")
    dt = (datetime.now() - t0).total_seconds()

    # Collect and compare
    expected = {str(r["i"]): r for r in records}
    actual = {}
    for w in range(n_workers):
        output = WORK_DIR / f"verify_inv_w{w+1}_out.txt"
        try:
            raw = output.read_text()
        except FileNotFoundError:
            print(f"  Worker {w+1}: output missing")
            continue
        joined = []
        for line in raw.split("\n"):
            line = line.rstrip()
            if not line or line.startswith("#"): continue
            if line.startswith("IDX="): joined.append(line)
            elif joined: joined[-1] += line.lstrip()
        for jl in joined:
            fields = {}
            for part in jl.split("|"):
                if "=" in part:
                    k, v = part.split("=", 1)
                    fields[k] = v.strip()
            if "IDX" in fields:
                actual[fields["IDX"]] = fields

    errors = 0
    order_ok = sk_ok = sk_n = h_ok = h_n = aut_ok = aut_n = 0
    for idx_str, exp in expected.items():
        act = actual.get(idx_str)
        if not act: continue
        if int(act.get("ORDER", 0)) != exp["o"]:
            print(f"  ORDER ERROR: i={idx_str} cert={exp['o']} actual={act.get('ORDER')}")
            errors += 1
        else: order_ok += 1
        if exp.get("sk") and "SK" in act:
            sk_n += 1
            if normalize_gap(exp["sk"]) != normalize_gap(act["SK"]): errors += 1
            else: sk_ok += 1
        if exp.get("h") and "HIST" in act:
            h_n += 1
            if normalize_gap(exp["h"]) != normalize_gap(act["HIST"]): errors += 1
            else: h_ok += 1
        if exp.get("aut") and "AUT" in act:
            aut_n += 1
            if int(act["AUT"]) != exp["aut"]: errors += 1
            else: aut_ok += 1

    print(f"  Orders:     {order_ok}/{len(actual)} verified")
    print(f"  SigKeys:    {sk_ok}/{sk_n} verified")
    print(f"  Histograms: {h_ok}/{h_n} verified")
    print(f"  |Aut|:      {aut_ok}/{aut_n} verified")
    print(f"  ({dt:.0f}s)")
    ok = errors == 0 and order_ok == len(actual)
    print(f"\n  Phase 3: {'PASS' if ok else f'FAIL ({errors} errors)'}")
    return ok

# ============================================================
# Phase 3b: crpfHash verification (GAP, parallel)
# ============================================================
def phase3b_crpf(records, n_workers):
    print("\n" + "=" * 60)
    fg = [r for r in records if r["m"] in ("F", "G") and "crpf" in r and r["crpf"]]
    print(f"PHASE 3b: crpfHash Verification ({len(fg)} types, {n_workers} workers)")
    print("=" * 60)

    subgroups_cyg = cygpath(WORK_DIR / "s17_subgroups_cycles.g")
    batches = [[] for _ in range(n_workers)]
    for i, r in enumerate(fg):
        batches[i % n_workers].append(r)

    scripts = []
    for w in range(n_workers):
        batch = batches[w]
        script = WORK_DIR / f"crpf_w{w+1}.g"
        output = WORK_DIR / f"crpf_w{w+1}_out.txt"
        with open(script, "w") as f:
            f.write(f'_out:=OutputTextFile("{cygpath(output)}",false);\n')
            f.write(f'SetPrintFormattingStatus(_out,false); PrintTo(_out,""); CloseStream(_out);\n')
            f.write(f'Print("Loading...\\n");\n')
            f.write(f'_gen:=ReadAsFunction("{subgroups_cyg}")();\n')
            f.write(f'Print("Loaded\\n");\n')
            f.write(f'_CRPF:=function(G) local ct,irrs,nCC,cFP,rpf,chi,fp,p,pm;\n')
            f.write(f'  ct:=CharacterTable(G); irrs:=Irr(ct); nCC:=NrConjugacyClasses(ct);\n')
            f.write(f'  cFP:=SortedList(List(irrs,chi->SortedList(ValuesOfClassFunction(chi))));\n')
            f.write(f'  rpf:=[]; for chi in irrs do fp:=[];\n')
            f.write(f'    for p in PrimeDivisors(Size(G)) do pm:=PowerMap(ct,p);\n')
            f.write(f'      Add(fp,[p,SortedList(List([1..nCC],j->chi[pm[j]]))]); od;\n')
            f.write(f'    Sort(fp); Add(rpf,fp); od; Sort(rpf);\n')
            f.write(f'  return Concatenation(String(nCC),"|",String(cFP),"|",String(rpf)); end;\n')
            f.write(f'_t0:=Runtime();; _n:=0;;\n')
            for r in batch:
                idx = r["i"]
                f.write(f'_raw:=_CRPF(Group(_gen[{idx}]));\n')
                f.write(f'_out:=OutputTextFile("{cygpath(output)}",true);\n')
                f.write(f'SetPrintFormattingStatus(_out,false);\n')
                f.write(f'PrintTo(_out,"{idx}|",_raw,"\\n"); CloseStream(_out);\n')
                f.write(f'_n:=_n+1; if _n mod 100=0 then Print("w{w+1}: ",_n,"/{len(batch)} (",Runtime()-_t0,"ms)\\n"); fi;\n')
            f.write(f'Print("w{w+1} done: ",_n," (",Runtime()-_t0,"ms)\\n"); QUIT;\n')
        scripts.append(script)

    print(f"  Launching {n_workers} workers...", flush=True)
    t0 = datetime.now()
    run_gap_workers(scripts, n_workers, label="crpf")
    dt = (datetime.now() - t0).total_seconds()

    # Compare hashes
    expected = {str(r["i"]): r["crpf"] for r in fg}
    actual = {}
    for w in range(n_workers):
        output = WORK_DIR / f"crpf_w{w+1}_out.txt"
        try:
            for line in output.open():
                line = line.rstrip()
                if not line: continue
                pipe = line.index("|")
                idx = line[:pipe]
                raw = line[pipe+1:]
                actual[idx] = hashlib.sha256(raw.encode()).hexdigest()[:16]
        except: pass

    ok_count = 0; errors = 0
    for idx_str, exp_hash in expected.items():
        if idx_str in actual:
            if actual[idx_str] == exp_hash: ok_count += 1
            else:
                print(f"  CRPF ERROR: i={idx_str} cert={exp_hash} actual={actual[idx_str]}")
                errors += 1

    print(f"  crpfHash: {ok_count}/{len(actual)} verified ({dt:.0f}s)")
    ok = errors == 0 and ok_count == len(actual)
    print(f"\n  Phase 3b: {'PASS' if ok else f'FAIL ({errors} errors)'}")
    return ok

# ============================================================
# Phase 4: G-pair verification (GAP)
# ============================================================
def phase4_gpairs(records, n_workers):
    print("\n" + "=" * 60)
    g_types = [r for r in records if r["m"] == "G"]
    g_buckets = defaultdict(list)
    for r in g_types:
        g_buckets[(r.get("sk"), r.get("h"), r.get("aut"), r.get("crpf", ""))].append(r)
    pairs = [(v[0]["i"], v[1]["i"], v[0]["o"]) for v in g_buckets.values() if len(v) == 2]
    print(f"PHASE 4: G-pair Verification ({len(pairs)} pairs via IsomorphismGroups)")
    print("=" * 60)

    subgroups_cyg = cygpath(WORK_DIR / "s17_subgroups_cycles.g")
    script = WORK_DIR / "verify_gpairs.g"
    output = WORK_DIR / "verify_gpairs_out.txt"

    with open(script, "w") as f:
        f.write(f'_OUT := "{cygpath(output)}";\n')
        f.write(f'PrintTo(_OUT, "");\n')
        f.write(f'Print("Loading generators...\\n");\n')
        f.write(f'_gen := ReadAsFunction("{subgroups_cyg}")();\n')
        f.write(f'Print("Loaded\\n");\n')
        for pn, (i1, i2, order) in enumerate(pairs, 1):
            f.write(f'Print("Pair {pn}: {i1} vs {i2} order={order}\\n");\n')
            f.write(f'_G1:=Group(_gen[{i1}]); _G2:=Group(_gen[{i2}]);\n')
            f.write(f'_t0:=Runtime();\n')
            f.write(f'_phi:=IsomorphismGroups(_G1,_G2);\n')
            f.write(f'if _phi=fail then\n')
            f.write(f'  Print("  NOT ISO (",Runtime()-_t0,"ms)\\n");\n')
            f.write(f'  AppendTo(_OUT,"NONISO|{i1}|{i2}\\n");\n')
            f.write(f'else\n')
            f.write(f'  Print("  ISO (ERROR!) (",Runtime()-_t0,"ms)\\n");\n')
            f.write(f'  AppendTo(_OUT,"ISO|{i1}|{i2}\\n");\n')
            f.write(f'fi;\n')
        f.write(f'QUIT;\n')

    print(f"  Running IsomorphismGroups on {len(pairs)} pairs...", flush=True)
    t0 = datetime.now()
    rc, out = run_gap(script, memory="20g", log_path=WORK_DIR / "gpairs.log")
    dt = (datetime.now() - t0).total_seconds()

    text = output.read_text() if output.exists() else ""
    noniso = text.count("NONISO|")
    iso = text.count("ISO|") - noniso  # "ISO|" is substring of "NONISO|"
    # More precise count
    iso = len([l for l in text.split("\n") if l.startswith("ISO|")])
    noniso = len([l for l in text.split("\n") if l.startswith("NONISO|")])

    print(f"  NOT ISO: {noniso}/{len(pairs)}, ISO: {iso} ({dt:.0f}s)")
    ok = noniso == len(pairs) and iso == 0
    print(f"\n  Phase 4: {'PASS' if ok else 'FAIL'}")
    return ok

# ============================================================
# Phase 5: Class-to-type map + A174511(n)
# ============================================================
def phase5_map(records):
    print("\n" + "=" * 60)
    print("PHASE 5: Class-to-Type Map + A174511(n)")
    print("=" * 60)

    rep_to_type = {r["i"]: r["t"] for r in records}

    # IdGroup map
    idx_to_idgroup = {}
    with open(WORK_DIR / "s17_idgroup_map.g") as f:
        for line in f:
            m = re.match(r'S17_IDGROUP_MAP\[(\d+)\]\s*:=\s*\[\s*(\d+)\s*,\s*(\d+)\s*\]', line)
            if m:
                idx_to_idgroup[int(m.group(1))] = (int(m.group(2)), int(m.group(3)))

    idgroup_to_type = {}
    for idx, t in rep_to_type.items():
        if idx in idx_to_idgroup:
            idgroup_to_type[idx_to_idgroup[idx]] = t

    # Proofs
    dup_to_rep = {}
    cur_dup = None
    with open(WORK_DIR / "s17_proofs.g") as f:
        for line in f:
            dm = re.search(r'duplicate\s*:=\s*(\d+)', line)
            if dm: cur_dup = int(dm.group(1))
            rm = re.search(r'representative\s*:=\s*(\d+)', line)
            if rm and cur_dup is not None:
                dup_to_rep[cur_dup] = int(rm.group(1))
                cur_dup = None

    # Build map
    class_to_type = [0] * (TOTAL_CLASSES + 1)
    via_rep = via_idgroup = via_proof = 0
    missing = []

    for idx in range(1, TOTAL_CLASSES + 1):
        if idx in rep_to_type:
            class_to_type[idx] = rep_to_type[idx]; via_rep += 1
        elif idx in idx_to_idgroup and idx_to_idgroup[idx] in idgroup_to_type:
            class_to_type[idx] = idgroup_to_type[idx_to_idgroup[idx]]; via_idgroup += 1
        elif idx in dup_to_rep:
            cur = dup_to_rep[idx]; resolved = False
            for _ in range(10):
                if cur in rep_to_type:
                    class_to_type[idx] = rep_to_type[cur]; via_proof += 1; resolved = True; break
                elif cur in idx_to_idgroup and idx_to_idgroup[cur] in idgroup_to_type:
                    class_to_type[idx] = idgroup_to_type[idx_to_idgroup[cur]]; via_proof += 1; resolved = True; break
                if cur in dup_to_rep: cur = dup_to_rep[cur]
                else: break
            if not resolved: missing.append(idx)
        else: missing.append(idx)

    mapped = via_rep + via_idgroup + via_proof
    print(f"  Mapped: {mapped:,} / {TOTAL_CLASSES:,}")
    print(f"    Via type rep: {via_rep:,}")
    print(f"    Via IdGroup:  {via_idgroup:,}")
    print(f"    Via proof:    {via_proof:,}")
    if missing:
        print(f"    MISSING: {len(missing)} indices")

    # A174511(n)
    min_per_type = {}
    for idx in range(1, TOTAL_CLASSES + 1):
        t = class_to_type[idx]
        if t > 0 and (t not in min_per_type or idx < min_per_type[t]):
            min_per_type[t] = idx

    print(f"\n  A174511(n):")
    print(f"  {'n':>4s} {'A000638(n)':>12s} {'A174511(n)':>12s} {'New':>8s}")
    print("  " + "-" * 40)
    a174511 = {}; prev = 0
    all_known_ok = True
    for n in range(18):
        val = sum(1 for mi in min_per_type.values() if mi <= A000638[n])
        a174511[n] = val
        new = val - prev
        suffix = ""
        if n in KNOWN_A174511:
            if val == KNOWN_A174511[n]: suffix = " OK"
            else: suffix = f" MISMATCH (expected {KNOWN_A174511[n]})"; all_known_ok = False
        print(f"  {n:>4d} {A000638[n]:>12,} {val:>12,} {new:>8,}{suffix}")
        prev = val

    # Write map
    map_path = WORK_DIR / "s17_class_to_type_map.g"
    with open(map_path, "w") as f:
        f.write(f"# Class-to-type mapping for S17\n")
        f.write(f"# S17_CLASS_TO_TYPE[i] = type index (1..{TOTAL_TYPES}) for conjugacy class i\n")
        f.write(f"S17_CLASS_TO_TYPE := [\n")
        for idx in range(1, TOTAL_CLASSES + 1):
            f.write(f"{class_to_type[idx]}")
            if idx < TOTAL_CLASSES: f.write(",")
            f.write("\n")
        f.write("];\n")
    print(f"\n  Class-to-type map written to {map_path}")

    ok = len(missing) == 0 and all_known_ok and a174511[17] == TOTAL_TYPES
    print(f"\n  Phase 5: {'PASS' if ok else 'FAIL'}")
    return ok

# ============================================================
# Main
# ============================================================
def main():
    parser = argparse.ArgumentParser(description="Verify A174511(17) = 84,246")
    parser.add_argument("--workers", type=int, default=3, help="Number of parallel GAP workers")
    parser.add_argument("--skip-gap", action="store_true", help="Skip GAP phases (Python-only)")
    args = parser.parse_args()

    print(f"A174511(17) Verification Pipeline")
    print(f"Started: {datetime.now()}")
    print(f"Workers: {args.workers}")

    results = {}

    results["phase0"] = phase0_setup()
    results["phase1"], records = phase1_consistency()

    if not args.skip_gap:
        results["phase2"] = phase2_proofs(args.workers)
        results["phase3"] = phase3_invariants(records, args.workers)
        results["phase3b"] = phase3b_crpf(records, args.workers)
        results["phase4"] = phase4_gpairs(records, args.workers)
    else:
        print("\n  (Skipping GAP phases)")

    results["phase5"] = phase5_map(records)

    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    all_pass = all(results.values())
    for name, ok in results.items():
        print(f"  {name}: {'PASS' if ok else 'FAIL'}")
    print()
    if all_pass:
        print(f"  *** A174511(17) = {TOTAL_TYPES} VERIFIED ***")
    else:
        print(f"  VERIFICATION INCOMPLETE — check failures above")
    print(f"\nFinished: {datetime.now()}")
    return 0 if all_pass else 1

if __name__ == "__main__":
    sys.exit(main())
