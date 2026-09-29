#!/usr/bin/env python3
"""Step 2 launcher of the S17 certificate audit: compute and save character tables (2026-09-27).

Runs audit_tables.g in N lanes (GAP processes at idle priority).  Resumable: jobs already present
in tables/ct_w*.g are skipped.  A job whose BEGIN line sits in the lane log for longer than CAP_S
is killed, recorded in tables/timeouts.txt, and the lane relaunches without it.

Usage:  python run_tables.py [--lanes 2] [--cap-min 40]
"""
import argparse, json, re, subprocess, threading, time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
TABLES = HERE / "tables"
GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
cyg = lambda p: "/cygdrive/" + str(p).replace("\\", "/").replace("C:", "c", 1)


def done_jobs():
    done = set()
    for f in TABLES.glob("ct_w*.g"):
        with open(f, encoding="latin-1") as fh:
            for line in fh:
                m = re.match(r"CT\[(\d+)\]", line)
                if m: done.add(int(m.group(1)))
    return done


def timed_out():
    """Jobs never to retry: watchdog timeouts/crashes (timeouts.txt) and GAP errors (ERROR lines in logs)."""
    p = TABLES / "timeouts.txt"
    bad = {int(l.split()[0]) for l in p.read_text().splitlines() if l.strip()} if p.exists() else set()
    for f in TABLES.glob("log_w*.txt"):
        bad |= {int(l.split()[1]) for l in f.read_text().splitlines() if l.startswith("ERROR ")}
    return bad


def lane(k, jobs, cap_s):
    out, log = TABLES / f"ct_w{k}.g", TABLES / f"log_w{k}.txt"
    launch = 0
    while True:
        skip = done_jobs() | timed_out()
        todo = [j for j in jobs if j["job"] not in skip]
        if not todo:
            return
        launch += 1
        hdr = TABLES / f"_jobs_w{k}.g"
        hdr.write_text(
            "JOBS := [" + ",".join(f"[{j['job']},{j['t']},{j['i']},{'true' if j['selftest'] else 'false'}]"
                                   for j in todo) + "];;\n"
            f'OUTFILE := "{cyg(out)}";;\nLOGFILE := "{cyg(log)}";;\nSELFTEST_SEED := {1000 * k + launch};;\n'
            f'Read("{cyg(HERE / "types.g")}");\nRead("{cyg(HERE / "audit_tables.g")}");\n', newline="\n")
        with open(TABLES / f"gap_w{k}.txt", "a") as glog:
            glog.write(f"# launch {launch} at {datetime.now()} with {len(todo)} jobs\n"); glog.flush()
            p = subprocess.Popen([GAP_BASH, "--login", "-c", f'/opt/gap-4.15.1/gap -q -o 12g "{cyg(hdr)}"'],
                                 stdout=glog, stderr=subprocess.STDOUT,
                                 creationflags=subprocess.IDLE_PRIORITY_CLASS)
            while True:
                time.sleep(10)
                lines = log.read_text().splitlines() if log.exists() else []
                last = lines[-1] if lines else ""
                if p.poll() is not None:
                    break                                   # finished or crashed: loop re-checks todo
                if last.startswith("BEGIN") and time.time() - log.stat().st_mtime > cap_s:
                    subprocess.run(["taskkill", "/F", "/T", "/PID", str(p.pid)], capture_output=True)
                    p.wait()
                    with open(TABLES / "timeouts.txt", "a") as f:
                        f.write(f"{last.split()[1]} lane{k} {datetime.now()}\n")
                    break
            if p.returncode not in (0, None):
                lines = log.read_text().splitlines() if log.exists() else []
                last = lines[-1] if lines else ""
                if last.startswith("BEGIN") and int(last.split()[1]) not in timed_out():
                    # crashed inside a job (e.g. out of memory): record it so the relaunch moves on
                    with open(TABLES / "timeouts.txt", "a") as f:
                        f.write(f"{last.split()[1]} lane{k} CRASH rc={p.returncode} {datetime.now()}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lanes", type=int, default=2)
    ap.add_argument("--cap-min", type=float, default=40)
    a = ap.parse_args()
    jobs = json.load(open(HERE / "types.json"))["jobs"]
    jobs.sort(key=lambda j: -j["o"])                       # big first; round-robin keeps lanes balanced
    lanes = [jobs[k::a.lanes] for k in range(a.lanes)]
    ts = [threading.Thread(target=lane, args=(k + 1, lanes[k], a.cap_min * 60)) for k in range(a.lanes)]
    for t in ts: t.start()
    for t in ts: t.join()
    print(f"done: {len(done_jobs())} tables, {len(timed_out())} timeouts")


if __name__ == "__main__":
    main()
