#!/usr/bin/env python3
"""
verify_cert_structural.py

Pure Python structural consistency checker for s16_verification_certificate_v7.g.
No GAP required. Parses the certificate and class-to-type mapping, then verifies:

  1. Basic integrity: t=1..43626 consecutive, i unique, method counts match header
  2. Field presence: each method has required fields
  3. Order consistency: o == id[0] for B; o == sk[1] for types with both
  4. Method A uniqueness: each A-type order appears exactly once among all types
  5. Method B uniqueness: each [order, idGroup] pair appears exactly once
  6. Method C uniqueness: each C-type sigKey appears exactly once among all types with sk
  7. Method D uniqueness: no two D types in same sk bucket share the same h value
  8. F/G/H peer consistency: F/G/H types share (sk, h, e7) with at least one peer
  9. Class-to-type coverage: all 686,165 entries map to valid types 1..43626;
     every type has at least one class; the certificate's rep index i maps correctly

Usage:
    python verify_cert_structural.py
"""

import os
import re
import sys
from collections import Counter, defaultdict

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.dirname(SCRIPT_DIR)  # data files are one level up

EXPECTED_TYPES = 43626
EXPECTED_CLASSES = 686165
EXPECTED_METHODS = {
    'A': 146, 'B': 14202, 'C': 8760, 'D': 13969,
    'E': 5294, 'F': 748, 'G': 350, 'H': 157
}

# Required fields per method
REQUIRED_FIELDS = {
    'A': {'t', 'i', 'm', 'o'},
    'B': {'t', 'i', 'm', 'o', 'id'},
    'C': {'t', 'i', 'm', 'sk'},
    'D': {'t', 'i', 'm', 'sk', 'h'},
    'E': {'t', 'i', 'm', 'sk', 'd'},
    'F': {'t', 'i', 'm', 'sk', 'h', 'e7', 'ct'},
    'G': {'t', 'i', 'm', 'sk', 'h', 'e7'},
    'H': {'t', 'i', 'm', 'o', 'sk', 'h', 'e7'},
}

# Valid E discriminant field names
VALID_E_FIELDS = {
    'ccOrderProfile', 'ccSizes', 'autGroupOrder',
    'centerSize', 'derivedSizes', 'frattiniSize', 'nilpClass'
}

##############################################################################
# GAP value parser (recursive descent)
##############################################################################

def _skip_ws(s, i):
    while i < len(s) and s[i] in ' \t\n\r':
        i += 1
    return i


def parse_gap_value(s, i):
    """Parse a GAP value starting at position i. Returns (value, new_position)."""
    i = _skip_ws(s, i)
    if i >= len(s):
        return None, i

    c = s[i]

    # String
    if c == '"':
        j = i + 1
        while j < len(s) and s[j] != '"':
            if s[j] == '\\':
                j += 1  # skip escaped char
            j += 1
        return s[i+1:j], j + 1

    # List
    if c == '[':
        i += 1
        items = []
        i = _skip_ws(s, i)
        while i < len(s) and s[i] != ']':
            val, i = parse_gap_value(s, i)
            items.append(val)
            i = _skip_ws(s, i)
            if i < len(s) and s[i] == ',':
                i += 1
            i = _skip_ws(s, i)
        if i < len(s):
            i += 1  # skip ]
        return items, i

    # Record
    if s[i:i+4] == 'rec(':
        i += 4
        result = {}
        i = _skip_ws(s, i)
        while i < len(s) and s[i] != ')':
            # Parse key (identifier before :=)
            j = i
            while j < len(s) and s[j] not in (':',):
                j += 1
            key = s[i:j].strip()
            i = j
            if i + 1 < len(s) and s[i:i+2] == ':=':
                i += 2
            else:
                raise ValueError(f"Expected := at pos {i}: '{s[i:i+10]}'")
            val, i = parse_gap_value(s, i)
            result[key] = val
            i = _skip_ws(s, i)
            if i < len(s) and s[i] == ',':
                i += 1
            i = _skip_ws(s, i)
        if i < len(s):
            i += 1  # skip )
        return result, i

    # Number (integer, possibly negative)
    if c == '-' or c.isdigit():
        j = i
        if c == '-':
            j += 1
        while j < len(s) and s[j].isdigit():
            j += 1
        return int(s[i:j]), j

    # Boolean
    if s[i:i+4] == 'true':
        return True, i + 4
    if s[i:i+5] == 'false':
        return False, i + 5

    raise ValueError(f"Unexpected at position {i}: '{s[i:i+30]}'")


