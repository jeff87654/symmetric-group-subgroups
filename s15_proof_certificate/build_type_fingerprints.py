#!/usr/bin/env python3
"""
Build type_fingerprints_s15.g for the S15 verification.

For each of the ~16,446 isomorphism types (8,001 IdGroup + 8,445 large),
generates a minimal fingerprint record containing only the cheapest invariant
fields needed to distinguish it from all same-order types.

Input files (all in s15_proof_certificate/):
  - s15_large_invariants.g  : 29,088 records with precomputed invariants
  - combined_proof.g        : 20,643 duplicate→representative mappings
  - s15_idgroups.g          : 8,001 IdGroup type strings
  - collision_analysis.json : collision report from analyze_noniso.py

Optional input:
  - additional_invariants.g : extra invariants for collision groups (if any)

Output:
  - type_fingerprints_s15.g : GAP-readable fingerprint file

All large type representatives use originalIndex (position in s15_subgroups.g).
IdGroup types use representative:=0 (placeholder, assigned by verification).
"""

import re
import json
import sys
from collections import defaultdict
from itertools import combinations
from pathlib import Path
from datetime import datetime

# ── Paths ──────────────────────────────────────────────────────────────────
BASE_DIR = Path(r"C:\Users\jeffr\Downloads\Symmetric Groups\s15_proof_certificate")
INVARIANTS_FILE = BASE_DIR / "s15_large_invariants.g"
PROOF_FILE = BASE_DIR / "combined_proof.g"
IDGROUPS_FILE = BASE_DIR / "s15_idgroups.g"
COLLISION_FILE = BASE_DIR / "collision_analysis.json"
ADDITIONAL_INV_FILE = BASE_DIR / "additional_invariants.g"
AUTGROUP_FILE = BASE_DIR / "autgroup_orders.g"
STUBBORN_RESULTS_FILE = BASE_DIR / "stubborn_pair_results.g"
STUBBORN_INV_FILE = BASE_DIR / "stubborn_invariants.g"
OUTPUT_FILE = BASE_DIR / "type_fingerprints_s15.g"


# ── Parsing helpers ────────────────────────────────────────────────────────

def extract_bracket_expr(text, start_pos):
    """Extract a balanced bracket expression starting at start_pos."""
    if start_pos >= len(text) or text[start_pos] != '[':
        return None
    depth = 0
    i = start_pos
    while i < len(text):
        if text[i] == '[':
            depth += 1
        elif text[i] == ']':
            depth -= 1
            if depth == 0:
                return text[start_pos:i + 1]
        i += 1
    return None


def normalize_str(s):
    s = s.replace('\\\n', '').replace('\n', ' ')
    return re.sub(r'\s+', ' ', s).strip()


def parse_histogram_to_dict(hist_str):
    """Parse histogram string into {order: count}."""
    if not hist_str:
        return {}
    result = {}
    for m in re.finditer(r'\[\s*(\d+)\s*,\s*(\d+)\s*\]', hist_str):
        result[int(m.group(1))] = int(m.group(2))
    return result


def parse_abelian_invariants(s):
    """Parse abelian invariants string like '[ 2, 2, 4 ]' into sorted list."""
    if not s or s.strip() == '[ ]' or s.strip() == '[]':
        return []
    nums = [int(x) for x in re.findall(r'\d+', s)]
    return sorted(nums)


