#!/usr/bin/env python3
"""
Build S16 verification certificate from S17 data + S16 representative indices.

Two-phase approach:
  Phase 1 (Python): Match S16 v7 types to S17 types where possible,
    using [order,id] for B-types, unique order for A-types, and sigKey matching.
  Phase 2 (GAP): For unmatched types, compute full histograms from S16 data,
    then complete matching. If still unmatched, compute |Aut| and crpfHash.

Usage:
  python build_s16_certificate.py              # Phase 1 only (fast, Python)
  python build_s16_certificate.py --phase2     # After GAP computation
"""
import argparse, json, re, subprocess, sys, os
from collections import defaultdict, Counter
from datetime import datetime
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
S17_CERT = BASE / "s17_proof_certificate" / "data" / "s17_verification_certificate_v5.g"
S17_C2T  = BASE / "s17_proof_certificate" / "work" / "s17_class_to_type_map.g"
S17_IMAP = BASE / "s17_proof_certificate" / "work" / "s17_idgroup_map.g"
S16_V7   = BASE / "s16_final_results" / "s16_verification_certificate_v7.g"
S16_SUBS = BASE / "s16_final_results" / "s16_subgroups.g"

SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR = SCRIPT_DIR / "data"
WORK_DIR = SCRIPT_DIR / "work"

OUTPUT = DATA_DIR / "s16_verification_certificate.g"
UNMATCHED_FILE = WORK_DIR / "unmatched_indices.json"
HISTOGRAMS_FILE = WORK_DIR / "computed_histograms.json"
AUT_FILE = WORK_DIR / "computed_aut.json"
CRPF_FILE = WORK_DIR / "computed_crpf.json"

TOTAL_S16_CLASSES = 686165
EXPECTED_S16_TYPES = 43626

GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"

# ============================================================
# Parsers
# ============================================================
def parse_rec(line):
    """Parse a GAP rec(...) into a Python dict."""
    line = line.strip().rstrip(",")
    if not line.startswith("rec(") or not line.endswith(")"):
        return None
    inner = line[4:-1]
    d = {}
    pos = 0
    while pos < len(inner):
        while pos < len(inner) and inner[pos] in " \t":
            pos += 1
        if pos >= len(inner):
            break
        eq_pos = inner.find(":=", pos)
        if eq_pos < 0:
            break
        key = inner[pos:eq_pos].strip()
        pos = eq_pos + 2
        val_str, pos = extract_value(inner, pos)
        d[key] = parse_value(val_str.strip())
    return d

def extract_value(s, pos):
    depth = 0
    in_str = False
    start = pos
    while pos < len(s):
        c = s[pos]
        if in_str:
            if c == '"': in_str = False
            pos += 1; continue
        if c == '"': in_str = True; pos += 1; continue
        if c in "([": depth += 1
        elif c in ")]": depth -= 1
        elif c == "," and depth == 0:
            return s[start:pos], pos + 1
        pos += 1
    return s[start:pos], pos

def parse_value(s):
    s = s.strip()
    if s.startswith('"') and s.endswith('"'): return s[1:-1]
    if s.startswith("rec("): return parse_rec(s)
    if s.startswith("["): return parse_list(s)
    try: return int(s)
    except ValueError:
        try: return float(s)
        except ValueError: return s

def parse_list(s):
    s = s.strip()
    if not s.startswith("[") or not s.endswith("]"): return s
    inner = s[1:-1].strip()
    if not inner: return []
    items = []
    pos = 0
    while pos < len(inner):
        val_str, pos = extract_value(inner, pos)
        val_str = val_str.strip()
        if val_str: items.append(parse_value(val_str))
    return items

def parse_s17_cert():
    types = {}
    with open(S17_CERT) as f:
        for line in f:
            line = line.strip()
            if not line.startswith("rec("): continue
            d = parse_rec(line)
            if d and "t" in d: types[d["t"]] = d
    print(f"  S17 certificate: {len(types)} types")
    return types

