#!/usr/bin/env python3
"""
phase_a2_compute_leaves.py - Phase A-2: Parallel leaf lattice computation for S15

Launches parallel GAP workers to compute ConjugacyClassesSubgroups on each leaf
group discovered by Phase A-1 (phase_a1_enumerate.py).

Each worker processes its assigned batch of leaves sequentially, saving results
incrementally with checkpoints after each leaf.

Prerequisites:
  - Phase A-1 must have completed (leaves.g, leaf_batch_*.g files)
  - compute_s15_recursive.g must exist

Input:
  maxsub_output_s15/leaf_batch_1.g through leaf_batch_N.g

Output:
  maxsub_output_s15/leaf_results_1.g through leaf_results_N.g
  Each file contains: maxsub_results := [rec(gens := [...], inv := [...], source := "..."), ...]

Resume support: Each leaf has a unique label. On re-run, completed leaves
(identified by their label appearing before a successful checkpoint in the
output file) are skipped.

Usage:
  python phase_a2_compute_leaves.py             # Run all workers
  python phase_a2_compute_leaves.py 2           # Run worker 2 only
  python phase_a2_compute_leaves.py 1 3         # Run workers 1 through 3
"""

import subprocess
import sys
import os
import re
import time
from pathlib import Path
from datetime import datetime
from concurrent.futures import ProcessPoolExecutor, as_completed

GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
BASE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups")
OUTPUT_DIR = BASE_DIR / "maxsub_output_s15"
N = 15
TIMEOUT = 72 * 3600  # 72 hours max per worker


def sanitize_label_py(s):
    """Sanitize a label for use as a GAP record field name.
    Must match the GAP SanitizeLabel function in the worker script."""
    result = "L"
    for ch in s:
        if ch.isalnum() or ch == '_':
            result += ch
        else:
            result += "_"
    return result

# Memory allocation per worker
# With 3 workers: ~20g each (fits in 64g with overhead)
WORKER_MEMORY = "20g"

def windows_to_cygwin_path(win_path: str) -> str:
    path = str(win_path).replace('\\', '/')
    if len(path) >= 2 and path[1] == ':':
        drive = path[0].lower()
        path = f'/cygdrive/{drive}{path[2:]}'
    return path

BASE_CYGWIN = windows_to_cygwin_path(str(BASE_DIR))
OUTPUT_CYGWIN = windows_to_cygwin_path(str(OUTPUT_DIR))


def get_completed_leaves(result_file: Path) -> set:
    """Parse a result file to find which leaves have been completed."""
    completed = set()
    if not result_file.exists():
        return completed

    content = result_file.read_text(encoding='utf-8', errors='replace')
    # Look for checkpoint markers: "# Leaf complete: <label> (<count> subgroups)"
    for m in re.finditer(r'# Leaf complete: ([^\s(]+)', content):
        completed.add(m.group(1))

    return completed


def count_leaf_batches() -> int:
    """Count how many leaf_batch_*.g files exist."""
    count = 0
    while True:
        batch_file = OUTPUT_DIR / f"leaf_batch_{count + 1}.g"
        if batch_file.exists():
            count += 1
        else:
            break
    return count


