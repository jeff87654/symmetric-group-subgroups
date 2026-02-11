import subprocess
from datetime import datetime

GAP_BASH = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
script_path = "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s14_final/verification/verify_a174511_14.g"
output_file = r"C:\Users\jeffr\Downloads\Symmetric Groups\s14_final\verification\verify_output_phaseD_v2.txt"

cmd = [GAP_BASH, "--login", "-c", f'/opt/gap-4.15.1/gap -q -o 20g "{script_path}"']

print(f"Starting A174511(14) verification at {datetime.now()}")
print(f"Output: {output_file}")

with open(output_file, "w") as out:
    out.write(f"# Started at {datetime.now()}\n\n")
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    for line in proc.stdout:
        print(line, end='')
        out.write(line)
        out.flush()
    proc.wait()
    out.write(f"\n# Finished at {datetime.now()}\n")
    out.write(f"# Exit code: {proc.returncode}\n")

print(f"\nFinished at {datetime.now()} with exit code {proc.returncode}")
