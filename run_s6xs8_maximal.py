import subprocess
import sys

gap_bash = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
script_path = "/cygdrive/c/Users/jeffr/Downloads/Loops/s14_s6xs8_maximal.g"
cmd = f'/opt/gap-4.15.1/gap -q -o 50g {script_path}'

print("S6 x S8 via Maximal Subgroups")
print("=" * 60)
print("This processes S6 x S8 by computing subgroups of each")
print("maximal subgroup separately, with checkpointing after each.")
print()
print("Checkpoint file: s6xs8_checkpoint.txt")
print("=" * 60)
print()
sys.stdout.flush()

process = subprocess.Popen(
    [gap_bash, '--login', '-c', cmd],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    cwd=r"C:\Program Files\GAP-4.15.1\runtime\bin"
)

with open(r"c:\Users\jeffr\Downloads\Loops\gap_output_s6xs8.txt", "w") as f:
    for line in iter(process.stdout.readline, ''):
        print(line, end='')
        f.write(line)
        f.flush()
        sys.stdout.flush()

process.wait()
print(f"\nProcess completed with return code: {process.returncode}")
