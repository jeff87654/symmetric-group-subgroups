# Deduplicating Isomorphic Groups in Enumerations

## The Problem

When enumerating subgroups of symmetric groups (or any large group), you encounter many conjugate copies of the same abstract group. The goal is to keep exactly one representative of each isomorphism class.

## Why Structure Descriptions Fail

GAP's `StructureDescription` (and similar notation like `C4 x C2 : C2`) is **not a unique identifier**. Multiple non-isomorphic groups can share the same description because semidirect product notation `A : B` doesn't specify which homomorphism `B → Aut(A)` is used.

### Examples of Ambiguous Descriptions

| Description | Order | Non-isomorphic groups with this description |
|-------------|-------|---------------------------------------------|
| `(C4 x C2) : C2` | 16 | SmallGroup(16, 3) and SmallGroup(16, 13) |
| `C5 : C4` | 20 | SmallGroup(20, 1) and SmallGroup(20, 3) |
| `(C4 x C4) : C2` | 32 | **5 different groups**: SmallGroup(32, 11/24/31/33/34) |
| `(C8 : C4) : C2` | 64 | **8 different groups** |
| `C3 : ((C4 x C4) : C2)` | 96 | **16 different groups** |

### Implication

If you only store structure descriptions, you cannot reliably detect duplicates OR you may incorrectly merge distinct groups. You need the actual group (as generators) to determine isomorphism.

## The Solution: Fingerprints + Lazy Isomorphism Testing

### Core Algorithm

```
NewGroupArrives(G):
    fingerprint = ComputeFingerprint(G)
    
    if fingerprint not in database:
        database[fingerprint] = [G]
        return "NEW"
    
    for H in database[fingerprint]:
        if IsomorphismGroups(G, H) ≠ fail:
            return "DUPLICATE"
    
    database[fingerprint].append(G)
    return "NEW"
```

### What Makes a Good Fingerprint

Fingerprints should be:
- **Fast to compute**: O(|G|) or O(|G| log |G|)
- **Highly discriminating**: Few non-isomorphic groups share them

#### Recommended Fingerprint Tuple

```gap
Fingerprint := function(G)
    return [
        Size(G),                    # Order
        Size(Center(G)),            # |Z(G)|
        Size(DerivedSubgroup(G)),   # |G'| (commutator subgroup)
        Size(FrattiniSubgroup(G)),  # |Φ(G)|
        AbelianInvariants(G),       # Structure of abelianization G/G'
        IsAbelian(G),
        IsSolvable(G),
        IsNilpotent(G),
        Exponent(G),                # LCM of all element orders
        NrConjugacyClasses(G)
    ];
end;
```

#### Optional Additional Invariants (more expensive)

```gap
# Multiset of element orders
Collected(List(Elements(G), Order));

# Multiset of conjugacy class sizes  
SortedList(List(ConjugacyClasses(G), Size));

# Derived length (for solvable groups)
DerivedLength(G);
```

### Effectiveness

In practice, fingerprints are highly discriminating:
- For S6 (1,455 subgroups, 29 unique): All 29 had **distinct fingerprints** → zero isomorphism tests needed
- For S5 (156 subgroups, 16 unique): 140 isomorphism tests vs 12,090 naive comparisons (86× reduction)

Even when fingerprints collide, you only test isomorphism within small buckets rather than against the entire database.

## Recommended Storage Format

### For Each Unique Group, Store:

```json
{
  "order": 120,
  "fingerprint": [120, 1, 60, 1, [2], false, true, false, 60, 9],
  "generators": [[1,2,3,5,4], [2,4,1,3,5]],
  "structure": "S5",
  "first_found_in": "S5"
}
```

### Permutation Encoding Options

1. **Image list** (recommended for small degree): For σ ∈ Sₙ, store `[1^σ, 2^σ, ..., n^σ]`
   - Example: `(1,2,3)` in S5 → `[2, 3, 1, 4, 5]`
   - Fixed size: n integers per permutation

2. **Cycle notation string**: Human-readable but variable length
   - Example: `"(1,2,3)(4,5)"`

3. **Sparse format**: For permutations moving few points
   - Store only `[[i, i^σ] for i in MovedPoints(σ)]`

### Why Store Generators, Not Elements

- A group of order 1,000,000 might need only 2-3 generators
- Generators as permutations on n points: ~n bytes each
- Total: typically 30-60 bytes per group for S15 subgroups

## GAP Implementation

### Building the Database