def parse_s17_c2t():
    c2t = []
    with open(S17_C2T) as f:
        for line in f:
            line = line.strip().rstrip(",")
            if line.startswith("#") or line.startswith("S17") or line in ("", "[", "];"): continue
            for part in line.split(","):
                part = part.strip()
                if part:
                    try: c2t.append(int(part))
                    except ValueError: pass
    print(f"  S17 class-to-type map: {len(c2t)} entries")
    return c2t

def parse_s17_idgroup_map():
    idmap = {}
    with open(S17_IMAP) as f:
        for line in f:
            m = re.match(r'S17_IDGROUP_MAP\[(\d+)\]\s*:=\s*\[(\d+),\s*(\d+)\]', line.strip())
            if m: idmap[int(m.group(1))] = (int(m.group(2)), int(m.group(3)))
    print(f"  S17 IdGroup map: {len(idmap)} entries")
    return idmap

def parse_s16_v7():
    types = {}
    with open(S16_V7) as f:
        for line in f:
            line = line.strip()
            if not line.startswith("rec("): continue
            d = parse_rec(line)
            if d and "t" in d:
                if "o" not in d and "sk" in d and isinstance(d["sk"], list):
                    d["o"] = d["sk"][0]
                types[d["t"]] = d
    print(f"  S16 v7 certificate: {len(types)} types")
    return types

