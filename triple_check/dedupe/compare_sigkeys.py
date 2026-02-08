"""
Compare sigKey distributions between Triple-Check (TC) deduplication results
and the master_isomorphism_types.json file.

Uses a 4-tuple match key (order, derived_size, classes, abelianInvariants)
since derivedLength encoding differs: TC uses -1 for non-solvable, master uses 0.
"""

import json
import re
import sys
from collections import Counter

# ── File paths ──────────────────────────────────────────────────────────────
CLEAN_FILE = r"C:\Users\jeffr\Downloads\Symmetric Groups\triple_check\conjugacy_cache\s14_large_invariants_clean.g"
FINAL_RESULT = r"C:\Users\jeffr\Downloads\Symmetric Groups\triple_check\dedupe\final_result.json"
MASTER_FILE = r"C:\Users\jeffr\Downloads\Symmetric Groups\Partition\verify_s14_v3\master_isomorphism_types.json"


def parse_gap_list(s):
    """Parse a GAP-style list like '[ 2, 3 ]' or '[  ]' into a Python list of ints."""
    s = s.strip()
    # Remove outer brackets
    inner = s.strip("[]").strip()
    if not inner:
        return []
    return [int(x.strip()) for x in inner.split(",")]


def parse_clean_file(path):
    """
    Parse the s14_large_invariants_clean.g file.
    Returns dict: index -> sigKey (as tuple for hashing).
    sigKey format: (order, derived_size, conjugacy_classes, derived_length, abelian_invariants_tuple)
    """
    records = {}
    with open(path, "r") as f:
        content = f.read()

    # Match each rec(...) block - find index and sigKey
    # Pattern: index := N, ... sigKey := [ ... ],
    rec_pattern = re.compile(
        r'rec\((.*?)\)(?:,|\s*\])', re.DOTALL
    )

    for m in rec_pattern.finditer(content):
        block = m.group(1)

        # Extract index
        idx_match = re.search(r'\bindex\s*:=\s*(\d+)', block)
        if not idx_match:
            continue
        idx = int(idx_match.group(1))

        # Extract sigKey := [ ... ]
        # The sigKey can contain nested lists like [ 2, 2 ]
        # Pattern: sigKey := [ val, val, val, val, [ vals ] ]
        sk_match = re.search(r'sigKey\s*:=\s*(\[.*?\])\s*,\s*\n', block)
        if not sk_match:
            # Try alternate: sigKey at end or followed by comma
            sk_match = re.search(r'sigKey\s*:=\s*(\[[^\]]*\[[^\]]*\][^\]]*\])', block)
        if not sk_match:
            # Simplest case: no nested brackets (empty abelian invariants)
            sk_match = re.search(r'sigKey\s*:=\s*(\[[^\[]*?\])', block)

        if not sk_match:
            print(f"WARNING: Could not parse sigKey for index {idx}")
            continue

        sk_str = sk_match.group(1)
        # Parse: [ order, derived, classes, derivedLength, [ abelianInvariants ] ]
        # Remove outer brackets
        inner = sk_str.strip("[] \t")

        # Find the nested list (abelian invariants)
        nested_match = re.search(r'\[([^\]]*)\]', sk_str[1:])  # skip first [
        if nested_match:
            abel_str = nested_match.group(1).strip()
            abel = tuple(int(x.strip()) for x in abel_str.split(",") if x.strip()) if abel_str else ()
            # Get the part before the nested list
            before_nested = sk_str[1:sk_str.index("[", 1)].strip().rstrip(",").strip()
            parts = [x.strip() for x in before_nested.split(",") if x.strip()]
        else:
            abel = ()
            parts = [x.strip() for x in inner.split(",") if x.strip()]

        if len(parts) < 4:
            print(f"WARNING: sigKey has {len(parts)} parts for index {idx}: {sk_str}")
            continue

        order = int(parts[0])
        derived = int(parts[1])
        classes = int(parts[2])
        dl = int(parts[3])

        sigkey = (order, derived, classes, dl, abel)
        records[idx] = sigkey

    return records


def parse_master_file(path):
    """
    Parse master_isomorphism_types.json.
    Returns list of sigKeys for large groups only.
    sigKey format: (order, derived, classes, derivedLength, abelian_invariants_tuple)
    """
    with open(path, "r") as f:
        data = json.load(f)

    sigkeys = []
    for entry in data["types"]:
        if entry["type"] != "large":
            continue
        fp = entry["fingerprint"]
        order = entry["order"]
        derived = fp["derived"]
        classes = fp["classes"]
        dl = fp["derivedLength"]
        abel_str = fp["abelianInvariants"]
        if abel_str.strip():
            abel = tuple(int(x.strip()) for x in abel_str.split(","))
        else:
            abel = ()
        sigkeys.append((order, derived, classes, dl, abel))

    return sigkeys


