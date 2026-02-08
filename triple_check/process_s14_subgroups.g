# Process S14 subgroups to compute IdGroups and invariants for large groups
# Part of Triple Check verification for A174511(14)

# Configuration - set by Python launcher
if not IsBound(WORKER_ID) then
    WORKER_ID := 1;
fi;
if not IsBound(NUM_WORKERS) then
    NUM_WORKERS := 1;
fi;
if not IsBound(CHECKPOINT_INTERVAL) then
    CHECKPOINT_INTERVAL := 100;
fi;

Print("Worker ", WORKER_ID, " of ", NUM_WORKERS, " starting\n");
Print("Checkpoint interval: ", CHECKPOINT_INTERVAL, "\n");

# Paths
BASE_DIR := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/";
INPUT_FILE := Concatenation(BASE_DIR, "conjugacy_cache/s14_subgroups.g");
CHECKPOINT_DIR := Concatenation(BASE_DIR, "triple_check/checkpoints/");
IDGROUPS_FILE := Concatenation(CHECKPOINT_DIR, "worker_", String(WORKER_ID), "_idgroups.g");
LARGE_FILE := Concatenation(CHECKPOINT_DIR, "worker_", String(WORKER_ID), "_large.g");

# Check if order is IdGroup-compatible
IsIdGroupCompatible := function(order)
    return order < 2000 and not order in [512, 768, 1024, 1536];
end;

# Compute sigKey
ComputeSigKey := function(G)
    local order, D, derivedSize, numClasses, derivedLength, abelianInvariants;
    order := Size(G);
    D := DerivedSubgroup(G);
    derivedSize := Size(D);
    numClasses := NrConjugacyClasses(G);
    if IsSolvableGroup(G) then
        derivedLength := DerivedLength(G);
    else
        derivedLength := -1;
    fi;
    abelianInvariants := AbelianInvariants(G/D);
    return [order, derivedSize, numClasses, derivedLength, abelianInvariants];
end;

# Compute histogram via conjugacy classes (efficient)
ComputeHistogram := function(G)
    local classes, orderCounts, cc, ord, cnt, orders, histogram, maxOrd;
    classes := ConjugacyClasses(G);
    orderCounts := rec();
    for cc in classes do
        ord := Order(Representative(cc));
        cnt := Size(cc);
        if IsBound(orderCounts.(String(ord))) then
            orderCounts.(String(ord)) := orderCounts.(String(ord)) + cnt;
        else
            orderCounts.(String(ord)) := cnt;
        fi;
    od;
    orders := List(RecNames(orderCounts), x -> Int(x));
    Sort(orders);
    histogram := List(orders, o -> [o, orderCounts.(String(o))]);
    if Length(orders) > 0 then
        maxOrd := Maximum(orders);
    else
        maxOrd := 1;
    fi;
    return rec(histogram := histogram, maxOrder := maxOrd, numOrders := Length(orders));
end;

# Compute direct factors with factorGens for ALL factors (co-sorted)
ComputeDirectFactors := function(G)
    local result, factors, i, combined, name, gens;
    result := rec(isDirectProduct := false, factors := [], factorOrders := [],
                  numFactors := 1);

    factors := DirectFactorsOfGroup(G);

    if factors = fail or Length(factors) <= 1 then
        return result;
    fi;

    result.isDirectProduct := true;
    result.numFactors := Length(factors);

    # Build combined list for co-sorting: [order, name, gen_strings]
    combined := [];
    for i in [1..Length(factors)] do
        name := StructureDescription(factors[i]);
        gens := List(GeneratorsOfGroup(factors[i]), String);
        Add(combined, [Size(factors[i]), name, gens]);
    od;

    # Sort by (order, name) for canonical ordering
    Sort(combined, function(a, b)
        if a[1] <> b[1] then return a[1] < b[1]; fi;
        return a[2] < b[2];
    end);

    result.factorOrders := List(combined, x -> x[1]);
    result.factors := List(combined, x -> x[2]);
    result.factorGens := List(combined, x -> x[3]);

    return result;
end;

# Convert a large group to record format
MakeLargeGroupRecord := function(G, originalIndex, combinedIndex)
    local result, sigKey, histData, factorData;

    result := rec();
    result.source := "S14_TC";
    result.originalIndex := originalIndex;
    result.combinedIndex := combinedIndex;
    result.index := combinedIndex;

    sigKey := ComputeSigKey(G);
    result.sigKey := sigKey;
    result.order := sigKey[1];

    factorData := ComputeDirectFactors(G);
    result.isDirectProduct := factorData.isDirectProduct;
    result.factors := factorData.factors;
    result.factorOrders := factorData.factorOrders;
    result.numFactors := factorData.numFactors;
    if IsBound(factorData.factorGens) then
        result.factorGens := factorData.factorGens;
    fi;

    histData := ComputeHistogram(G);
    result.histogram := histData.histogram;
    result.maxOrder := histData.maxOrder;
    result.numOrders := histData.numOrders;

    # Store generators for potential isomorphism testing
    result.generators := List(GeneratorsOfGroup(G), String);

    return result;
