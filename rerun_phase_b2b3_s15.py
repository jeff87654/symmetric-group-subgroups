#!/usr/bin/env python3
"""Re-run Phase B-2 (parallel dedup) and B-3 (collect results) for S15.

Phase B-1 (phase_b1_s15.py) must have completed successfully first.
Bucket files must exist in maxsub_output_s15/dedup_work/.

Uses (element_order, fixed_point_count) sub-bucketing for large buckets
to avoid O(n^2) RepresentativeAction calls.

For groups of order > 5000, element enumeration is too expensive for
sub-bucketing. Uses cheaper invariants instead (Sylow subgroup sizes).
"""

import subprocess
import sys
import time
from pathlib import Path
from datetime import datetime
from concurrent.futures import ProcessPoolExecutor, as_completed

GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
BASE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups")
OUTPUT_DIR = BASE_DIR / "maxsub_output_s15"
DEDUP_DIR = OUTPUT_DIR / "dedup_work"
CACHE_DIR = BASE_DIR / "conjugacy_cache"
N = 15
EXPECTED_COUNT = 159129
NUM_WORKERS = 8

def windows_to_cygwin_path(win_path: str) -> str:
    path = str(win_path).replace('\\', '/')
    if len(path) >= 2 and path[1] == ':':
        drive = path[0].lower()
        path = f'/cygdrive/{drive}{path[2:]}'
    return path

BASE_CYGWIN = windows_to_cygwin_path(str(BASE_DIR))
DEDUP_CYGWIN = windows_to_cygwin_path(str(DEDUP_DIR))