```gap
# Initialize
db := rec(
    groups := [],      # List of records
    index := rec()     # fingerprint_string -> [indices]
);

# Add group if new
AddIfNew := function(db, G, degree)
    local fp, key, dominated, entry, H;
    
    fp := [Size(G), Size(Center(G)), Size(DerivedSubgroup(G)),
           Size(FrattiniSubgroup(G)), AbelianInvariants(G),
           IsAbelian(G), IsSolvable(G), Exponent(G), 
           NrConjugacyClasses(G)];
    key := String(fp);
    
    if not IsBound(db.index.(key)) then
        # New fingerprint - definitely new group
        Add(db.groups, rec(
            fingerprint := fp,
            generators := List(GeneratorsOfGroup(G), 
                              p -> ListPerm(p, degree)),
            structure := StructureDescription(G)
        ));
        db.index.(key) := [Length(db.groups)];
        return true;
    fi;
    
    # Check isomorphism with groups in same bucket
    for entry in db.index.(key) do
        H := Group(List(db.groups[entry].generators, PermList));
        if IsomorphismGroups(G, H) <> fail then
            return false;  # Duplicate
        fi;
    od;
    
    # New group with existing fingerprint
    Add(db.groups, rec(
        fingerprint := fp,
        generators := List(GeneratorsOfGroup(G), 
                          p -> ListPerm(p, degree)),
        structure := StructureDescription(G)
    ));
    Add(db.index.(key), Length(db.groups));
    return true;
end;
```

### Reconstructing a Group

```gap
# From stored format back to GAP group
ReconstructGroup := function(entry)
    return Group(List(entry.generators, PermList));
end;
```

## String-Level Deduplication (Partial Solution)

If you only have structure descriptions (no generators), you can still remove obvious duplicates:

### What String Normalization Catches

1. **Permuted direct products**: `S4 x S5` vs `S5 x S4`
2. **Whitespace variants**: `C3:C4` vs `C3 : C4`
3. **Trivial reorderings**: `A x B x C` vs `C x A x B`

### What It Misses

1. **Different semidirect products**: `(C4 x C2) : C2` (multiple non-isomorphic groups)
2. **Same group, different constructions**: A group appearing as both direct and semidirect product
3. **Associativity variations**: `(A : B) : C` vs `A : (B : C)` (may or may not be isomorphic)

### Python Normalization

```python
def normalize_direct_product(s):
    """Sort factors in direct products: 'S5 x S4' -> 'S4 x S5'"""
    tokens = tokenize_respecting_parens(s, delimiter=' x ')
    return ' x '.join(sorted(tokens))
```

This is useful as a first pass but **cannot guarantee correctness** without the actual groups.

## Complexity Summary

| Operation | Cost | Notes |
|-----------|------|-------|
| Compute fingerprint | O(\|G\| log \|G\|) | Dominated by conjugacy class computation |
| Fingerprint lookup | O(1) | Hash table |
| IsomorphismGroups | O(\|G\|^c) | Expensive, but rarely needed |
| Store generators | O(n × k) | n = degree, k = number of generators |

## Calling GAP from Python on Windows

GAP on Windows is typically installed with Cygwin, which requires special handling when calling from Python.

### The Problem

- `gap.bat` opens a GUI window that doesn't capture stdout properly
- Direct subprocess calls don't work reliably
- Paths must be converted to Cygwin format

### The Solution: Call via Cygwin Bash

```python
import subprocess
import sys

def windows_to_cygwin_path(win_path: str) -> str:
    """Convert Windows path to Cygwin path."""
    path = str(win_path).replace('\\', '/')
    if len(path) >= 2 and path[1] == ':':
        drive = path[0].lower()
        path = f'/cygdrive/{drive}{path[2:]}'
    return path

# Paths
gap_bash = r"C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe"
gap_script = "C:\\Users\\you\\script.g"
gap_script_cygwin = windows_to_cygwin_path(gap_script)

# Build command (quote paths with spaces!)
cmd = f'/opt/gap-4.15.1/gap -q "{gap_script_cygwin}"'

# Run via Cygwin bash
process = subprocess.Popen(
    [gap_bash, '--login', '-c', cmd],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    cwd=r"C:\Program Files\GAP-4.15.1\runtime\bin"
)

# Stream output to console
for line in iter(process.stdout.readline, ''):
    print(line, end='')
    sys.stdout.flush()

process.wait()
print(f"Return code: {process.returncode}")
```

### Key Points

1. **Use Cygwin bash**: `C:\Program Files\GAP-4.15.1\runtime\bin\bash.exe`
2. **Convert paths**: `C:\Users\...` → `/cygdrive/c/Users/...`
3. **Quote paths**: Paths with spaces need quotes in the command
4. **Set working directory**: To the Cygwin bin directory
5. **Use `--login -c`**: Run command in login shell

### GAP Function Naming Caveat

GAP has a built-in `Fingerprint` function. If you define your own fingerprinting function, use a different name like `GroupFingerprint` to avoid conflicts.

### Handling Trivial Groups

When reconstructing groups from stored generators, handle the trivial group specially:

```gap
if Length(entry.generators) = 0 then
    G := Group(());  # Trivial group
else
    G := Group(List(entry.generators, PermList));
fi;
```

## Recommendations

1. **For new enumerations**: Store generators + fingerprints from the start
2. **For existing description-only lists**:
   - Apply string normalization (removes ~20% duplicates)
   - Accept that some duplicates/false-merges may remain
   - Consider re-enumerating with proper storage if accuracy is critical
3. **For very large groups**: Consider additional cheap invariants to shrink buckets further
4. **For incremental building** (S14 → S15): Keep the S14 database and only test new subgroups against it
