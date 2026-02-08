#!/usr/bin/env python3
"""Precompute S14 conjugacy classes with aggressive garbage collection."""

import subprocess
import sys
import os
from pathlib import Path

def windows_to_cygwin_path(win_path: str) -> str:
    path = str(win_path).replace('\\', '/')
    if len(path) >= 2 and path[1] == ':':
        drive = path[0].lower()
        path = f'/cygdrive/{drive}{path[2:]}'
    return path

output_dir = Path(r'C:\Users\jeffr\Downloads\Symmetric Groups')
cache_dir = output_dir / 'conjugacy_cache'
cache_dir.mkdir(exist_ok=True)

cache_file = cache_dir / 's14_subgroups.g'
cache_file_cygwin = windows_to_cygwin_path(str(cache_file))

gap_script = f'''
# Precompute S14 conjugacy classes with aggressive garbage collection
# Working memory limited to 2^34 (16GB), total allowed 50GB

Print("Starting S14 conjugacy class precomputation...\\n");
Print("Setting up aggressive garbage collection...\\n");

# Show garbage collection messages
SetGasmanMessageStatus("full");

# Enable info messages for subgroup lattice computation
SetInfoLevel(InfoGroup, 2);
SetInfoLevel(InfoLattice, 2);

# Force garbage collection before starting
GASMAN("collect");
Print("Initial memory: ", GasmanStatistics(), "\\n");

Print("Computing conjugacy classes of subgroups of S14...\\n");
Print("This will take a long time. Progress will be shown via Info messages.\\n");
Print("Note: GAP uses a cyclic extension algorithm - it builds subgroups level by level.\\n");

# Compute with periodic GC
startTime := Runtime();
G := SymmetricGroup(14);
Print("Created S14, elapsed: ", Runtime() - startTime, " ms\\n");
Print("Order of S14: ", Size(G), " = 14! = ", Factorial(14), "\\n");
GASMAN("collect");

# Compute conjugacy classes - this is the long step
Print("\\n=== Starting conjugacy class computation ===\\n");
Print("Using LowIndexSubgroupsFpGroup approach for progress...\\n");
ccs := ConjugacyClassesSubgroups(G);
Print("\\n=== Computation complete ===\\n");
Print("Computed ", Length(ccs), " conjugacy classes\\n");
GASMAN("collect");

# Extract representatives and save
Print("Extracting representatives...\\n");
reps := List(ccs, Representative);
Print("Got ", Length(reps), " representatives\\n");
GASMAN("collect");

# Save to file
Print("Saving to file: {cache_file_cygwin}\\n");
output := OutputTextFile("{cache_file_cygwin}", false);
SetPrintFormattingStatus(output, false);
PrintTo(output, "# S14 conjugacy class representatives\\n");
PrintTo(output, "# Generated with aggressive GC\\n");
PrintTo(output, "return [\\n");
for i in [1..Length(reps)] do
    H := reps[i];
    if i > 1 then
        PrintTo(output, ",\\n");
    fi;
    PrintTo(output, "Group(", GeneratorsOfGroup(H), ")");
    if i mod 1000 = 0 then
        Print("  Saved ", i, "/", Length(reps), " subgroups\\n");
        GASMAN("collect");
    fi;
od;
PrintTo(output, "\\n];\\n");
CloseStream(output);

endTime := Runtime();
Print("\\nCompleted in ", (endTime - startTime) / 1000.0, " seconds\\n");
Print("Saved ", Length(reps), " subgroups to ", "{cache_file_cygwin}", "\\n");
QUIT;
'''

# Write GAP script
script_file = output_dir / 'precompute_s14.g'
with open(script_file, 'w') as f:
    f.write(gap_script)

print(f"GAP script written to: {script_file}")
print("Starting S14 precomputation with:")
print("  - Working memory limit: 16GB (2^34)")
print("  - Max memory: 50GB")
print("  - Aggressive garbage collection enabled")
print()

# Run GAP with memory settings
gap_script_cygwin = windows_to_cygwin_path(str(script_file))
gap_bash = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"

# Use -o 50g for 50GB max, no -m to use default initial
# Use -K 16g to limit GAP workspace to 16GB (forces more frequent GC)
cmd = f'/opt/gap-4.15.1/gap -o 50g -K 16g -q "{gap_script_cygwin}"'

print(f"Command: {cmd}")
print("=" * 60)

process = subprocess.Popen(
    [gap_bash, '--login', '-c', cmd],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    cwd=r"C:\Program Files\GAP-4.15.1\runtime\bin"
)

for line in iter(process.stdout.readline, ''):
    print(line, end='')
    sys.stdout.flush()

process.wait()
print(f"\nDone with exit code: {process.returncode}")