def run_dedup_worker(worker_id: int) -> dict:
    """Run a single dedup worker with sub-bucketing."""

    script = f'''
DedupWorkerMain := function()
    local Sn, workerId, startTime, bucketFile, outputFile,
          totalReps, totalTests, first, bIdx, bData, bucket, bucketKey,
          groups, genImages, bucketReps, H, found, rep, gens, g, elapsed,
          SUB_BUCKET_THRESHOLD, ELEMENT_ENUM_LIMIT, subBuckets, subKey,
          subKeys, subBucket, subReps, x, subStartTime, subElapsed,
          maxSubSize, ofpCounts, o, fp, k, entries, sylSizes, p, syl;

    MAXSUB_BASE := "{BASE_CYGWIN}";
    Read(Concatenation(MAXSUB_BASE, "/compute_s15_maxsub.g"));

    n := {N};
    Sn := SymmetricGroup(n);

    workerId := {worker_id};
    Print("=== Dedup Worker ", workerId, " started (V2 with sub-bucketing) ===\\n");
    startTime := Runtime();

    # Load bucket data
    bucketFile := Concatenation("{DEDUP_CYGWIN}",
                  "/worker_buckets_", String(workerId), ".g");
    Read(bucketFile);

    if not IsBound(worker_buckets) then
        Print("ERROR: No worker_buckets found\\n");
        return;
    fi;

    Print("Loaded ", Length(worker_buckets), " buckets\\n");

    outputFile := Concatenation("{DEDUP_CYGWIN}",
                  "/worker_results_", String(workerId), ".g");
    PrintTo(outputFile, "# Dedup worker ", String(workerId), " results (S15)\\n");
    AppendTo(outputFile, "worker_results := [\\n");

    totalReps := 0;
    totalTests := 0;
    first := true;
    SUB_BUCKET_THRESHOLD := 15;
    ELEMENT_ENUM_LIMIT := 5000;  # Max group order for element enumeration

    for bIdx in [1..Length(worker_buckets)] do
        bData := worker_buckets[bIdx];
        bucket := bData.groups;
        bucketKey := bData.key;

        # Reconstruct groups
        groups := [];
        for genImages in bucket do
            if Length(genImages) = 0 then
                Add(groups, Group(()));
            else
                Add(groups, Group(List(genImages, PermList)));
            fi;
        od;

        if Length(groups) <= SUB_BUCKET_THRESHOLD then
            # Small bucket: pairwise test as before
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
        else
            # Large bucket: sub-bucket first
            if Length(groups) > 30 then
                Print("  Bucket ", bIdx, "/", Length(worker_buckets),
                      ": ", Length(groups), " groups\\n");
            fi;
            subStartTime := Runtime();

            subBuckets := rec();
            for H in groups do
                if Size(H) <= ELEMENT_ENUM_LIMIT then
                    # Full element enumeration for (order, fixed_points) histogram
                    ofpCounts := rec();
                    for x in H do
                        o := Order(x);
                        fp := n - NrMovedPoints(x);
                        k := Concatenation(String(o), "_", String(fp));
                        if IsBound(ofpCounts.(k)) then
                            ofpCounts.(k) := ofpCounts.(k) + 1;
                        else
                            ofpCounts.(k) := 1;
                        fi;
                    od;
                    entries := SortedList(List(RecNames(ofpCounts),
                               k -> [k, ofpCounts.(k)]));
                    subKey := String(entries);
                else
                    # Large group: use cheaper invariant
                    # Sylow subgroup sizes for small primes + Frattini size
                    sylSizes := [];
                    for p in [2, 3, 5, 7, 11, 13] do
                        if Size(H) mod p = 0 then
                            syl := SylowSubgroup(H, p);
                            Add(sylSizes, [p, Size(syl)]);
                        fi;
                    od;
                    Add(sylSizes, ["F", Size(FrattiniSubgroup(H))]);
                    Add(sylSizes, ["E", Exponent(H)]);
                    subKey := String(sylSizes);
                fi;

                if not IsBound(subBuckets.(subKey)) then
                    subBuckets.(subKey) := [];
                fi;
                Add(subBuckets.(subKey), H);
            od;

            subElapsed := Runtime() - subStartTime;
            subKeys := RecNames(subBuckets);

            if Length(groups) > 30 then
                maxSubSize := Maximum(List(subKeys, k -> Length(subBuckets.(k))));
                Print("    Sub-bucketed into ", Length(subKeys),
                      " sub-buckets in ", Int(subElapsed/1000),
                      "s (max sub-bucket: ", maxSubSize, ")\\n");
            fi;

            # Process each sub-bucket independently
            bucketReps := [];
            for subKey in subKeys do
                subBucket := subBuckets.(subKey);
                subReps := [];
                for H in subBucket do
                    found := false;
                    for rep in subReps do
                        totalTests := totalTests + 1;
                        if RepresentativeAction(Sn, H, rep) <> fail then
                            found := true;
                            break;
                        fi;
                    od;
                    if not found then
                        Add(subReps, H);
                    fi;
                od;
                Append(bucketReps, subReps);
            od;

            if Length(groups) > 30 then
                subElapsed := Runtime() - subStartTime;
                Print("    -> ", Length(bucketReps), " unique reps in ",
                      Int(subElapsed/1000), "s (",
                      Length(groups) - Length(bucketReps), " dups, ",
                      totalTests, " total tests)\\n");
            fi;
        fi;

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

        # Progress every 100 buckets
        if bIdx mod 100 = 0 then
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
            log.write(f"# Dedup Worker {worker_id} (S15)\n# Started: {datetime.now()}\n\n")
            proc = subprocess.Popen(
                [GAP_BASH, '--login', '-c', cmd],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1,
            )
            for line in proc.stdout:
                log.write(line)
                log.flush()
                if any(kw in line for kw in ["Worker", "bucket", "complete",
                                              "reps", "ERROR", "Sub-bucket",
                                              "unique", "sub-bucket"]):
                    print(f"  [{worker_id}] {line.rstrip()}")
            proc.wait()
            log.write(f"\n# Finished: {datetime.now()}\n# Exit: {proc.returncode}\n")

        result["returncode"] = proc.returncode

        result_file = DEDUP_DIR / f"worker_results_{worker_id}.g"
        if result_file.exists():
            content = result_file.read_text()
            if "# Complete:" in content:
                result["success"] = True
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


def run_phase_b3():
    """Collect results from all workers into final cache file."""
    print("\n" + "=" * 60)
    print("Phase B-3: Collect results and verify")
    print("=" * 60)

    script = f'''
dedup_dir := "{DEDUP_CYGWIN}";
n := {N};

Print("=== Phase B-3: Collecting Results ===\\n\\n");

