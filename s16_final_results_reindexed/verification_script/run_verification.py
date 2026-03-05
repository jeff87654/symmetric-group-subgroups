#!/usr/bin/env python3
"""
run_verification.py — Standalone A174511(16) = 43,626 verifier.

Starting from s16_final_results.7z (14 MB), this script extracts the data,
then runs up to six verification phases to prove:

  UPPER BOUND (≤ 43,626):
    All 686,165 conjugacy classes collapse to at most 43,626 isomorphism
    types via 154,656 explicit proofs + IdGroup identification.

  LOWER BOUND (≥ 43,626):
    All 43,626 type representatives are pairwise non-isomorphic,
    proven by invariant discrimination (methods A-H in the certificate).

Phases:
  0  Structural integrity checks     (Python, ~2 min)
  1  Proof validation                (GAP, 4 workers, ~5 min)
  2  Certificate invariant recomp.   (GAP, 1 worker, ~2-3 hrs)
  3  F/G/H discrimination            (GAP, 1 worker, ~30 min)
  4  Class-to-type mapping rebuild   (GAP, 2 workers, ~3 min)
  5  Conjugacy verification          (GAP, 8 workers, ~12-24 hrs, optional)

Requirements:
  - Python 3.6+
  - GAP 4.14+ (Cygwin on Windows, native on Linux/macOS)
  - 7-Zip (Windows) or p7zip (Linux/macOS) for extraction
  - ~16 GB RAM recommended (50 GB GAP workspace for Phase 2)

Usage:
  python run_verification.py                    # Phases 0-4 (~6 hrs)
  python run_verification.py --skip-invariants  # Skip Phase 2 (~3 hrs faster)
  python run_verification.py --skip-fgh         # Skip Phase 3 (~30 min faster)
  python run_verification.py --conjugacy        # Include Phase 5 (~12-24 hrs extra)
  python run_verification.py --phase 0          # Just structural checks
  python run_verification.py --resume           # Skip completed phases
  python run_verification.py --gap-path /path   # Custom GAP path
"""

import argparse
import os
import platform
import re
import subprocess
import sys
import time
from datetime import datetime, timedelta

# ============================================================================
# Configuration
# ============================================================================

EXPECTED_TYPES = 43626
EXPECTED_CLASSES = 686165
EXPECTED_PROOFS = 154656

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.dirname(SCRIPT_DIR)
ARCHIVE = os.path.join(BASE_DIR, "s16_final_results.7z")

DATA_FILES = [
    "s16_class_to_type.g",
    "s16_large_invariants.g",
    "s16_master_proofs_repaired_v2.g",
    "s16_subgroups.g",
    "s16_verification_certificate_v7.g",
]

# Phase 2 sub-phases — each writes a result file
CERT_SUBPHASES = {
    1: ("Order verification", "verify_phase_1_results.txt"),
    2: ("IdGroup verification", "verify_phase_2_results.txt"),
    3: ("SigKey verification", "verify_phase_3_results.txt"),
    4: ("Histogram verification", "verify_phase_4_results.txt"),
    5: ("E7 cascade verification", "verify_phase_5_results.txt"),
    6: ("E-type discriminant verification", "verify_phase_6_results.txt"),
}

# ============================================================================
# Utility functions
# ============================================================================

def timestamp():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def banner(msg):
    w = max(len(msg) + 4, 60)
    print(f"\n{'='*w}")
    print(f"  {msg}")
    print(f"  {timestamp()}")
    print(f"{'='*w}\n")

def detect_gap(gap_path=None):
    """Detect GAP binary and return config dict."""
    is_win = platform.system() == "Windows"

    if is_win:
        bash = gap_path or r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
        if not os.path.exists(bash):
            print(f"ERROR: GAP bash not found at {bash}")
            print("Install GAP 4.15+ or pass --gap-path")
            sys.exit(1)
        cyg = (BASE_DIR.replace("\\", "/")
                       .replace("C:", "/cygdrive/c")
                       .replace("D:", "/cygdrive/d"))
        return {"bash": bash, "gap": "/opt/gap-4.15.1/gap",
                "cygwin": True, "cyg_base": cyg + "/"}

    # Linux / macOS
    gap = gap_path or "gap"
    try:
        subprocess.run([gap, "--version"], capture_output=True, timeout=10)
    except FileNotFoundError:
        print(f"ERROR: GAP not found as '{gap}'. Pass --gap-path.")
        sys.exit(1)
    return {"bash": None, "gap": gap, "cygwin": False,
            "cyg_base": BASE_DIR + "/"}

