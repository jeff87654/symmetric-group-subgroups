"""Re-launch the 2-group verification worker via WSL."""
import subprocess, os, datetime

QUAD_DIR = r'C:\Users\jeffr\Downloads\Symmetric Groups\triple_check\quad_check'
script_path = os.path.join(QUAD_DIR, '_verify_2groups_1.g')
log_path = os.path.join(QUAD_DIR, 'log_verify_2groups_1.txt')

wsl_script = '/mnt/c/Users/jeffr/Downloads/Symmetric Groups/triple_check/quad_check/_verify_2groups_1.g'

cmd = ['wsl', 'gap', '-q', '-o', '8g', wsl_script]

with open(log_path, 'w') as out:
    out.write(f'# 2-group verify worker 1 re-started at {datetime.datetime.now()}\n\n')
    out.flush()
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    print(f'Launched 2-group worker, PID={proc.pid}')
    for line in proc.stdout:
        print(line, end='')
        out.write(line)
        out.flush()
    proc.wait()
    out.write(f'\n# Finished at {datetime.datetime.now()}\n')
    out.write(f'# Exit code: {proc.returncode}\n')
    elapsed = (datetime.datetime.now() - datetime.datetime.now()).total_seconds()
    print(f'\nFinished with exit code {proc.returncode}')
