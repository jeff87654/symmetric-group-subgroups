# Process S16 subgroups to compute IdGroups and invariants for large groups
# Preparation step for A174511(16) computation
# Adapted from s15_processing/process_s15_subgroups.g

# Configuration - set by Python launcher
if not IsBound(WORKER_ID) then
    WORKER_ID := 1;
fi;
if not IsBound(NUM_WORKERS) then
    NUM_WORKERS := 1;
fi;
if not IsBound(CHECKPOINT_INTERVAL) then
    CHECKPOINT_INTERVAL := 200;
fi;

Print("Worker ", WORKER_ID, " of ", NUM_WORKERS, " starting\n");
Print("Checkpoint interval: ", CHECKPOINT_INTERVAL, "\n");

# Paths
BASE_DIR := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/";
INPUT_FILE := Concatenation(BASE_DIR, "conjugacy_cache/s16_subgroups.g");
ISO_MAP_FILE := Concatenation(BASE_DIR, "s16_processing/s15_iso_map.g");
CHECKPOINT_DIR := Concatenation(BASE_DIR, "s16_processing/checkpoints/");
IDGROUPS_FILE := Concatenation(CHECKPOINT_DIR, "worker_", String(WORKER_ID), "_idgroups.g");
LARGE_FILE := Concatenation(CHECKPOINT_DIR, "worker_", String(WORKER_ID), "_large.g");

# Number of S15 subgroups (first entries in s16_subgroups.g fix point 16)
S15_COUNT := 159129;

# Maximum order for DirectFactorsOfGroup (prevent hangs on huge groups)
MAX_DIRECT_FACTOR_ORDER := 100000000;  # 10^8

# Maximum order for StructureDescription on factors
MAX_STRUCT_DESC_ORDER := 50000000;  # 5*10^7

# Check if order is IdGroup-compatible
IsIdGroupCompatible := function(order)
    return order < 2000 and not order in [512, 768, 1024, 1536];
end;

# Compute sigKey — uses AbelianInvariants(G) directly (= invariants of G/G')
ComputeSigKey := function(G)
    local order, D, derivedSize, numClasses, derivedLength, abInv;
    order := Size(G);
    D := DerivedSubgroup(G);
    derivedSize := Size(D);
    numClasses := NrConjugacyClasses(G);
    if IsSolvableGroup(G) then
        derivedLength := DerivedLength(G);
    else
        derivedLength := -1;
    fi;
    abInv := ShallowCopy(AbelianInvariants(G));
    Sort(abInv);
    return [order, derivedSize, numClasses, derivedLength, abInv];
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
    local result, factors, i, combined, name, gens, order;
    result := rec(isDirectProduct := false, factors := [], factorOrders := [],
                  numFactors := 1);

    order := Size(G);

    # Skip for very large groups to prevent hangs
    if order > MAX_DIRECT_FACTOR_ORDER then
        return result;
    fi;

    factors := DirectFactorsOfGroup(G);

    if factors = fail or Length(factors) <= 1 then
        return result;
    fi;

    result.isDirectProduct := true;
    result.numFactors := Length(factors);

    # Build combined list for co-sorting: [order, name, gen_strings]
    combined := [];
    for i in [1..Length(factors)] do
        if Size(factors[i]) <= MAX_STRUCT_DESC_ORDER then
            name := StructureDescription(factors[i]);
        else
            name := Concatenation("Order", String(Size(factors[i])));
        fi;
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
MakeLargeGroupRecord := function(G, idx)
    local result, sigKey, histData, factorData;

    result := rec();
    result.index := idx;

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

    # Check S15 iso map for pre-populated isomorphicTo
    if idx <= S15_COUNT and IsBound(S15_ISO_MAP.(String(idx))) then
        result.isomorphicTo := S15_ISO_MAP.(String(idx));
    fi;

    return result;
end;

# Format record for output
FormatRecord := function(r)
    local s, fields, f;
    s := "rec(\n";
    fields := ["index", "sigKey", "order",
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
    if IsBound(r.isomorphicTo) then
        s := Concatenation(s, "  isomorphicTo := ", String(r.isomorphicTo), ",\n");
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
    AppendTo(IDGROUPS_FILE, "# Format: S16_IDGROUP_MAP[index] := [order, id];\n\n");

    PrintTo(LARGE_FILE, "# Large groups from worker ", WORKER_ID, "\n");
    AppendTo(LARGE_FILE, "# Started: ", StringTime(Runtime()), "\n");
    AppendTo(LARGE_FILE, "S16_LARGE_W", String(WORKER_ID), " := [\n");
end;

# Write an IdGroup entry (map format instead of list)
WriteIdGroup := function(order, id, idx)
    AppendTo(IDGROUPS_FILE, "S16_IDGROUP_MAP[", idx, "] := [", order, ", ", id, "];\n");
end;

# Write a large group entry
WriteLargeGroup := function(r)
    AppendTo(LARGE_FILE, FormatRecord(r), ",\n");
end;

# Load S15 isomorphism map
Print("Loading S15 isomorphism map from ", ISO_MAP_FILE, "\n");
if IsExistingFile(ISO_MAP_FILE) then
    Read(ISO_MAP_FILE);
    Print("S15 iso map loaded: ", Length(RecNames(S15_ISO_MAP)), " entries\n");
else
    Print("WARNING: S15 iso map not found, creating empty map\n");
    S15_ISO_MAP := rec();
fi;

# Main processing function
ProcessSubgroups := function()
    local genLists, total, myIndices, idx, i, gens, G, order, idg, r,
          idgroupCount, largeCount, processedCount, lastCheckpoint,
          startTime, elapsed, rate, isoCount;

    Print("Loading generator lists from ", INPUT_FILE, "\n");
    genLists := ReadAsFunction(INPUT_FILE)();
    total := Length(genLists);
    Print("Loaded ", total, " generator lists\n");

    # Compute indices for this worker (round-robin)
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
    isoCount := 0;
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
            r := MakeLargeGroupRecord(G, idx);
            if IsBound(r.isomorphicTo) then
                isoCount := isoCount + 1;
            fi;
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
                  " (", idgroupCount, " idg, ", largeCount, " large, ",
                  isoCount, " iso) ",
                  "rate=", Int(rate), " groups/sec\n");
            lastCheckpoint := processedCount;
        fi;

        # Periodic garbage collection (every 300 for S16)
        if processedCount mod 300 = 0 then
            GASMAN("collect");
        fi;
    od;

    # Close the large group list
    AppendTo(LARGE_FILE, "];\n");
    AppendTo(LARGE_FILE, "# Completed: ", StringTime(Runtime()), "\n");
    AppendTo(LARGE_FILE, "# Total large groups: ", largeCount, "\n");

    # Close the idgroup file
    AppendTo(IDGROUPS_FILE, "# Completed: ", StringTime(Runtime()), "\n");
    AppendTo(IDGROUPS_FILE, "# Total IdGroups: ", idgroupCount, "\n");

    Print("\n=== Worker ", WORKER_ID, " COMPLETE ===\n");
    Print("IdGroups: ", idgroupCount, "\n");
    Print("Large groups: ", largeCount, "\n");
    Print("With isomorphicTo: ", isoCount, "\n");
    Print("Total processed: ", processedCount, "\n");

    return rec(idgroups := idgroupCount, large := largeCount,
               iso := isoCount, total := processedCount);
end;

# Run
result := ProcessSubgroups();
QUIT;