def parse_invariants_file(filepath):
    """Parse s15_large_invariants.g → dict keyed by originalIndex."""
    print(f"Parsing {filepath.name}...")
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    records = {}
    rec_starts = [m.start() for m in re.finditer(r'^rec\(', content, re.MULTILINE)]

    for i, start in enumerate(rec_starts):
        end = rec_starts[i + 1] if i + 1 < len(rec_starts) else len(content)
        rec_text = content[start:end]
        rec = {}

        m = re.search(r'originalIndex\s*:=\s*(\d+)', rec_text)
        if not m:
            continue
        rec['originalIndex'] = int(m.group(1))

        m = re.search(r'(?<!\w)order\s*:=\s*(\d+)', rec_text)
        if m:
            rec['order'] = int(m.group(1))

        # sigKey components
        m = re.search(r'sigKey\s*:=\s*', rec_text)
        if m:
            sigkey_str = extract_bracket_expr(rec_text, m.end())
            if sigkey_str:
                rec['sigKey'] = normalize_str(sigkey_str)
                # Parse sigKey components: [order, derivedSize, nrCC, derivedLength, abelianInvariants]
                inner = sigkey_str.strip('[] ')
                # Extract the abelian invariants part (nested bracket)
                ai_match = re.search(r'\[([^\[\]]*)\]\s*\]$', normalize_str(sigkey_str))
                # Parse numerics before the abelian invariants
                before_ai = normalize_str(sigkey_str)
                # Remove outer brackets and abelian invariants
                m2 = re.search(r'^\[\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(-?\d+)', before_ai)
                if m2:
                    rec['derivedSize'] = int(m2.group(2))
                    rec['nrCC'] = int(m2.group(3))
                    rec['derivedLength'] = int(m2.group(4))
                # Parse abelian invariants
                ai_m = re.search(r',\s*(\[[^\]]*\])\s*\]$', normalize_str(sigkey_str))
                if ai_m:
                    rec['abelianInvariants'] = parse_abelian_invariants(ai_m.group(1))

        # histogram
        m = re.search(r'histogram\s*:=\s*', rec_text)
        if m:
            hist_str = extract_bracket_expr(rec_text, m.end())
            if hist_str:
                hist_str = normalize_str(hist_str)
                rec['histogram_str'] = hist_str
                rec['histogram'] = parse_histogram_to_dict(hist_str)

        m = re.search(r'maxOrder\s*:=\s*(\d+)', rec_text)
        if m:
            rec['maxOrder'] = int(m.group(1))

        records[rec['originalIndex']] = rec

    print(f"  Parsed {len(records)} records")
    return records


def parse_proof_duplicates(filepath):
    """Parse combined_proof.g → set of duplicate originalIndices."""
    print(f"Parsing {filepath.name}...")
    duplicates = set()
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            m = re.search(r'duplicate\s*:=\s*(\d+)', line)
            if m:
                duplicates.add(int(m.group(1)))
    print(f"  Found {len(duplicates)} duplicates")
    return duplicates


def parse_idgroups_file(filepath):
    """Parse s15_idgroups.g → list of [order, id] pairs."""
    print(f"Parsing {filepath.name}...")
    types = []
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            m = re.search(r'"?\[\s*(\d+)\s*,\s*(\d+)\s*\]"?', line)
            if m:
                types.append((int(m.group(1)), int(m.group(2))))
    print(f"  Found {len(types)} IdGroup types")
    return types