def make_match_key(sigkey):
    """Create a 4-tuple match key dropping derivedLength."""
    order, derived, classes, dl, abel = sigkey
    return (order, derived, classes, abel)


def fmt_sigkey(sk):
    """Format a sigKey tuple as a readable string."""
    if sk is None:
        return "(none)"
    order, derived, classes, dl, abel = sk
    abel_str = "[" + ",".join(str(x) for x in abel) + "]"
    return f"[{order}, {derived}, {classes}, {dl}, {abel_str}]"


def fmt_match_key(mk):
    """Format a match key tuple."""
    order, derived, classes, abel = mk
    abel_str = "[" + ",".join(str(x) for x in abel) + "]"
    return f"({order}, {derived}, {classes}, {abel_str})"


def main():
    # ── Step 1: Parse clean file ────────────────────────────────────────────
    print("Parsing clean file...")
    clean_records = parse_clean_file(CLEAN_FILE)
    print(f"  Parsed {len(clean_records)} records from clean file")

    # ── Step 2: Load final_result.json ──────────────────────────────────────
    print("Loading final_result.json...")
    with open(FINAL_RESULT, "r") as f:
        final_data = json.load(f)
    rep_indices = set(final_data["all_rep_indices"])
    print(f"  {len(rep_indices)} representative indices")

    # ── Step 3: Count TC reps per sigKey ────────────────────────────────────
    tc_sigkey_counts = Counter()
    tc_sigkeys_by_matchkey = {}  # match_key -> set of full sigkeys
    missing_indices = []
    for idx in rep_indices:
        if idx not in clean_records:
            missing_indices.append(idx)
            continue
        sk = clean_records[idx]
        tc_sigkey_counts[sk] += 1
        mk = make_match_key(sk)
        tc_sigkeys_by_matchkey.setdefault(mk, set()).add(sk)

    if missing_indices:
        print(f"  WARNING: {len(missing_indices)} rep indices not found in clean file!")
        print(f"    First few: {missing_indices[:10]}")

    tc_total = sum(tc_sigkey_counts.values())
    print(f"  TC: {len(tc_sigkey_counts)} unique sigKeys, {tc_total} total reps")

    # ── Step 4: Count master large groups per sigKey ────────────────────────
    print("Parsing master file...")
    master_sigkeys = parse_master_file(MASTER_FILE)
    print(f"  {len(master_sigkeys)} large groups in master")

    master_sigkey_counts = Counter()
    master_sigkeys_by_matchkey = {}
    for sk in master_sigkeys:
        master_sigkey_counts[sk] += 1
        mk = make_match_key(sk)
        master_sigkeys_by_matchkey.setdefault(mk, set()).add(sk)

    master_total = sum(master_sigkey_counts.values())
    print(f"  Master: {len(master_sigkey_counts)} unique sigKeys, {master_total} total large groups")

    # ── Step 5: Compare using 4-tuple match keys ───────────────────────────
    print("\n" + "=" * 120)
    print("COMPARISON: sigKey-by-sigKey (using 4-tuple match key)")
    print("=" * 120)

    all_match_keys = set(tc_sigkeys_by_matchkey.keys()) | set(master_sigkeys_by_matchkey.keys())

    # For each match key, sum counts
    tc_by_mk = Counter()
    for sk, cnt in tc_sigkey_counts.items():
        tc_by_mk[make_match_key(sk)] += cnt

    master_by_mk = Counter()
    for sk, cnt in master_sigkey_counts.items():
        master_by_mk[make_match_key(sk)] += cnt

    # Find discrepancies
    discrepancies = []
    tc_only = []
    master_only = []
    matches = 0

    for mk in sorted(all_match_keys):
        tc_cnt = tc_by_mk.get(mk, 0)
        m_cnt = master_by_mk.get(mk, 0)

        if tc_cnt == m_cnt:
            matches += 1
            continue

        # Get full sigKeys from each source
        tc_sks = tc_sigkeys_by_matchkey.get(mk, set())
        m_sks = master_sigkeys_by_matchkey.get(mk, set())

        # Pick representative sigKey for display
        tc_sk = sorted(tc_sks)[0] if tc_sks else None
        m_sk = sorted(m_sks)[0] if m_sks else None

        diff = tc_cnt - m_cnt

        if tc_cnt == 0:
            master_only.append((mk, tc_sk, m_sk, m_cnt, tc_cnt, diff))
        elif m_cnt == 0:
            tc_only.append((mk, tc_sk, m_sk, m_cnt, tc_cnt, diff))
        else:
            discrepancies.append((mk, tc_sk, m_sk, m_cnt, tc_cnt, diff))

    # ── Print discrepancies table ───────────────────────────────────────────
    if discrepancies:
        print(f"\n{'DISCREPANCIES (present in BOTH, different counts)':}")
        print("-" * 160)
        print(f"{'Match Key (order, derived, classes, abel)':<55} {'Master sigKey':<40} {'TC sigKey':<40} {'Master':>6} {'TC':>6} {'Diff':>6}")
        print("-" * 160)
        for mk, tc_sk, m_sk, m_cnt, tc_cnt, diff in sorted(discrepancies, key=lambda x: (x[0][0], x[0][1])):
            sign = "+" if diff > 0 else ""
            print(f"{fmt_match_key(mk):<55} {fmt_sigkey(m_sk):<40} {fmt_sigkey(tc_sk):<40} {m_cnt:>6} {tc_cnt:>6} {sign}{diff:>5}")
        print("-" * 160)
        print(f"Total discrepancies: {len(discrepancies)}")
        disc_master_total = sum(x[3] for x in discrepancies)
        disc_tc_total = sum(x[4] for x in discrepancies)
        print(f"Sum of master counts in discrepant keys: {disc_master_total}")
        print(f"Sum of TC counts in discrepant keys: {disc_tc_total}")
        print(f"Net difference: {disc_tc_total - disc_master_total:+d}")
    else:
        print("\nNo discrepancies found (all shared match keys have equal counts).")

    # ── Print TC-only table ─────────────────────────────────────────────────
    if tc_only:
        print(f"\n{'KEYS ONLY IN TC (not in master)':}")
        print("-" * 110)
        print(f"{'Match Key (order, derived, classes, abel)':<55} {'TC sigKey':<40} {'TC Count':>8}")
        print("-" * 110)
        for mk, tc_sk, m_sk, m_cnt, tc_cnt, diff in sorted(tc_only, key=lambda x: (x[0][0], x[0][1])):
            print(f"{fmt_match_key(mk):<55} {fmt_sigkey(tc_sk):<40} {tc_cnt:>8}")
        print("-" * 110)
        print(f"Total TC-only keys: {len(tc_only)}, total groups: {sum(x[4] for x in tc_only)}")
    else:
        print("\nNo TC-only keys.")

    # ── Print master-only table ─────────────────────────────────────────────
    if master_only:
        print(f"\n{'KEYS ONLY IN MASTER (not in TC)':}")
        print("-" * 110)
        print(f"{'Match Key (order, derived, classes, abel)':<55} {'Master sigKey':<40} {'Master Count':>12}")
        print("-" * 110)
        for mk, tc_sk, m_sk, m_cnt, tc_cnt, diff in sorted(master_only, key=lambda x: (x[0][0], x[0][1])):
            print(f"{fmt_match_key(mk):<55} {fmt_sigkey(m_sk):<40} {m_cnt:>12}")
        print("-" * 110)
        print(f"Total master-only keys: {len(master_only)}, total groups: {sum(x[3] for x in master_only)}")
    else:
        print("\nNo master-only keys.")

    # ── Summary statistics ──────────────────────────────────────────────────
    print(f"\n{'=' * 120}")
    print("SUMMARY STATISTICS")
    print(f"{'=' * 120}")
    print(f"Total unique 4-tuple match keys:        {len(all_match_keys)}")
    print(f"  Match keys in both sources:            {matches + len(discrepancies)}")
    print(f"    Matching counts:                     {matches}")
    print(f"    Different counts:                    {len(discrepancies)}")
    print(f"  Match keys only in TC:                 {len(tc_only)}")
    print(f"  Match keys only in master:             {len(master_only)}")
    print()
    print(f"Master large groups total:               {master_total}")
    print(f"TC representative groups total:          {tc_total}")
    print(f"Overall difference (TC - master):        {tc_total - master_total:+d}")
    print()

    # Break down where the difference comes from
    disc_diff = sum(x[4] - x[3] for x in discrepancies) if discrepancies else 0
    tc_only_total = sum(x[4] for x in tc_only)
    master_only_total = sum(x[3] for x in master_only)
    print(f"Difference breakdown:")
    print(f"  From discrepant shared keys:           {disc_diff:+d}")
    print(f"  From TC-only keys:                     +{tc_only_total}")
    print(f"  From master-only keys:                 -{master_only_total}")
    print(f"  Total:                                 {disc_diff + tc_only_total - master_only_total:+d}")

    # Cross-check with a(14) values
    print(f"\na(14) cross-check:")
    print(f"  Master: {final_data.get('idgroup_types', '?')} IdGroup (TC) + {master_total} large (master) = {final_data.get('idgroup_types', 0) + master_total}")
    print(f"  TC:     {final_data.get('idgroup_types', '?')} IdGroup (TC) + {tc_total} large (TC) = {final_data.get('idgroup_types', 0) + tc_total}")
    print(f"  Known:  4591 IdGroup (master) + 3164 large = 7755")


if __name__ == "__main__":
    main()