# ============================================================
# Phase 1: Match what we can from S17
# ============================================================
def phase1_match(s17_cert, s17_c2t, s17_idmap, s16_v7):
    """Match S16 v7 types to S17 types. Returns matched dict and unmatched list."""
    # Determine S16 types
    s16_s17_types = set()
    for idx in range(TOTAL_S16_CLASSES):
        s16_s17_types.add(s17_c2t[idx])
    print(f"  S17 types at S16: {len(s16_s17_types)}")

    # Build (order, id) -> S17 type
    oi_to_type = {}
    for idx, (order, gid) in s17_idmap.items():
        if idx - 1 < len(s17_c2t):
            key = (order, gid)
            if key not in oi_to_type:
                oi_to_type[key] = s17_c2t[idx - 1]
    print(f"  (order,id) -> type: {len(oi_to_type)} entries")

    # Build S17 lookups
    s17_by_sk = defaultdict(list)
    for t in s16_s17_types:
        e = s17_cert[t]
        sk = e.get("sk")
        if sk: s17_by_sk[str(sk)].append(t)

    matched = {}  # s16_v7_t -> s17_t
    used_s17 = set()

    # Pass 1: B-types by [order, id]
    for s16t, s16e in s16_v7.items():
        if s16e.get("m") != "B": continue
        oid = s16e.get("id")
        if oid and isinstance(oid, list) and len(oid) == 2:
            key = (int(oid[0]), int(oid[1]))
            s17t = oi_to_type.get(key)
            if s17t and s17t in s16_s17_types:
                matched[s16t] = s17t; used_s17.add(s17t)
    print(f"  Pass 1 (B by [o,id]): {len(matched)}")

    # Pass 2: A-types by unique order
    s17_order = defaultdict(list)
    for t in s16_s17_types:
        s17_order[s17_cert[t]["o"]].append(t)
    for s16t, s16e in s16_v7.items():
        if s16t in matched or s16e.get("m") != "A": continue
        o = s16e.get("o")
        cands = [t for t in s17_order.get(o, []) if t not in used_s17]
        if len(cands) == 1:
            matched[s16t] = cands[0]; used_s17.add(cands[0])
    a_count = sum(1 for s16t, s16e in s16_v7.items()
                  if s16t in matched and s16e.get("m") == "A")
    print(f"  Pass 2 (A by order): {a_count}")

    # Pass 3: unique sigKey among remaining candidates
    prev = len(matched)
    for s16t, s16e in s16_v7.items():
        if s16t in matched: continue
        sk = s16e.get("sk")
        if sk is None: continue
        sk_n = str(sk)
        cands = [t for t in s17_by_sk.get(sk_n, []) if t not in used_s17]
        if len(cands) == 1:
            matched[s16t] = cands[0]; used_s17.add(cands[0])
    print(f"  Pass 3 (unique sk): {len(matched) - prev}")

    # Pass 4: sigKey + histogram subset matching
    prev = len(matched)
    for s16t, s16e in s16_v7.items():
        if s16t in matched: continue
        sk = s16e.get("sk")
        h = s16e.get("h")
        if sk is None: continue
        sk_n = str(sk)
        cands = [t for t in s17_by_sk.get(sk_n, []) if t not in used_s17]
        if len(cands) == 1:
            matched[s16t] = cands[0]; used_s17.add(cands[0]); continue
        if len(cands) == 0 or h is None: continue
        # Extract [order, count] pairs from S16 histogram
        s16_pairs = set()
        if isinstance(h, list):
            for entry in h:
                if isinstance(entry, list) and len(entry) >= 2:
                    s16_pairs.add((int(entry[0]), int(entry[1])))
        if not s16_pairs: continue
        hits = []
        for t in cands:
            s17_h = s17_cert[t].get("h")
            if not isinstance(s17_h, list): continue
            s17_pairs = set()
            for entry in s17_h:
                if isinstance(entry, list) and len(entry) >= 2:
                    s17_pairs.add((int(entry[0]), int(entry[1])))
            if s16_pairs.issubset(s17_pairs):
                hits.append(t)
        if len(hits) == 1:
            matched[s16t] = hits[0]; used_s17.add(hits[0])
    print(f"  Pass 4 (sk+h subset): {len(matched) - prev}")

    # Pass 5: elimination (candidates that became unique after previous passes)
    prev = len(matched)
    changed = True
    while changed:
        changed = False
        for s16t, s16e in s16_v7.items():
            if s16t in matched: continue
            sk = s16e.get("sk")
            if sk is None: continue
            cands = [t for t in s17_by_sk.get(str(sk), []) if t not in used_s17]
            if len(cands) == 1:
                matched[s16t] = cands[0]; used_s17.add(cands[0])
                changed = True
    print(f"  Pass 5 (elimination): {len(matched) - prev}")

    # Collect unmatched
    unmatched = []
    for s16t in sorted(s16_v7.keys()):
        if s16t not in matched:
            unmatched.append(s16t)

    print(f"\n  Matched: {len(matched)} / {len(s16_v7)}")
    print(f"  Unmatched: {len(unmatched)}")

    return matched, unmatched, s16_s17_types, used_s17, s17_by_sk

