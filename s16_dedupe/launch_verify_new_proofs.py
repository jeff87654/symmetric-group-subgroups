"""
Launch GAP to verify new proofs from staging file.
Writes output to verify_new_proofs_output.txt.
"""

import subprocess
from datetime import datetime

GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
SCRIPT = "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s16_dedupe/verify_new_proofs.g"
OUTPUT = r"C:\Users\jeffr\Downloads\Symmetric Groups\s16_dedupe\verify_new_proofs_output.txt"

cmd = [GAP_BASH, "--login", "-c", f'/opt/gap-4.15.1/gap -q -o 8g "{SCRIPT}"']

print(f"Launching GAP verification...")
print(f"Script: {SCRIPT}")
print(f"Output: {OUTPUT}")
print()

with open(OUTPUT, "w") as out:
    out.write(f"# Started at {datetime.now()}\n\n")
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, bufsize=1)
    for line in proc.stdout:
        print(line, end='')
        out.write(line)
        out.flush()
    proc.wait()
    out.write(f"\n# Finished at {datetime.now()}\n")
    out.write(f"# Exit code: {proc.returncode}\n")

print(f"\nExit code: {proc.returncode}")
print(f"Output saved to: {OUTPUT}")
