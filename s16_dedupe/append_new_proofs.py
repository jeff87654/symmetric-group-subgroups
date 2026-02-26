"""
Append new proofs to S16 master proof file.

Usage:
    python append_new_proofs.py --extract   # Phase 1: extract & dedup, write staging file
    python append_new_proofs.py --append    # Phase 3: append verified proofs to master

Between --extract and --append, run launch_verify_new_proofs.py to verify in GAP.
"""

import os
import re
import sys
from datetime import datetime


BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROOFS_DIR = os.path.join(BASE_DIR, "proofs")
DIFFICULT_DIR = os.path.join(BASE_DIR, "Difficult")
MASTER_FILE = os.path.join(PROOFS_DIR, "s16_master_proofs.g")
STAGING_FILE = os.path.join(PROOFS_DIR, "new_proofs_staging.g")
VERIFY_OUTPUT = os.path.join(BASE_DIR, "verify_new_proofs_output.txt")


# --- Bracket-matching parser (from build_master_proofs.py) ---

def find_array_body(content):
    """Find text between ':= [' and the closing '];;' or '];'.

    If the file was interrupted (no closing bracket), returns all content
    after ':= [' so that split_records can still extract complete records.
    """
    match = re.search(r':=\s*\[', content)
    if not match:
        return None
    start = match.end()

    depth = 1
    i = start
    while i < len(content) and depth > 0:
        ch = content[i]
        if ch == '[':
            depth += 1
        elif ch == ']':
            depth -= 1
        elif ch == '"':
            i += 1
            while i < len(content) and content[i] != '"':
                if content[i] == '\\':
                    i += 1
                i += 1
        i += 1

    if depth != 0:
        return content[start:]

    return content[start:i - 1]


def split_records(body):
    """Split array body into individual rec(...) strings using bracket-matching."""
    records = []
    i = 0
    body = body.strip()

    while i < len(body):
        while i < len(body) and body[i] in ' \t\n\r,':
            i += 1

        if i < len(body) and body[i] == '#':
            while i < len(body) and body[i] != '\n':
                i += 1
            continue

        if i >= len(body):
            break

        if not body[i:].startswith('rec('):
            i += 1
            continue

        rec_start = i
        i += 4
        depth = 1

        while i < len(body) and depth > 0:
            ch = body[i]
            if ch in '([':
                depth += 1
            elif ch in ')]':
                depth -= 1
            elif ch == '"':
                i += 1
                while i < len(body) and body[i] != '"':
                    if body[i] == '\\':
                        i += 1
                    i += 1
            i += 1

        if depth == 0:
            records.append(body[rec_start:i])

    return records


def extract_duplicate(rec_str):
    """Extract the duplicate:=N field from a record string."""
    match = re.search(r'duplicate\s*:=\s*(\d+)', rec_str)
    if match:
        return int(match.group(1))
    return None


# --- Candidate file list ---

def get_candidate_files():
    """Return list of (filepath, label) for all candidate proof files."""
    candidates = []

    # proofs/ directory - audit proofs
    for n in range(1, 9):
        candidates.append((os.path.join(PROOFS_DIR, f"audit_proof_{n}.g"),
                           f"audit_proof_{n}.g"))

    # proofs/ directory - audit re-runs
    for suffix in ["2r", "4r", "6r", "6r2"]:
        candidates.append((os.path.join(PROOFS_DIR, f"audit_proof_{suffix}.g"),
                           f"audit_proof_{suffix}.g"))

    # proofs/ directory - audit stalled
    candidates.append((os.path.join(PROOFS_DIR, "audit_proof_stalled_graphiso.g"),
                        "audit_proof_stalled_graphiso.g"))

    # proofs/ directory - DP proof regeneration (all versions, different bucket ranges)
    # v1: work 1-~60, v2: buckets 23-38, v3: 61-63, v4: 61-547, v5: 607-608+42,
    # v6: ~850 buckets, v7: work 851-2051, v8: work 2052-end
    for n in range(1, 9):
        candidates.append((os.path.join(PROOFS_DIR, f"proof_regen_dp_v{n}.g"),
                           f"proof_regen_dp_v{n}.g"))

    # proofs/ directory - 2-group proofs
    candidates.append((os.path.join(PROOFS_DIR, "proof_regen_2group_1.g"),
                        "proof_regen_2group_1.g"))

    # proofs/ directory - normal proofs
    for n in range(1, 4):
        candidates.append((os.path.join(PROOFS_DIR, f"proof_regen_normal_{n}.g"),
                           f"proof_regen_normal_{n}.g"))

    # proofs/ directory - specialPCS proofs
    for n in range(1, 4):
        candidates.append((os.path.join(PROOFS_DIR, f"proof_regen_specialpcs_{n}.g"),
                           f"proof_regen_specialpcs_{n}.g"))

    # Difficult/ directory
    candidates.append((os.path.join(DIFFICULT_DIR, "graph_iso_audit_stalled_proofs.g"),
                        "Difficult/graph_iso_audit_stalled_proofs.g"))
    candidates.append((os.path.join(DIFFICULT_DIR, "graph_iso_audit_b2087_proofs.g"),
                        "Difficult/graph_iso_audit_b2087_proofs.g"))
    candidates.append((os.path.join(DIFFICULT_DIR, "graph_iso_b1182_b1185_proofs.g"),
                        "Difficult/graph_iso_b1182_b1185_proofs.g"))

    return candidates


