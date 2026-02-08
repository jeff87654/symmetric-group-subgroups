#!/usr/bin/env python3
"""
validate_implementation.py - Pre-flight validation for deduplication implementations

Run this BEFORE starting any long deduplication computation to verify:
1. Required files exist
2. GAP scripts have correct syntax
3. Critical functions are implemented correctly
4. Ground truth test cases pass

Usage:
    python validate_implementation.py <implementation_dir>
    python validate_implementation.py  # Uses current directory

Example:
    python validate_implementation.py ../cross_dedup_v2
"""

import subprocess
import sys
import json
import re
from pathlib import Path
from datetime import datetime

# GAP executable
GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
TESTS_DIR = Path(__file__).parent


def run_gap_script(script_content: str, timeout: int = 120) -> tuple[int, str]:
    """Run GAP code and return (exit_code, output)."""
    import tempfile

    with tempfile.NamedTemporaryFile(mode='w', suffix='.g', delete=False, encoding='utf-8') as f:
        f.write(script_content)
        script_path = f.name

    # Convert to Cygwin path
    cygwin_path = script_path.replace('\\', '/').replace('C:', '/cygdrive/c')

    cmd = [GAP_BASH, "--login", "-c", f'/opt/gap-4.15.1/gap -q -o 4g "{cygwin_path}"']

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        return result.returncode, result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return -1, "TIMEOUT"
    except Exception as e:
        return -1, str(e)
    finally:
        Path(script_path).unlink(missing_ok=True)


def check_file_exists(impl_dir: Path, filename: str) -> tuple[bool, str]:
    """Check if a required file exists."""
    path = impl_dir / filename
    if path.exists():
        return True, f"Found: {filename}"
    return False, f"Missing: {filename}"


def check_gap_syntax(impl_dir: Path, script_name: str) -> tuple[bool, str]:
    """Check if a GAP script has valid syntax."""
    script_path = impl_dir / "scripts" / script_name
    if not script_path.exists():
        return False, f"Script not found: {script_name}"

    # Read first 100 lines and check for obvious syntax errors
    content = script_path.read_text(encoding='utf-8')

    # Check for common issues
    issues = []

    # Check balanced parentheses/brackets
    if content.count('(') != content.count(')'):
        issues.append("Unbalanced parentheses")
    if content.count('[') != content.count(']'):
        issues.append("Unbalanced brackets")
    if content.count('{') != content.count('}'):
        issues.append("Unbalanced braces")

    # Check for required functions
    if 'cross_dedupe_direct' in script_name:
        if 'CompareAllAmbiguousFactors' not in content:
            issues.append("Missing CompareAllAmbiguousFactors function")
        if 'RecNames' not in content:
            issues.append("Missing RecNames usage for factor iteration")

    if 'cross_dedupe_2groups' in script_name:
        if 'LoadPackage("anupq")' not in content and 'LoadPackage( "anupq" )' not in content:
            issues.append("Missing ANUPQ package load")
        if 'IsIsomorphicPGroup' not in content:
            issues.append("Missing IsIsomorphicPGroup")

    if issues:
        return False, f"{script_name}: " + ", ".join(issues)
    return True, f"{script_name}: Syntax OK"


def check_critical_algorithm(impl_dir: Path) -> tuple[bool, str]:
    """
    Test the critical multi-factor comparison algorithm.
    This is the bug that caused the a(14) undercount.
    """
    # Find the direct products script
    script_path = impl_dir / "scripts" / "cross_dedupe_direct.g"
    if not script_path.exists():
        return False, "cross_dedupe_direct.g not found"

    content = script_path.read_text(encoding='utf-8')

    # Extract the CompareAllAmbiguousFactors function
    match = re.search(
        r'CompareAllAmbiguousFactors\s*:=\s*function\s*\([^)]*\)(.*?)end;',
        content,
        re.DOTALL
    )

    if not match:
        return False, "Could not find CompareAllAmbiguousFactors function"

    func_body = match.group(1)

    # Check for critical patterns that indicate correct implementation
    checks = []

    # Must iterate over ALL names, not just first
    if 'for name1 in names1' in func_body or 'for name in names1' in func_body:
        checks.append(("Iterates over all factors", True))
    else:
        checks.append(("Iterates over all factors", False))

    # Must track matched factors
    if 'matched' in func_body.lower():
        checks.append(("Tracks matched factors", True))
    else:
        checks.append(("Tracks matched factors", False))

    # Must check that all factors matched
    if 'Length(matched)' in func_body or 'Length( matched )' in func_body:
        checks.append(("Verifies all factors matched", True))
    else:
        checks.append(("Verifies all factors matched", False))

    failed = [c[0] for c in checks if not c[1]]
    if failed:
        return False, "Algorithm issues: " + ", ".join(failed)

    return True, "Critical algorithm implementation looks correct"