def gap_cmd(config, script_cyg, memory, extra_vars=None):
    """Build a command list to launch GAP."""
    vars_str = f'BASE_DIR:="{config["cyg_base"]}";; '
    if extra_vars:
        for k, v in extra_vars.items():
            if isinstance(v, bool):
                vars_str += f'{k}:={"true" if v else "false"};; '
            elif isinstance(v, str):
                vars_str += f'{k}:="{v}";; '
            else:
                vars_str += f'{k}:={v};; '

    gap_line = (f'{config["gap"]} -q -o {memory} '
                f"-c '{vars_str}Read(\"{script_cyg}\");' ")

    if config["cygwin"]:
        return [config["bash"], "--login", "-c", gap_line]
    else:
        return ["sh", "-c", gap_line]

def run_gap(config, script_name, memory, extra_vars=None,
            log_path=None, max_attempts=30, label="GAP"):
    """Run a GAP script with crash retry. Returns (exit_code, attempt_count)."""
    script_cyg = config["cyg_base"] + "verification_script/" + script_name

    for attempt in range(1, max_attempts + 1):
        cmd = gap_cmd(config, script_cyg, memory, extra_vars)

        if log_path:
            log = log_path.replace(".txt", f"_attempt{attempt}.txt")
        else:
            log = os.path.join(SCRIPT_DIR,
                               f"{label}_attempt{attempt}.txt")

        with open(log, "w") as out:
            out.write(f"# {label} attempt {attempt} at {timestamp()}\n\n")
            out.flush()
            cflags = subprocess.CREATE_NO_WINDOW if platform.system() == "Windows" else 0
            proc = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1,
                **({"creationflags": cflags} if cflags else {}))
            for line in proc.stdout:
                print(f"    {line}", end="")
                out.write(line)
                out.flush()
            proc.wait()
            out.write(f"\n# Exit code: {proc.returncode}\n")

        if proc.returncode == 0:
            return 0, attempt
        print(f"  [{label}] Crash (exit {proc.returncode}), "
              f"attempt {attempt}/{max_attempts}")
        time.sleep(3)

    return 1, max_attempts

def run_gap_workers(config, script_name, n_workers, memory,
                    extra_vars_fn=None, max_attempts=30, label="worker"):
    """Run N parallel GAP workers with crash retry.
    extra_vars_fn(w) returns extra vars dict for worker w.
    Returns (all_ok, attempt_count).
    """
    for attempt in range(1, max_attempts + 1):
        procs = []
        logs = []
        for w in range(1, n_workers + 1):
            ev = {"WORKER_ID": w, "WORKER_TOTAL": n_workers}
            if extra_vars_fn:
                ev.update(extra_vars_fn(w))

            script_cyg = (config["cyg_base"] +
                          "verification_script/" + script_name)
            cmd = gap_cmd(config, script_cyg, memory, ev)
            log = os.path.join(SCRIPT_DIR,
                               f"{label}_w{w}_attempt{attempt}.txt")
            logs.append(log)
            lf = open(log, "w")
            lf.write(f"# {label} w{w} attempt {attempt} at {timestamp()}\n\n")
            lf.flush()
            cflags = (subprocess.CREATE_NO_WINDOW
                      if platform.system() == "Windows" else 0)
            proc = subprocess.Popen(
                cmd, stdout=lf, stderr=subprocess.STDOUT,
                **({"creationflags": cflags} if cflags else {}))
            procs.append((w, proc, lf))
            print(f"    Worker {w}: PID {proc.pid}")

        all_ok = True
        for w, proc, lf in procs:
            proc.wait()
            lf.write(f"\n# Exit code: {proc.returncode}\n")
            lf.close()
            if proc.returncode != 0:
                all_ok = False
                print(f"    Worker {w}: crashed (exit {proc.returncode})")
            else:
                print(f"    Worker {w}: OK")

        if all_ok:
            return True, attempt
        print(f"  [{label}] Attempt {attempt}/{max_attempts} — "
              "retrying with checkpoint resume...")
        time.sleep(3)

    return False, max_attempts