def phase_extract():
    """Phase 1: Extract new proofs from candidate files, dedup against master."""
    print("=" * 60)
    print("Phase 1: Extract and deduplicate new proofs")
    print("=" * 60)
    print()

    # Step 1: Parse master file to get existing duplicate indices
    print(f"Reading master file: {os.path.basename(MASTER_FILE)}")
    with open(MASTER_FILE, 'r', encoding='utf-8', errors='replace') as f:
        master_content = f.read()

    existing_dups = set()
    for m in re.finditer(r'duplicate\s*:=\s*(\d+)', master_content):
        existing_dups.add(int(m.group(1)))
    print(f"  Existing proofs in master: {len(existing_dups)}")
    print()

    # Step 2: Scan candidate files
    candidates = get_candidate_files()
    new_proofs = {}  # duplicate_index -> rec_string
    total_extracted = 0
    total_skipped_existing = 0
    files_with_proofs = 0
    files_missing = 0
    source_files = []

    for filepath, label in candidates:
        if not os.path.exists(filepath):
            print(f"  MISSING: {label}")
            files_missing += 1
            continue

        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()

        body = find_array_body(content)
        if body is None or body.strip() == '':
            print(f"  SKIP (empty): {label}")
            continue

        records = split_records(body)
        if not records:
            print(f"  SKIP (no records): {label}")
            continue

        file_new = 0
        file_existing = 0

        for rec_str in records:
            dup_idx = extract_duplicate(rec_str)
            if dup_idx is None:
                continue

            if dup_idx in existing_dups:
                file_existing += 1
                total_skipped_existing += 1
            elif dup_idx in new_proofs:
                # Already found in an earlier candidate file, keep first
                file_existing += 1
            else:
                new_proofs[dup_idx] = rec_str
                file_new += 1
                total_extracted += 1

        if file_new > 0:
            files_with_proofs += 1
            source_files.append(label)
            suffix = f" ({file_existing} already in master)" if file_existing else ""
            print(f"  OK: {label} -> {file_new} new{suffix}")
        elif file_existing > 0:
            print(f"  SKIP (all in master): {label} ({file_existing} records)")
        else:
            print(f"  SKIP (empty): {label}")

    # Sort by duplicate index
    sorted_dups = sorted(new_proofs.keys())

    print()
    print("=" * 60)
    print(f"Candidate files scanned: {len(candidates)}")
    print(f"  Missing:               {files_missing}")
    print(f"  With new proofs:       {files_with_proofs}")
    print(f"Already in master:       {total_skipped_existing}")
    print(f"New unique proofs:       {len(sorted_dups)}")
    print("=" * 60)
    print()

    if len(sorted_dups) == 0:
        print("No new proofs to add!")
        return

    # Step 3: Write staging file
    print(f"Writing staging file: {os.path.basename(STAGING_FILE)}")
    with open(STAGING_FILE, 'w', encoding='utf-8') as f:
        f.write("# New proofs staging file - to be verified then appended to master\n")
        f.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"# New unique proofs: {len(sorted_dups)}\n")
        f.write(f"# Source files ({files_with_proofs}):\n")
        for sf in sorted(source_files):
            f.write(f"#   {sf}\n")
        f.write("\n")
        f.write("NEW_PROOFS_STAGING := [\n")

        for i, dup_idx in enumerate(sorted_dups):
            rec_str = new_proofs[dup_idx]
            f.write("  ")
            f.write(rec_str.strip())
            if i < len(sorted_dups) - 1:
                f.write(",")
            f.write("\n")

        f.write("];;\n")

    print(f"  Wrote {len(sorted_dups)} proofs")
    print()
    print("Next step: run launch_verify_new_proofs.py to verify in GAP")
    print(f"Then run: python append_new_proofs.py --append")


