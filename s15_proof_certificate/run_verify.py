"""
Run verify_a174511_15.g - full verification of A174511(15) = 16,438 and A000638(15) = 159,129
Phase B: IdGroup + orbit structure + proof verification (~10 min)
Phase A: Invariant recomputation (~28 min)
Phase C: Non-isomorphism verification (~2 min)
Phase D: Conjugacy class completeness (~5-15 min)
"""

import subprocess
from datetime import datetime

GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
SCRIPT = "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s15_proof_certificate/verify_a174511_15.g"
OUTPUT_LOG = r"C:\Users\jeffr\Downloads\Symmetric Groups\s15_proof_certificate\verify_output_final.txt"

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
