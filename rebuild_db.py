#!/usr/bin/env python3
"""Rebuild the GAP database from JSON file."""

import json
import subprocess
import sys

def windows_to_cygwin_path(win_path: str) -> str:
    path = str(win_path).replace('\\', '/')
    if len(path) >= 2 and path[1] == ':':
        drive = path[0].lower()
        path = f'/cygdrive/{drive}{path[2:]}'
    return path

# Load JSON data
with open('subgroups_of_Sn.json', 'r') as f:
    groups = json.load(f)

print(f"Loaded {len(groups)} groups from JSON")

# Convert to GAP format
gap_code = '''
dbFile := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/subgroups_db.g";
Print("Rebuilding database from JSON data...\\n");

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
    if ord <= 2000 and ord > 1 then
        if NrSmallGroups(ord) <> fail then
            smallId := IdSmallGroup(G);
            if smallId <> fail then
                fp.smallGroupId := smallId;
            fi;
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
with open('rebuild_db.g', 'w') as f:
    f.write(gap_code)

print("GAP script written to rebuild_db.g")
print("Running GAP...")

gap_script_cygwin = windows_to_cygwin_path('C:/Users/jeffr/Downloads/Symmetric Groups/rebuild_db.g')
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