def run_leaf_worker(worker_id: int) -> dict:
    """Run a single leaf computation worker."""
    batch_file = OUTPUT_DIR / f"leaf_batch_{worker_id}.g"
    result_file = OUTPUT_DIR / f"leaf_results_{worker_id}.g"
    log_file = OUTPUT_DIR / f"leaf_worker_{worker_id}.log"

    if not batch_file.exists():
        return {"worker_id": worker_id, "success": False,
                "error": f"Batch file {batch_file.name} not found"}

    # Check for already-completed leaves (resume support)
    completed = get_completed_leaves(result_file)
    resume_mode = len(completed) > 0

    batch_cygwin = windows_to_cygwin_path(str(batch_file))
    result_cygwin = windows_to_cygwin_path(str(result_file))

    # Build the GAP script
    # Key design: process leaves sequentially, checkpoint after each one
    script = f'''
# Sanitize a label string for use as GAP record field name
# Replaces non-alphanumeric chars with underscores, prefixes with "L"
SanitizeLabel := function(s)
    local result, i, ch;
    result := "L";
    for i in [1..Length(s)] do
        ch := s[i];
        if ch in "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_" then
            Append(result, [ch]);
        else
            Append(result, "_");
        fi;
    od;
    return result;
end;

LeafWorkerMain := function()
    local MAXSUB_BASE, n, workerId, startTime, batchFile, outputFile,
          i, entry, G, gens, ccs, reps, H, genImages, g, inv, j,
          leafStart, leafElapsed, totalCount, skipped,
          completedLeaves, resumeMode, label_str, safeLabel;

    MAXSUB_BASE := "{BASE_CYGWIN}";
    Read(Concatenation(MAXSUB_BASE, "/compute_s15_maxsub.g"));

    n := {N};
    workerId := {worker_id};
    resumeMode := {"true" if resume_mode else "false"};

    Print("=== Leaf Worker ", workerId, " started ===\\n");
    startTime := Runtime();

    # Load batch
    Read("{batch_cygwin}");
    if not IsBound(leaf_batch) then
        Print("ERROR: No leaf_batch found!\\n");
        return;
    fi;
    Print("Loaded ", Length(leaf_batch), " leaves\\n");

    # Set of completed leaves (for resume support)
    # Keys are sanitized labels (valid GAP identifiers)
    completedLeaves := rec();
'''

    # If resuming, add the completed leaves to skip
    # Sanitize labels the same way the GAP SanitizeLabel function does
    if completed:
        script += '    # Previously completed leaves\n'
        for label in completed:
            safe = sanitize_label_py(label)
            script += f'    completedLeaves.{safe} := true;\n'
        script += f'    Print("Resuming: {len(completed)} leaves already completed\\n");\n'

    script += f'''
    outputFile := "{result_cygwin}";

    if not resumeMode then
        PrintTo(outputFile, "# Leaf worker ", String(workerId), " results (S{N})\\n");
        AppendTo(outputFile, "# Batch: {batch_file.name}\\n");
        AppendTo(outputFile, "# Started: ", StringTime(Runtime()), "\\n");
        AppendTo(outputFile, "maxsub_results := [\\n");
    fi;

    totalCount := 0;
    skipped := 0;

    for i in [1..Length(leaf_batch)] do
        entry := leaf_batch[i];
        label_str := entry.label;
        safeLabel := SanitizeLabel(label_str);

        # Check if already completed (resume support)
        if IsBound(completedLeaves.(safeLabel)) then
            skipped := skipped + 1;
            if skipped mod 50 = 0 then
                Print("  Skipped ", skipped, " already-completed leaves\\n");
            fi;
            continue;
        fi;

        Print("\\n--- Leaf ", i, "/", Length(leaf_batch),
              ": ", label_str, " (order ", entry.order, ") ---\\n");
        leafStart := Runtime();

        # Reconstruct group
        gens := List(entry.genImages, PermList);
        if Length(gens) = 0 then
            G := Group(());
        else
            G := Group(gens);
        fi;

        # Compute conjugacy classes of subgroups
        Print("  Computing ConjugacyClassesSubgroups...\\n");
        ccs := ConjugacyClassesSubgroups(G);
        Print("  Found ", Length(ccs), " conjugacy classes\\n");

        reps := List(ccs, Representative);

        # Save each representative
        for j in [1..Length(reps)] do
            H := reps[j];
            genImages := [];
            for g in GeneratorsOfGroup(H) do
                Add(genImages, ListPerm(g, n));
            od;

            inv := ComputeInvariantKey(H, n);

            if totalCount > 0 or resumeMode then
                AppendTo(outputFile, ",\\n");
            fi;
            AppendTo(outputFile, "  rec(gens := ", genImages,
                     ", inv := ", inv,
                     ", source := \\"", label_str, "\\")");
            totalCount := totalCount + 1;
        od;

        leafElapsed := Runtime() - leafStart;
        Print("  Leaf complete: ", Length(reps), " subgroups in ",
              Int(leafElapsed/1000), "s\\n");

        # Checkpoint marker (used by resume support)
        AppendTo(outputFile, "\\n# Leaf complete: ", label_str,
                 " (", Length(reps), " subgroups in ", Int(leafElapsed/1000), "s)\\n");

        GASMAN("collect");
    od;

    AppendTo(outputFile, "\\n];\\n");

    elapsed := Runtime() - startTime;
    Print("\\n=== Leaf Worker ", workerId, " complete ===\\n");
    Print("  Total subgroups saved: ", totalCount, "\\n");
    Print("  Leaves processed: ", Length(leaf_batch) - skipped, "\\n");
    Print("  Leaves skipped (resume): ", skipped, "\\n");
    Print("  Time: ", Int(elapsed/1000), " seconds\\n");
    AppendTo(outputFile, "# Complete: ", totalCount, " subgroups from ",
             Length(leaf_batch) - skipped, " leaves in ",
             Int(elapsed/1000), " seconds\\n");
end;

LeafWorkerMain();
QUIT;
'''

    script_file = OUTPUT_DIR / f"leaf_worker_{worker_id}.g"
    with open(script_file, 'w') as f:
        f.write(script)

    script_cygwin = windows_to_cygwin_path(str(script_file))
    cmd = f'/opt/gap-4.15.1/gap -q -o {WORKER_MEMORY} "{script_cygwin}"'

    start_time = time.time()
    result = {
        "worker_id": worker_id,
        "success": False,
        "total_subs": 0,
        "elapsed": 0,
        "error": None,
    }

    try:
        with open(log_file, 'w' if not resume_mode else 'a') as log:
            log.write(f"\n# Leaf Worker {worker_id}\n")
            log.write(f"# {'Resumed' if resume_mode else 'Started'}: {datetime.now()}\n")
            log.write(f"# Memory: {WORKER_MEMORY}\n\n")
            log.flush()

            proc = subprocess.Popen(
                [GAP_BASH, '--login', '-c', cmd],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )

            for line in proc.stdout:
                log.write(line)
                log.flush()
                line_s = line.strip()
                if any(kw in line_s for kw in [
                    "Leaf Worker", "Leaf ", "Computing", "Found",
                    "complete", "ERROR", "---", "Total", "subgroups"
                ]):
                    print(f"  [W{worker_id}] {line_s}")

            proc.wait(timeout=TIMEOUT)
            result["returncode"] = proc.returncode

            log.write(f"\n# Finished: {datetime.now()}\n")
            log.write(f"# Exit code: {proc.returncode}\n")

    except subprocess.TimeoutExpired:
        proc.kill()
        result["error"] = f"TIMEOUT after {TIMEOUT}s"
        print(f"  [W{worker_id}] TIMEOUT!")
    except Exception as e:
        result["error"] = str(e)
        print(f"  [W{worker_id}] ERROR: {e}")

    result["elapsed"] = time.time() - start_time

    # Check for success
    if result_file.exists():
        content = result_file.read_text(encoding='utf-8', errors='replace')
        if "# Complete:" in content:
            result["success"] = True
            m = re.search(r'# Complete: (\d+) subgroups', content)
            if m:
                result["total_subs"] = int(m.group(1))

    return result


