#!/usr/bin/env python3
"""
Test Runner for Deduplication Verification Tests

Runs all GAP test scripts and collects results into a JSON file.
Separates WSL-only tests (ANUPQ) from Cygwin-compatible tests.

Usage:
    python run_all_tests.py [--wsl-only] [--cygwin-only] [--all]
"""

import subprocess
import sys
import os
import json
from datetime import datetime
from pathlib import Path

# Configuration
GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
BASE_PATH = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups\Partition\tests")
CYGWIN_PATH = "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/Partition/tests"
WSL_PATH = "/mnt/c/Users/jeffr/Downloads/Symmetric Groups/Partition/tests"

# Test files categorized by environment
CYGWIN_TESTS = [
    ("test_factor_comparison.g", "Factor Comparison Tests"),
    ("test_bucket54_regression.g", "Bucket 54 Regression Test"),
    ("test_deduplication_integration.g", "Deduplication Integration Tests"),
]

# Quick tests - only the most critical ones
QUICK_TESTS = [
    ("test_factor_comparison.g", "Factor Comparison Tests"),
    ("test_bucket54_regression.g", "Bucket 54 Regression Test"),
]

WSL_TESTS = [
    ("test_anupq_comprehensive.g", "ANUPQ Comprehensive Tests"),
    ("test_anupq_real_data.g", "ANUPQ Real Data Tests"),
]


def run_gap_cygwin(script_name: str, description: str) -> dict:
    """Run a GAP script via Cygwin GAP."""
    script_path = f"{CYGWIN_PATH}/{script_name}"
    output_file = BASE_PATH / f"{Path(script_name).stem}_output.txt"

    print(f"\n{'='*60}")
    print(f"Running: {description}")
    print(f"Script: {script_name}")
    print(f"{'='*60}")

    cmd = [GAP_BASH, "--login", "-c", f'/opt/gap-4.15.1/gap -q -o 8g "{script_path}"']

    result = {
        "script": script_name,
        "description": description,
        "environment": "cygwin",
        "start_time": datetime.now().isoformat(),
        "status": "unknown",
        "exit_code": None,
        "output_file": str(output_file),
    }

    try:
        with open(output_file, "w", encoding="utf-8") as out:
            out.write(f"# Started at {datetime.now()}\n")
            out.write(f"# Script: {script_name}\n\n")

            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )

            for line in proc.stdout:
                print(line, end='')
                out.write(line)
                out.flush()

            proc.wait()

            out.write(f"\n# Finished at {datetime.now()}\n")
            out.write(f"# Exit code: {proc.returncode}\n")

            result["exit_code"] = proc.returncode
            result["status"] = "success" if proc.returncode == 0 else "failed"

    except Exception as e:
        result["status"] = "error"
        result["error"] = str(e)
        print(f"ERROR: {e}")

    result["end_time"] = datetime.now().isoformat()
    return result


def run_gap_wsl(script_name: str, description: str) -> dict:
    """Run a GAP script via WSL."""
    script_path = f"{WSL_PATH}/{script_name}"
    output_file = BASE_PATH / f"{Path(script_name).stem}_output.txt"

    print(f"\n{'='*60}")
    print(f"Running: {description} (WSL)")
    print(f"Script: {script_name}")
    print(f"{'='*60}")

    cmd = ["wsl", "gap", "-q", "-o", "8g", script_path]

    result = {
        "script": script_name,
        "description": description,
        "environment": "wsl",
        "start_time": datetime.now().isoformat(),
        "status": "unknown",
        "exit_code": None,
        "output_file": str(output_file),
    }

    try:
        with open(output_file, "w", encoding="utf-8") as out:
            out.write(f"# Started at {datetime.now()}\n")
            out.write(f"# Script: {script_name} (WSL)\n\n")

            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )

            for line in proc.stdout:
                print(line, end='')
                out.write(line)
                out.flush()

            proc.wait()

            out.write(f"\n# Finished at {datetime.now()}\n")
            out.write(f"# Exit code: {proc.returncode}\n")

            result["exit_code"] = proc.returncode
            result["status"] = "success" if proc.returncode == 0 else "failed"

    except FileNotFoundError:
        result["status"] = "skipped"
        result["error"] = "WSL not available"
        print("WARNING: WSL not available, skipping this test")
    except Exception as e:
        result["status"] = "error"
        result["error"] = str(e)
        print(f"ERROR: {e}")

    result["end_time"] = datetime.now().isoformat()
    return result