end;

# Format record for output
FormatRecord := function(r)
    local s, fields, f;
    s := "rec(\n";
    fields := ["source", "originalIndex", "combinedIndex", "index", "sigKey", "order",
               "isDirectProduct", "factors", "factorOrders", "numFactors",
               "histogram", "maxOrder", "numOrders", "generators"];
    for f in fields do
        if IsBound(r.(f)) then
            s := Concatenation(s, "  ", f, " := ", String(r.(f)), ",\n");
        fi;
    od;
    if IsBound(r.factorGens) then
        s := Concatenation(s, "  factorGens := ", String(r.factorGens), ",\n");
    fi;
    # Remove trailing comma and newline, add closing
    s := s{[1..Length(s)-2]};
    s := Concatenation(s, "\n)");
    return s;
end;

# Initialize checkpoint files
InitCheckpointFiles := function()
    PrintTo(IDGROUPS_FILE, "# IdGroups from worker ", WORKER_ID, "\n");
    AppendTo(IDGROUPS_FILE, "# Started: ", StringTime(Runtime()), "\n");
    AppendTo(IDGROUPS_FILE, "S14_IDGROUPS_W", String(WORKER_ID), " := [\n");

    PrintTo(LARGE_FILE, "# Large groups from worker ", WORKER_ID, "\n");
    AppendTo(LARGE_FILE, "# Started: ", StringTime(Runtime()), "\n");
    AppendTo(LARGE_FILE, "S14_LARGE_W", String(WORKER_ID), " := [\n");
end;

# Write an IdGroup entry
WriteIdGroup := function(order, id, originalIndex)
    AppendTo(IDGROUPS_FILE, "  \"[", order, ", ", id, "]\",  # idx=", originalIndex, "\n");
end;

# Write a large group entry
WriteLargeGroup := function(r)
    AppendTo(LARGE_FILE, FormatRecord(r), ",\n");
end;

# Main processing function
ProcessSubgroups := function()
    local genLists, total, myIndices, idx, i, gens, G, order, idg, r,
          idgroupCount, largeCount, processedCount, lastCheckpoint,
          startTime, elapsed, rate;

    Print("Loading generator lists from ", INPUT_FILE, "\n");
    genLists := ReadAsFunction(INPUT_FILE)();
    total := Length(genLists);
    Print("Loaded ", total, " generator lists\n");

    # Compute indices for this worker
    myIndices := [];
    idx := WORKER_ID;
    while idx <= total do
        Add(myIndices, idx);
        idx := idx + NUM_WORKERS;
    od;
    Print("Worker ", WORKER_ID, " will process ", Length(myIndices), " groups\n");

    # Initialize files
    InitCheckpointFiles();

    idgroupCount := 0;
    largeCount := 0;
    processedCount := 0;
    lastCheckpoint := 0;
    startTime := Runtime();

    for i in [1..Length(myIndices)] do
        idx := myIndices[i];
        gens := List(genLists[idx], PermList);
        G := Group(gens);
        order := Size(G);

        if IsIdGroupCompatible(order) then
            # Can use IdGroup
            idg := IdGroup(G);
            WriteIdGroup(idg[1], idg[2], idx);
            idgroupCount := idgroupCount + 1;
        else
            # Large group - compute full invariants
            largeCount := largeCount + 1;
            r := MakeLargeGroupRecord(G, idx, largeCount);
            WriteLargeGroup(r);
        fi;

        processedCount := processedCount + 1;

        # Progress report at checkpoint intervals
        if processedCount - lastCheckpoint >= CHECKPOINT_INTERVAL then
            elapsed := Runtime() - startTime;
            if elapsed > 0 then
                rate := Float(processedCount) / Float(elapsed) * 1000.0;
            else
                rate := 0.0;
            fi;
            Print("Worker ", WORKER_ID, ": ", processedCount, "/", Length(myIndices),
                  " (", idgroupCount, " idg, ", largeCount, " large) ",
                  "rate=", Int(rate), " groups/sec\n");
            lastCheckpoint := processedCount;
        fi;
    od;

    # Close the lists
    AppendTo(IDGROUPS_FILE, "];\n");
    AppendTo(IDGROUPS_FILE, "# Completed: ", StringTime(Runtime()), "\n");
    AppendTo(IDGROUPS_FILE, "# Total IdGroups: ", idgroupCount, "\n");

    AppendTo(LARGE_FILE, "];\n");
    AppendTo(LARGE_FILE, "# Completed: ", StringTime(Runtime()), "\n");
    AppendTo(LARGE_FILE, "# Total large groups: ", largeCount, "\n");

    Print("\n=== Worker ", WORKER_ID, " COMPLETE ===\n");
    Print("IdGroups: ", idgroupCount, "\n");
    Print("Large groups: ", largeCount, "\n");
    Print("Total processed: ", processedCount, "\n");

    return rec(idgroups := idgroupCount, large := largeCount, total := processedCount);
end;

# Run
result := ProcessSubgroups();
QUIT;