# ============================================================
# Phase 2: Compute missing histograms from S16 data via GAP
# ============================================================
def generate_histogram_workers(unmatched_types, s16_v7, n_workers=3):
    """Generate GAP worker scripts to compute full histograms."""
    WORK_DIR.mkdir(exist_ok=True)
    indices = []
    for s16t in unmatched_types:
        indices.append((s16t, s16_v7[s16t]["i"]))

    # Save unmatched info
    with open(UNMATCHED_FILE, "w") as f:
        json.dump(indices, f)
    print(f"  Saved {len(indices)} unmatched type indices to {UNMATCHED_FILE}")

    # Split among workers
    chunks = [[] for _ in range(n_workers)]
    for i, item in enumerate(indices):
        chunks[i % n_workers].append(item)

    scripts = []
    subs_cyg = cygpath(S16_SUBS)
    for w in range(n_workers):
        script = WORK_DIR / f"compute_hist_w{w+1}.g"
        out_file = WORK_DIR / f"hist_w{w+1}_out.txt"
        out_cyg = cygpath(out_file)
        chunk = chunks[w]

        with open(script, "w") as f:
            f.write(f'# Worker {w+1}: compute histograms for {len(chunk)} types\n')
            f.write(f'Print("Loading s16_subgroups.g...\\n");;\n')
            f.write(f'_allGens := ReadAsFunction("{subs_cyg}")();;\n')
            f.write(f'Print("Loaded ", Length(_allGens), " classes\\n");;\n\n')
            # Clear output file
            f.write(f'PrintTo("{out_cyg}", "");;\n\n')
            f.write('_ComputeHist := function(gens)\n')
            f.write('  local G, hist, x, o;\n')
            f.write('  G := Group(List(gens, PermList));\n')
            f.write('  hist := rec();\n')
            f.write('  for x in G do\n')
            f.write('    o := Order(x);\n')
            f.write('    if IsBound(hist.(String(o))) then\n')
            f.write('      hist.(String(o)) := hist.(String(o)) + 1;\n')
            f.write('    else\n')
            f.write('      hist.(String(o)) := 1;\n')
            f.write('    fi;\n')
            f.write('  od;\n')
            f.write('  return hist;\n')
            f.write('end;;\n\n')
            f.write('_FormatHist := function(h)\n')
            f.write('  local keys, result;\n')
            f.write('  keys := List(RecNames(h), x -> Int(x));\n')
            f.write('  Sort(keys);\n')
            f.write('  result := List(keys, k -> Concatenation("[", String(k), ",", String(h.(String(k))), "]"));\n')
            f.write('  return Concatenation("[", JoinStringsWithSeparator(result, ","), "]");\n')
            f.write('end;;\n\n')

            for idx, (s16t, s16_idx) in enumerate(chunk):
                f.write(f'# Type {s16t}, S16 index {s16_idx}\n')
                if (idx + 1) % 50 == 1:
                    f.write(f'Print("w{w+1}: {idx+1}/{len(chunk)} t={s16t}\\n");;\n')
                f.write(f'_h := _ComputeHist(_allGens[{s16_idx}]);;\n')
                f.write(f'_hs := _FormatHist(_h);;\n')
                # Histogram only — no |Aut| (too expensive for large groups)
                f.write(f'AppendTo("{out_cyg}", "{s16t}|", _hs, "\\n");;\n')
            f.write(f'Print("w{w+1}: DONE ({len(chunk)} types)\\n");;\n')
            f.write('QUIT;\n')

        scripts.append(script)

    print(f"  Generated {n_workers} GAP worker scripts")
    return scripts

def cygpath(winpath):
    p = str(winpath).replace("\\", "/")
    if len(p) >= 2 and p[1] == ":":
        return f"/cygdrive/{p[0].lower()}/{p[2:].lstrip('/')}"
    return p

def launch_gap_workers(scripts, n_workers=3):
    """Launch GAP workers in parallel."""
    import threading
    results = {}
    def worker(idx, script):
        log = WORK_DIR / f"hist_w{idx+1}.log"
        cmd = [GAP_BASH, "--login", "-c",
               f'/opt/gap-4.15.1/gap -q -o 8g "{cygpath(script)}"']
        with open(log, "w") as logf:
            logf.write(f"# Started: {datetime.now()}\n")
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, bufsize=1)
            for line in proc.stdout:
                print(line, end="")
                logf.write(line)
                logf.flush()
            proc.wait()
            logf.write(f"\n# Exit: {proc.returncode}\n")
        results[idx] = proc.returncode

    threads = []
    for i, s in enumerate(scripts):
        t = threading.Thread(target=worker, args=(i, s))
        t.start()
        threads.append(t)
    for t in threads:
        t.join()
    return results

