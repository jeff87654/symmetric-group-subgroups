#!/usr/bin/env python3
"""
dedup_parallel.py - Parallel Phase B deduplication for S14 maximal subgroup approach.

Phase B-1: Load all worker data, bucket by invariant key, save bucket files
Phase B-2: N parallel GAP workers process assigned buckets
Phase B-3: Collect results, verify count

This replaces the single-process deduplicate_maxsub.g with a faster parallel approach.
"""

import subprocess
import sys
import os
import json
import time
from pathlib import Path
from datetime import datetime
from concurrent.futures import ProcessPoolExecutor, as_completed

GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
BASE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups")
OUTPUT_DIR = BASE_DIR / "maxsub_output"
DEDUP_DIR = OUTPUT_DIR / "dedup_work"
CACHE_DIR = BASE_DIR / "conjugacy_cache"

N = 14
EXPECTED_COUNT = 75154
NUM_WORKERS = 6  # Number of parallel dedup workers

def windows_to_cygwin_path(win_path: str) -> str:
    path = str(win_path).replace('\\', '/')
    if len(path) >= 2 and path[1] == ':':
        drive = path[0].lower()
        path = f'/cygdrive/{drive}{path[2:]}'
    return path

BASE_CYGWIN = windows_to_cygwin_path(str(BASE_DIR))
DEDUP_CYGWIN = windows_to_cygwin_path(str(DEDUP_DIR))


