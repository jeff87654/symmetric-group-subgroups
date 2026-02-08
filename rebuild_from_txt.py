#!/usr/bin/env python3
"""Rebuild the GAP database from the text file backup."""

import subprocess
import sys
import re

def windows_to_cygwin_path(win_path: str) -> str:
    path = str(win_path).replace('\\', '/')
    if len(path) >= 2 and path[1] == ':':
        drive = path[0].lower()
        path = f'/cygdrive/{drive}{path[2:]}'
    return path

def parse_groups_file(filename: str) -> list:
    """Parse the gap_groups text file format."""
    groups = []
    current_group = {}

    with open(filename, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line == 'GROUPS_START':
                continue
            elif line.startswith('GROUP:'):
                current_group = {'number': int(line.split(':')[1])}
            elif line.startswith('FIRST_FOUND:'):
                current_group['first_found'] = line.split(':')[1]
            elif line.startswith('ORDER:'):
                current_group['order'] = int(line.split(':')[1])
            elif line.startswith('STRUCTURE:'):
                current_group['structure'] = line.split(':', 1)[1]
            elif line.startswith('DEGREE:'):
                current_group['degree'] = int(line.split(':')[1])
            elif line.startswith('GENERATORS_IMAGE:'):
                current_group['generators_image'] = line.split(':', 1)[1]
            elif line.startswith('GENERATORS_CYCLE:'):
                current_group['generators_cycle'] = line.split(':', 1)[1]
            elif line == 'GROUP_END':
                groups.append(current_group)
                current_group = {}

    return groups

# Parse the backup file
input_file = r'C:\Users\jeffr\Downloads\Symmetric Groups\gap_groups - Copy (3).txt'
groups = parse_groups_file(input_file)
print(f"Loaded {len(groups)} groups from backup")

# Generate GAP code
gap_code = '''
dbFile := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/subgroups_db.g";
Print("Rebuilding database from backup...\\n");

# Create empty database
db := rec( groups := [], index := rec() );

# Helper to compute fingerprint
GroupFingerprint := function(G)
    local fp, ord, smallId;
    ord := Size(G);
    fp := rec(
        size := ord,
        centerSize := Size(Center(G)),
        derivedSize := Size(DerivedSubgroup(G)),
        frattiniSize := Size(FrattiniSubgroup(G)),
        abelianInvariants := AbelianInvariants(G),
        isAbelian := IsAbelian(G),
        isSolvable := IsSolvable(G),
        isNilpotent := IsNilpotent(G),
        exponent := Exponent(G),
        nrConjugacyClasses := NrConjugacyClasses(G),
        smallGroupId := fail,
        derivedLength := fail
    );
    # Try to get SmallGroup ID (works for some orders <= 2000)
    # Note: Some orders don't have SmallGroups ID data installed by default
    # These are powers of 2 >= 512, and multiples like 768, 1536
    if ord <= 2000 and ord > 1 and not ord in [512, 768, 1024, 1536] then
        smallId := IdSmallGroup(G);
        if smallId <> fail then
            fp.smallGroupId := smallId;
        fi;
    fi;
    if fp.isSolvable then
        fp.derivedLength := DerivedLength(G);
    fi;
    return fp;
end;

# Process each group
'''

# Add each group
for i, g in enumerate(groups):
    gens_image = g.get('generators_image', '')
    degree = g.get('degree', 2)
    first_found = g.get('first_found', 'S2')
    structure = g.get('structure', '?')

    # Escape special characters in structure description for GAP
    structure = structure.replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ').replace('\r', '')

    # Parse generators from image format
    if gens_image:
        # Format is like: [ 2, 1 ];[ 3, 2, 1 ]
        gen_lists = gens_image.split(';')
        gens_gap = []
        for gen in gen_lists:
            gen = gen.strip()
            if gen:
                gens_gap.append(gen)
        if gens_gap:
            gens_str = ', '.join(gens_gap)
        else:
            gens_str = ''
    else:
        gens_str = ''

    if gens_str:
        gap_code += f'''
gens := [{gens_str}];
G := Group(List(gens, PermList));
'''
    else:
        gap_code += '''
gens := [];
G := Group(());
'''

    gap_code += f'''
fp := GroupFingerprint(G);
Add(db.groups, rec(
    fingerprint := fp,
    generators := gens,
    structure := "{structure}",
    firstFoundIn := "{first_found}",
    degree := {degree}
));
'''

    if (i + 1) % 100 == 0:
        gap_code += f'Print("Processed {i + 1} groups...\\n");\n'

gap_code += '''
Print("Total groups: ", Length(db.groups), "\\n");

# Save database
output := OutputTextFile(dbFile, false);
SetPrintFormattingStatus(output, false);
PrintTo(output, "return ");
PrintTo(output, db);
PrintTo(output, ";\\n");
CloseStream(output);
Print("Database saved\\n");
QUIT;
'''

# Write GAP script
gap_script = r'C:\Users\jeffr\Downloads\Symmetric Groups\rebuild_from_txt.g'
with open(gap_script, 'w') as f:
    f.write(gap_code)

print("GAP script written to rebuild_from_txt.g")
print("Running GAP...")

gap_script_cygwin = windows_to_cygwin_path(gap_script)
gap_bash = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
cmd = f'/opt/gap-4.15.1/gap -q "{gap_script_cygwin}"'

process = subprocess.Popen(
    [gap_bash, '--login', '-c', cmd],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    cwd=r"C:\Program Files\GAP-4.15.1\runtime\bin"
)

for line in iter(process.stdout.readline, ''):
    print(line, end='')
    sys.stdout.flush()

process.wait()
print(f"Done with exit code: {process.returncode}")