Read(Concatenation(dedup_dir, "/singletons.g"));
Print("Singletons: ", Length(singleton_reps), "\\n");
totalCount := Length(singleton_reps);

outputFile := "{windows_to_cygwin_path(str(CACHE_DIR / 's15_subgroups.g'))}";
PrintTo(outputFile, "# Conjugacy class representatives for S15\\n");
AppendTo(outputFile, "# Computed via maximal subgroup decomposition\\n");
AppendTo(outputFile, "# Computed: {datetime.now()}\\n");
AppendTo(outputFile, "return [\\n");

for i in [1..Length(singleton_reps)] do
    if i > 1 then
        AppendTo(outputFile, ",\\n");
    fi;
    AppendTo(outputFile, "  ", singleton_reps[i]);
od;

written := Length(singleton_reps);
Unbind(singleton_reps);
GASMAN("collect");

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
    print("Phase B-2 & B-3: Parallel Dedup for S15")
    print("=" * 60)
    print(f"Started: {datetime.now()}")
    print(f"Workers: {NUM_WORKERS}")
    print()

    # Verify B-1 output exists
    singletons_file = DEDUP_DIR / "singletons.g"
    if not singletons_file.exists():
        print("ERROR: Phase B-1 output (singletons.g) not found!")
        print("Run phase_b1_s15.py first.")
        return 1

    for i in range(1, NUM_WORKERS + 1):
        bucket_file = DEDUP_DIR / f"worker_buckets_{i}.g"
        if not bucket_file.exists():
            print(f"ERROR: Phase B-1 output (worker_buckets_{i}.g) not found!")
            return 1

    # Check for already-completed dedup workers (resume support)
    completed_workers = set()
    for i in range(1, NUM_WORKERS + 1):
        result_file = DEDUP_DIR / f"worker_results_{i}.g"
        if result_file.exists():
            content = result_file.read_text()
            if "# Complete:" in content:
                completed_workers.add(i)
                for line in content.split('\n'):
                    if line.startswith("# Complete:"):
                        parts = line.split()
                        reps = int(parts[2])
                        print(f"  Worker {i} already completed: {reps} reps")
                        break

    workers_to_run = [i for i in range(1, NUM_WORKERS + 1) if i not in completed_workers]

    if completed_workers:
        print(f"\n  {len(completed_workers)} workers already completed, "
              f"{len(workers_to_run)} to run\n")

    if not workers_to_run:
        print("All workers already completed. Proceeding to Phase B-3...")
    else:
        print(f"All Phase B-1 outputs found. Starting parallel dedup ({len(workers_to_run)} workers)...\n")

        # Phase B-2: Parallel dedup with sub-bucketing
        print("=" * 60)
        print(f"Phase B-2: Parallel dedup ({len(workers_to_run)} workers)")
        print("=" * 60)

        results = []
        with ProcessPoolExecutor(max_workers=min(len(workers_to_run), NUM_WORKERS)) as executor:
            futures = {executor.submit(run_dedup_worker, i): i for i in workers_to_run}
            for future in as_completed(futures):
                worker_id = futures[future]
                try:
                    result = future.result()
                    results.append(result)
                    if result["success"]:
                        print(f"\n  Worker {worker_id}: {result['reps']} reps in "
                              f"{result['elapsed']:.0f}s")
                    else:
                        print(f"\n  Worker {worker_id}: FAILED - "
                              f"{result.get('error', 'unknown')}")
                except Exception as e:
                    print(f"\n  Worker {worker_id}: Exception: {e}")
                    results.append({"worker_id": worker_id, "success": False,
                                    "error": str(e)})

        total_reps = sum(r.get("reps", 0) for r in results)
        failed = [r for r in results if not r.get("success")]
        print(f"\nTotal reps from new workers: {total_reps}")

        if failed:
            print(f"\nWARNING: {len(failed)} workers failed!")
            for r in failed:
                print(f"  Worker {r['worker_id']}: {r.get('error', 'unknown')}")
            print("\nFix issues and re-run. Completed workers will be skipped.")
            return 1

    # Phase B-3: Collect results
    if not run_phase_b3():
        print("Phase B-3 FAILED!")
        return 1

    print(f"\nDone: {datetime.now()}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