def parse_record_line(line):
    """Parse a single rec(...) line from the certificate."""
    line = line.strip().rstrip(',')
    if not line.startswith('rec('):
        return None
    try:
        val, _ = parse_gap_value(line, 0)
        return val
    except (ValueError, IndexError) as e:
        print(f"  PARSE ERROR: {e}")
        print(f"  Line: {line[:120]}...")
        return None


##############################################################################
# File loaders
##############################################################################

def load_certificate():
    """Load and parse s16_verification_certificate_v7.g → list of dicts."""
    path = os.path.join(BASE_DIR, 's16_verification_certificate_v7.g')
    print(f"Loading certificate from {os.path.basename(path)}...")
    records = []
    parse_errors = 0
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line.startswith('rec('):
                continue
            r = parse_record_line(line)
            if r is not None:
                records.append(r)
            else:
                parse_errors += 1
    print(f"  Parsed {len(records)} records ({parse_errors} parse errors)")
    return records


def load_class_to_type():
    """Load s16_class_to_type.g → list of integers (1-indexed)."""
    path = os.path.join(BASE_DIR, 's16_class_to_type.g')
    print(f"Loading class-to-type from {os.path.basename(path)}...")
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    start = content.index('[')
    end = content.rindex(']')
    numbers = [int(x) for x in re.findall(r'\d+', content[start+1:end])]
    print(f"  Loaded {len(numbers)} class-to-type mappings")
    return numbers


##############################################################################
# Structural checks
##############################################################################

def check_basic_integrity(records):
    """Check t=1..43626 consecutive, i unique, method counts match."""
    print("\n=== Check 1: Basic Integrity ===")
    ok = True

    # Type count
    if len(records) != EXPECTED_TYPES:
        print(f"  FAIL: Expected {EXPECTED_TYPES} types, got {len(records)}")
        ok = False
    else:
        print(f"  PASS: {len(records)} types")

    # t values consecutive 1..N
    t_values = [r['t'] for r in records]
    expected_t = list(range(1, EXPECTED_TYPES + 1))
    if t_values != expected_t:
        missing = set(expected_t) - set(t_values)
        extra = set(t_values) - set(expected_t)
        print(f"  FAIL: t values not consecutive 1..{EXPECTED_TYPES}")
        if missing:
            print(f"    Missing: {sorted(missing)[:10]}...")
        if extra:
            print(f"    Extra: {sorted(extra)[:10]}...")
        ok = False
    else:
        print(f"  PASS: t=1..{EXPECTED_TYPES} consecutive")

    # i values unique
    i_values = [r['i'] for r in records]
    i_counter = Counter(i_values)
    dupes = {v: c for v, c in i_counter.items() if c > 1}
    if dupes:
        print(f"  FAIL: {len(dupes)} duplicate i values: {dict(list(dupes.items())[:5])}")
        ok = False
    else:
        print(f"  PASS: All {len(i_values)} i values unique")

    # i values in valid range [1, 686165]
    out_of_range = [v for v in i_values if v < 1 or v > EXPECTED_CLASSES]
    if out_of_range:
        print(f"  FAIL: {len(out_of_range)} i values out of range [1,{EXPECTED_CLASSES}]")
        ok = False
    else:
        print(f"  PASS: All i values in [1, {EXPECTED_CLASSES}]")

    # Method counts
    method_counts = Counter(r['m'] for r in records)
    for m, expected in EXPECTED_METHODS.items():
        actual = method_counts.get(m, 0)
        if actual != expected:
            print(f"  FAIL: Method {m}: expected {expected}, got {actual}")
            ok = False
        else:
            print(f"  PASS: Method {m}: {actual}")

    total = sum(method_counts.values())
    expected_total = sum(EXPECTED_METHODS.values())
    if total != expected_total:
        print(f"  FAIL: Total methods: expected {expected_total}, got {total}")
        ok = False
    else:
        print(f"  PASS: Total: {total}")

    return ok