def parse_result_file(result_file: Path) -> dict:
    """Parse a GAP result file to extract pass/fail counts."""
    try:
        with open(result_file, "r", encoding="utf-8") as f:
            content = f.read()

        # Extract pass/fail counts using simple parsing
        parsed = {}

        # Look for passCount := X
        if "passCount :=" in content:
            start = content.find("passCount :=") + len("passCount :=")
            end = content.find(",", start)
            if end == -1:
                end = content.find("\n", start)
            parsed["passCount"] = int(content[start:end].strip())

        # Look for failCount := X
        if "failCount :=" in content:
            start = content.find("failCount :=") + len("failCount :=")
            end = content.find(",", start)
            if end == -1:
                end = content.find("\n", start)
            parsed["failCount"] = int(content[start:end].strip())

        # Look for errorCount := X
        if "errorCount :=" in content:
            start = content.find("errorCount :=") + len("errorCount :=")
            end = content.find(",", start)
            if end == -1:
                end = content.find("\n", start)
            parsed["errorCount"] = int(content[start:end].strip())

        return parsed
    except Exception as e:
        return {"error": str(e)}


def main():
    """Main test runner."""
    args = sys.argv[1:]

    run_cygwin = True
    run_wsl = True
    quick_mode = "--quick" in args
    cygwin_tests_to_run = QUICK_TESTS if quick_mode else CYGWIN_TESTS

    if "--wsl-only" in args:
        run_cygwin = False
    elif "--cygwin-only" in args:
        run_wsl = False
    # --all is default behavior

    if quick_mode:
        run_wsl = False  # Quick mode skips WSL tests

    print("\n" + "="*60)
    print("DEDUPLICATION VERIFICATION TEST SUITE")
    print("="*60)
    print(f"Started: {datetime.now()}")
    print(f"Base path: {BASE_PATH}")

    all_results = {
        "run_time": datetime.now().isoformat(),
        "tests": [],
        "summary": {
            "total_tests": 0,
            "passed": 0,
            "failed": 0,
            "errors": 0,
            "skipped": 0,
        }
    }

    # Run Cygwin tests
    if run_cygwin:
        print("\n" + "-"*60)
        print("CYGWIN TESTS")
        print("-"*60)

        for script, desc in cygwin_tests_to_run:
            result = run_gap_cygwin(script, desc)
            all_results["tests"].append(result)

            # Parse result file if available
            # Map script names to result file names
            result_file_map = {
                "test_factor_comparison.g": "factor_results.txt",
                "test_bucket54_regression.g": "bucket54_regression_result.txt",
                "test_deduplication_integration.g": "integration_results.txt",
            }
            result_file_name = result_file_map.get(script, "")
            if result_file_name:
                result_file = BASE_PATH / result_file_name
                if result_file.exists():
                    parsed = parse_result_file(result_file)
                    result["parsed"] = parsed
                    if "passCount" in parsed:
                        all_results["summary"]["passed"] += parsed["passCount"]
                    if "failCount" in parsed:
                        all_results["summary"]["failed"] += parsed["failCount"]
                    if "errorCount" in parsed:
                        all_results["summary"]["errors"] += parsed.get("errorCount", 0)

    # Run WSL tests
    if run_wsl:
        print("\n" + "-"*60)
        print("WSL TESTS (ANUPQ)")
        print("-"*60)

        for script, desc in WSL_TESTS:
            result = run_gap_wsl(script, desc)
            all_results["tests"].append(result)

            if result["status"] == "skipped":
                all_results["summary"]["skipped"] += 1
            else:
                # Parse result file if available
                result_file_map = {
                    "test_anupq_comprehensive.g": "anupq_results.txt",
                    "test_anupq_real_data.g": "anupq_real_data_results.txt",
                }
                result_file_name = result_file_map.get(script, "")
                if result_file_name:
                    result_file = BASE_PATH / result_file_name
                    if result_file.exists():
                        parsed = parse_result_file(result_file)
                        result["parsed"] = parsed
                        if "passCount" in parsed:
                            all_results["summary"]["passed"] += parsed["passCount"]
                        if "failCount" in parsed:
                            all_results["summary"]["failed"] += parsed["failCount"]
                        if "errorCount" in parsed:
                            all_results["summary"]["errors"] += parsed.get("errorCount", 0)

    # Calculate totals
    all_results["summary"]["total_tests"] = (
        all_results["summary"]["passed"] +
        all_results["summary"]["failed"] +
        all_results["summary"]["errors"]
    )

    # Write JSON results
    json_file = BASE_PATH / "test_results.json"
    with open(json_file, "w", encoding="utf-8") as f:
        json.dump(all_results, f, indent=2)

    # Print summary
    print("\n" + "="*60)
    print("FINAL SUMMARY")
    print("="*60)

    s = all_results["summary"]
    print(f"Total tests run: {s['total_tests']}")
    print(f"  Passed:  {s['passed']}")
    print(f"  Failed:  {s['failed']}")
    print(f"  Errors:  {s['errors']}")
    print(f"  Skipped: {s['skipped']}")

    print(f"\nResults written to: {json_file}")

    # Per-script summary
    print("\nPer-script results:")
    for test in all_results["tests"]:
        status_icon = {
            "success": "[OK]",
            "failed": "[FAIL]",
            "error": "[ERR]",
            "skipped": "[SKIP]",
            "unknown": "[???]",
        }.get(test["status"], "[???]")

        parsed = test.get("parsed", {})
        if parsed:
            print(f"  {status_icon} {test['description']}: "
                  f"{parsed.get('passCount', '?')} pass, "
                  f"{parsed.get('failCount', '?')} fail")
        else:
            print(f"  {status_icon} {test['description']}")

    print(f"\nCompleted: {datetime.now()}")

    # Exit with error code if any tests failed
    if s["failed"] > 0 or s["errors"] > 0:
        return 1
    return 0


