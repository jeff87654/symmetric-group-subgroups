#############################################################################
#
#  Quadruple Check - Phase 2B: Shared Verification Library
#
#  For each non-DP bucket from the triple check:
#  1. Verify reps are mutually non-isomorphic (all pairs fail IsomorphismGroups)
#  2. Verify non-reps each match some rep (IsomorphismGroups succeeds)
#
#  Two functions:
#    VerifyBucketRegular(indices, reps, dataByIndex)
#    VerifyBucket2Groups(indices, reps, dataByIndex)
#
#############################################################################

LogProgress := function(msg)
    Print(msg, "\n");
end;

# Reconstruct group from generator strings
ReconstructGroup := function(rec_data)
    local gens;
    gens := List(rec_data.generators, s -> EvalString(s));
    return Group(gens);
end;

# Verify a regular (non-2-group) bucket
VerifyBucketRegular := function(indices, repIndices, dataByIndex)
    local errors, repSet, nonRepIndices, groups, i, j, phi, idx, matched, foundMatch;

    errors := 0;
    repSet := Set(repIndices);
    nonRepIndices := Filtered(indices, x -> not (x in repSet));

    # Reconstruct all groups
    groups := rec();
    for idx in indices do
        groups.(idx) := ReconstructGroup(dataByIndex.(idx));
    od;

    # Step 1: Verify reps are mutually non-isomorphic
    if Length(repIndices) > 1 then
        for i in [1..Length(repIndices)] do
            for j in [i+1..Length(repIndices)] do
                phi := IsomorphismGroups(groups.(repIndices[i]), groups.(repIndices[j]));
                if phi <> fail then
                    Print("  ERROR: reps ", repIndices[i], " and ", repIndices[j],
                          " ARE isomorphic (should be non-iso)\n");
                    errors := errors + 1;
                fi;
            od;
        od;
    fi;

    # Step 2: Verify each non-rep matches some rep
    for idx in nonRepIndices do
        foundMatch := false;
        for i in [1..Length(repIndices)] do
            phi := IsomorphismGroups(groups.(idx), groups.(repIndices[i]));
            if phi <> fail then
                foundMatch := true;
                break;
            fi;
        od;
        if not foundMatch then
            Print("  ERROR: non-rep ", idx, " matches NO rep (under-counting)\n");
            errors := errors + 1;
        fi;
    od;

    return errors;
end;

# Verify a 2-group bucket using ANUPQ
VerifyBucket2Groups := function(indices, repIndices, dataByIndex)
    local errors, repSet, nonRepIndices, groups, pcGroups, i, j, idx,
          matched, foundMatch, iso;

    errors := 0;
    repSet := Set(repIndices);
    nonRepIndices := Filtered(indices, x -> not (x in repSet));

    # Reconstruct all groups and convert to PcGroup
    groups := rec();
    pcGroups := rec();
    for idx in indices do
        groups.(idx) := ReconstructGroup(dataByIndex.(idx));
        pcGroups.(idx) := Image(IsomorphismPcGroup(groups.(idx)));
    od;

    # Step 1: Verify reps are mutually non-isomorphic
    if Length(repIndices) > 1 then
        for i in [1..Length(repIndices)] do
            for j in [i+1..Length(repIndices)] do
                iso := IsIsomorphicPGroup(pcGroups.(repIndices[i]), pcGroups.(repIndices[j]));
                if iso then
                    Print("  ERROR: reps ", repIndices[i], " and ", repIndices[j],
                          " ARE isomorphic (should be non-iso)\n");
                    errors := errors + 1;
                fi;
            od;
        od;
    fi;

    # Step 2: Verify each non-rep matches some rep
    for idx in nonRepIndices do
        foundMatch := false;
        for i in [1..Length(repIndices)] do
            iso := IsIsomorphicPGroup(pcGroups.(idx), pcGroups.(repIndices[i]));
            if iso then
                foundMatch := true;
                break;
            fi;
        od;
        if not foundMatch then
            Print("  ERROR: non-rep ", idx, " matches NO rep (under-counting)\n");
            errors := errors + 1;
        fi;
    od;

    return errors;
end;

Print("QC Verify Common library loaded.\n");