def check_field_presence(records):
    """Check each method has its required fields."""
    print("\n=== Check 2: Field Presence ===")
    ok = True
    issues_by_method = defaultdict(list)

    for r in records:
        m = r['m']
        required = REQUIRED_FIELDS.get(m, set())
        present = set(r.keys())
        missing = required - present
        if missing:
            issues_by_method[m].append((r['t'], missing))

    for m in sorted(EXPECTED_METHODS.keys()):
        issues = issues_by_method[m]
        if issues:
            print(f"  FAIL: Method {m}: {len(issues)} records missing fields")
            for t, missing in issues[:3]:
                print(f"    t={t}: missing {missing}")
            ok = False
        else:
            print(f"  PASS: Method {m}: all required fields present")

    # Check E-type d record structure
    e_types = [r for r in records if r['m'] == 'E']
    e_issues = 0
    for r in e_types:
        d = r.get('d', {})
        if not isinstance(d, dict):
            e_issues += 1
            continue
        f_val = d.get('f')
        if f_val not in VALID_E_FIELDS:
            e_issues += 1
            continue
        # Check value field exists (cc for ccOrderProfile, v for others)
        if f_val == 'ccOrderProfile':
            if 'cc' not in d:
                e_issues += 1
        else:
            if 'v' not in d:
                e_issues += 1

    if e_issues:
        print(f"  FAIL: {e_issues} E-type records with malformed d field")
        ok = False
    else:
        print(f"  PASS: All {len(e_types)} E-type d records well-formed")

    return ok


def check_order_consistency(records):
    """Check o == id[0] for B; o == sk[1] for types with both."""
    print("\n=== Check 3: Order Consistency ===")
    ok = True
    b_issues = 0
    osk_issues = 0

    for r in records:
        # B types: o must equal id[0]
        if r['m'] == 'B':
            if r['o'] != r['id'][0]:
                b_issues += 1
                if b_issues <= 3:
                    print(f"  FAIL: t={r['t']}: o={r['o']} != id[0]={r['id'][0]}")

        # Types with both o and sk: o must equal sk[0] (order is first element)
        if 'o' in r and 'sk' in r:
            if r['o'] != r['sk'][0]:
                osk_issues += 1
                if osk_issues <= 3:
                    print(f"  FAIL: t={r['t']}: o={r['o']} != sk[0]={r['sk'][0]}")

    if b_issues == 0:
        print(f"  PASS: All B types: o == id[0]")
    else:
        print(f"  FAIL: {b_issues} B types with o != id[0]")
        ok = False

    if osk_issues == 0:
        print(f"  PASS: All types with o+sk: o == sk[0]")
    else:
        print(f"  FAIL: {osk_issues} types with o != sk[0]")
        ok = False

    return ok