def read_computed_data(n_workers=3):
    """Read computed histograms and aut values from worker output files.
    Format: s16t|histogram_str or s16t|histogram_str|aut_size
    Handles GAP line-continuation (backslash at end of line)."""
    histograms = {}  # s16_t -> histogram string
    aut_values = {}  # s16_t -> aut size
    for w in range(n_workers):
        out_file = WORK_DIR / f"hist_w{w+1}_out.txt"
        if not out_file.exists():
            continue
        with open(out_file) as f:
            # Join continuation lines (GAP wraps with \ at end)
            full_lines = []
            buf = ""
            for line in f:
                line = line.rstrip("\r\n")
                if line.endswith("\\"):
                    buf += line[:-1]  # strip trailing backslash, accumulate
                else:
                    buf += line
                    full_lines.append(buf)
                    buf = ""
            if buf:
                full_lines.append(buf)
        for line in full_lines:
            line = line.strip()
            if not line or "|" not in line:
                continue
            parts = line.split("|")
            try:
                s16t = int(parts[0])
                h_str = parts[1].strip()
                histograms[s16t] = h_str
                if len(parts) >= 3:
                    aut_values[s16t] = int(parts[2].strip())
            except (ValueError, IndexError):
                pass
    # Also read from aut-specific output files
    for w in range(n_workers):
        out_file = WORK_DIR / f"aut_w{w+1}_out.txt"
        if not out_file.exists():
            continue
        with open(out_file) as f:
            for line in f:
                line = line.strip()
                if not line or "|" not in line:
                    continue
                parts = line.split("|")
                try:
                    s16t = int(parts[0])
                    aut_values[s16t] = int(parts[1].strip())
                except (ValueError, IndexError):
                    pass
    print(f"  Read {len(histograms)} histograms, {len(aut_values)} aut values")
    return histograms, aut_values

# ============================================================
# Phase 2: Re-match with computed data
# ============================================================
def phase2_match(unmatched, matched, used_s17, s17_by_sk, s17_cert, s16_v7,
                 histograms, aut_values, s16_s17_types):
    """Re-match unmatched types using computed histograms and aut values."""
    newly_matched = 0
    still_unmatched = []

    for s16t in unmatched:
        if s16t in matched:
            continue
        s16e = s16_v7[s16t]
        sk = s16e.get("sk")
        if sk is None:
            still_unmatched.append(s16t)
            continue
        sk_n = str(sk)
        cands = [t for t in s17_by_sk.get(sk_n, []) if t not in used_s17]
        if len(cands) == 0:
            still_unmatched.append(s16t)
            continue
        if len(cands) == 1:
            matched[s16t] = cands[0]; used_s17.add(cands[0])
            newly_matched += 1
            continue

        # Try full histogram match
        h_str = histograms.get(s16t)
        if h_str:
            for t in cands:
                s17_h = s17_cert[t].get("h")
                if s17_h and str(s17_h) == h_str:
                    matched[s16t] = t; used_s17.add(t)
                    newly_matched += 1
                    break
            else:
                # Histogram didn't match any candidate exactly — try normalized
                h_normalized = re.sub(r"\s+", "", h_str)
                for t in cands:
                    s17_h = s17_cert[t].get("h")
                    if s17_h:
                        s17_h_n = re.sub(r"\s+", "", str(s17_h))
                        if h_normalized == s17_h_n:
                            matched[s16t] = t; used_s17.add(t)
                            newly_matched += 1
                            break
                else:
                    still_unmatched.append(s16t)
        else:
            still_unmatched.append(s16t)

    # Second pass: elimination
    changed = True
    while changed:
        changed = False
        remaining = []
        for s16t in still_unmatched:
            if s16t in matched:
                changed = True
                continue
            s16e = s16_v7[s16t]
            sk = s16e.get("sk")
            if sk is None:
                remaining.append(s16t)
                continue
            cands = [t for t in s17_by_sk.get(str(sk), []) if t not in used_s17]
            if len(cands) == 1:
                matched[s16t] = cands[0]; used_s17.add(cands[0])
                newly_matched += 1
                changed = True
            else:
                remaining.append(s16t)
        still_unmatched = remaining

    # Third pass: try aut matching for stubborn types
    final_unmatched = []
    for s16t in still_unmatched:
        if s16t in matched: continue
        s16e = s16_v7[s16t]
        sk = s16e.get("sk")
        if sk is None:
            final_unmatched.append(s16t); continue
        cands = [t for t in s17_by_sk.get(str(sk), []) if t not in used_s17]
        if len(cands) == 0:
            final_unmatched.append(s16t); continue
        if len(cands) == 1:
            matched[s16t] = cands[0]; used_s17.add(cands[0])
            newly_matched += 1; continue
        # Try (histogram, aut) combination
        h_str = histograms.get(s16t)
        aut = aut_values.get(s16t)
        if h_str and aut:
            h_n = re.sub(r"\s+", "", h_str)
            for t in cands:
                s17_h = s17_cert[t].get("h")
                s17_aut = s17_cert[t].get("aut")
                if s17_h and s17_aut:
                    if re.sub(r"\s+", "", str(s17_h)) == h_n and s17_aut == aut:
                        matched[s16t] = t; used_s17.add(t)
                        newly_matched += 1
                        break
            else:
                final_unmatched.append(s16t)
        else:
            final_unmatched.append(s16t)

    # Final elimination pass
    changed = True
    while changed:
        changed = False
        remaining = []
        for s16t in final_unmatched:
            if s16t in matched:
                changed = True; continue
            s16e = s16_v7[s16t]
            sk = s16e.get("sk")
            if sk is None: remaining.append(s16t); continue
            cands = [t for t in s17_by_sk.get(str(sk), []) if t not in used_s17]
            if len(cands) == 1:
                matched[s16t] = cands[0]; used_s17.add(cands[0])
                newly_matched += 1; changed = True
            elif len(cands) == 0:
                remaining.append(s16t)
            else:
                remaining.append(s16t)
        final_unmatched = remaining

    print(f"  Phase 2: {newly_matched} newly matched")
    print(f"  Still unmatched: {len(final_unmatched)}")
    if final_unmatched:
        for s16t in final_unmatched[:10]:
            s16e = s16_v7[s16t]
            sk = s16e.get("sk")
            cands = [t for t in s17_by_sk.get(str(sk), []) if t not in used_s17] if sk else []
            print(f"    t={s16t} m={s16e.get('m')} o={s16e.get('o')} cands={len(cands)}")

    return final_unmatched