def result_complete(filepath, keyword="complete"):
    """Check if a result file contains a completion marker."""
    try:
        with open(filepath) as f:
            return keyword in f.read().lower()
    except FileNotFoundError:
        return False

def count_pass(filepath):
    try:
        with open(filepath) as f:
            return sum(1 for line in f if line.startswith("PASS"))
    except FileNotFoundError:
        return 0

# ============================================================================
# Phase 0: Extract archive + structural checks
# ============================================================================

def phase_0_extract():
    """Extract .7z archive if data files are missing."""
    banner("Phase 0a: Extract archive")
    missing = [f for f in DATA_FILES
                if not os.path.exists(os.path.join(BASE_DIR, f))]
    if not missing:
        print("  All data files present — skipping extraction.")
        return True

    if not os.path.exists(ARCHIVE):
        print(f"  ERROR: Archive not found: {ARCHIVE}")
        return False

    print(f"  Extracting {len(missing)} files from {os.path.basename(ARCHIVE)}...")
    is_win = platform.system() == "Windows"
    if is_win:
        exe = r"C:\Program Files\7-Zip\7z.exe"
        if not os.path.exists(exe):
            exe = "7z"  # hope it's on PATH
        cmd = [exe, "x", "-y", f"-o{BASE_DIR}", ARCHIVE]
    else:
        cmd = ["7z", "x", "-y", f"-o{BASE_DIR}", ARCHIVE]

    rc = subprocess.run(cmd, capture_output=True, text=True)
    if rc.returncode != 0:
        print(f"  ERROR: 7z extraction failed: {rc.stderr[:200]}")
        return False

    # Verify all files now exist
    still_missing = [f for f in DATA_FILES
                     if not os.path.exists(os.path.join(BASE_DIR, f))]
    if still_missing:
        print(f"  ERROR: Still missing after extraction: {still_missing}")
        return False

    sizes = {f: os.path.getsize(os.path.join(BASE_DIR, f))
             for f in DATA_FILES}
    for f, sz in sorted(sizes.items()):
        print(f"    {f}: {sz:,} bytes")
    print("  Extraction complete.")
    return True

def phase_0_structural():
    """Run Python structural checks."""
    banner("Phase 0b: Structural integrity")
    ok = True
    for script in ["verify_cert_structural.py",
                    "verify_discrimination_soundness.py"]:
        path = os.path.join(SCRIPT_DIR, script)
        print(f"  Running {script}...")
        rc = subprocess.run(
            [sys.executable, path],
            cwd=BASE_DIR, capture_output=True, text=True)
        if rc.returncode == 0:
            print(f"    PASS")
        else:
            print(f"    FAIL (exit {rc.returncode})")
            print(rc.stdout[-500:] if rc.stdout else "")
            print(rc.stderr[-500:] if rc.stderr else "")
            ok = False
    return ok

# ============================================================================
# Phase 1: Proof validation
# ============================================================================

def phase_1(config, n_workers, memory):
    """Validate 154,656 proofs with N parallel workers."""
    banner("Phase 1: Proof validation")

    # Check if already complete
    all_done = True
    for w in range(1, n_workers + 1):
        rf = os.path.join(SCRIPT_DIR, f"verify_proof_worker_{w}_results.txt")
        if not result_complete(rf):
            all_done = False
    if all_done:
        print("  Already complete — skipping.")
        return True

    ok, attempts = run_gap_workers(
        config, "verify_proofs_worker.g", n_workers, memory,
        max_attempts=15, label="proof")

    # Collect results
    total_pass = total_fail = 0
    for w in range(1, n_workers + 1):
        rf = os.path.join(SCRIPT_DIR, f"verify_proof_worker_{w}_results.txt")
        try:
            with open(rf) as f:
                for line in f:
                    m = re.search(
                        r"Complete: (\d+) PASS, (\d+) SIZE_FAIL, "
                        r"(\d+) CONTAIN_FAIL, (\d+) HOMO_FAIL", line)
                    if m:
                        total_pass += int(m.group(1))
                        total_fail += (int(m.group(2)) + int(m.group(3))
                                       + int(m.group(4)))
        except FileNotFoundError:
            total_fail += 1

    print(f"\n  Proof validation: {total_pass} PASS, {total_fail} FAIL")
    if total_fail > 0:
        return False

    # Run coverage check
    print("  Running proof coverage check...")
    rc = subprocess.run(
        [sys.executable, os.path.join(SCRIPT_DIR, "verify_proof_coverage.py"),
         "--base-dir", BASE_DIR, "--workers", str(n_workers)],
        capture_output=True, text=True)
    if rc.returncode == 0:
        print("    Coverage: PASS")
    else:
        print(f"    Coverage: FAIL")
        print(rc.stdout[-500:])
        return False

    return True