def run_phase_b1():
    """Phase B-1: Load all data, bucket, save bucket files."""
    print("=" * 60)
    print("Phase B-1: Load data and bucket by invariant key")
    print("=" * 60)

    script = f'''
MAXSUB_BASE := "{BASE_CYGWIN}";
Read(Concatenation(MAXSUB_BASE, "/compute_s14_maxsub.g"));

n := {N};
dedup_dir := "{DEDUP_CYGWIN}";

Print("=== Phase B-1: Loading and Bucketing ===\\n\\n");
startTime := Runtime();

# Load all worker files
allSubs := [];
workerFiles := [
    "intrans_1x13", "intrans_2x12", "intrans_3x11",
    "intrans_4x10", "intrans_5x9", "intrans_6x8",
    "intrans_7x7", "wreath_2wr7", "wreath_7wr2",
];

for label in workerFiles do
    filename := Concatenation(MAXSUB_BASE, "/maxsub_output/", label, ".g");
    if IsExistingFile(filename) then
        Print("  Loading ", label, "...");
        subs := LoadMaxSubResults(filename, n);
        Print(" ", Length(subs), " subgroups\\n");
        Append(allSubs, subs);
        GASMAN("collect");
    else
        Print("  WARNING: Missing file for ", label, "\\n");
    fi;
od;

# Load primitive groups
nrPrim := NrPrimitiveGroups(n);
for i in [1..nrPrim] do
    G := PrimitiveGroup(n, i);
    if Size(G) < Factorial(n) and Size(G) < Factorial(n)/2 then
        label := Concatenation("primitive_", String(i));
        filename := Concatenation(MAXSUB_BASE, "/maxsub_output/", label, ".g");
        if IsExistingFile(filename) then
            Print("  Loading ", label, "...");
            subs := LoadMaxSubResults(filename, n);
            Print(" ", Length(subs), " subgroups\\n");
            Append(allSubs, subs);
            GASMAN("collect");
        fi;
    fi;
od;

Print("\\nTotal loaded: ", Length(allSubs), "\\n");

# Add A14 and S14
A14 := AlternatingGroup(n);
inv_A14 := [Size(A14), [n], -1, -1, 1, -1, [], Size(A14)];
Add(allSubs, rec(group := A14, inv := inv_A14, source := "special_A14"));

S14 := SymmetricGroup(n);
inv_S14 := [Size(S14), [n], -1, -1, 1, -1, [], Factorial(n)/2];
Add(allSubs, rec(group := S14, inv := inv_S14, source := "special_S14"));

Print("Total after specials: ", Length(allSubs), "\\n\\n");

# Bucket by invariant key
Print("Bucketing by invariant key...\\n");
buckets := rec();
for entry in allSubs do
    key := InvariantKeyToString(entry.inv);
    if not IsBound(buckets.(key)) then
        buckets.(key) := [];
    fi;
    Add(buckets.(key), entry);
od;

bucketKeys := RecNames(buckets);
Print("Total buckets: ", Length(bucketKeys), "\\n");

# Count singletons
singletons := 0;
multiGroup := 0;
for k in bucketKeys do
    if Length(buckets.(k)) = 1 then
        singletons := singletons + 1;
    else
        multiGroup := multiGroup + 1;
    fi;
od;
Print("Singletons: ", singletons, "\\n");
Print("Multi-group: ", multiGroup, "\\n\\n");

# Save singletons directly
Print("Saving singleton representatives...\\n");
singletonFile := Concatenation(dedup_dir, "/singletons.g");
PrintTo(singletonFile, "# Singleton bucket representatives\\n");
AppendTo(singletonFile, "singleton_reps := [\\n");
sCount := 0;
for k in bucketKeys do
    if Length(buckets.(k)) = 1 then
        entry := buckets.(k)[1];
        gens := GeneratorsOfGroup(entry.group);
        genImages := [];
        for g in gens do
            Add(genImages, ListPerm(g, n));
        od;
        if sCount > 0 then
            AppendTo(singletonFile, ",\\n");
        fi;
        AppendTo(singletonFile, "  ", genImages);
        sCount := sCount + 1;
    fi;
od;
AppendTo(singletonFile, "\\n];\\n");
Print("  Saved ", sCount, " singletons\\n");

# Distribute multi-group buckets across workers
# Sort by size (largest first) and round-robin assign
Print("\\nDistributing multi-group buckets across {NUM_WORKERS} workers...\\n");
multiBucketKeys := Filtered(bucketKeys, k -> Length(buckets.(k)) > 1);

# Sort by size descending
sizes := List(multiBucketKeys, k -> Length(buckets.(k)));
perm := Sortex(sizes);
multiBucketKeys := Permuted(multiBucketKeys, perm);
# Reverse to get largest first
multiBucketKeys := Reversed(multiBucketKeys);

# Round-robin assignment (largest first for load balancing)
numWorkers := {NUM_WORKERS};
workerBuckets := List([1..numWorkers], i -> []);
for i in [1..Length(multiBucketKeys)] do
    workerIdx := ((i - 1) mod numWorkers) + 1;
    Add(workerBuckets[workerIdx], multiBucketKeys[i]);
od;

# Report distribution
for w in [1..numWorkers] do
    totalGroups := Sum(workerBuckets[w], k -> Length(buckets.(k)));
    Print("  Worker ", w, ": ", Length(workerBuckets[w]),
          " buckets, ", totalGroups, " total groups\\n");
od;

# Save each worker's bucket data
Print("\\nSaving worker bucket files...\\n");
for w in [1..numWorkers] do
    workerFile := Concatenation(dedup_dir, "/worker_buckets_", String(w), ".g");
    PrintTo(workerFile, "# Dedup worker ", String(w), " bucket data\\n");
    AppendTo(workerFile, "worker_buckets := [\\n");
    first := true;
    for k in workerBuckets[w] do
        bucket := buckets.(k);
        # Save each group in the bucket as generator images
        bucketData := [];
        for entry in bucket do
            gens := GeneratorsOfGroup(entry.group);
            genImages := [];
            for g in gens do
                Add(genImages, ListPerm(g, n));
            od;
            Add(bucketData, genImages);
        od;
        if not first then
            AppendTo(workerFile, ",\\n");
        fi;
        first := false;
        AppendTo(workerFile, "  rec(key := ", k, ", groups := ", bucketData, ")");
    od;
    AppendTo(workerFile, "\\n];\\n");
    Print("  Saved worker ", w, " data\\n");
od;

elapsed := Runtime() - startTime;
Print("\\nPhase B-1 complete in ", Int(elapsed/1000), " seconds\\n");
Print("Singletons: ", sCount, "\\n");
Print("Multi-group buckets distributed to ", numWorkers, " workers\\n");

QUIT;
'''

    script_file = DEDUP_DIR / "phase_b1.g"
    log_file = DEDUP_DIR / "phase_b1.log"

    with open(script_file, 'w') as f:
        f.write(script)

    script_cygwin = windows_to_cygwin_path(str(script_file))
    cmd = f'/opt/gap-4.15.1/gap -q -o 50g "{script_cygwin}"'

    print(f"Command: {cmd}")
    print(f"Log: {log_file}")
    print()

    start_time = time.time()
    with open(log_file, 'w') as log:
        log.write(f"# Phase B-1\n# Started: {datetime.now()}\n\n")
        proc = subprocess.Popen(
            [GAP_BASH, '--login', '-c', cmd],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
        )
        for line in proc.stdout:
            print(line, end='')
            sys.stdout.flush()
            log.write(line)
            log.flush()
        proc.wait()
        log.write(f"\n# Finished: {datetime.now()}\n# Exit: {proc.returncode}\n")

    elapsed = time.time() - start_time
    print(f"\nPhase B-1 completed in {elapsed:.0f}s (exit code {proc.returncode})")
    return proc.returncode == 0


