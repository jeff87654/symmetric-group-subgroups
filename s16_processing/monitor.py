#!/usr/bin/env python3
"""
Monitor S16 processing progress. Updates every 60 seconds.
Reads worker checkpoint files to estimate progress and ETA.
"""

import re
import sys
import time
from pathlib import Path
from datetime import datetime, timedelta

BASE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups")
CHECKPOINTS_DIR = BASE_DIR / "s16_processing" / "checkpoints"

NUM_WORKERS = 8
EXPECTED_TOTAL = 686165


def count_idgroups(filepath):
    """Count IdGroup entries in a worker file"""
    if not filepath.exists():
        return 0
    count = 0
    with open(filepath, 'r') as f:
        for line in f:
            if line.startswith('S16_IDGROUP_MAP['):
                count += 1
    return count


def count_large_groups(filepath):
    """Count large group records in a worker file"""
    if not filepath.exists():
        return 0
    count = 0
    with open(filepath, 'r') as f:
        for line in f:
            if line.strip().startswith('rec('):
                count += 1
    return count


def get_last_progress_line(filepath):
    """Get the last progress report line from worker output"""
    if not filepath.exists():
        return None
    last = None
    with open(filepath, 'r') as f:
        for line in f:
            if 'rate=' in line:
                last = line.strip()
    return last


def check_complete(filepath):
    """Check if a worker has completed"""
    if not filepath.exists():
        return False, None
    with open(filepath, 'r') as f:
        content = f.read()
    if 'COMPLETE' in content:
        # Extract exit code
        match = re.search(r'Exit code: (\d+)', content)
        code = int(match.group(1)) if match else None
        return True, code
    return False, None


def main():
    print(f"S16 Processing Monitor")
    print(f"Expected total: {EXPECTED_TOTAL:,} groups across {NUM_WORKERS} workers")
    print(f"Press Ctrl+C to stop monitoring\n")

    start_time = datetime.now()
    prev_total = 0
    prev_time = start_time

    try:
        while True:
            now = datetime.now()
            total_idg = 0
            total_large = 0
            total_iso = 0
            all_complete = True
            worker_lines = []

            for wid in range(1, NUM_WORKERS + 1):
                idg_file = CHECKPOINTS_DIR / f"worker_{wid}_idgroups.g"
                large_file = CHECKPOINTS_DIR / f"worker_{wid}_large.g"
                output_file = CHECKPOINTS_DIR / f"worker_{wid}_output.txt"

                idg = count_idgroups(idg_file)
                large = count_large_groups(large_file)
                total = idg + large

                complete, exit_code = check_complete(output_file)
                if not complete:
                    all_complete = False

                # Count isomorphicTo in large file
                iso = 0
                if large_file.exists():
                    with open(large_file, 'r') as f:
                        for line in f:
                            if 'isomorphicTo' in line:
                                iso += 1

                total_idg += idg
                total_large += large
                total_iso += iso

                status = ""
                if complete:
                    status = f" DONE (exit {exit_code})" if exit_code == 0 else f" FAILED ({exit_code})"
                else:
                    last = get_last_progress_line(output_file)
                    if last:
                        rate_match = re.search(r'rate=(\d+)', last)
                        if rate_match:
                            status = f" {rate_match.group(0)} g/s"

                worker_lines.append(
                    f"  W{wid}: {total:>7,} ({idg:>6,} idg + {large:>6,} lg){status}"
                )

            grand_total = total_idg + total_large
            pct = grand_total / EXPECTED_TOTAL * 100

            # Compute rate over last interval
            elapsed_interval = (now - prev_time).total_seconds()
            if elapsed_interval > 0 and prev_total > 0:
                rate = (grand_total - prev_total) / elapsed_interval
            else:
                rate = 0

            elapsed_total = (now - start_time).total_seconds()
            if grand_total > 0 and elapsed_total > 0:
                avg_rate = grand_total / elapsed_total
                remaining = EXPECTED_TOTAL - grand_total
                if avg_rate > 0:
                    eta_seconds = remaining / avg_rate
                    eta = now + timedelta(seconds=eta_seconds)
                    eta_str = f"ETA {eta.strftime('%H:%M:%S')} ({eta_seconds/3600:.1f}h)"
                else:
                    eta_str = "ETA unknown"
            else:
                eta_str = "ETA calculating..."

            # Clear screen and print
            print(f"\033[2J\033[H", end="")  # clear screen
            print(f"S16 Processing Monitor — {now.strftime('%Y-%m-%d %H:%M:%S')}")
            print(f"{'=' * 65}")
            print(f"Progress: {grand_total:>9,} / {EXPECTED_TOTAL:,}  ({pct:5.1f}%)")
            print(f"IdGroups: {total_idg:>9,}   Large: {total_large:>7,}   isomorphicTo: {total_iso:>6,}")
            if rate > 0:
                print(f"Rate: {rate:,.0f} groups/sec (interval)   {avg_rate:,.0f} groups/sec (avg)")
            print(f"{eta_str}")
            print(f"{'=' * 65}")
            for line in worker_lines:
                print(line)
            print(f"{'=' * 65}")

            if all_complete:
                print(f"\nAll workers COMPLETE!")
                print(f"Total: {grand_total:,} (idg={total_idg:,} + large={total_large:,})")
                if grand_total == EXPECTED_TOTAL:
                    print(f"Coverage: PASSED")
                else:
                    print(f"Coverage: MISMATCH (expected {EXPECTED_TOTAL:,}, diff={EXPECTED_TOTAL - grand_total})")
                print(f"\nRun: python s16_processing/merge_s16_results.py")
                break

            prev_total = grand_total
            prev_time = now
            time.sleep(60)

    except KeyboardInterrupt:
        print(f"\n\nMonitoring stopped. Workers are still running.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