def main():
    print("=" * 60)
    print("Phase A-2: Parallel Leaf Lattice Computation for S15")
    print("=" * 60)
    print(f"Started: {datetime.now()}")
    print(f"Memory per worker: {WORKER_MEMORY}")
    print()

    # Determine which workers to run
    num_batches = count_leaf_batches()
    if num_batches == 0:
        print("ERROR: No leaf_batch_*.g files found!")
        print("Run phase_a1_enumerate.py first.")
        return 1

    print(f"Found {num_batches} leaf batch files")

    if len(sys.argv) == 1:
        worker_ids = list(range(1, num_batches + 1))
    elif len(sys.argv) == 2:
        worker_ids = [int(sys.argv[1])]
    elif len(sys.argv) == 3:
        start = int(sys.argv[1])
        end = int(sys.argv[2])
        worker_ids = list(range(start, end + 1))
    else:
        print("Usage: python phase_a2_compute_leaves.py [worker_id | start end]")
        return 1

    # Check for resume state
    for wid in worker_ids:
        result_file = OUTPUT_DIR / f"leaf_results_{wid}.g"
        completed = get_completed_leaves(result_file)
        if completed:
            print(f"  Worker {wid}: {len(completed)} leaves already completed (will resume)")
        elif result_file.exists():
            content = result_file.read_text(encoding='utf-8', errors='replace')
            if "# Complete:" in content:
                print(f"  Worker {wid}: ALREADY COMPLETE")
                worker_ids = [w for w in worker_ids if w != wid]

    if not worker_ids:
        print("\nAll workers already complete!")
        return 0

    print(f"\nRunning workers: {worker_ids}")
    max_parallel = min(len(worker_ids), 3)
    print(f"Max parallel: {max_parallel}")
    print()

    # Launch workers in parallel
    all_results = []
    with ProcessPoolExecutor(max_workers=max_parallel) as executor:
        futures = {executor.submit(run_leaf_worker, wid): wid for wid in worker_ids}
        for future in as_completed(futures):
            wid = futures[future]
            try:
                result = future.result()
                all_results.append(result)
                if result["success"]:
                    print(f"\n  Worker {wid}: {result['total_subs']} subgroups in "
                          f"{result['elapsed']:.0f}s ({result['elapsed']/3600:.1f}h)")
                else:
                    print(f"\n  Worker {wid}: FAILED - {result.get('error', 'unknown')}")
            except Exception as e:
                print(f"\n  Worker {wid}: Exception: {e}")
                all_results.append({"worker_id": wid, "success": False, "error": str(e)})

    # Summary
    print(f"\n{'='*60}")
    print("Phase A-2 Summary")
    print(f"{'='*60}")

    total_subs = sum(r.get("total_subs", 0) for r in all_results)
    succeeded = [r for r in all_results if r.get("success")]
    failed = [r for r in all_results if not r.get("success")]

    print(f"  Completed: {len(succeeded)}/{len(all_results)}")
    print(f"  Total subgroups: {total_subs:,}")
    if failed:
        print(f"  Failed: {len(failed)}")
        for r in failed:
            print(f"    Worker {r['worker_id']}: {r.get('error', 'unknown')}")
        return 1

    print(f"\nPhase A-2 complete!")
    print(f"  Next: python compute_s15_maxsub.py  (direct workers)")
    print(f"  Then: python phase_a4_combine.py     (combine results)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