def run_dedup_worker(worker_id: int) -> dict:
    """Run a single dedup worker for Phase B-2."""

    script = f'''
DedupWorkerMain := function()
    local Sn, workerId, startTime, bucketFile, outputFile,
          totalReps, totalTests, first, bIdx, bData, bucket, bucketKey,
          groups, genImages, bucketReps, H, found, rep, gens, g, elapsed;

    MAXSUB_BASE := "{BASE_CYGWIN}";
    Read(Concatenation(MAXSUB_BASE, "/compute_s14_maxsub.g"));

    n := {N};
    Sn := SymmetricGroup(n);

    workerId := {worker_id};
    Print("=== Dedup Worker ", workerId, " started ===\\n");
    startTime := Runtime();

    # Load bucket data for this worker
    bucketFile := Concatenation("{DEDUP_CYGWIN}",
                  "/worker_buckets_", String(workerId), ".g");
    Read(bucketFile);

    if not IsBound(worker_buckets) then
        Print("ERROR: No worker_buckets found\\n");
        return;
    fi;

    Print("Loaded ", Length(worker_buckets), " buckets\\n");

    # Process each bucket
    outputFile := Concatenation("{DEDUP_CYGWIN}",
                  "/worker_results_", String(workerId), ".g");
    PrintTo(outputFile, "# Dedup worker ", String(workerId), " results\\n");
    AppendTo(outputFile, "worker_results := [\\n");

    totalReps := 0;
    totalTests := 0;
    first := true;

    for bIdx in [1..Length(worker_buckets)] do
        bData := worker_buckets[bIdx];
        bucket := bData.groups;
        bucketKey := bData.key;

        # Reconstruct groups from generators
        groups := [];
        for genImages in bucket do
            if Length(genImages) = 0 then
                Add(groups, Group(()));
            else
                Add(groups, Group(List(genImages, PermList)));
            fi;
        od;

        # Deduplicate within bucket by S14-conjugacy
        bucketReps := [];
        for H in groups do
            found := false;
            for rep in bucketReps do
                totalTests := totalTests + 1;
                if RepresentativeAction(Sn, H, rep) <> fail then
                    found := true;
                    break;
                fi;
            od;
            if not found then
                Add(bucketReps, H);
            fi;
        od;

        # Save unique representatives
        for rep in bucketReps do
            gens := GeneratorsOfGroup(rep);
            genImages := [];
            for g in gens do
                Add(genImages, ListPerm(g, n));
            od;
            if not first then
                AppendTo(outputFile, ",\\n");
            fi;
            first := false;
            AppendTo(outputFile, "  ", genImages);
            totalReps := totalReps + 1;
        od;

        # Progress
        if bIdx mod 100 = 0 or Length(bucket) > 30 then
            elapsed := Runtime() - startTime;
            Print("  Worker ", workerId, ": bucket ", bIdx, "/",
                  Length(worker_buckets), ", ", totalReps, " reps, ",
                  totalTests, " tests (", Int(elapsed/1000), "s)\\n");
        fi;

        if bIdx mod 500 = 0 then
            GASMAN("collect");
        fi;
    od;

    AppendTo(outputFile, "\\n];\\n");

    elapsed := Runtime() - startTime;
    Print("\\n=== Worker ", workerId, " complete ===\\n");
    Print("  Unique reps: ", totalReps, "\\n");
    Print("  Conjugacy tests: ", totalTests, "\\n");
    Print("  Time: ", Int(elapsed/1000), " seconds\\n");
    AppendTo(outputFile, "# Complete: ", totalReps, " reps in ",
             Int(elapsed/1000), " seconds\\n");
end;

DedupWorkerMain();
QUIT;
'''
    script_file = DEDUP_DIR / f"dedup_worker_{worker_id}.g"
    log_file = DEDUP_DIR / f"dedup_worker_{worker_id}.log"

    with open(script_file, 'w') as f:
        f.write(script)

    script_cygwin = windows_to_cygwin_path(str(script_file))
    cmd = f'/opt/gap-4.15.1/gap -q -o 8g "{script_cygwin}"'

    start_time = time.time()
    result = {"worker_id": worker_id, "success": False, "reps": 0, "elapsed": 0}

    try:
        with open(log_file, 'w') as log:
            log.write(f"# Dedup Worker {worker_id}\n# Started: {datetime.now()}\n\n")
            proc = subprocess.Popen(
                [GAP_BASH, '--login', '-c', cmd],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1,
            )
            for line in proc.stdout:
                log.write(line)
                log.flush()
                if any(kw in line for kw in ["Worker", "bucket", "complete", "reps", "ERROR"]):
                    print(f"  [{worker_id}] {line.rstrip()}")
            proc.wait()
            log.write(f"\n# Finished: {datetime.now()}\n# Exit: {proc.returncode}\n")

        result["returncode"] = proc.returncode

        # Check for completion
        result_file = DEDUP_DIR / f"worker_results_{worker_id}.g"
        if result_file.exists():
            content = result_file.read_text()
            if "# Complete:" in content:
                result["success"] = True
                # Extract rep count from completion line
                for line in content.split('\n'):
                    if line.startswith("# Complete:"):
                        parts = line.split()
                        result["reps"] = int(parts[2])
                        break

    except Exception as e:
        result["error"] = str(e)
        print(f"  [{worker_id}] ERROR: {e}")

    result["elapsed"] = time.time() - start_time
    return result


