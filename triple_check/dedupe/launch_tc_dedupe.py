#!/usr/bin/env python3
"""
Launch Triple-Check Deduplication: 12 parallel workers.

Execution order:
1. Run tc_test_validation.g - MUST pass
2. Launch 12 workers in parallel:
   - 1 DP worker (Cygwin)
   - 1 2-group worker (WSL + ANUPQ)
   - 10 regular workers (Cygwin)
3. Monitor progress, report status
"""

import subprocess
import sys
import os
import json
import time
import threading
from datetime import datetime
from pathlib import Path
from collections import defaultdict

# Configuration
GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
BASE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups\triple_check")
DEDUPE_DIR = BASE_DIR / "dedupe"
LOGS_DIR = DEDUPE_DIR / "logs"
RESULTS_DIR = DEDUPE_DIR / "results"

CYGWIN_BASE = "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/triple_check/dedupe"
WSL_BASE = "/mnt/c/Users/jeffr/Downloads/Symmetric Groups/triple_check/dedupe"

# Worker definitions: (name, script, environment, memory)
WORKERS = [
    ("dp", "worker_dp.g", "cygwin", "8g"),
    ("2groups", "worker_2groups.g", "wsl", "8g"),
]
for i in range(1, 11):
    WORKERS.append((f"regular_{i}", f"worker_regular_{i}.g", "cygwin", "8g"))


def run_validation():
    """Run validation script. Returns True if all tests pass."""
    print("=" * 60)
    print("STEP 1: Running validation...")
    print("=" * 60)

    script_path = f"{CYGWIN_BASE}/tc_test_validation.g"
    log_file = LOGS_DIR / "validation.log"

    cmd = [GAP_BASH, "--login", "-c", f'/opt/gap-4.15.1/gap -q -o 8g "{script_path}"']

    with open(log_file, "w", encoding="utf-8") as out:
        out.write(f"# Validation started at {datetime.now()}\n\n")
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        for line in proc.stdout:
            print(f"[validation] {line}", end='')
            out.write(line)
            out.flush()
        proc.wait()
        out.write(f"\n# Exit code: {proc.returncode}\n")

    # Check result
    result_file = DEDUPE_DIR / "validation_result.txt"
    if result_file.exists():
        content = result_file.read_text()
        if "failCount := 0" in content and "passed := true" in content:
            print("\n*** VALIDATION PASSED ***\n")
            return True
        else:
            print("\n*** VALIDATION FAILED ***")
            print("Check logs/validation.log for details")
            return False
    else:
        print("\n*** VALIDATION RESULT FILE NOT FOUND ***")
        if proc.returncode != 0:
            print(f"GAP exited with code {proc.returncode}")
        return False


def launch_worker(name, script, environment, memory):
    """Launch a single worker and capture output."""
    log_file = LOGS_DIR / f"worker_{name}.log"

    if environment == "cygwin":
        script_path = f"{CYGWIN_BASE}/{script}"
        cmd = [GAP_BASH, "--login", "-c",
               f'/opt/gap-4.15.1/gap -q -o {memory} "{script_path}"']
    elif environment == "wsl":
        script_path = f"{WSL_BASE}/{script}"
        cmd = ["wsl", "gap", "-q", "-o", memory, script_path]
    else:
        raise ValueError(f"Unknown environment: {environment}")

    start_time = time.time()

    result = {
        "name": name,
        "script": script,
        "environment": environment,
        "start_time": datetime.now().isoformat(),
        "status": "running",
        "exit_code": None,
        "log_file": str(log_file),
        "last_line": "",
        "bucket_count": 0,
    }

    try:
        with open(log_file, "w", encoding="utf-8") as out:
            out.write(f"# Worker {name} started at {datetime.now()}\n")
            out.write(f"# Script: {script}\n")
            out.write(f"# Environment: {environment}\n\n")

            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )

            result["pid"] = proc.pid

            for line in proc.stdout:
                print(f"[{name}] {line}", end='')
                out.write(line)
                out.flush()
                result["last_line"] = line.strip()

                # Track bucket progress
                if "Bucket " in line and "complete:" in line:
                    result["bucket_count"] += 1

            proc.wait()

            elapsed = time.time() - start_time
            out.write(f"\n# Finished at {datetime.now()}\n")
            out.write(f"# Elapsed: {elapsed:.1f}s\n")
            out.write(f"# Exit code: {proc.returncode}\n")

            result["exit_code"] = proc.returncode
            result["elapsed"] = elapsed
            result["end_time"] = datetime.now().isoformat()

            if proc.returncode == 0 and "COMPLETE" in result["last_line"]:
                result["status"] = "success"
            elif proc.returncode == 0:
                result["status"] = "success"
            else:
                result["status"] = "failed"

    except FileNotFoundError as e:
        result["status"] = "error"
        result["error"] = f"Executable not found: {e}"
        print(f"[{name}] ERROR: {e}")
    except Exception as e:
        result["status"] = "error"
        result["error"] = str(e)
        print(f"[{name}] ERROR: {e}")

    return result


