#!/usr/bin/env python3
"""
Phase 0: Factor Order Analysis

Parses s14_large_invariants_clean.g and classifies every DP group's factors:
- IdGroup-compatible: order < 2000 and not in {512, 768, 1024, 1536}
- 2-group factor: order in {512, 1024}
- Excluded: order in {768, 1536}
- Large: order >= 2000

Output: factor_analysis.json
"""

import re
import json
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
INPUT_FILE = os.path.join(SCRIPT_DIR, "..", "conjugacy_cache", "s14_large_invariants_clean.g")

IDGROUP_EXCLUDED = {512, 768, 1024, 1536}


def classify_factor_order(order):
    """Classify a factor order for IdGroup compatibility."""
    if order >= 2000:
        return "large"
    if order in IDGROUP_EXCLUDED:
        if order in (512, 1024):
            return "2group"
        return "excluded"  # 768, 1536
    return "idgroup_ok"


def parse_invariants_file(filepath):
    """Parse the s14_large_invariants_clean.g file to extract group records.

    Uses a bracket-matching parser for robustness with nested structures.
    """
    with open(filepath, "r") as f:
        content = f.read()

    groups = []
    total_dp = 0
    total_non_dp = 0

    # Find each rec(...) block
    # We'll parse index, isDirectProduct, factors, factorOrders, factorGens
    rec_pattern = re.compile(r'rec\(')

    pos = 0
    while True:
        m = rec_pattern.search(content, pos)
        if not m:
            break

        # Find the matching closing paren using bracket counting
        start = m.start()
        depth = 0
        i = m.end() - 1  # position of '('
        for i in range(m.end() - 1, len(content)):
            if content[i] == '(':
                depth += 1
            elif content[i] == ')':
                depth -= 1
                if depth == 0:
                    break

        rec_text = content[start:i+1]
        pos = i + 1

        # Extract index
        idx_m = re.search(r'index\s*:=\s*(\d+)', rec_text)
        if not idx_m:
            continue
        index = int(idx_m.group(1))

        # Extract isDirectProduct
        dp_m = re.search(r'isDirectProduct\s*:=\s*(true|false)', rec_text)
        if not dp_m:
            continue
        is_dp = dp_m.group(1) == "true"

        if not is_dp:
            total_non_dp += 1
            continue

        total_dp += 1

        # Extract factorOrders
        fo_m = re.search(r'factorOrders\s*:=\s*\[\s*([^\]]*)\]', rec_text)
        if not fo_m:
            continue
        fo_text = fo_m.group(1).strip()
        if not fo_text:
            continue
        factor_orders = [int(x.strip()) for x in fo_text.split(",") if x.strip()]

        # Extract factor names
        # factors := [ "name1", "name2", ... ]
        fac_m = re.search(r'factors\s*:=\s*\[', rec_text)
        factor_names = []
        if fac_m:
            # Parse the list of strings
            fstart = fac_m.end()
            fend = rec_text.find(']', fstart)
            ftext = rec_text[fstart:fend]
            factor_names = re.findall(r'"([^"]*)"', ftext)

        # Classify each factor
        factor_classes = []
        all_idgroup = True
        has_fallback = False
        for order in factor_orders:
            cls = classify_factor_order(order)
            factor_classes.append(cls)
            if cls != "idgroup_ok":
                all_idgroup = False
            if cls in ("2group", "excluded", "large"):
                has_fallback = True

        groups.append({
            "index": index,
            "factorOrders": factor_orders,
            "factorNames": factor_names,
            "factorClasses": factor_classes,
            "allIdGroup": all_idgroup,
            "hasFallback": has_fallback,
            "numFactors": len(factor_orders)
        })

    return groups, total_dp, total_non_dp


def main():
    print("Phase 0: Factor Order Analysis")
    print(f"Input: {INPUT_FILE}")
    print()

    groups, total_dp, total_non_dp = parse_invariants_file(INPUT_FILE)

    print(f"Total records parsed: {total_dp + total_non_dp}")
    print(f"  Direct products (DP): {total_dp}")
    print(f"  Non-direct products: {total_non_dp}")
    print()

    # Count by classification
    all_idgroup_count = sum(1 for g in groups if g["allIdGroup"])
    fallback_count = sum(1 for g in groups if g["hasFallback"])

    print(f"DP groups with ALL factors IdGroup-compatible: {all_idgroup_count}")
    print(f"DP groups needing fallback (some non-IdGroup factor): {fallback_count}")
    print()

    # Detailed factor classification
    factor_class_counts = {"idgroup_ok": 0, "2group": 0, "excluded": 0, "large": 0}
    for g in groups:
        for cls in g["factorClasses"]:
            factor_class_counts[cls] += 1

    print("Factor classification counts (across all DP groups):")
    for cls, count in sorted(factor_class_counts.items()):
        print(f"  {cls}: {count}")
    print()

    # Unique factor orders in non-IdGroup categories
    non_idgroup_orders = {}
    for g in groups:
        for order, cls in zip(g["factorOrders"], g["factorClasses"]):
            if cls != "idgroup_ok":
                non_idgroup_orders.setdefault(cls, set()).add(order)

    print("Non-IdGroup factor orders by category:")
    for cls in sorted(non_idgroup_orders.keys()):
        orders = sorted(non_idgroup_orders[cls])
        print(f"  {cls}: {orders}")
    print()

    # Groups needing fallback, grouped by their non-IdGroup factor orders
    fallback_groups = [g for g in groups if g["hasFallback"]]
    fallback_by_orders = {}
    for g in fallback_groups:
        non_id_orders = tuple(sorted(
            order for order, cls in zip(g["factorOrders"], g["factorClasses"])
            if cls != "idgroup_ok"
        ))
        fallback_by_orders.setdefault(non_id_orders, []).append(g["index"])

    print(f"Fallback groups by non-IdGroup factor orders ({len(fallback_by_orders)} distinct combos):")
    for orders, indices in sorted(fallback_by_orders.items()):
        print(f"  {list(orders)}: {len(indices)} groups (indices: {indices[:5]}{'...' if len(indices) > 5 else ''})")

    # Write output
    output = {
        "totalRecords": total_dp + total_non_dp,
        "totalDP": total_dp,
        "totalNonDP": total_non_dp,
        "allIdGroupCount": all_idgroup_count,
        "fallbackCount": fallback_count,
        "factorClassCounts": factor_class_counts,
        "nonIdGroupOrders": {cls: sorted(orders) for cls, orders in non_idgroup_orders.items()},
        "fallbackByOrders": {str(k): v for k, v in fallback_by_orders.items()},
        "groups": groups
    }

    output_file = os.path.join(SCRIPT_DIR, "factor_analysis.json")
    with open(output_file, "w") as f:
        json.dump(output, f, indent=2)

    print(f"\nOutput written to: {output_file}")


if __name__ == "__main__":
    main()