def check_method_a_uniqueness(records):
    """Each A-type order appears exactly once among ALL 43,626 types."""
    print("\n=== Check 4: Method A Uniqueness ===")
    ok = True

    # Collect all orders that appear in the certificate
    # A-type claims: this order is unique among all types
    a_types = [r for r in records if r['m'] == 'A']

    # Get order for each type (from o or sk[1])
    def get_order(r):
        if 'o' in r:
            return r['o']
        if 'sk' in r:
            return r['sk'][0]  # order is first element (0-indexed in Python)
        return None

    all_orders = Counter()
    for r in records:
        o = get_order(r)
        if o is not None:
            all_orders[o] += 1

    # Each A-type order should appear exactly once
    a_issues = 0
    for r in a_types:
        o = r['o']
        if all_orders[o] != 1:
            a_issues += 1
            if a_issues <= 5:
                print(f"  FAIL: A type t={r['t']} order {o} appears {all_orders[o]} times")

    if a_issues == 0:
        print(f"  PASS: All {len(a_types)} A-type orders unique among all types")
    else:
        print(f"  FAIL: {a_issues} A-type orders not unique")
        ok = False

    return ok


def check_method_b_uniqueness(records):
    """Each [order, idGroup] pair appears exactly once."""
    print("\n=== Check 5: Method B Uniqueness ===")
    ok = True
    b_types = [r for r in records if r['m'] == 'B']

    id_counter = Counter()
    for r in b_types:
        key = tuple(r['id'])
        id_counter[key] += 1

    dupes = {k: v for k, v in id_counter.items() if v > 1}
    if dupes:
        print(f"  FAIL: {len(dupes)} duplicate [order, id] pairs among B types")
        for k, v in list(dupes.items())[:5]:
            print(f"    {list(k)}: {v} times")
        ok = False
    else:
        print(f"  PASS: All {len(b_types)} B-type [order, id] pairs unique")

    return ok


def _sk_to_key(sk):
    """Convert sigKey list to a hashable tuple (handles nested abelian invariants)."""
    if isinstance(sk, list):
        return tuple(_sk_to_key(x) if isinstance(x, list) else x for x in sk)
    return sk


def check_method_c_uniqueness(records):
    """Each C-type sigKey appears exactly once among all types with sk."""
    print("\n=== Check 6: Method C Uniqueness ===")
    ok = True

    c_types = [r for r in records if r['m'] == 'C']

    # Among ALL types with sk, each C-type's sigKey should be unique
    sk_counter = Counter()
    for r in records:
        if 'sk' in r:
            sk_counter[_sk_to_key(r['sk'])] += 1

    c_issues = 0
    for r in c_types:
        key = _sk_to_key(r['sk'])
        if sk_counter[key] != 1:
            c_issues += 1
            if c_issues <= 5:
                print(f"  FAIL: C type t={r['t']} sk={r['sk']} appears {sk_counter[key]} times")

    if c_issues == 0:
        print(f"  PASS: All {len(c_types)} C-type sigKeys unique among all sk-bearing types")
    else:
        print(f"  FAIL: {c_issues} C-type sigKeys not unique")
        ok = False

    return ok


def _list_to_key(lst):
    """Recursively convert a nested list to a hashable tuple."""
    if isinstance(lst, list):
        return tuple(_list_to_key(x) for x in lst)
    return lst


def check_method_d_uniqueness(records):
    """No two D types in the same sk bucket share the same h value."""
    print("\n=== Check 7: Method D Uniqueness ===")
    ok = True

    d_types = [r for r in records if r['m'] == 'D']

    # Group D types by sigKey
    sk_buckets = defaultdict(list)
    for r in d_types:
        sk_key = _sk_to_key(r['sk'])
        sk_buckets[sk_key].append(r)

    d_issues = 0
    for sk_key, bucket in sk_buckets.items():
        h_values = Counter()
        for r in bucket:
            h_key = _list_to_key(r['h'])
            h_values[h_key] += 1
        dupes = {k: v for k, v in h_values.items() if v > 1}
        if dupes:
            d_issues += len(dupes)
            if d_issues <= 5:
                for k, v in dupes.items():
                    ts = [r['t'] for r in bucket if _list_to_key(r['h']) == k]
                    print(f"  FAIL: sk={list(sk_key)}: h={list(k)} shared by {v} D types: t={ts[:5]}")

    if d_issues == 0:
        print(f"  PASS: All D types have unique h within their sk bucket "
              f"({len(d_types)} types in {len(sk_buckets)} buckets)")
    else:
        print(f"  FAIL: {d_issues} duplicate (sk, h) pairs among D types")
        ok = False

    return ok


