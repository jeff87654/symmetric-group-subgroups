"""Launch S16 proof validation in GAP.

Validates all 154,663 proofs in s16_master_proofs_repaired_v2.g
against the actual s16_subgroups.g conjugacy class representatives.

Each proof is checked to be a valid bijective homomorphism (isomorphism)
between the duplicate group and its representative.
"""
import subprocess
from datetime import datetime

GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
script_path = "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s16_dedupe/proofs/validate_s16_proofs.g"
output_file = r"C:\Users\jeffr\Downloads\Symmetric Groups\s16_dedupe\proofs\validation_output.txt"

cmd = [GAP_BASH, "--login", "-c",
       f'/opt/gap-4.15.1/gap -q -o 16g "{script_path}"']

print(f"Starting S16 proof validation at {datetime.now()}")
print(f"Output: {output_file}")
print()

with open(output_file, "w") as out:
    out.write(f"# S16 Proof Validation\n")
    out.write(f"# Started at {datetime.now()}\n\n")
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, bufsize=1)
    for line in proc.stdout:
        print(line, end='')
        out.write(line)
        out.flush()
    proc.wait()
    out.write(f"\n# Finished at {datetime.now()}\n")
    out.write(f"# Exit code: {proc.returncode}\n")

print(f"\nFinished at {datetime.now()}")
print(f"Exit code: {proc.returncode}")