def run_validation(impl_dir: str) -> int:
    """Run validation on an implementation directory."""
    from validate_implementation import validate_implementation
    results = validate_implementation(Path(impl_dir))
    return 0 if results['overall'] else 1


def print_help():
    """Print usage help."""
    print("""
Deduplication Verification Test Suite
=====================================

Usage:
    python run_all_tests.py [options]

Options:
    --cygwin-only     Run only Cygwin-compatible tests (no ANUPQ)
    --wsl-only        Run only WSL tests (ANUPQ)
    --all             Run all tests (default)
    --validate <dir>  Validate an implementation directory before running
    --quick           Run only critical tests (factor comparison + bucket 54)
    --help            Show this help message

Examples:
    python run_all_tests.py --cygwin-only
    python run_all_tests.py --validate ../cross_dedup_v2
    python run_all_tests.py --quick

The --validate option checks:
    - Required directories and files exist
    - GAP script syntax is valid
    - Critical algorithm (multi-factor bug fix) is implemented correctly
    - Ground truth test cases pass
""")


if __name__ == "__main__":
    # Handle special options
    if "--help" in sys.argv or "-h" in sys.argv:
        print_help()
        sys.exit(0)

    if "--validate" in sys.argv:
        idx = sys.argv.index("--validate")
        if idx + 1 < len(sys.argv):
            impl_dir = sys.argv[idx + 1]
            sys.exit(run_validation(impl_dir))
        else:
            print("Error: --validate requires a directory argument")
            sys.exit(1)

    sys.exit(main())