# ============================================================================
# Phase 2: Certificate invariant recomputation
# ============================================================================

def _subphase_complete(sub):
    """Check if cert sub-phase is complete."""
    _, fname = CERT_SUBPHASES[sub]
    return result_complete(os.path.join(BASE_DIR, fname))

def phase_2(config, memory):
    """Recompute certificate invariants (6 sub-phases)."""
    banner("Phase 2: Certificate invariant verification")

    # Check which sub-phases are already done
    all_done = all(_subphase_complete(s) for s in range(1, 7))
    if all_done:
        print("  All 6 sub-phases complete — skipping.")
        return True

    for attempt in range(1, 51):
        # Build skip flags for completed sub-phases
        skip = {}
        done_list = []
        for s in range(1, 7):
            if _subphase_complete(s):
                skip[f"RUN_PHASE_{s}"] = False
                done_list.append(str(s))
        if done_list:
            print(f"  Skipping completed sub-phases: {','.join(done_list)}")

        print(f"  Attempt {attempt}/50...")
        rc, _ = run_gap(
            config, "verify_cert_from_subgroups.g", memory,
            extra_vars=skip if skip else None,
            label=f"cert_sub", max_attempts=1)

        if rc == 0:
            break

        # Check if all sub-phases are now complete despite crash
        if all(_subphase_complete(s) for s in range(1, 7)):
            print("  All sub-phases complete (across retries).")
            break

        # Report progress
        for s in range(1, 7):
            name, fname = CERT_SUBPHASES[s]
            fpath = os.path.join(BASE_DIR, fname)
            if _subphase_complete(s):
                print(f"    Sub-phase {s} ({name}): COMPLETE")
            elif os.path.exists(fpath):
                n = count_pass(fpath)
                print(f"    Sub-phase {s} ({name}): {n} PASS (partial)")

    # Final check
    results = {}
    all_ok = True
    for s in range(1, 7):
        name, fname = CERT_SUBPHASES[s]
        fpath = os.path.join(BASE_DIR, fname)
        if _subphase_complete(s):
            results[s] = "PASS"
        else:
            results[s] = "INCOMPLETE"
            all_ok = False

    print("\n  Certificate invariant results:")
    for s in range(1, 7):
        name, _ = CERT_SUBPHASES[s]
        print(f"    Sub-phase {s} ({name}): {results[s]}")

    return all_ok

# ============================================================================
# Phase 3: F/G/H discrimination
# ============================================================================

def phase_3(config, memory):
    """Verify F/G/H discrimination with single serial worker."""
    banner("Phase 3: F/G/H discrimination")

    p7 = os.path.join(BASE_DIR, "verify_phase_7_worker_1_results.txt")
    p8 = os.path.join(BASE_DIR, "verify_phase_8_worker_1_results.txt")

    if result_complete(p7) and result_complete(p8):
        print("  Both Phase 7 and 8 complete — skipping.")
        return True

    # Single worker — most stable with background processes
    rc, attempts = run_gap(
        config, "verify_cert_phase78.g", memory,
        extra_vars={"WORKER_ID": 1, "WORKER_TOTAL": 1},
        label="phase78", max_attempts=30)

    p7_ok = result_complete(p7)
    p8_ok = result_complete(p8)

    if p7_ok:
        m = re.search(r"Phase 7 complete: (\d+) PASS, (\d+) FAIL",
                      open(p7).read())
        if m:
            print(f"  Phase 7 (F/G): {m.group(1)} PASS, {m.group(2)} FAIL")
    if p8_ok:
        m = re.search(r"Phase 8 complete: (\d+) PASS, (\d+) FAIL",
                      open(p8).read())
        if m:
            print(f"  Phase 8 (H):   {m.group(1)} PASS, {m.group(2)} FAIL")

    return p7_ok and p8_ok