def run_ground_truth_tests() -> tuple[bool, str]:
    """Run the ground truth test suite."""
    ground_truth_path = TESTS_DIR / "ground_truth_cases.g"

    if not ground_truth_path.exists():
        return False, "ground_truth_cases.g not found"

    # Create a test script
    cygwin_path = str(ground_truth_path).replace('\\', '/').replace('C:', '/cygdrive/c')

    test_script = f'''
Read("{cygwin_path}");
result := RunGroundTruthTests();
if result then
    Print("GROUND_TRUTH_PASSED\\n");
else
    Print("GROUND_TRUTH_FAILED\\n");
fi;
QUIT;
'''

    exit_code, output = run_gap_script(test_script, timeout=180)

    if "GROUND_TRUTH_PASSED" in output:
        # Count passed tests
        passed = output.count("PASS:")
        return True, f"Ground truth tests: {passed} passed"
    elif "GROUND_TRUTH_FAILED" in output:
        failed = output.count("FAIL:")
        return False, f"Ground truth tests: {failed} failed"
    else:
        return False, f"Ground truth test error: {output[:500]}"


def validate_implementation(impl_dir: Path) -> dict:
    """Run all validation checks on an implementation directory."""
    results = {
        'timestamp': datetime.now().isoformat(),
        'implementation_dir': str(impl_dir),
        'checks': [],
        'passed': 0,
        'failed': 0,
        'overall': False
    }

    print("=" * 60)
    print("IMPLEMENTATION VALIDATION")
    print("=" * 60)
    print(f"Directory: {impl_dir}")
    print(f"Timestamp: {results['timestamp']}")
    print()

    # Check 1: Required directories
    print("--- Checking directory structure ---")
    for subdir in ['scripts', 'results', 'logs']:
        path = impl_dir / subdir
        if path.exists():
            print(f"  OK: {subdir}/")
            results['checks'].append({'name': f'dir_{subdir}', 'passed': True})
            results['passed'] += 1
        else:
            print(f"  MISSING: {subdir}/")
            results['checks'].append({'name': f'dir_{subdir}', 'passed': False})
            results['failed'] += 1
    print()

    # Check 2: Required files
    print("--- Checking required files ---")
    required_files = [
        'bucket_assignments.json',
        'combined_s13_s14.g'
    ]
    for filename in required_files:
        passed, msg = check_file_exists(impl_dir, filename)
        print(f"  {'OK' if passed else 'FAIL'}: {msg}")
        results['checks'].append({'name': f'file_{filename}', 'passed': passed})
        if passed:
            results['passed'] += 1
        else:
            results['failed'] += 1
    print()

    # Check 3: GAP script syntax
    print("--- Checking GAP script syntax ---")
    scripts = [
        'cross_dedupe_direct.g',
        'cross_dedupe_2groups.g',
        'cross_dedupe_bucket_1.g'
    ]
    for script in scripts:
        passed, msg = check_gap_syntax(impl_dir, script)
        print(f"  {'OK' if passed else 'FAIL'}: {msg}")
        results['checks'].append({'name': f'syntax_{script}', 'passed': passed})
        if passed:
            results['passed'] += 1
        else:
            results['failed'] += 1
    print()

    # Check 4: Critical algorithm
    print("--- Checking critical algorithm (multi-factor bug fix) ---")
    passed, msg = check_critical_algorithm(impl_dir)
    print(f"  {'OK' if passed else 'FAIL'}: {msg}")
    results['checks'].append({'name': 'critical_algorithm', 'passed': passed})
    if passed:
        results['passed'] += 1
    else:
        results['failed'] += 1
    print()

    # Check 5: Ground truth tests
    print("--- Running ground truth tests ---")
    passed, msg = run_ground_truth_tests()
    print(f"  {'OK' if passed else 'FAIL'}: {msg}")
    results['checks'].append({'name': 'ground_truth', 'passed': passed})
    if passed:
        results['passed'] += 1
    else:
        results['failed'] += 1
    print()

    # Summary
    print("=" * 60)
    print("VALIDATION SUMMARY")
    print("=" * 60)
    print(f"Passed: {results['passed']}")
    print(f"Failed: {results['failed']}")

    results['overall'] = results['failed'] == 0

    if results['overall']:
        print("\n>>> VALIDATION PASSED - Safe to run computation <<<")
    else:
        print("\n>>> VALIDATION FAILED - Fix issues before running <<<")

    # Save results
    results_path = impl_dir / 'validation_results.json'
    with open(results_path, 'w') as f:
        json.dump(results, f, indent=2)
    print(f"\nResults saved to: {results_path}")

    return results


def main():
    if len(sys.argv) > 1:
        impl_dir = Path(sys.argv[1])
    else:
        impl_dir = Path.cwd()

    if not impl_dir.exists():
        print(f"Error: Directory not found: {impl_dir}")
        sys.exit(1)

    results = validate_implementation(impl_dir)
    sys.exit(0 if results['overall'] else 1)


if __name__ == "__main__":
    main()