# ============================================================
# Method assignment & output
# ============================================================
def assign_methods_and_write(matched, s17_cert, s16_v7, histograms, aut_values):
    """Assign methods A-G and write certificate."""
    types = []
    for s16t, s17t in sorted(matched.items()):
        s17e = s17_cert[s17t]
        s16e = s16_v7[s16t]
        entry = {
            "s16_idx": s16e["i"],
            "o": s17e["o"],
            "sk": s17e.get("sk"),
            "h": s17e.get("h"),
            "aut": s17e.get("aut"),
            "crpfHash": s17e.get("crpfHash"),
        }
        # If we computed a histogram/aut from S16 data and S17 didn't have it,
        # use the computed values
        if entry["h"] is None and s16t in histograms:
            entry["h"] = histograms[s16t]  # string form
        if entry["aut"] is None and s16t in aut_values:
            entry["aut"] = aut_values[s16t]
        types.append(entry)

    n = len(types)
    method = [None] * n
    EXCLUDED = {512, 768, 1024, 1536}

    # A: unique order
    order_count = defaultdict(list)
    for i, t in enumerate(types):
        order_count[t["o"]].append(i)
    for o, indices in order_count.items():
        if len(indices) == 1: method[indices[0]] = "A"

    # B: IdGroup eligible
    for i, t in enumerate(types):
        if method[i]: continue
        if t["o"] < 2000 and t["o"] not in EXCLUDED: method[i] = "B"

    # C: unique sigKey
    sk_count = defaultdict(list)
    for i, t in enumerate(types):
        if method[i]: continue
        sk = t.get("sk")
        if sk is not None: sk_count[str(sk)].append(i)
    for sk, indices in sk_count.items():
        if len(indices) == 1: method[indices[0]] = "C"

    # D: unique (sk, h)
    skh_count = defaultdict(list)
    for i, t in enumerate(types):
        if method[i]: continue
        sk, h = t.get("sk"), t.get("h")
        if sk is not None and h is not None:
            skh_count[(str(sk), str(h))].append(i)
    for key, indices in skh_count.items():
        if len(indices) == 1: method[indices[0]] = "D"

    # E: unique (sk, h, aut)
    skha_count = defaultdict(list)
    for i, t in enumerate(types):
        if method[i]: continue
        sk, h, aut = t.get("sk"), t.get("h"), t.get("aut")
        if sk is not None and h is not None and aut is not None:
            skha_count[(str(sk), str(h), aut)].append(i)
    for key, indices in skha_count.items():
        if len(indices) == 1: method[indices[0]] = "E"

    # F: unique crpfHash
    crpf_count = defaultdict(list)
    for i, t in enumerate(types):
        if method[i]: continue
        crpf = t.get("crpfHash")
        if crpf is not None:
            sk, h, aut = t.get("sk"), t.get("h"), t.get("aut")
            crpf_count[(str(sk), str(h), aut, crpf)].append(i)
    for key, indices in crpf_count.items():
        if len(indices) == 1: method[indices[0]] = "F"

    # G: remaining
    g_pairs = []
    remaining = defaultdict(list)
    for i in range(n):
        if method[i] is None:
            t = types[i]
            key = (str(t.get("sk")), str(t.get("h")), t.get("aut"), t.get("crpfHash"))
            remaining[key].append(i)
    for key, indices in remaining.items():
        for i in indices: method[i] = "G"
        if len(indices) == 2:
            g_pairs.append(tuple(indices))

    # Print counts
    mcounts = Counter(method)
    print(f"\n  Method counts:")
    for m in "ABCDEFG":
        print(f"    {m}: {mcounts.get(m, 0)}")
    print(f"    Total: {sum(mcounts.values())}")
    unassigned = mcounts.get(None, 0)
    if unassigned:
        print(f"    Unassigned: {unassigned}")

    # Sort and renumber
    method_order = {"A": 0, "B": 1, "C": 2, "D": 3, "E": 4, "F": 5, "G": 6}
    indices = list(range(n))
    indices.sort(key=lambda i: (
        method_order.get(method[i], 99), types[i]["o"],
        str(types[i].get("sk", "")), str(types[i].get("h", "")),
    ))
    new_t = {}
    for rank, i in enumerate(indices):
        new_t[i] = rank + 1

    pair_map = {}
    for a, b in g_pairs:
        pair_map[a] = b; pair_map[b] = a

    # Write
    with open(OUTPUT, "w") as f:
        f.write(f"# S16 Verification Certificate\n")
        f.write(f"# A174511(16) = {n}\n")
        f.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
        f.write(f"# Derived from verified S17 certificate (s17_verification_certificate_v5.g)\n")
        f.write(f"#\n")
        f.write(f"# Method counts:\n")
        for m in "ABCDEFG":
            f.write(f"#   {m}: {mcounts.get(m, 0)}\n")
        f.write(f"#   Total: {sum(mcounts.values())}\n")
        f.write(f"#\n")
        f.write(f"# Method descriptions:\n")
        f.write(f"#   A: Unique order.\n")
        f.write(f"#   B: Unique [order, idGroup] pair.\n")
        f.write(f"#   C: Unique sigKey = [order, |G'|, nrCC, derivedLength, abelInv].\n")
        f.write(f"#   D: Unique (sigKey, element-order histogram) pair.\n")
        f.write(f"#   E: Unique (sigKey, histogram, |Aut(G)|) triple.\n")
        f.write(f"#   F: Distinguished by canonical RPF hash (crpfHash) within E-bucket.\n")
        f.write(f"#   G: Confirmed distinct by IsomorphismGroups (all invariants match).\n")
        f.write(f"#\n")
        f.write(f"S16_VERIFY := [\n")
        for rank, i in enumerate(indices):
            t = types[i]; m = method[i]; tn = new_t[i]
            parts = [f"t:={tn}", f"i:={t['s16_idx']}", f'm:="{m}"', f"o:={t['o']}"]
            if m in ("C","D","E","F","G") and t.get("sk") is not None:
                parts.append(f"sk:={format_gap(t['sk'])}")
            if m in ("D","E","F","G") and t.get("h") is not None:
                parts.append(f"h:={format_gap(t['h'])}")
            if m in ("E","F","G") and t.get("aut") is not None:
                parts.append(f"aut:={t['aut']}")
            if m in ("F","G") and t.get("crpfHash") is not None:
                parts.append(f'crpfHash:="{t["crpfHash"]}"')
            if m == "G" and i in pair_map:
                pt = new_t.get(pair_map[i])
                if pt: parts.append(f"pair:={pt}")
            comma = "," if rank < len(indices) - 1 else ""
            f.write(f"rec({','.join(parts)}){comma}\n")
        f.write(f"];\n")

    print(f"\n  Written: {OUTPUT}")
    print(f"  Size: {OUTPUT.stat().st_size / 1e6:.1f} MB")