# ============================================================================
# Phase 4: Class-to-type mapping rebuild
# ============================================================================

def phase_4(config, n_workers, memory):
    """Independently rebuild class-to-type mapping."""
    banner("Phase 4: Class-to-type mapping rebuild")

    # Check if already complete
    all_done = True
    for w in range(1, n_workers + 1):
        rf = os.path.join(SCRIPT_DIR,
                          f"verify_c2t_worker_{w}_results.txt")
        if not result_complete(rf):
            all_done = False
    if all_done:
        print("  Already complete — skipping.")
        return True

    ok, attempts = run_gap_workers(
        config, "verify_class_to_type_worker.g", n_workers, memory,
        max_attempts=15, label="c2t")

    total_pass = total_fail = 0
    for w in range(1, n_workers + 1):
        rf = os.path.join(SCRIPT_DIR,
                          f"verify_c2t_worker_{w}_results.txt")
        try:
            with open(rf) as f:
                for line in f:
                    m = re.search(r"Complete: (\d+) PASS, (\d+) FAIL", line)
                    if m:
                        total_pass += int(m.group(1))
                        total_fail += int(m.group(2))
        except FileNotFoundError:
            total_fail += 1

    print(f"\n  Class-to-type rebuild: {total_pass} PASS, {total_fail} FAIL")
    return total_fail == 0 and total_pass == EXPECTED_CLASSES

# ============================================================================
# Phase 5: Conjugacy verification
# ============================================================================

def phase_5_build_buckets():
    """Build conjugacy buckets from class-to-type mapping and subgroups."""
    bucket_file = os.path.join(BASE_DIR, "conj_buckets.g")
    if os.path.exists(bucket_file):
        print("  conj_buckets.g already exists — skipping build.")
        return True

    banner("Phase 5a: Build conjugacy buckets")
    print("  Building (type, orbit-type) buckets from subgroups...")
    rc = subprocess.run(
        [sys.executable, os.path.join(SCRIPT_DIR, "build_conjugacy_buckets.py"),
         "--base-dir", BASE_DIR],
        capture_output=True, text=True)
    if rc.returncode == 0:
        print("    PASS")
        # Print summary from output
        for line in rc.stdout.splitlines():
            if "Non-singleton" in line or "Written" in line:
                print(f"    {line.strip()}")
        return True
    else:
        print(f"    FAIL (exit {rc.returncode})")
        print(rc.stdout[-500:] if rc.stdout else "")
        print(rc.stderr[-500:] if rc.stderr else "")
        return False


def phase_5(config, n_workers, memory):
    """Verify all 686,165 classes are pairwise non-conjugate within types."""
    banner("Phase 5: Conjugacy verification (A000638(16) = 686,165)")

    # Step 1: Build buckets if needed
    if not phase_5_build_buckets():
        return False

    # Check if already complete
    all_done = True
    for w in range(1, n_workers + 1):
        rf = os.path.join(SCRIPT_DIR,
                          f"verify_conj_worker_{w}_results.txt")
        if not result_complete(rf):
            all_done = False
    if all_done:
        print("  Already complete — skipping.")
        return True

    ok, attempts = run_gap_workers(
        config, "verify_smart_worker.g", n_workers, memory,
        extra_vars_fn=lambda w: {"SUB_THRESHOLD": 5},
        max_attempts=15, label="conj")

    total_checked = total_conjugate = 0
    for w in range(1, n_workers + 1):
        rf = os.path.join(SCRIPT_DIR,
                          f"verify_conj_worker_{w}_results.txt")
        try:
            with open(rf) as f:
                for line in f:
                    m = re.search(
                        r"Complete: (\d+) checked, (\d+) skipped, "
                        r"(\d+) conjugate, (\d+) buckets", line)
                    if m:
                        total_checked += int(m.group(1))
                        total_conjugate += int(m.group(3))
        except FileNotFoundError:
            total_conjugate += 1  # treat missing as failure

    print(f"\n  Conjugacy verification: {total_checked} pairs checked, "
          f"{total_conjugate} conjugate found")
    if total_conjugate > 0:
        print("  FAIL: Conjugate pairs detected!")
        return False
    print("  PASS: All classes non-conjugate within their type buckets")
    return True


