#############################################################################
#
#  Quadruple Check - Phase 1A: Compute Factor IdGroups
#
#  For each DP group assigned to this worker:
#    1. Reconstruct each factor from factorGens[i] strings
#    2. If factor order is IdGroup-compatible: compute IdGroup(factor)
#    3. If not: compute extended invariants
#    4. Build canonical key = sorted list of per-factor labels
#
#  Arguments (set before Read):
#    WORKER_ID      - integer worker ID (1-4)
#    START_INDEX    - first group index to process (inclusive)
#    END_INDEX      - last group index to process (inclusive)
#    INPUT_FILE     - path to s14_large_invariants_clean.g
#    OUTPUT_FILE    - path for checkpoint output
#
#############################################################################

Print("=== Quadruple Check Phase 1A: Factor IdGroup Worker ", WORKER_ID, " ===\n");
Print("Processing indices ", START_INDEX, " to ", END_INDEX, "\n");
Print("Input: ", INPUT_FILE, "\n");
Print("Output: ", OUTPUT_FILE, "\n\n");

# Load the data
Read(INPUT_FILE);
Print("Loaded ", Length(S14_TC_LARGE), " group records\n\n");

IDGROUP_EXCLUDED := [512, 768, 1024, 1536];

IsIdGroupCompatible := function(order)
    return order < 2000 and not (order in IDGROUP_EXCLUDED);
end;

# Compute extended invariants for a group (when IdGroup is not available)
ExtendedInvariants := function(G)
    local order, nrCC, dl, exp, ai, cs, ds;
    order := Size(G);
    nrCC := NrConjugacyClasses(G);
    if IsSolvableGroup(G) then
        dl := DerivedLength(G);
    else
        dl := -1;
    fi;
    exp := Exponent(G);
    ai := ShallowCopy(AbelianInvariants(G));
    Sort(ai);
    cs := Size(Centre(G));
    ds := Size(DerivedSubgroup(G));
    return Concatenation("X[", String(order), ",", String(nrCC), ",",
                         String(dl), ",", String(exp), ",",
                         String(ai), ",", String(cs), ",", String(ds), "]");
end;

# Process groups
processed := 0;
errors := 0;

PrintTo(OUTPUT_FILE, "# QC Phase 1A Worker ", WORKER_ID, " results\n");
AppendTo(OUTPUT_FILE, "# Processing indices ", START_INDEX, " to ", END_INDEX, "\n\n");
AppendTo(OUTPUT_FILE, "QC_FACTOR_RESULTS_", WORKER_ID, " := [\n");

firstEntry := true;

for idx in [START_INDEX..END_INDEX] do
    if idx > Length(S14_TC_LARGE) then break; fi;

    rec_data := S14_TC_LARGE[idx];

    # Skip non-DP groups
    if not rec_data.isDirectProduct then continue; fi;
    if not IsBound(rec_data.factorGens) then continue; fi;
    if Length(rec_data.factorGens) = 0 then continue; fi;

    processed := processed + 1;

    # Compute per-factor labels
    factorLabels := [];
    allIdGroup := true;

    for fIdx in [1..Length(rec_data.factorGens)] do
        genStrings := rec_data.factorGens[fIdx];

        # Reconstruct factor group from generator strings
        gens := List(genStrings, s -> EvalString(s));
        F := Group(gens);
        fOrder := Size(F);

        if IsIdGroupCompatible(fOrder) then
            id := IdGroup(F);
            Add(factorLabels, Concatenation("[", String(id[1]), ",", String(id[2]), "]"));
        else
            allIdGroup := false;
            inv := ExtendedInvariants(F);
            Add(factorLabels, inv);
        fi;
    od;

    # Sort factor labels for canonical ordering
    Sort(factorLabels);
    canonKey := JoinStringsWithSeparator(factorLabels, "|");

    # Write result
    if not firstEntry then
        AppendTo(OUTPUT_FILE, ",\n");
    fi;
    firstEntry := false;

    AppendTo(OUTPUT_FILE, "rec(index:=", rec_data.index,
             ",canonKey:=\"", canonKey,
             "\",allIdGroup:=", allIdGroup,
             ",numFactors:=", Length(rec_data.factorGens),
             ",factorOrders:=", rec_data.factorOrders, ")");

    if processed mod 100 = 0 then
        Print("Worker ", WORKER_ID, ": processed ", processed, " DP groups (at index ", idx, ")\n");
    fi;
od;

AppendTo(OUTPUT_FILE, "\n];\n");
AppendTo(OUTPUT_FILE, "\n# Worker ", WORKER_ID, " complete\n");
AppendTo(OUTPUT_FILE, "# Processed: ", processed, " DP groups\n");
AppendTo(OUTPUT_FILE, "# Errors: ", errors, "\n");

Print("\n=== Worker ", WORKER_ID, " complete ===\n");
Print("Processed: ", processed, " DP groups\n");
Print("Errors: ", errors, "\n");

QuitGap(errors);