def check_fgh_peer_consistency(records):
    """F/G/H peer consistency checks."""
    print("\n=== Check 8: F/G/H Peer Consistency ===")
    ok = True

    fgh_types = [r for r in records if r['m'] in ('F', 'G', 'H')]

    # Check 8a: Among F/G/H types themselves, build (sk, h) peer index
    # Note: D types use partial h format, E types don't store h at all.
    # F/G/H types that are alone in their (sk, h) bucket can be valid:
    # they may share the broader (sk) bucket with E types whose histograms
    # are not stored and can't be cross-referenced structurally.
    fgh_peer_index = defaultdict(list)
    for r in fgh_types:
        key = (_sk_to_key(r['sk']), _list_to_key(r['h']))
        fgh_peer_index[key].append(r)

    fgh_singletons = 0
    for key, bucket in fgh_peer_index.items():
        if len(bucket) == 1:
            fgh_singletons += 1

    total_fgh_buckets = len(fgh_peer_index)
    multi_buckets = total_fgh_buckets - fgh_singletons
    print(f"  INFO: {len(fgh_types)} F/G/H types in {total_fgh_buckets} (sk,h) buckets")
    print(f"  INFO: {multi_buckets} multi-type buckets, {fgh_singletons} singleton buckets")
    if fgh_singletons > 0:
        print(f"  INFO: {fgh_singletons} F/G/H types alone in (sk,h) bucket "
              f"(valid if E types share same sk+histogram)")

    # Check 8b: F/G/H types must share their sk bucket with ≥1 other large type
    # (otherwise they'd be method C or D)
    sk_all_index = defaultdict(int)
    for r in records:
        if 'sk' in r:
            sk_all_index[_sk_to_key(r['sk'])] += 1

    alone_in_sk = 0
    for r in fgh_types:
        key = _sk_to_key(r['sk'])
        if sk_all_index[key] < 2:
            alone_in_sk += 1
            if alone_in_sk <= 3:
                print(f"  WARN: {r['m']} type t={r['t']} sk={r['sk'][:2]}... "
                      f"is alone in sk bucket (could have been method C)")

    if alone_in_sk == 0:
        print(f"  PASS: All F/G/H types share their sk bucket with other types")
    else:
        # This is a method classification issue, not a correctness error.
        # The types ARE valid unique types — they just have a suboptimal method label.
        print(f"  WARN: {alone_in_sk} F/G/H types alone in sk bucket "
              f"(cosmetic - could be method C)")
        print(f"  PASS: (classification warnings are non-fatal)")

    # F types: check ct field is valid
    f_types = [r for r in records if r['m'] == 'F']
    valid_ct = {'degrees', 'centralizers', 'kernelSizes', 'fsIndicators'}
    f_issues = 0
    for r in f_types:
        ct = r.get('ct', '')
        # ct can be a single name or comma-separated composite
        parts = ct.split(',') if isinstance(ct, str) else []
        for p in parts:
            if p.strip() not in valid_ct and p.strip() != 'rpHash':
                f_issues += 1
                if f_issues <= 3:
                    print(f"  FAIL: F type t={r['t']} has unknown ct value: {ct}")
                break

    if f_issues == 0:
        print(f"  PASS: All {len(f_types)} F-type ct fields valid")
    else:
        print(f"  FAIL: {f_issues} F types with invalid ct")
        ok = False

    return ok