def run_phase_b2():
    """Phase B-2: Run parallel dedup workers."""
    print("\n" + "=" * 60)
    print(f"Phase B-2: Parallel deduplication ({NUM_WORKERS} workers)")
    print("=" * 60)

    results = []
    with ProcessPoolExecutor(max_workers=NUM_WORKERS) as executor:
        futures = {executor.submit(run_dedup_worker, i): i
                   for i in range(1, NUM_WORKERS + 1)}
        for future in as_completed(futures):
            worker_id = futures[future]
            try:
                result = future.result()
                results.append(result)
                if result["success"]:
                    print(f"  Worker {worker_id}: {result['reps']} reps in {result['elapsed']:.0f}s")
                else:
                    print(f"  Worker {worker_id}: FAILED")
            except Exception as e:
                print(f"  Worker {worker_id}: Exception: {e}")
                results.append({"worker_id": worker_id, "success": False, "error": str(e)})

    total_reps = sum(r.get("reps", 0) for r in results)
    print(f"\nTotal reps from workers: {total_reps}")
    return results


def run_phase_b3(worker_results):
    """Phase B-3: Collect results and cross-deduplicate between workers.

    Within each worker, buckets are fully deduplicated. But different workers
    process different buckets (by invariant key), so there's NO overlap between
    workers. We just need to collect all results.
    """
    print("\n" + "=" * 60)
    print("Phase B-3: Collect results and verify")
    print("=" * 60)

    # Since each worker handles completely separate buckets (partitioned by
    # invariant key), there's no cross-worker overlap. We just concatenate.
    script = f'''
MAXSUB_BASE := "{BASE_CYGWIN}";
dedup_dir := "{DEDUP_CYGWIN}";
n := {N};

Print("=== Phase B-3: Collecting Results ===\\n\\n");

# Load singletons
Read(Concatenation(dedup_dir, "/singletons.g"));
Print("Singletons: ", Length(singleton_reps), "\\n");
totalCount := Length(singleton_reps);

# Start output file
outputFile := Concatenation(MAXSUB_BASE, "/conjugacy_cache/s14_subgroups.g");
PrintTo(outputFile, "# Conjugacy class representatives for S14\\n");
AppendTo(outputFile, "# Computed via maximal subgroup decomposition\\n");
AppendTo(outputFile, "# Computed: {datetime.now()}\\n");
AppendTo(outputFile, "return [\\n");

# Write singletons
for i in [1..Length(singleton_reps)] do
    if i > 1 then
        AppendTo(outputFile, ",\\n");
    fi;
    AppendTo(outputFile, "  ", singleton_reps[i]);
od;

written := Length(singleton_reps);
Unbind(singleton_reps);
GASMAN("collect");

# Load worker results
for w in [1..{NUM_WORKERS}] do
    resultFile := Concatenation(dedup_dir, "/worker_results_", String(w), ".g");
    if IsExistingFile(resultFile) then
        Read(resultFile);
        if IsBound(worker_results) then
            Print("Worker ", w, ": ", Length(worker_results), " reps\\n");
            for i in [1..Length(worker_results)] do
                AppendTo(outputFile, ",\\n");
                AppendTo(outputFile, "  ", worker_results[i]);
                written := written + 1;
            od;
            totalCount := totalCount + Length(worker_results);
            Unbind(worker_results);
            GASMAN("collect");
        else
            Print("WARNING: No results from worker ", w, "\\n");
        fi;
    else
        Print("WARNING: Missing result file for worker ", w, "\\n");
    fi;
od;

AppendTo(outputFile, "\\n];\\n");

Print("\\n=== Final Count ===\\n");
Print("  Total unique conjugacy classes: ", totalCount, "\\n");
Print("  Expected: {EXPECTED_COUNT}\\n");
if totalCount = {EXPECTED_COUNT} then
    Print("  MATCH!\\n");
else
    Print("  MISMATCH! Off by ", AbsInt(totalCount - {EXPECTED_COUNT}), "\\n");
fi;
Print("  Written to: ", outputFile, "\\n");

QUIT;
'''

    script_file = DEDUP_DIR / "phase_b3.g"
    log_file = DEDUP_DIR / "phase_b3.log"

    with open(script_file, 'w') as f:
        f.write(script)

    script_cygwin = windows_to_cygwin_path(str(script_file))
    cmd = f'/opt/gap-4.15.1/gap -q -o 16g "{script_cygwin}"'

    start_time = time.time()
    with open(log_file, 'w') as log:
        log.write(f"# Phase B-3\n# Started: {datetime.now()}\n\n")
        proc = subprocess.Popen(
            [GAP_BASH, '--login', '-c', cmd],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
        )
        for line in proc.stdout:
            print(line, end='')
            sys.stdout.flush()
            log.write(line)
            log.flush()
        proc.wait()
        log.write(f"\n# Finished: {datetime.now()}\n# Exit: {proc.returncode}\n")

    elapsed = time.time() - start_time
    print(f"\nPhase B-3 completed in {elapsed:.0f}s (exit code {proc.returncode})")
    return proc.returncode == 0


