#!/usr/bin/env python3
"""Step 4 launcher of the S17 certificate audit (2026-09-27): complete coset-action searches.

Pairs = residual pairs (no invariant separated them) + pairs with equal IdGroup (isomorphic: an explicit
validated map is still recorded for the merge).  Each pair maps type b's representative onto type a's
(a < b).  Resumable; a pair whose BEGIN line is older than --cap-min is killed and recorded as timeout.

Usage:  python run_search.py [--lanes 2] [--budget-min 30] [--cap-min 60]
"""
import argparse, json, re, subprocess, threading, time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
S = HERE / "search"
GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
cyg = lambda p: "/cygdrive/" + str(p).replace("\\", "/").replace("C:", "c", 1)


def finished():
    done = set()
    for f in S.glob("pairs_w*.g"):
        for line in open(f, encoding="latin-1"):
            m = re.match(r"PAIR\[(\d+),(\d+)\]", line)
            if m: done.add((int(m.group(1)), int(m.group(2))))
    for f in S.glob("log_w*.txt"):
        for line in f.read_text().splitlines():
            if line.startswith(("ERROR", "TIMEOUT")):
                done.add((int(line.split()[1]), int(line.split()[2])))
    return done


def lane(k, pairs, budget_ms, cap_s):
    out, log = S / f"pairs_w{k}.g", S / f"log_w{k}.txt"
    while True:
        todo = [p for p in pairs if (p[0], p[1]) not in finished()]
        if not todo:
            return
        hdr = S / f"_pairs_w{k}.g"
        hdr.write_text("PAIRS := [" + ",".join(f"[{a},{b},{ia},{ib}]" for a, b, ia, ib in todo) + "];;\n"
                       f'OUTFILE := "{cyg(out)}";;\nLOGFILE := "{cyg(log)}";;\nBUDGET_MS := {budget_ms};;\n'
                       f'Read("{cyg(HERE / "types.g")}");\nRead("{cyg(HERE / "coset_engine.g")}");\n'
                       f'Read("{cyg(HERE / "audit_search.g")}");\n', newline="\n")
        with open(S / f"gap_w{k}.txt", "a") as glog:
            glog.write(f"# launch at {datetime.now()} with {len(todo)} pairs\n"); glog.flush()
            p = subprocess.Popen([GAP_BASH, "--login", "-c", f'/opt/gap-4.15.1/gap -q -o 12g "{cyg(hdr)}"'],
                                 stdout=glog, stderr=subprocess.STDOUT, creationflags=subprocess.IDLE_PRIORITY_CLASS)
            while p.poll() is None:
                time.sleep(10)
                lines = log.read_text().splitlines() if log.exists() else []
                last = lines[-1] if lines else ""
                if last.startswith("BEGIN") and time.time() - log.stat().st_mtime > cap_s:
                    subprocess.run(["taskkill", "/F", "/T", "/PID", str(p.pid)], capture_output=True)
                    p.wait()
                    with open(log, "a") as f:
                        f.write(f"TIMEOUT {last.split()[1]} {last.split()[2]} {datetime.now()}\n")
            if p.returncode not in (0, None):
                lines = log.read_text().splitlines() if log.exists() else []
                last = lines[-1] if lines else ""
                if last.startswith("BEGIN"):
                    with open(log, "a") as f:
                        f.write(f"TIMEOUT {last.split()[1]} {last.split()[2]} crash rc={p.returncode}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lanes", type=int, default=2)
    ap.add_argument("--budget-min", type=float, default=30)
    ap.add_argument("--cap-min", type=float, default=60)
    a = ap.parse_args()
    S.mkdir(exist_ok=True)
    res = json.load(open(HERE / "invariant_results.json"))
    types = {r["t"]: r for r in json.load(open(HERE / "types.json"))["types"]}
    raw = [tuple(sorted(p[:2])) for p in res["residual"]] + [tuple(sorted(p[:2])) for p in res["idgroup_iso"]]
    pairs = sorted({(x, y, types[x]["i"], types[y]["i"]) for x, y in raw}, key=lambda p: -types[p[0]]["o"])
    print(f"{len(pairs)} pairs ({len(res['residual'])} residual, {len(res['idgroup_iso'])} same-IdGroup)")
    lanes = [pairs[k::a.lanes] for k in range(a.lanes)]
    ts = [threading.Thread(target=lane, args=(k + 1, lanes[k], int(a.budget_min * 60000), a.cap_min * 60))
          for k in range(a.lanes)]
    for t in ts: t.start()
    for t in ts: t.join()
    print(f"done: {len(finished())} pairs finished")


if __name__ == "__main__":
    main()
