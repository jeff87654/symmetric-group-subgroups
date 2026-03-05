#!/usr/bin/env python3
"""Build (type, orbit-type) buckets for conjugacy verification.
Writes non-singleton buckets to a GAP-readable file, sorted by size ascending.
"""

import argparse, re, os, sys
from collections import defaultdict


def compute_orbit_type(generators):
    if not generators:
        return (1,) * 16
    parent = list(range(17))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        a, b = find(a), find(b)
        if a != b:
            parent[a] = b

    for gen in generators:
        for i in range(16):
            if gen[i] != i + 1:
                union(i + 1, gen[i])
    sizes = defaultdict(int)
    for i in range(1, 17):
        sizes[find(i)] += 1
    return tuple(sorted(sizes.values()))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-dir", default=None,
                        help="Path to s16_final_results_reindexed/")
    args = parser.parse_args()
    REINDEXED = args.base_dir or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    print("Reading class-to-type...")
    with open(os.path.join(REINDEXED, "s16_class_to_type.g")) as f:
        text = f.read()
    m = re.search(r'\[\s*([\d\s,]+)\s*\]', text, re.DOTALL)
    c2t = [int(x) for x in m.group(1).replace('\n', ' ').split(',') if x.strip()]
    print(f"  {len(c2t)} classes")

    print("Parsing subgroups and computing orbit types...")
    with open(os.path.join(REINDEXED, "s16_subgroups.g")) as f:
        text = f.read()

    start = text.index('return [') + len('return [')
    buckets = defaultdict(list)
    pos = start
    entry_idx = 0

    while pos < len(text):
        while pos < len(text) and text[pos] in ' \t\n\r,':
            pos += 1
        if pos >= len(text) or text[pos] == ']':
            break
        if text[pos] != '[':
            break
        depth = 0
        entry_start = pos
        while pos < len(text):
            if text[pos] == '[':
                depth += 1
            elif text[pos] == ']':
                depth -= 1
                if depth == 0:
                    pos += 1
                    break
            pos += 1
        entry_text = text[entry_start:pos]
        inner_lists = re.findall(r'\[([\d,\s]+)\]', entry_text)
        generators = []
        for il in inner_lists:
            images = [int(x) for x in il.split(',')]
            if len(images) == 16:
                generators.append(images)
        orbit_type = compute_orbit_type(generators)
        t = c2t[entry_idx]
        buckets[(t, orbit_type)].append(entry_idx + 1)
        entry_idx += 1
        if entry_idx % 100000 == 0:
            print(f"  {entry_idx:,}...", file=sys.stderr)

    print(f"  {entry_idx:,} entries, {len(buckets):,} total buckets")

    multi = {k: v for k, v in buckets.items() if len(v) > 1}
    sorted_buckets = sorted(multi.values(), key=len)
    total_pairs = sum(len(b) * (len(b) - 1) // 2 for b in sorted_buckets)
    total_entries = sum(len(b) for b in sorted_buckets)
    print(f"  Non-singleton: {len(sorted_buckets):,} buckets, "
          f"{total_entries:,} entries, {total_pairs:,} pairs")

    out_path = os.path.join(REINDEXED, "conj_buckets.g")
    print(f"Writing {out_path}...")
    with open(out_path, 'w') as f:
        f.write(f"# Conjugacy verification buckets\n")
        f.write(f"# {len(sorted_buckets)} non-singleton (type, orbit-type) buckets\n")
        f.write(f"# {total_pairs} total pairwise checks (before sub-bucketing)\n")
        f.write(f"# Sorted by size (ascending)\n")
        f.write(f"CONJ_BUCKETS := [\n")
        for i, bucket in enumerate(sorted_buckets):
            line = "[" + ",".join(str(x) for x in bucket) + "]"
            if i < len(sorted_buckets) - 1:
                line += ","
            f.write(line + "\n")
        f.write("];\n")

    print(f"  Written {os.path.getsize(out_path):,} bytes")


if __name__ == '__main__':
    main()
