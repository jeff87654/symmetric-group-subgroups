#############################################################################
#
#  Quadruple Check - Phase 1C: DP Fallback
#
#  For multi-group fallback buckets where factors lack IdGroup,
#  reconstruct the non-IdGroup factors and use IsomorphismGroups
#  on individual factors (much smaller than full groups).
#
#  Two DP groups are isomorphic iff their factor multisets match up to
#  isomorphism. Since IdGroup-compatible factors already match by canonical
#  key, we only need to test the non-IdGroup factors pairwise.
#
#  Arguments (set before Read):
#    FALLBACK_FILE  - path to fallback bucket definitions
#    INPUT_FILE     - path to s14_large_invariants_clean.g
#    OUTPUT_FILE    - path for results
#
#############################################################################

Print("=== Quadruple Check Phase 1C: DP Fallback ===\n");
Print("Input: ", INPUT_FILE, "\n");
Print("Fallback: ", FALLBACK_FILE, "\n");
Print("Output: ", OUTPUT_FILE, "\n\n");

# Load data
Read(INPUT_FILE);
Print("Loaded ", Length(S14_TC_LARGE), " group records\n");

Read(FALLBACK_FILE);
Print("Loaded ", Length(FALLBACK_BUCKETS), " fallback buckets\n\n");

IDGROUP_EXCLUDED := [512, 768, 1024, 1536];

IsIdGroupCompatible := function(order)
    return order < 2000 and not (order in IDGROUP_EXCLUDED);
end;

# For a DP group, extract the non-IdGroup factors as actual Group objects
GetNonIdGroupFactors := function(rec_data)
    local result, fi_idx, gens, F, fOrder;
    result := [];
    for fi_idx in [1..Length(rec_data.factorGens)] do
        gens := List(rec_data.factorGens[fi_idx], s -> EvalString(s));
        F := Group(gens);
        fOrder := Size(F);
        if not IsIdGroupCompatible(fOrder) then
            Add(result, F);
        fi;
    od;
    return result;
end;

# Check if two lists of groups are pairwise isomorphic (same multiset)
# Uses greedy bipartite matching
AreFactorListsIsomorphic := function(list1, list2)
    local matched, i, j, found;
    if Length(list1) <> Length(list2) then return false; fi;
    matched := BlistList([1..Length(list2)], []);
    for i in [1..Length(list1)] do
        found := false;
        for j in [1..Length(list2)] do
            if matched[j] then continue; fi;
            if Size(list1[i]) <> Size(list2[j]) then continue; fi;
            if IsomorphismGroups(list1[i], list2[j]) <> fail then
                matched[j] := true;
                found := true;
                break;
            fi;
        od;
        if not found then return false; fi;
    od;
    return true;
end;

# Process each fallback bucket
totalReps := 0;
errors := 0;

PrintTo(OUTPUT_FILE, "# QC Phase 1C Fallback results\n\n");
AppendTo(OUTPUT_FILE, "QC_FALLBACK_RESULTS := [\n");

firstEntry := true;

for bkt in FALLBACK_BUCKETS do
    indices := bkt.indices;
    bktKey := bkt.key;
    n := Length(indices);

    Print("Bucket: ", n, " groups, key=", bktKey{[1..Minimum(80, Length(bktKey))]}, "\n");

    if n = 1 then
        # Singleton - already a representative
        if not firstEntry then AppendTo(OUTPUT_FILE, ",\n"); fi;
        firstEntry := false;
        AppendTo(OUTPUT_FILE, "rec(key:=\"", bktKey, "\",reps:=", indices, ",size:=1)");
        totalReps := totalReps + 1;
        Print("  -> 1 rep (singleton)\n");
        continue;
    fi;

    # Extract non-IdGroup factors for each group
    factorLists := [];
    for idx in indices do
        Add(factorLists, GetNonIdGroupFactors(S14_TC_LARGE[idx]));
    od;

    # Greedy dedup: compare each group to existing reps
    reps := [indices[1]];
    repFactors := [factorLists[1]];

    for i in [2..n] do
        isNew := true;
        for j in [1..Length(reps)] do
            if AreFactorListsIsomorphic(factorLists[i], repFactors[j]) then
                isNew := false;
                break;
            fi;
        od;
        if isNew then
            Add(reps, indices[i]);
            Add(repFactors, factorLists[i]);
        fi;
    od;

    if not firstEntry then AppendTo(OUTPUT_FILE, ",\n"); fi;
    firstEntry := false;
    AppendTo(OUTPUT_FILE, "rec(key:=\"", bktKey, "\",reps:=", reps, ",size:=", n, ")");
    totalReps := totalReps + Length(reps);
    Print("  -> ", Length(reps), " reps (from ", n, " groups)\n");
od;

AppendTo(OUTPUT_FILE, "\n];\n\n");
AppendTo(OUTPUT_FILE, "# Total representatives: ", totalReps, "\n");
AppendTo(OUTPUT_FILE, "# Errors: ", errors, "\n");

Print("\n=== Phase 1C complete ===\n");
Print("Total fallback reps: ", totalReps, "\n");
Print("Errors: ", errors, "\n");

QuitGap(errors);