def find_cheapest_distinguisher(rec_a, rec_b):
    """Find cheapest invariant that distinguishes two same-order records.

    Returns (field_name, value_a, value_b) or None if indistinguishable.
    Invariant cascade (from cheapest to most expensive):
      1. derivedSize
      2. nrCC
      3. derivedLength
      4. abelianInvariants
      5. maxOrder (exponent)
      6. histogram at specific element order k
      7. centerSize (from additional_invariants.g)
      8. frattiniSize
      9. nilpotencyClass
     10. numNormalSubs
     11. derivedSeriesSizes (list comparison)
     12. classSizes (list comparison)
     13. autGroupOrder
     -- Tier 7: from compute_stubborn_invariants.g --
     14. fittingSize
     15. socleSize
     16. lowerCentralSizes (list comparison)
     17. upperCentralSizes (list comparison)
     18. chiefLength
     19. numMaximalSubs
     20. schurMultiplier (list comparison)
     -- Tier 8: p-group specific --
     21. pRank
     22. omegaSizes (list comparison)
     23. agemoSizes (list comparison)
    """
    # Tier 1: sigKey components
    for field in ['derivedSize', 'nrCC', 'derivedLength']:
        va = rec_a.get(field)
        vb = rec_b.get(field)
        if va is not None and vb is not None and va != vb:
            return (field, va, vb)

    # abelianInvariants (list comparison)
    ai_a = rec_a.get('abelianInvariants')
    ai_b = rec_b.get('abelianInvariants')
    if ai_a is not None and ai_b is not None and ai_a != ai_b:
        return ('abelianInvariants', ai_a, ai_b)

    # Tier 2: max element order
    max_a = rec_a.get('maxOrder')
    max_b = rec_b.get('maxOrder')
    if max_a is not None and max_b is not None and max_a != max_b:
        return ('maxElementOrder', max_a, max_b)

    # Tier 3: histogram at specific element order
    hist_a = rec_a.get('histogram', {})
    hist_b = rec_b.get('histogram', {})
    if hist_a and hist_b:
        all_orders = sorted(set(hist_a.keys()) | set(hist_b.keys()))
        for k in all_orders:
            ca = hist_a.get(k, 0)
            cb = hist_b.get(k, 0)
            if ca != cb:
                field = f"nrElementsOfOrder{k}"
                return (field, ca, cb)

    # Tier 4: additional invariants (from compute_additional_invariants.g)
    for field in ['centerSize', 'frattiniSize', 'nilpotencyClass', 'numNormalSubs']:
        va = rec_a.get(field)
        vb = rec_b.get(field)
        if va is not None and vb is not None and va != vb:
            return (field, va, vb)

    # derivedSeriesSizes (list comparison)
    dss_a = rec_a.get('derivedSeriesSizes')
    dss_b = rec_b.get('derivedSeriesSizes')
    if dss_a is not None and dss_b is not None and dss_a != dss_b:
        return ('derivedSeriesSizes', dss_a, dss_b)

    # classSizes (list comparison)
    cs_a = rec_a.get('classSizes')
    cs_b = rec_b.get('classSizes')
    if cs_a is not None and cs_b is not None and cs_a != cs_b:
        return ('classSizes', cs_a, cs_b)

    # autGroupOrder (expensive but very discriminating)
    aut_a = rec_a.get('autGroupOrder')
    aut_b = rec_b.get('autGroupOrder')
    if aut_a is not None and aut_b is not None and aut_a != aut_b:
        return ('autGroupOrder', aut_a, aut_b)

    # Tier 7: stubborn invariants (from compute_stubborn_invariants.g)
    for field in ['fittingSize', 'socleSize']:
        va = rec_a.get(field)
        vb = rec_b.get(field)
        if va is not None and vb is not None and va != vb:
            return (field, va, vb)

    for list_field in ['lowerCentralSizes', 'upperCentralSizes']:
        va = rec_a.get(list_field)
        vb = rec_b.get(list_field)
        if va is not None and vb is not None and va != vb:
            return (list_field, va, vb)

    for field in ['chiefLength', 'numMaximalSubs']:
        va = rec_a.get(field)
        vb = rec_b.get(field)
        if va is not None and vb is not None and va != vb:
            return (field, va, vb)

    # schurMultiplier (list comparison, moderate-expensive)
    sm_a = rec_a.get('schurMultiplier')
    sm_b = rec_b.get('schurMultiplier')
    if sm_a is not None and sm_b is not None and sm_a != sm_b:
        return ('schurMultiplier', sm_a, sm_b)

    # Tier 8: p-group specific invariants
    for field in ['pRank']:
        va = rec_a.get(field)
        vb = rec_b.get(field)
        if va is not None and vb is not None and va != vb:
            return (field, va, vb)

    for list_field in ['omegaSizes', 'agemoSizes']:
        va = rec_a.get(list_field)
        vb = rec_b.get(list_field)
        if va is not None and vb is not None and va != vb:
            return (list_field, va, vb)

    return None