def main():
    print("=" * 60)
    print("Parallel Phase B Deduplication for A005432(14)")
    print("=" * 60)
    print(f"Started: {datetime.now()}")
    print(f"Workers: {NUM_WORKERS}")
    print()

    DEDUP_DIR.mkdir(exist_ok=True)
    CACHE_DIR.mkdir(exist_ok=True)

    overall_start = time.time()

    # Check that all worker files exist
    required = [
        "intrans_1x13", "intrans_2x12", "intrans_3x11",
        "intrans_4x10", "intrans_5x9", "intrans_6x8",
        "intrans_7x7", "wreath_2wr7", "wreath_7wr2",
        "primitive_1", "primitive_2",
    ]
    missing = []
    for label in required:
        f = OUTPUT_DIR / f"{label}.g"
        if not f.exists():
            missing.append(label)
        else:
            # Check for completion marker
            content = f.read_text()
            if "# Complete:" not in content:
                missing.append(f"{label} (incomplete)")

    if missing:
        print(f"WARNING: Missing/incomplete worker outputs: {missing}")
        print("Phase B may produce incorrect results!")
        response = input("Continue anyway? [y/N] ")
        if response.lower() != 'y':
            return 1

    # Phase B-1
    if not run_phase_b1():
        print("Phase B-1 FAILED!")
        return 1

    # Phase B-2
    worker_results = run_phase_b2()
    failed = [r for r in worker_results if not r.get("success")]
    if failed:
        print(f"\nWARNING: {len(failed)} workers failed!")
        for r in failed:
            print(f"  Worker {r['worker_id']}: {r.get('error', 'unknown')}")
        return 1

    # Phase B-3
    if not run_phase_b3(worker_results):
        print("Phase B-3 FAILED!")
        return 1

    total_elapsed = time.time() - overall_start
    print(f"\n{'='*60}")
    print(f"Phase B Complete")
    print(f"  Total time: {total_elapsed:.0f}s ({total_elapsed/3600:.1f}h)")
    print(f"  Output: {CACHE_DIR / 's14_subgroups.g'}")
    print(f"{'='*60}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