def monitor_workers(threads, results):
    """Periodically print worker status summary."""
    while any(t.is_alive() for t in threads):
        time.sleep(30)

        running = []
        completed = []
        failed = []

        for name, r in results.items():
            if r["status"] == "running":
                running.append(name)
            elif r["status"] == "success":
                completed.append(name)
            elif r["status"] in ("failed", "error"):
                failed.append(name)

        # Only print if there are still running workers
        if running:
            print(f"\n--- Status update ({datetime.now().strftime('%H:%M:%S')}) ---")
            print(f"  Running ({len(running)}): {', '.join(running)}")
            print(f"  Completed ({len(completed)}): {', '.join(completed)}")
            if failed:
                print(f"  FAILED ({len(failed)}): {', '.join(failed)}")
            print()


def main():
    """Main launcher."""
    print("\n" + "=" * 60)
    print("TRIPLE-CHECK DEDUPLICATION LAUNCHER")
    print("=" * 60)
    print(f"Started: {datetime.now()}")
    print(f"Workers: {len(WORKERS)}")
    print()

    # Create log directory
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    # Step 1: Validation
    if not run_validation():
        print("\nABORTING: Validation failed. Fix issues and retry.")
        sys.exit(1)

    # Step 2: Launch all workers
    print("=" * 60)
    print("STEP 2: Launching 12 workers...")
    print("=" * 60)
    print()

    results = {}
    threads = []
    start_time = time.time()

    def worker_thread(name, script, env, mem):
        r = launch_worker(name, script, env, mem)
        results[name] = r

    for name, script, env, mem in WORKERS:
        results[name] = {
            "name": name,
            "status": "running",
            "bucket_count": 0,
            "last_line": "",
        }
        t = threading.Thread(target=worker_thread, args=(name, script, env, mem))
        t.start()
        threads.append(t)
        print(f"  Launched: {name} ({env})")

    print(f"\nAll {len(WORKERS)} workers launched. Monitoring...\n")

    # Monitor thread
    monitor = threading.Thread(target=monitor_workers, args=(threads, results))
    monitor.daemon = True
    monitor.start()

    # Wait for all to complete
    for t in threads:
        t.join()

    total_elapsed = time.time() - start_time

    # Step 3: Summary
    print("\n" + "=" * 60)
    print("STEP 3: FINAL SUMMARY")
    print("=" * 60)
    print(f"Total elapsed: {total_elapsed:.1f}s ({total_elapsed/60:.1f}m)")
    print()

    all_success = True
    for name, _, _, _ in WORKERS:
        r = results.get(name, {"status": "unknown"})
        status = r.get("status", "unknown")
        elapsed = r.get("elapsed", 0)
        exit_code = r.get("exit_code", "?")
        buckets = r.get("bucket_count", "?")

        icon = {
            "success": "[OK]",
            "failed": "[FAIL]",
            "error": "[ERR]",
            "unknown": "[???]",
        }.get(status, "[???]")

        print(f"  {icon} {name:>14}: exit={exit_code}, "
              f"elapsed={elapsed:.0f}s, buckets={buckets}")

        if status != "success":
            all_success = False
            log_file = LOGS_DIR / f"worker_{name}.log"
            if log_file.exists():
                print(f"       Last lines of {log_file.name}:")
                lines = log_file.read_text().strip().split('\n')
                for line in lines[-10:]:
                    print(f"         {line}")

    print()
    if all_success:
        print("*** ALL WORKERS COMPLETED SUCCESSFULLY ***")
        print("\nNext step: python merge_tc_results.py")
    else:
        failed_workers = [name for name, _, _, _ in WORKERS
                         if results.get(name, {}).get("status") != "success"]
        print(f"*** {len(failed_workers)} WORKER(S) FAILED ***")
        print(f"Failed: {', '.join(failed_workers)}")
        print("Check logs/ directory for details")

    # Write summary JSON
    summary = {
        "timestamp": datetime.now().isoformat(),
        "total_elapsed_s": total_elapsed,
        "all_success": all_success,
        "workers": {name: {
            "status": results.get(name, {}).get("status", "unknown"),
            "exit_code": results.get(name, {}).get("exit_code"),
            "elapsed_s": results.get(name, {}).get("elapsed", 0),
        } for name, _, _, _ in WORKERS}
    }

    summary_path = DEDUPE_DIR / "launch_summary.json"
    with open(summary_path, 'w', encoding='utf-8') as f:
        json.dump(summary, f, indent=2)
    print(f"\nSummary written to: {summary_path}")

    sys.exit(0 if all_success else 1)


if __name__ == "__main__":
    main()