def format_gap(val):
    if isinstance(val, list):
        return "[" + ",".join(format_gap(v) for v in val) + "]"
    if isinstance(val, str):
        # Check if it's already a GAP list string
        if val.startswith("["): return val
        return f'"{val}"'
    return str(val)

# ============================================================
# Main
# ============================================================
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase2", action="store_true",
                       help="Run after GAP histogram computation")
    parser.add_argument("--compute", action="store_true",
                       help="Generate and run GAP workers for unmatched types")
    parser.add_argument("--workers", type=int, default=3)
    args = parser.parse_args()

    WORK_DIR.mkdir(exist_ok=True)

    print("Building S16 certificate from S17 data\n")
    print("Parsing files...")
    s17_cert = parse_s17_cert()
    s17_c2t = parse_s17_c2t()
    s17_idmap = parse_s17_idgroup_map()
    s16_v7 = parse_s16_v7()

    print("\nPhase 1: Match from S17 data...")
    matched, unmatched, s16_s17_types, used_s17, s17_by_sk = \
        phase1_match(s17_cert, s17_c2t, s17_idmap, s16_v7)

    if unmatched and args.compute:
        print(f"\nGenerating GAP workers for {len(unmatched)} unmatched types...")
        scripts = generate_histogram_workers(unmatched, s16_v7, args.workers)
        print("Launching GAP workers...")
        results = launch_gap_workers(scripts, args.workers)
        for w, rc in results.items():
            print(f"  Worker {w+1}: exit code {rc}")
        args.phase2 = True

    if unmatched and args.phase2:
        print("\nPhase 2: Re-match with computed data...")
        histograms, aut_values = read_computed_data(args.workers)
        still_unmatched = phase2_match(
            unmatched, matched, used_s17, s17_by_sk, s17_cert, s16_v7,
            histograms, aut_values, s16_s17_types)
        if still_unmatched:
            print(f"\n  WARNING: {len(still_unmatched)} types still unmatched!")
    else:
        histograms, aut_values = {}, {}

    if len(matched) < EXPECTED_S16_TYPES:
        print(f"\n  Only {len(matched)}/{EXPECTED_S16_TYPES} matched.")
        if not args.phase2 and not args.compute:
            print("  Run with --compute to compute missing histograms via GAP.")
            print("  Or run with --phase2 after manual GAP computation.")
            return

    print(f"\nAssigning methods and writing certificate ({len(matched)} types)...")
    assign_methods_and_write(matched, s17_cert, s16_v7, histograms, aut_values)
    print("\nDone!")

if __name__ == "__main__":
    main()