def phase_append():
    """Phase 3: Read verification results and append verified proofs to master.

    Fast path: extract failed duplicate indices from FAIL lines in verification
    output, then stream staging file skipping failed records. No bracket-matching.
    """
    print("=" * 60)
    print("Phase 3: Append verified proofs to master")
    print("=" * 60)
    print()

    # Read verification output
    if not os.path.exists(VERIFY_OUTPUT):
        print(f"ERROR: Verification output not found: {VERIFY_OUTPUT}")
        print("Run launch_verify_new_proofs.py first!")
        sys.exit(1)

    with open(VERIFY_OUTPUT, 'r', encoding='utf-8') as f:
        verify_content = f.read()

    # Parse summary
    passed_match = re.search(r'Passed:\s*(\d+)', verify_content)
    failed_match = re.search(r'Failed:\s*(\d+)', verify_content)
    total_match = re.search(r'Total proofs:\s*(\d+)', verify_content)

    if not passed_match or not total_match:
        print("ERROR: Could not parse verification output")
        sys.exit(1)

    n_passed = int(passed_match.group(1))
    n_failed = int(failed_match.group(1)) if failed_match else 0
    print(f"Verification: {n_passed} passed, {n_failed} failed")

    # Collect failed duplicate indices directly from FAIL lines (fast)
    failed_dups = set()
    for m in re.finditer(r'FAIL proof \d+ \(dup=(\d+)\)', verify_content):
        failed_dups.add(int(m.group(1)))
    print(f"Failed duplicate indices: {len(failed_dups)}")

    # Read staging file and extract records by regex (no bracket-matching)
    # Each record starts with "  rec(" and contains "duplicate:=N" or "duplicate := N"
    if not os.path.exists(STAGING_FILE):
        print(f"ERROR: Staging file not found: {STAGING_FILE}")
        sys.exit(1)

    with open(STAGING_FILE, 'r', encoding='utf-8', errors='replace') as f:
        staging_content = f.read()

    # Use find_array_body (fast - just finds start/end) but NOT split_records
    body = find_array_body(staging_content)
    if body is None:
        print("ERROR: Could not parse staging file")
        sys.exit(1)

    # Fast record splitting: top-level records start with "  rec(" (2-space indent).
    # Inner recs (e.g. in factorMappings) have deeper indent and must NOT be split.
    dup_pattern = re.compile(r'duplicate\s*:=\s*(\d+)')
    kept_records = []
    skipped = 0
    total = 0

    # Split on top-level record boundaries only (2-space indent at line start)
    parts = re.split(r'\n  (?=rec\()', '\n' + body)

    for part in parts:
        part = part.strip().rstrip(',')
        if not part.startswith('rec('):
            continue
        total += 1
        m = dup_pattern.search(part)
        if m and int(m.group(1)) in failed_dups:
            skipped += 1
            continue
        kept_records.append(part)

    print(f"Staging: {total} total, {skipped} failed, {len(kept_records)} to append")

    if len(kept_records) == 0:
        print("No verified proofs to append!")
        return

    # Read master and count existing proofs
    with open(MASTER_FILE, 'r', encoding='utf-8', errors='replace') as f:
        master_content = f.read()

    existing_count = len(re.findall(r'duplicate\s*:=\s*\d+', master_content))
    print(f"Existing proofs in master: {existing_count}")

    # Strip trailing ];;
    master_stripped = master_content.rstrip()
    if not master_stripped.endswith('];;'):
        print(f"ERROR: Master file doesn't end with ];;")
        sys.exit(1)

    master_stripped = master_stripped[:-3].rstrip()

    # Append new proofs
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    with open(MASTER_FILE, 'w', encoding='utf-8') as f:
        f.write(master_stripped)
        f.write(f',\n# --- New proofs appended {timestamp} ({len(kept_records)} proofs) ---\n')
        for i, rec_str in enumerate(kept_records):
            f.write("  ")
            f.write(rec_str)
            if i < len(kept_records) - 1:
                f.write(",")
            f.write("\n")
        f.write("];;\n")

    new_total = existing_count + len(kept_records)
    print(f"\nAppended {len(kept_records)} proofs to master.")
    print(f"New total: {new_total} proofs")


def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python append_new_proofs.py --extract   # Extract & dedup new proofs")
        print("  python append_new_proofs.py --append    # Append verified proofs to master")
        sys.exit(1)

    mode = sys.argv[1]
    if mode == "--extract":
        phase_extract()
    elif mode == "--append":
        phase_append()
    else:
        print(f"Unknown mode: {mode}")
        print("Use --extract or --append")
        sys.exit(1)


if __name__ == "__main__":
    main()