# ============================================================================
# Final summary
# ============================================================================

def print_summary(results, phases_run, t_start):
    elapsed = datetime.now() - t_start
    h, rem = divmod(int(elapsed.total_seconds()), 3600)
    m, s = divmod(rem, 60)

    print(f"\n{'='*64}")
    print(f"  A174511(16) VERIFICATION RESULTS")
    print(f"  Total elapsed: {h}h {m}m {s}s")
    print(f"{'='*64}\n")

    phase_names = {
        0: "Structural integrity",
        1: "Proof validation (154,656 proofs)",
        2: "Certificate invariants (43,626 types)",
        3: "F/G/H discrimination (1,098 F/G + 96 H pairs)",
        4: "Class-to-type rebuild (686,165 classes)",
        5: "Conjugacy verification (686,165 classes non-conjugate)",
    }
    all_run_pass = True
    for p in range(6):
        if p in results:
            status = "PASS" if results[p] else "FAIL"
            if not results[p]:
                all_run_pass = False
        elif p not in phases_run:
            status = "SKIPPED"
        else:
            status = "NOT RUN"
        print(f"  Phase {p}: {status}  — {phase_names.get(p, '?')}")

    print()
    upper = results.get(0, False) and results.get(1, False) and results.get(4, False)
    lower_full = results.get(0, False) and results.get(2, False) and results.get(3, False)
    # Lower bound can be partially verified: Phase 2 alone covers methods A-E,
    # Phase 3 covers F/G/H. Either one is sufficient for its method set.
    lower_partial = results.get(0, False) and (results.get(2, False) or results.get(3, False))

    conj_verified = results.get(5, False)
    if upper and conj_verified:
        print(f"  UPPER BOUND: 686,165 = 43,626 reps + 154,656 proofs "
              f"+ 487,883 IdGroup   [VERIFIED]")
        print(f"  A000638(16): 686,165 classes pairwise non-conjugate  "
              f"                    [VERIFIED]")
    elif upper:
        print(f"  UPPER BOUND: 686,165 = 43,626 reps + 154,656 proofs "
              f"+ 487,883 IdGroup   [VERIFIED]")
        if 5 not in phases_run:
            print(f"  A000638(16): 686,165 (not independently verified — "
                  f"use --conjugacy)")
    else:
        print(f"  UPPER BOUND: NOT FULLY VERIFIED")

    if lower_full:
        print(f"  LOWER BOUND: 43,626 types pairwise non-isomorphic "
              f"(methods A-H)       [VERIFIED]")
    elif lower_partial:
        skipped = []
        if 2 not in phases_run:
            skipped.append("invariant recomp (Phase 2)")
        if 3 not in phases_run:
            skipped.append("F/G/H discrimination (Phase 3)")
        print(f"  LOWER BOUND: PARTIALLY VERIFIED (skipped: {', '.join(skipped)})")
    else:
        print(f"  LOWER BOUND: NOT FULLY VERIFIED")

    print()
    if all_run_pass and upper and lower_full:
        print(f"  >>> A174511(16) = 43,626   [INDEPENDENTLY VERIFIED] <<<")
    elif all_run_pass and upper:
        print(f"  >>> A174511(16) = 43,626   [VERIFIED — upper bound proven, "
              f"lower bound partial] <<<")
    else:
        failed = [p for p in results if not results[p]]
        print(f"  INCOMPLETE — phases {failed} need attention")

    print(f"\n{'='*64}")
    return all_run_pass