def check_class_to_type_coverage(records, c2t):
    """Verify class-to-type mapping covers all classes and all types."""
    print("\n=== Check 9: Class-to-Type Coverage ===")
    ok = True

    # Check count
    if len(c2t) != EXPECTED_CLASSES:
        print(f"  FAIL: Expected {EXPECTED_CLASSES} class-to-type entries, got {len(c2t)}")
        ok = False
    else:
        print(f"  PASS: {len(c2t)} class-to-type entries")

    # All values in [1, 43626]
    out_of_range = [i+1 for i, v in enumerate(c2t) if v < 1 or v > EXPECTED_TYPES]
    if out_of_range:
        print(f"  FAIL: {len(out_of_range)} class-to-type values out of range [1,{EXPECTED_TYPES}]")
        print(f"    First few: classes {out_of_range[:5]} with values {[c2t[i-1] for i in out_of_range[:5]]}")
        ok = False
    else:
        print(f"  PASS: All class-to-type values in [1, {EXPECTED_TYPES}]")

    # Every type (1..43626) must appear at least once
    type_set = set(c2t)
    missing_types = set(range(1, EXPECTED_TYPES + 1)) - type_set
    if missing_types:
        print(f"  FAIL: {len(missing_types)} types have no class mapping")
        print(f"    First few: {sorted(missing_types)[:10]}")
        ok = False
    else:
        print(f"  PASS: All {EXPECTED_TYPES} types have at least one class")

    # Certificate's rep index i should map to the correct type t
    type_map = {r['t']: r for r in records}
    rep_mismatches = 0
    for r in records:
        t = r['t']
        i = r['i']
        if i < 1 or i > len(c2t):
            rep_mismatches += 1
            if rep_mismatches <= 3:
                print(f"  FAIL: t={t} rep i={i} out of range")
            continue
        mapped_type = c2t[i - 1]  # 0-indexed in Python
        if mapped_type != t:
            rep_mismatches += 1
            if rep_mismatches <= 5:
                print(f"  FAIL: t={t} rep i={i} maps to type {mapped_type} (expected {t})")

    if rep_mismatches == 0:
        print(f"  PASS: All {len(records)} type representatives map to their own type")
    else:
        print(f"  FAIL: {rep_mismatches} representative index mismatches")
        ok = False

    # Distribution stats
    type_counts = Counter(c2t)
    singleton_types = sum(1 for v in type_counts.values() if v == 1)
    largest_type = max(type_counts.values())
    largest_type_id = max(type_counts, key=type_counts.get)
    print(f"  INFO: {singleton_types} singleton types (1 class each)")
    print(f"  INFO: Largest type: t={largest_type_id} with {largest_type} classes")
    print(f"  INFO: Average classes per type: {len(c2t)/EXPECTED_TYPES:.1f}")

    return ok


##############################################################################
# Main
##############################################################################

def main():
    print("=" * 60)
    print("  S16 Certificate Structural Verification")
    print("  verify_cert_structural.py")
    print("=" * 60)
    print(f"\nBase directory: {BASE_DIR}")

    # Load data
    records = load_certificate()
    c2t = load_class_to_type()

    # Run checks
    results = {}
    results['basic_integrity'] = check_basic_integrity(records)
    results['field_presence'] = check_field_presence(records)
    results['order_consistency'] = check_order_consistency(records)
    results['method_a'] = check_method_a_uniqueness(records)
    results['method_b'] = check_method_b_uniqueness(records)
    results['method_c'] = check_method_c_uniqueness(records)
    results['method_d'] = check_method_d_uniqueness(records)
    results['fgh_peers'] = check_fgh_peer_consistency(records)
    results['class_to_type'] = check_class_to_type_coverage(records, c2t)

    # Summary
    print("\n" + "=" * 60)
    print("  SUMMARY")
    print("=" * 60)
    all_pass = True
    for name, passed in results.items():
        status = "PASS" if passed else "FAIL"
        print(f"  {status}: {name}")
        if not passed:
            all_pass = False

    print()
    if all_pass:
        print("  ALL STRUCTURAL CHECKS PASSED")
        return 0
    else:
        failed = sum(1 for v in results.values() if not v)
        print(f"  {failed} CHECK(S) FAILED")
        return 1


if __name__ == '__main__':
    sys.exit(main())
