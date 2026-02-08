#!/usr/bin/env python3
"""
Precompute and cache conjugacy classes of subgroups for Sn.
This allows the main enumeration to skip the expensive ConjugacyClassesSubgroups computation.
"""

import subprocess
import sys
import argparse
from pathlib import Path


def windows_to_cygwin_path(win_path: str) -> str:
    """Convert Windows path to Cygwin path."""
    path = str(win_path).replace('\\', '/')
    if len(path) >= 2 and path[1] == ':':
        drive = path[0].lower()
        path = f'/cygdrive/{drive}{path[2:]}'
    return path


def generate_precompute_script(n: int, cache_dir: str) -> str:
    """Generate GAP script to compute and save conjugacy classes for Sn."""
    return f'''
# Precompute conjugacy classes for S{n}
# This can be run in advance to speed up the main enumeration

n := {n};
cacheDir := "{cache_dir}";

Print("Computing conjugacy classes for S", n, "...\\n");
Print("This may take a while for large n.\\n");

startTime := Runtime();

Sn := SymmetricGroup(n);
subgroupClasses := ConjugacyClassesSubgroups(Sn);
nSubgroups := Length(subgroupClasses);

elapsed := Float(Runtime() - startTime) / 1000.0;
Print("Found ", nSubgroups, " conjugacy classes in ", elapsed, " seconds\\n");

# Save to file
filename := Concatenation(cacheDir, "s", String(n), "_subgroups.g");
Print("Saving to ", filename, "...\\n");

output := OutputTextFile(filename, false);
SetPrintFormattingStatus(output, false);
PrintTo(output, "# Conjugacy class representatives for S", n, "\\n");
PrintTo(output, "# ", nSubgroups, " subgroups\\n");
PrintTo(output, "# Computed in ", elapsed, " seconds\\n");
PrintTo(output, "return [\\n");

for i in [1..nSubgroups] do
    H := Representative(subgroupClasses[i]);
    gens := List(GeneratorsOfGroup(H), p -> ListPerm(p, n));
    PrintTo(output, "  ", gens);
    if i < nSubgroups then
        PrintTo(output, ",");
    fi;
    PrintTo(output, "\\n");

    # Progress
    if i mod 1000 = 0 then
        Print("  Saved ", i, "/", nSubgroups, " subgroups\\n");
    fi;
od;

PrintTo(output, "];\\n");
CloseStream(output);

Print("Done! Saved ", nSubgroups, " subgroups to ", filename, "\\n");

QUIT;
'''


def main():
    parser = argparse.ArgumentParser(
        description='Precompute conjugacy classes for Sn'
    )
    parser.add_argument('n', type=int, help='Compute for Sn')
    parser.add_argument('--output-dir', type=str, default='.',
                       help='Output directory (default: current directory)')

    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    cache_dir = output_dir / 'conjugacy_cache'
    cache_dir.mkdir(parents=True, exist_ok=True)

    cache_dir_cygwin = windows_to_cygwin_path(cache_dir) + '/'

    print(f"Precomputing conjugacy classes for S{args.n}")
    print(f"Cache directory: {cache_dir}")
    print("=" * 60)
    sys.stdout.flush()

    # Generate and save GAP script
    gap_code = generate_precompute_script(args.n, cache_dir_cygwin)
    gap_script = output_dir / f'precompute_s{args.n}.g'

    with open(gap_script, 'w', encoding='utf-8') as f:
        f.write(gap_code)

    print(f"GAP script written to: {gap_script}")
    print("Running GAP...")
    print("=" * 60)
    sys.stdout.flush()

    # Run GAP
    gap_bash = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
    gap_script_cygwin = windows_to_cygwin_path(gap_script)
    cmd = f'/opt/gap-4.15.1/gap -q "{gap_script_cygwin}"'

    process = subprocess.Popen(
        [gap_bash, '--login', '-c', cmd],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        cwd=r"C:\Program Files\GAP-4.15.1\runtime\bin"
    )

    # Stream output
    for line in iter(process.stdout.readline, ''):
        print(line, end='')
        sys.stdout.flush()

    process.wait()
    print(f"\nProcess completed with return code: {process.returncode}")


if __name__ == '__main__':
    main()