def parse_additional_invariants(filepath):
    """Parse additional_invariants.g → dict keyed by originalIndex.

    Each record has: centerSize, frattiniSize, nilpotencyClass,
    classSizes (list), derivedSeriesSizes (list), numNormalSubs.
    """
    print(f"Parsing {filepath.name}...")
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    results = {}
    rec_starts = [m.start() for m in re.finditer(r'rec\(', content)]

    for i, start in enumerate(rec_starts):
        end = rec_starts[i + 1] if i + 1 < len(rec_starts) else len(content)
        rec_text = content[start:end]

        m = re.search(r'originalIndex\s*:=\s*(\d+)', rec_text)
        if not m:
            continue
        idx = int(m.group(1))
        rec = {'originalIndex': idx}

        for field in ['centerSize', 'frattiniSize', 'nilpotencyClass', 'numNormalSubs', 'order']:
            m = re.search(rf'{field}\s*:=\s*(-?\d+)', rec_text)
            if m:
                rec[field] = int(m.group(1))

        # classSizes and derivedSeriesSizes are lists
        for list_field in ['classSizes', 'derivedSeriesSizes']:
            m = re.search(rf'{list_field}\s*:=\s*', rec_text)
            if m:
                bracket_str = extract_bracket_expr(rec_text, m.end())
                if bracket_str:
                    nums = [int(x) for x in re.findall(r'-?\d+', bracket_str)]
                    rec[list_field] = nums

        results[idx] = rec

    print(f"  Parsed {len(results)} additional invariant records")
    return results


def parse_stubborn_invariants(filepath):
    """Parse stubborn_invariants.g -> dict keyed by originalIndex.

    Each record has: fittingSize, socleSize, lowerCentralSizes,
    upperCentralSizes, chiefLength, numMaximalSubs, schurMultiplier,
    and for p-groups: pRank, omegaSizes, agemoSizes.
    """
    print(f"Parsing {filepath.name}...")
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    results = {}
    rec_starts = [m.start() for m in re.finditer(r'rec\(', content)]

    for i, start in enumerate(rec_starts):
        end = rec_starts[i + 1] if i + 1 < len(rec_starts) else len(content)
        rec_text = content[start:end]

        m = re.search(r'originalIndex\s*:=\s*(\d+)', rec_text)
        if not m:
            continue
        idx = int(m.group(1))
        rec = {'originalIndex': idx}

        for field in ['order', 'fittingSize', 'socleSize', 'chiefLength',
                       'numMaximalSubs', 'pRank']:
            m = re.search(rf'{field}\s*:=\s*(-?\d+)', rec_text)
            if m:
                rec[field] = int(m.group(1))

        for list_field in ['lowerCentralSizes', 'upperCentralSizes',
                           'schurMultiplier', 'omegaSizes', 'agemoSizes']:
            m = re.search(rf'{list_field}\s*:=\s*', rec_text)
            if m:
                bracket_str = extract_bracket_expr(rec_text, m.end())
                if bracket_str:
                    nums = [int(x) for x in re.findall(r'-?\d+', bracket_str)]
                    rec[list_field] = nums

        results[idx] = rec

    print(f"  Parsed {len(results)} stubborn invariant records")
    return results


