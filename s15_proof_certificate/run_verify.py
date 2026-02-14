"""
Run verify_a174511_15.g - full verification of A174511(15) = 16,438 and A000638(15) = 159,129
Phase B: IdGroup + orbit structure + proof verification (~13 min)
Phase A: Invariant recomputation (~24 min)          [--skip-invariants to skip]
Phase C: Non-isomorphism verification (~2 min)
Phase D: Conjugacy class completeness (~43 min)     [--skip-conjugacy to skip]
"""

import argparse
import subprocess
from datetime import datetime

GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
SCRIPT = "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s15_proof_certificate/verify_a174511_15.g"
OUTPUT_LOG = r"C:\Users\jeffr\Downloads\Symmetric Groups\s15_proof_certificate\verify_output_final.txt"

parser = argparse.ArgumentParser(description="Run A174511(15) verification")
parser.add_argument("--skip-invariants", action="store_true",
                    help="Skip Phase A (fingerprint invariant recomputation)")
parser.add_argument("--skip-conjugacy", action="store_true",
                    help="Skip Phase D (non-conjugacy verification)")
args = parser.parse_args()

# Build GAP preamble to set flags before loading the script
preamble = ""
if args.skip_invariants:
    preamble += "RUN_PHASE_A := false; "
    print("NOTE: Skipping Phase A (invariant verification)")
if args.skip_conjugacy:
    preamble += "RUN_PHASE_D := false; "
    print("NOTE: Skipping Phase D (non-conjugacy verification)")

if preamble:
    gap_cmd = f'{preamble}Read("{SCRIPT}");'
    cmd = [GAP_BASH, "--login", "-c", f'/opt/gap-4.15.1/gap -q -o 30g -c \'{gap_cmd}\'']
else:
    cmd = [GAP_BASH, "--login", "-c", f'/opt/gap-4.15.1/gap -q -o 30g "{SCRIPT}"']

print(f"Starting verification at {datetime.now()}")
print(f"Log: {OUTPUT_LOG}")

with open(OUTPUT_LOG, "w") as out:
    out.write(f"# Started at {datetime.now()}\n\n")
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    for line in proc.stdout:
        print(line, end='')
        out.write(line)
        out.flush()
    proc.wait()
    out.write(f"\n# Finished at {datetime.now()}\n")
    out.write(f"# Exit code: {proc.returncode}\n")

print(f"\nFinished at {datetime.now()}")
print(f"Exit code: {proc.returncode}")
