#!/usr/bin/env python3
"""
Creates a concise summary of subgroups sorted by order.
Reads from gap_groups.txt and outputs a summary table.
"""

import json
from pathlib import Path
from datetime import datetime


def parse_groups_file(filepath: str) -> list:
    """Parse the GAP groups output file."""
    groups = []
    current_group = {}

    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except FileNotFoundError:
        return []

    lines = content.split('\n')
    in_groups = False

    for line in lines:
        line = line.strip()

        if line == 'GROUPS_START':
            in_groups = True
        elif line == 'GROUPS_END':
            in_groups = False
        elif in_groups:
            if line.startswith('GROUP:'):
                current_group = {'number': int(line[6:])}
            elif line.startswith('FIRST_FOUND:'):
                current_group['first_found'] = line[12:]
            elif line.startswith('ORDER:'):
                current_group['order'] = int(line[6:])
            elif line.startswith('STRUCTURE:'):
                current_group['structure'] = line[10:]
            elif line.startswith('DEGREE:'):
                current_group['degree'] = int(line[7:])
            elif line.startswith('GENERATORS_IMAGE:'):
                current_group['generators_image'] = line[17:]
            elif line.startswith('GENERATORS_CYCLE:'):
                current_group['generators_cycle'] = line[17:]
            elif line == 'GROUP_END':
                groups.append(current_group)
                current_group = {}

    return groups


def main():
    output_dir = Path('.')
    gap_groups_file = output_dir / 'gap_groups.txt'

    # Parse groups
    groups = parse_groups_file(str(gap_groups_file))

    if not groups:
        print("No groups found in gap_groups.txt")
        return

    # Sort by order, then by first appearance
    def sort_key(g):
        sn_order = {f'S{i}': i for i in range(1, 20)}
        return (g.get('order', 0), sn_order.get(g.get('first_found', 'S1'), 99))

    groups_sorted = sorted(groups, key=sort_key)

    # Write summary
    summary_file = output_dir / 'subgroups_summary.txt'
    with open(summary_file, 'w', encoding='utf-8') as f:
        f.write("=" * 80 + "\n")
        f.write("SUBGROUPS OF SYMMETRIC GROUPS - SUMMARY\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"Total unique groups: {len(groups)}\n")
        f.write("=" * 80 + "\n\n")

        # Header
        f.write(f"{'#':<6} {'Order':<12} {'First In':<10} {'Structure'}\n")
        f.write("-" * 80 + "\n")

        for g in groups_sorted:
            num = g.get('number', '?')
            order = g.get('order', '?')
            first = g.get('first_found', '?')
            struct = g.get('structure', '?')
            f.write(f"{num:<6} {order:<12} {first:<10} {struct}\n")

        f.write("-" * 80 + "\n")
        f.write(f"\nTotal: {len(groups)} groups\n")

        # Summary by first appearance
        f.write("\n" + "=" * 80 + "\n")
        f.write("GROUPS BY FIRST APPEARANCE\n")
        f.write("=" * 80 + "\n")

        by_sn = {}
        for g in groups:
            sn = g.get('first_found', 'Unknown')
            by_sn[sn] = by_sn.get(sn, 0) + 1

        for sn in sorted(by_sn.keys(), key=lambda x: int(x[1:]) if x[1:].isdigit() else 99):
            f.write(f"  {sn}: {by_sn[sn]} groups\n")

    print(f"Summary written to: {summary_file}")
    print(f"Total groups: {len(groups)}")


if __name__ == '__main__':
    main()