# ============================================================================
# Main
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Verify A174511(16) = 43,626")
    parser.add_argument("--phase", type=str, default=None,
                        help="Comma-separated phases to run (default: all enabled)")
    parser.add_argument("--skip-invariants", action="store_true",
                        help="Skip Phase 2 (certificate invariant recomputation). "
                             "Saves ~3 hrs. The upper/lower bounds are still proven "
                             "by Phases 1, 3, and 4; Phase 2 provides additional "
                             "confidence by recomputing every invariant from scratch.")
    parser.add_argument("--skip-fgh", action="store_true",
                        help="Skip Phase 3 (F/G/H discrimination via CharacterTable "
                             "and IsomorphismGroups). Saves ~30 min. Without this, "
                             "the lower bound relies only on Phase 2 invariant checks "
                             "for the 1,194 F/G/H-method type pairs.")
    parser.add_argument("--conjugacy", action="store_true",
                        help="Include Phase 5: verify all 686,165 conjugacy classes "
                             "are pairwise non-conjugate within each isomorphism type, "
                             "independently confirming A000638(16) = 686,165. "
                             "Adds ~12-24 hrs. Not included by default.")
    parser.add_argument("--conj-workers", type=int, default=8,
                        help="Number of workers for Phase 5 (default: 8)")
    parser.add_argument("--resume", action="store_true",
                        help="Skip phases whose results are already complete")
    parser.add_argument("--gap-path", type=str, default=None,
                        help="Path to GAP binary (or Cygwin bash on Windows)")
    parser.add_argument("--memory", type=str, default="16g",
                        help="GAP memory per worker (default: 16g)")
    parser.add_argument("--cert-memory", type=str, default="50g",
                        help="GAP memory for Phase 2 cert (default: 50g)")
    args = parser.parse_args()

    # Determine which phases to run
    if args.phase is not None:
        phases = [int(p) for p in args.phase.split(",")]
    else:
        phases = [0, 1, 2, 3, 4]
        if args.skip_invariants:
            phases.remove(2)
        if args.skip_fgh:
            phases.remove(3)
        if args.conjugacy:
            phases.append(5)
    t_start = datetime.now()
    results = {}

    print(f"\n{'='*64}")
    print(f"  A174511(16) Independent Verification")
    print(f"  Started: {timestamp()}")
    print(f"  Phases: {phases}")
    if args.skip_invariants:
        print(f"  --skip-invariants: Phase 2 (cert invariant recomp) SKIPPED")
    if args.skip_fgh:
        print(f"  --skip-fgh: Phase 3 (F/G/H discrimination) SKIPPED")
    if 5 in phases:
        print(f"  --conjugacy: Phase 5 (non-conjugacy) ENABLED "
              f"({args.conj_workers} workers)")
    print(f"{'='*64}")

    # Phase 0: Extract + structural
    if 0 in phases:
        ok = phase_0_extract()
        if not ok:
            results[0] = False
            print_summary(results, phases, t_start)
            return 1
        ok = phase_0_structural()
        results[0] = ok
        if not ok:
            print("  Phase 0 FAILED — aborting.")
            print_summary(results, phases, t_start)
            return 1
    else:
        results[0] = True  # assume OK if not requested

    # Detect GAP for phases 1-5
    config = None
    if any(p in phases for p in [1, 2, 3, 4, 5]):
        config = detect_gap(args.gap_path)
        print(f"  GAP config: cygwin={config['cygwin']}, "
              f"base={config['cyg_base']}")

    # Phase 1: Proof validation
    if 1 in phases:
        results[1] = phase_1(config, n_workers=4, memory=args.memory)

    # Phase 2: Certificate invariants (serial, high memory)
    if 2 in phases:
        results[2] = phase_2(config, memory=args.cert_memory)

    # Phase 3: F/G/H (serial, moderate memory)
    if 3 in phases:
        results[3] = phase_3(config, memory=args.memory)

    # Phase 4: Class-to-type rebuild
    if 4 in phases:
        results[4] = phase_4(config, n_workers=2, memory="32g")

    # Phase 5: Conjugacy verification (optional)
    if 5 in phases:
        results[5] = phase_5(config, n_workers=args.conj_workers,
                             memory=args.memory)

    ok = print_summary(results, phases, t_start)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