def main():
    print("=" * 72)
    print("  Build S15 Type Fingerprints")
    print("=" * 72)
    print()

    # ── Step 1: Parse data ──
    records = parse_invariants_file(INVARIANTS_FILE)
    duplicates = parse_proof_duplicates(PROOF_FILE)
    idgroup_types = parse_idgroups_file(IDGROUPS_FILE)

    # Load collision analysis
    if COLLISION_FILE.exists():
        with open(COLLISION_FILE, 'r') as f:
            collision_data = json.load(f)
        print(f"Loaded collision analysis: "
              f"{collision_data.get('real_collisions', '?')} real collisions")
    else:
        print("WARNING: collision_analysis.json not found. Run analyze_noniso.py first.")
        collision_data = None

    # Load additional invariants (if computed)
    if ADDITIONAL_INV_FILE.exists():
        additional = parse_additional_invariants(ADDITIONAL_INV_FILE)
        # Merge into records
        merged = 0
        for idx, add_rec in additional.items():
            if idx in records:
                for field in ['centerSize', 'frattiniSize', 'nilpotencyClass',
                              'numNormalSubs', 'classSizes', 'derivedSeriesSizes']:
                    if field in add_rec:
                        records[idx][field] = add_rec[field]
                merged += 1
        print(f"  Merged additional invariants for {merged} groups")
    else:
        print("No additional_invariants.g found (may not be needed)")

    # Load autgroup orders (second round, if computed)
    if AUTGROUP_FILE.exists():
        print(f"Parsing {AUTGROUP_FILE.name}...")
        with open(AUTGROUP_FILE, 'r', encoding='utf-8') as f:
            aut_content = f.read()
        aut_merged = 0
        for m in re.finditer(r'originalIndex\s*:=\s*(\d+).*?autGroupOrder\s*:=\s*(\d+)', aut_content, re.DOTALL):
            idx = int(m.group(1))
            aut_order = int(m.group(2))
            if idx in records:
                records[idx]['autGroupOrder'] = aut_order
                aut_merged += 1
        print(f"  Merged autGroupOrder for {aut_merged} groups")
    else:
        print("No autgroup_orders.g found (may not be needed)")

    # Load stubborn invariants (third round, if computed)
    if STUBBORN_INV_FILE.exists():
        stubborn_inv = parse_stubborn_invariants(STUBBORN_INV_FILE)
        stub_merged = 0
        for idx, stub_rec in stubborn_inv.items():
            if idx in records:
                for field in ['fittingSize', 'socleSize', 'chiefLength',
                              'numMaximalSubs', 'pRank',
                              'lowerCentralSizes', 'upperCentralSizes',
                              'schurMultiplier', 'omegaSizes', 'agemoSizes']:
                    if field in stub_rec:
                        records[idx][field] = stub_rec[field]
                stub_merged += 1
        print(f"  Merged stubborn invariants for {stub_merged} groups")
    else:
        print("No stubborn_invariants.g found (may not be needed)")

    # Load GAP-certified non-isomorphic pairs (from test_stubborn_pairs.g)
    gap_certified_pairs = []
    if STUBBORN_RESULTS_FILE.exists():
        print(f"Parsing {STUBBORN_RESULTS_FILE.name}...")
        with open(STUBBORN_RESULTS_FILE, 'r', encoding='utf-8') as f:
            stub_content = f.read()
        for m in re.finditer(
            r'indexA\s*:=\s*(\d+)\s*,\s*indexB\s*:=\s*(\d+)\s*,\s*order\s*:=\s*(\d+)\s*,\s*result\s*:=\s*"non-isomorphic"',
            stub_content
        ):
            gap_certified_pairs.append((int(m.group(1)), int(m.group(2)), int(m.group(3))))
        print(f"  Found {len(gap_certified_pairs)} GAP-certified non-isomorphic pairs")
    else:
        print("No stubborn_pair_results.g found (may not be needed)")

    # ── Step 2: Compute representative set ──
    all_indices = set(records.keys())
    rep_set = all_indices - duplicates
    rep_list = sorted(rep_set)

    print(f"\n  Representatives: {len(rep_set)}")
    print(f"  IdGroup types: {len(idgroup_types)}")

    # ── Step 3: For each pair of same-order reps, find minimal distinguishing fields ──
    # Group reps by order
    order_buckets = defaultdict(list)
    for idx in rep_list:
        order_buckets[records[idx]['order']].append(idx)

    # For each representative, track which fields are needed to distinguish it
    # from all other same-order reps
    needed_fields = defaultdict(set)  # originalIndex → set of field names

    # Build set of GAP-certified pairs for quick lookup
    gap_certified_set = set()
    for a, b, _ in gap_certified_pairs:
        gap_certified_set.add((min(a, b), max(a, b)))

    total_pairs = 0
    distinguished = 0
    gap_certified_count = 0
    undistinguished = 0

    for order, indices in sorted(order_buckets.items()):
        if len(indices) < 2:
            continue

        for a, b in combinations(indices, 2):
            total_pairs += 1
            result = find_cheapest_distinguisher(records[a], records[b])

            if result is not None:
                field, va, vb = result
                needed_fields[a].add(field)
                needed_fields[b].add(field)
                distinguished += 1
            else:
                if (min(a, b), max(a, b)) in gap_certified_set:
                    # GAP-certified non-isomorphic pair
                    gap_certified_count += 1
                    needed_fields[a].add('_GAP_CERTIFIED')
                    needed_fields[b].add('_GAP_CERTIFIED')
                else:
                    undistinguished += 1
                    print(f"  UNDISTINGUISHED: ({a}, {b}) order={order}")
                    needed_fields[a].add('_NEEDS_ADDITIONAL')
                    needed_fields[b].add('_NEEDS_ADDITIONAL')

    print(f"\n  Same-order pairs: {total_pairs}")
    print(f"  Distinguished by invariants: {distinguished}")
    print(f"  Distinguished by GAP IsomorphismGroups: {gap_certified_count}")
    print(f"  Undistinguished: {undistinguished}")

    if undistinguished > 0:
        print(f"\n  WARNING: {undistinguished} pairs need additional invariants!")
        print(f"  Run compute_additional_invariants.g first.")
        # Continue anyway to generate partial fingerprints

    # ── Step 4: Generate fingerprint file ──
    print(f"\nGenerating {OUTPUT_FILE.name}...")

    # Invariant field priority (order matters for the cascade in verification)
    FIELD_PRIORITY = [
        'derivedSize', 'nrCC', 'derivedLength', 'abelianInvariants',
        'exponent',
    ]
    # Dynamic element-order fields get added as needed

    type_index = 0

    with open(OUTPUT_FILE, 'w', encoding='utf-8') as out:
        out.write("# Minimal type fingerprints for S15\n")
        out.write(f"# {len(idgroup_types)} IdGroup types + "
                  f"{len(rep_set)} large types = "
                  f"{len(idgroup_types) + len(rep_set)} total\n")
        out.write("# Each large type stores only the fields needed to distinguish\n")
        out.write("# it from all same-order types (from sigKey/histogram)\n")
        out.write("#\n")
        out.write("# Field cascade (cheap to expensive):\n")
        out.write("#   derivedSize, nrCC, derivedLength, abelianInvariants,\n")
        out.write("#   maxElementOrder, nrElementsOfOrderK (various K from histogram),\n")
        out.write("#   centerSize, frattiniSize, nilpotencyClass, numNormalSubs,\n")
        out.write("#   derivedSeriesSizes, classSizes, autGroupOrder,\n")
        out.write("#   fittingSize, socleSize, lowerCentralSizes, upperCentralSizes,\n")
        out.write("#   chiefLength, numMaximalSubs, schurMultiplier,\n")
        out.write("#   pRank, omegaSizes, agemoSizes (p-groups only)\n")
        out.write("#\n")
        out.write(f"# {len(gap_certified_pairs)} pairs resolved by direct GAP IsomorphismGroups\n")
        out.write(f"#\n")
        out.write(f"# Generated: {datetime.now().isoformat()}\n\n")

        out.write("S15_TYPE_INFO := [\n")

        # IdGroup types first (representative=0, assigned by verification Phase B)
        for ord_val, id_val in idgroup_types:
            type_index += 1
            out.write(f"  rec(typeIndex:={type_index}, representative:=0, "
                      f"order:={ord_val}, "
                      f"idGroup:=[ {ord_val}, {id_val} ]),\n")

        n_idg = type_index

        # Large types with minimal distinguishing fields
        for idx in rep_list:
            type_index += 1
            rec = records[idx]
            fields = needed_fields.get(idx, set())

            parts = [
                f"typeIndex:={type_index}",
                f"representative:={idx}",
                f"order:={rec['order']}",
                "idGroup:=fail",
            ]

            # Add needed fields from sigKey components
            if 'derivedSize' in fields and 'derivedSize' in rec:
                parts.append(f"derivedSize:={rec['derivedSize']}")
            if 'nrCC' in fields and 'nrCC' in rec:
                parts.append(f"nrCC:={rec['nrCC']}")
            if 'derivedLength' in fields and 'derivedLength' in rec:
                parts.append(f"derivedLength:={rec['derivedLength']}")
            if 'abelianInvariants' in fields and 'abelianInvariants' in rec:
                ai = rec['abelianInvariants']
                ai_str = "[ " + ", ".join(str(x) for x in ai) + " ]" if ai else "[ ]"
                parts.append(f"abelianInvariants:={ai_str}")
            if 'maxElementOrder' in fields and 'maxOrder' in rec:
                parts.append(f"maxElementOrder:={rec['maxOrder']}")

            # Add element-order count fields from histogram
            hist = rec.get('histogram', {})
            for field in sorted(fields):
                m = re.match(r'nrElementsOfOrder(\d+)', field)
                if m:
                    k = int(m.group(1))
                    count = hist.get(k, 0)
                    parts.append(f"{field}:={count}")

            # Add additional invariant fields (from compute_additional_invariants.g)
            for field in ['centerSize', 'frattiniSize', 'nilpotencyClass', 'numNormalSubs']:
                if field in fields and field in rec:
                    parts.append(f"{field}:={rec[field]}")

            # derivedSeriesSizes (list field)
            if 'derivedSeriesSizes' in fields and 'derivedSeriesSizes' in rec:
                dss = rec['derivedSeriesSizes']
                dss_str = "[ " + ", ".join(str(x) for x in dss) + " ]"
                parts.append(f"derivedSeriesSizes:={dss_str}")

            # classSizes (list field)
            if 'classSizes' in fields and 'classSizes' in rec:
                cs = rec['classSizes']
                cs_str = "[ " + ", ".join(str(x) for x in cs) + " ]"
                parts.append(f"classSizes:={cs_str}")

            # autGroupOrder (from compute_autgroup_order.g, second round)
            if 'autGroupOrder' in fields and 'autGroupOrder' in rec:
                parts.append(f"autGroupOrder:={rec['autGroupOrder']}")

            # Stubborn invariants (from compute_stubborn_invariants.g, third round)
            for field in ['fittingSize', 'socleSize', 'chiefLength',
                          'numMaximalSubs', 'pRank']:
                if field in fields and field in rec:
                    parts.append(f"{field}:={rec[field]}")

            for list_field in ['lowerCentralSizes', 'upperCentralSizes',
                               'schurMultiplier', 'omegaSizes', 'agemoSizes']:
                if list_field in fields and list_field in rec:
                    vals = rec[list_field]
                    vals_str = "[ " + ", ".join(str(x) for x in vals) + " ]"
                    parts.append(f"{list_field}:={vals_str}")

            # Mark groups that are part of GAP-certified pairs
            if '_GAP_CERTIFIED' in fields:
                parts.append("gapCertified:=true")

            # For singleton-order reps (no same-order peers), store at least
            # derivedSize and nrCC for verification
            if not fields or fields == {'_GAP_CERTIFIED'}:
                if 'derivedSize' in rec:
                    parts.append(f"derivedSize:={rec['derivedSize']}")
                if 'nrCC' in rec:
                    parts.append(f"nrCC:={rec['nrCC']}")

            out.write(f"  rec({', '.join(parts)})")
            if type_index < len(idgroup_types) + len(rep_set):
                out.write(",")
            out.write("\n")

        out.write("];\n\n")

        # Write GAP-certified non-isomorphic pairs
        out.write(f"# {len(gap_certified_pairs)} pairs certified non-isomorphic by GAP IsomorphismGroups\n")
        out.write("# These pairs share all computed invariants but GAP confirms they are\n")
        out.write("# non-isomorphic. Verification: IsomorphismGroups(G_a, G_b) = fail\n")
        out.write("S15_GAP_CERTIFIED_NONISO := [\n")
        for i, (a, b, order) in enumerate(gap_certified_pairs):
            comma = "," if i < len(gap_certified_pairs) - 1 else ""
            out.write(f"  [ {a}, {b}, {order} ]{comma}\n")
        out.write("];\n")

    n_large = type_index - n_idg
    print(f"  Written {type_index} type records "
          f"({n_idg} IdGroup + {n_large} large)")
    print(f"  Written {len(gap_certified_pairs)} GAP-certified non-iso pairs")
    print(f"  File size: {OUTPUT_FILE.stat().st_size:,} bytes")

    # Verify counts
    expected_total = len(idgroup_types) + len(rep_set)
    assert type_index == expected_total, \
        f"Type count mismatch: wrote {type_index}, expected {expected_total}"

    print(f"\n  A174511(15) = {expected_total}")
    print(f"  ({len(idgroup_types)} IdGroup + {len(rep_set)} large)")


if __name__ == '__main__':
    main()
