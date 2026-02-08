###############################################################################
#
# deduplicate_maxsub.g - Phase B: Load all worker outputs and deduplicate
#
# This script:
# 1. Loads all worker checkpoint files from maxsub_output/
# 2. Adds A14 and S14 as single classes
# 3. Buckets all subgroups by invariant key
# 4. Deduplicates by S14-conjugacy within each bucket
# 5. Verifies count = 75,154
# 6. Saves to conjugacy_cache/s14_subgroups.g
#
# Memory: Run with -o 50g
#
###############################################################################

MAXSUB_BASE := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups";
Read(Concatenation(MAXSUB_BASE, "/compute_s14_maxsub.g"));

n := 14;
EXPECTED_COUNT := 75154;
startTime := Runtime();

###############################################################################
# Step 1: Load all worker output files
###############################################################################

Print("=== Phase B: Deduplication ===\n\n");
Print("Step 1: Loading worker output files...\n");

allSubs := [];
workerFiles := [
    # Intransitive maximal subgroups
    "intrans_1x13",
    "intrans_2x12",
    "intrans_3x11",
    "intrans_4x10",
    "intrans_5x9",
    "intrans_6x8",
    "intrans_7x7",
    # Wreath product maximal subgroups
    "wreath_2wr7",
    "wreath_7wr2",
    # Primitive maximal subgroups - loaded dynamically below
];

# Load each worker file
for label in workerFiles do
    filename := Concatenation(MAXSUB_OUTPUT, "/", label, ".g");
    if IsExistingFile(filename) then
        Print("  Loading ", label, "...");
        subs := LoadMaxSubResults(filename, n);
        Print(" ", Length(subs), " subgroups\n");
        Append(allSubs, subs);
        GASMAN("collect");
    else
        Print("  WARNING: Missing file for ", label, "\n");
    fi;
od;

# Load primitive group workers
nrPrim := NrPrimitiveGroups(n);
for i in [1..nrPrim] do
    G := PrimitiveGroup(n, i);
    if Size(G) < Factorial(n) and Size(G) < Factorial(n)/2 then
        label := Concatenation("primitive_", String(i));
        filename := Concatenation(MAXSUB_OUTPUT, "/", label, ".g");
        if IsExistingFile(filename) then
            Print("  Loading ", label, "...");
            subs := LoadMaxSubResults(filename, n);
            Print(" ", Length(subs), " subgroups\n");
            Append(allSubs, subs);
            GASMAN("collect");
        else
            Print("  WARNING: Missing file for ", label, "\n");
        fi;
    fi;
od;

Print("\nTotal subgroups loaded from workers: ", Length(allSubs), "\n\n");

###############################################################################
# Step 2: Add A14 and S14 as single conjugacy classes
###############################################################################

Print("Step 2: Adding A14 and S14...\n");

# A14 - use simple invariant key (unique by order + transitivity)
A14 := AlternatingGroup(n);
inv_A14 := [Size(A14), [n], -1, -1, 1, -1, [], Size(A14)];  # Unique: only group of this order
Add(allSubs, rec(group := A14, inv := inv_A14, source := "special_A14"));
Print("  Added A14 (order ", Size(A14), ")\n");

# S14 - use simple invariant key (unique by order)
S14 := SymmetricGroup(n);
inv_S14 := [Size(S14), [n], -1, -1, 1, -1, [], Factorial(n)/2];  # Unique: only group of this order
Add(allSubs, rec(group := S14, inv := inv_S14, source := "special_S14"));
Print("  Added S14 (order ", Size(S14), ")\n");

Print("  Total after adding specials: ", Length(allSubs), "\n\n");

###############################################################################
# Step 3: Deduplicate by S14-conjugacy
###############################################################################

Print("Step 3: Deduplicating by S14-conjugacy...\n\n");

reps := DeduplicateByConjugacy(allSubs, n);

# Free memory
allSubs := [];
GASMAN("collect");

###############################################################################
# Step 4: Verify count
###############################################################################

Print("\n=== Verification ===\n");
Print("  Total unique conjugacy classes: ", Length(reps), "\n");
Print("  Expected (A005432(14)):         ", EXPECTED_COUNT, "\n");

if Length(reps) = EXPECTED_COUNT then
    Print("  MATCH! Count is correct.\n");
else
    Print("  *** MISMATCH! Off by ", AbsInt(Length(reps) - EXPECTED_COUNT), " ***\n");
    if Length(reps) < EXPECTED_COUNT then
        Print("  Missing ", EXPECTED_COUNT - Length(reps), " classes\n");
    else
        Print("  Extra ", Length(reps) - EXPECTED_COUNT, " classes\n");
    fi;
fi;

###############################################################################
# Step 5: Sanity checks
###############################################################################

Print("\n=== Sanity Checks ===\n");

# Check for trivial group
trivCount := 0;
s14Count := 0;
a14Count := 0;
for H in reps do
    if Size(H) = 1 then trivCount := trivCount + 1; fi;
    if Size(H) = Factorial(n) then s14Count := s14Count + 1; fi;
    if Size(H) = Factorial(n)/2 and IsSimple(H) then a14Count := a14Count + 1; fi;
od;
Print("  Trivial group (expect 1): ", trivCount, "\n");
Print("  S14 (expect 1): ", s14Count, "\n");
Print("  A14 (expect 1): ", a14Count, "\n");

# Order distribution summary
orderDist := rec();
for H in reps do
    key := String(Size(H));
    if not IsBound(orderDist.(key)) then
        orderDist.(key) := 0;
    fi;
    orderDist.(key) := orderDist.(key) + 1;
od;
Print("  Distinct orders represented: ", Length(RecNames(orderDist)), "\n");

###############################################################################
# Step 6: Save to conjugacy_cache
###############################################################################

Print("\n=== Saving Results ===\n");

outputFile := Concatenation(MAXSUB_CACHE, "/s14_subgroups.g");
elapsed := Runtime() - startTime;
SaveConjugacyClasses(reps, n, outputFile, elapsed);

totalElapsed := Runtime() - startTime;
Print("\n=== All Done ===\n");
Print("  Total time: ", Int(totalElapsed/1000), " seconds\n");
Print("  Output: ", outputFile, "\n");
Print("  Count: ", Length(reps), "\n");

QUIT;
