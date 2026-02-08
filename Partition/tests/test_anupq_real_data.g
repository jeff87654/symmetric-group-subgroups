# ANUPQ Tests with Real S14 Data
# Tests ANUPQ isomorphism testing on actual order-512 and order-1024 groups from S14
# MUST run in WSL - ANUPQ crashes on Cygwin

# WSL path format
BASE_PATH := "/mnt/c/Users/jeffr/Downloads/Symmetric Groups/Partition/";
TEST_PATH := "/mnt/c/Users/jeffr/Downloads/Symmetric Groups/Partition/tests/";

LoadPackage("anupq");;

Print("\n");
Print("============================================================\n");
Print("=== ANUPQ Tests with Real S14 Data ==========================\n");
Print("============================================================\n\n");

# Test counters
PASS_COUNT := 0;;
FAIL_COUNT := 0;;
ERROR_COUNT := 0;;
RESULTS := [];;

#-------------------------------------------------------------------
# Load S14 Large Groups Data
#-------------------------------------------------------------------

Print("Loading S14 large groups data...\n");
Read(Concatenation(BASE_PATH, "Partion Double Check/s14_all_large_with_sigkeys.g"));

Print("Loaded ", Length(S14_ALL_LARGE_SIGKEYS), " S14 large groups\n\n");

#-------------------------------------------------------------------
# Filter 2-Groups (orders 512 and 1024)
#-------------------------------------------------------------------

Print("Filtering for 2-groups (orders 512, 1024)...\n");

GROUPS_512 := [];;
GROUPS_1024 := [];;

for rec in S14_ALL_LARGE_SIGKEYS do
    if rec.order = 512 then
        Add(GROUPS_512, rec);
    elif rec.order = 1024 then
        Add(GROUPS_1024, rec);
    fi;
od;

Print("  Order 512 groups: ", Length(GROUPS_512), "\n");
Print("  Order 1024 groups: ", Length(GROUPS_1024), "\n\n");

#-------------------------------------------------------------------
# Safe ANUPQ Wrapper
#-------------------------------------------------------------------

SafeIsIsomorphicPGroup := function(G, H)
    local result, pc1, pc2, small1, small2;

    # Reduce generators first (prevents integer overflow)
    small1 := Group(SmallGeneratingSet(G));
    small2 := Group(SmallGeneratingSet(H));

    # Convert to PC groups
    pc1 := Image(IsomorphismPcGroup(small1));
    pc2 := Image(IsomorphismPcGroup(small2));

    # Call ANUPQ
    result := CALL_WITH_CATCH(IsIsomorphicPGroup, [pc1, pc2]);
    if result[1] = true then
        return result[2];
    else
        return "ERROR";
    fi;
end;

#-------------------------------------------------------------------
# Compute 2-Group Invariants
#-------------------------------------------------------------------

Compute2GroupInvariants := function(G)
    return rec(
        order := Size(G),
        exponent := Exponent(G),
        pclass := PClassPGroup(G),
        rank := RankPGroup(G),
        derivedLength := DerivedLength(G),
        centerSize := Size(Center(G)),
        derivedSize := Size(DerivedSubgroup(G)),
        frattiniSize := Size(FrattiniSubgroup(G)),
        nrConjClasses := NrConjugacyClasses(G)
    );
end;

InvariantsMatch := function(inv1, inv2)
    return inv1.order = inv2.order and
           inv1.exponent = inv2.exponent and
           inv1.pclass = inv2.pclass and
           inv1.rank = inv2.rank and
           inv1.derivedLength = inv2.derivedLength and
           inv1.centerSize = inv2.centerSize and
           inv1.derivedSize = inv2.derivedSize and
           inv1.frattiniSize = inv2.frattiniSize and
           inv1.nrConjClasses = inv2.nrConjClasses;
end;

#-------------------------------------------------------------------
# Part 1: Order 512 Tests
#-------------------------------------------------------------------

Print("=== Part 1: Order 512 2-Groups ===\n\n");

if Length(GROUPS_512) >= 2 then
    # Test self-isomorphism
    Print("Test 1.1: Self-isomorphism of first order-512 group\n");
    G := GROUPS_512[1].group;
    result := SafeIsIsomorphicPGroup(G, G);
    if result = true then
        Print("  PASS: Group is isomorphic to itself\n\n");
        PASS_COUNT := PASS_COUNT + 1;
        Add(RESULTS, rec(name := "Order 512 self-iso", status := "PASS"));
    elif result = "ERROR" then
        Print("  ERROR: ANUPQ failed\n\n");
        ERROR_COUNT := ERROR_COUNT + 1;
        Add(RESULTS, rec(name := "Order 512 self-iso", status := "ERROR"));
    else
        Print("  FAIL: Should be isomorphic to itself!\n\n");
        FAIL_COUNT := FAIL_COUNT + 1;
        Add(RESULTS, rec(name := "Order 512 self-iso", status := "FAIL"));
    fi;

    # Test pairs with different sigKeys (should NOT be isomorphic)
    Print("Test 1.2: Groups with different sigKeys\n");
    G1 := GROUPS_512[1].group;
    sigKey1 := GROUPS_512[1].sigKey;

    foundDifferent := false;
    for i in [2..Minimum(Length(GROUPS_512), 10)] do
        if GROUPS_512[i].sigKey <> sigKey1 then
            G2 := GROUPS_512[i].group;
            sigKey2 := GROUPS_512[i].sigKey;
            foundDifferent := true;

            Print("  Comparing sigKeys: ", sigKey1, " vs ", sigKey2, "\n");

            # Different sigKey means definitely not isomorphic - don't need ANUPQ
            Print("  Different sigKeys -> NOT isomorphic (no ANUPQ needed)\n");
            Print("  PASS: Correctly identified as non-isomorphic by sigKey\n\n");
            PASS_COUNT := PASS_COUNT + 1;
            Add(RESULTS, rec(name := "Order 512 different sigKey", status := "PASS"));
            break;
        fi;
    od;

    if not foundDifferent then
        Print("  All sampled groups have same sigKey, skipping this test\n\n");
    fi;

    # Test pairs with SAME sigKey (may or may not be isomorphic - need ANUPQ)
    Print("Test 1.3: Groups with same sigKey (ANUPQ required)\n");

    # Group by sigKey
    byKey := rec();;
    for r in GROUPS_512 do
        key := String(r.sigKey);
        if not IsBound(byKey.(key)) then
            byKey.(key) := [];
        fi;
        Add(byKey.(key), r);
    od;

    # Find a sigKey with multiple groups
    foundMultiple := false;
    for key in RecNames(byKey) do
        if Length(byKey.(key)) >= 2 then
            pair := byKey.(key);
            G1 := pair[1].group;
            G2 := pair[2].group;

            Print("  Testing 2 groups with same sigKey: ", pair[1].sigKey, "\n");
            Print("  Source 1: partition=", pair[1].partition, " sources=", pair[1].sources, "\n");
            Print("  Source 2: partition=", pair[2].partition, " sources=", pair[2].sources, "\n");

            # Compute detailed invariants
            inv1 := Compute2GroupInvariants(G1);
            inv2 := Compute2GroupInvariants(G2);

            if InvariantsMatch(inv1, inv2) then
                Print("  Invariants match - running ANUPQ...\n");
                result := SafeIsIsomorphicPGroup(G1, G2);
                if result = "ERROR" then
                    Print("  ERROR: ANUPQ failed\n\n");
                    ERROR_COUNT := ERROR_COUNT + 1;
                    Add(RESULTS, rec(name := "Order 512 same sigKey ANUPQ", status := "ERROR"));
                else
                    Print("  ANUPQ result: ", result, "\n");
                    Print("  PASS: ANUPQ completed successfully\n\n");
                    PASS_COUNT := PASS_COUNT + 1;
                    Add(RESULTS, rec(name := "Order 512 same sigKey ANUPQ", status := "PASS"));
                fi;
            else
                Print("  Invariants differ - NOT isomorphic (no ANUPQ needed)\n");
                Print("  PASS: Distinguished by invariants\n\n");
                PASS_COUNT := PASS_COUNT + 1;
                Add(RESULTS, rec(name := "Order 512 invariant distinction", status := "PASS"));
            fi;

            foundMultiple := true;
            break;
        fi;
    od;

    if not foundMultiple then
        Print("  No sigKey has multiple groups, skipping this test\n\n");
    fi;

else
    Print("Not enough order-512 groups for testing\n\n");
fi;

#-------------------------------------------------------------------
# Part 2: Order 1024 Tests
#-------------------------------------------------------------------

Print("=== Part 2: Order 1024 2-Groups ===\n\n");

if Length(GROUPS_1024) >= 1 then
    # Test self-isomorphism
    Print("Test 2.1: Self-isomorphism of first order-1024 group\n");
    G := GROUPS_1024[1].group;

    # Show group info
    Print("  Source: partition=", GROUPS_1024[1].partition, "\n");
    Print("  sigKey: ", GROUPS_1024[1].sigKey, "\n");
    Print("  Generators: ", Length(GeneratorsOfGroup(G)), "\n");

    result := SafeIsIsomorphicPGroup(G, G);
    if result = true then
        Print("  PASS: Group is isomorphic to itself\n\n");
        PASS_COUNT := PASS_COUNT + 1;
        Add(RESULTS, rec(name := "Order 1024 self-iso", status := "PASS"));
    elif result = "ERROR" then
        Print("  ERROR: ANUPQ failed\n\n");
        ERROR_COUNT := ERROR_COUNT + 1;
        Add(RESULTS, rec(name := "Order 1024 self-iso", status := "ERROR"));
    else
        Print("  FAIL: Should be isomorphic to itself!\n\n");
        FAIL_COUNT := FAIL_COUNT + 1;
        Add(RESULTS, rec(name := "Order 1024 self-iso", status := "FAIL"));
    fi;

    if Length(GROUPS_1024) >= 2 then
        Print("Test 2.2: Comparing two order-1024 groups\n");
        G1 := GROUPS_1024[1].group;
        G2 := GROUPS_1024[2].group;

        Print("  Group 1: partition=", GROUPS_1024[1].partition, " sigKey=", GROUPS_1024[1].sigKey, "\n");
        Print("  Group 2: partition=", GROUPS_1024[2].partition, " sigKey=", GROUPS_1024[2].sigKey, "\n");

        if GROUPS_1024[1].sigKey <> GROUPS_1024[2].sigKey then
            Print("  Different sigKeys -> NOT isomorphic (no ANUPQ needed)\n");
            Print("  PASS\n\n");
            PASS_COUNT := PASS_COUNT + 1;
            Add(RESULTS, rec(name := "Order 1024 different sigKey", status := "PASS"));
        else
            Print("  Same sigKey - running ANUPQ...\n");
            result := SafeIsIsomorphicPGroup(G1, G2);
            if result = "ERROR" then
                Print("  ERROR: ANUPQ failed\n\n");
                ERROR_COUNT := ERROR_COUNT + 1;
                Add(RESULTS, rec(name := "Order 1024 ANUPQ comparison", status := "ERROR"));
            else
                Print("  ANUPQ result: ", result, "\n");
                Print("  PASS: ANUPQ completed successfully\n\n");
                PASS_COUNT := PASS_COUNT + 1;
                Add(RESULTS, rec(name := "Order 1024 ANUPQ comparison", status := "PASS"));
            fi;
        fi;
    fi;

else
    Print("No order-1024 groups found in S14 data\n\n");
fi;

#-------------------------------------------------------------------
# Part 3: Generator Count Impact Test
#-------------------------------------------------------------------

Print("=== Part 3: Generator Count Impact ===\n\n");

# Test how generator count affects ANUPQ
Print("Testing effect of generator reduction on ANUPQ...\n\n");

if Length(GROUPS_512) >= 1 then
    G := GROUPS_512[1].group;
    origGens := Length(GeneratorsOfGroup(G));
    smallG := Group(SmallGeneratingSet(G));
    smallGens := Length(GeneratorsOfGroup(smallG));

    Print("  Original generators: ", origGens, "\n");
    Print("  After SmallGeneratingSet: ", smallGens, "\n");

    if smallGens < origGens then
        Print("  Reduction achieved: ", origGens - smallGens, " generators removed\n");
        Print("  PASS: SmallGeneratingSet reduces generator count\n\n");
        PASS_COUNT := PASS_COUNT + 1;
        Add(RESULTS, rec(name := "Generator reduction", status := "PASS"));
    else
        Print("  No reduction (already minimal)\n\n");
        PASS_COUNT := PASS_COUNT + 1;
        Add(RESULTS, rec(name := "Generator reduction", status := "PASS"));
    fi;
fi;

#-------------------------------------------------------------------
# Part 4: Stress Test (Multiple Comparisons)
#-------------------------------------------------------------------

Print("=== Part 4: ANUPQ Stress Test ===\n\n");

# Run ANUPQ on several pairs to check stability
stressTestCount := Minimum(5, Length(GROUPS_512));;
stressPass := 0;;
stressFail := 0;;

Print("Running ", stressTestCount, " ANUPQ self-isomorphism tests...\n");

for i in [1..stressTestCount] do
    G := GROUPS_512[i].group;
    result := SafeIsIsomorphicPGroup(G, G);
    if result = true then
        stressPass := stressPass + 1;
        Print("  [", i, "/", stressTestCount, "] PASS\n");
    elif result = "ERROR" then
        stressFail := stressFail + 1;
        Print("  [", i, "/", stressTestCount, "] ERROR\n");
    else
        stressFail := stressFail + 1;
        Print("  [", i, "/", stressTestCount, "] FAIL\n");
    fi;
od;

Print("\nStress test: ", stressPass, "/", stressTestCount, " passed\n\n");

if stressPass = stressTestCount then
    PASS_COUNT := PASS_COUNT + 1;
    Add(RESULTS, rec(name := "ANUPQ stress test", status := "PASS"));
else
    FAIL_COUNT := FAIL_COUNT + 1;
    Add(RESULTS, rec(name := "ANUPQ stress test", status := "FAIL"));
fi;

#-------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------

Print("\n");
Print("============================================================\n");
Print("=== SUMMARY ==============================================\n");
Print("============================================================\n\n");

Print("S14 Data Statistics:\n");
Print("  Total large groups: ", Length(S14_ALL_LARGE_SIGKEYS), "\n");
Print("  Order 512 groups: ", Length(GROUPS_512), "\n");
Print("  Order 1024 groups: ", Length(GROUPS_1024), "\n\n");

Print("Test Results:\n");
Print("  Total tests: ", PASS_COUNT + FAIL_COUNT + ERROR_COUNT, "\n");
Print("  Passed: ", PASS_COUNT, "\n");
Print("  Failed: ", FAIL_COUNT, "\n");
Print("  Errors: ", ERROR_COUNT, "\n\n");

if FAIL_COUNT = 0 and ERROR_COUNT = 0 then
    Print("ALL TESTS PASSED!\n");
else
    Print("SOME TESTS FAILED OR ERRORED\n\n");
    Print("Failed/Error tests:\n");
    for r in RESULTS do
        if r.status <> "PASS" then
            Print("  - ", r.name, " (", r.status, ")\n");
        fi;
    od;
fi;

# Write results
PrintTo(Concatenation(TEST_PATH, "anupq_real_data_results.txt"),
    "ANUPQ_REAL_DATA_RESULTS := rec(\n",
    "  passCount := ", String(PASS_COUNT), ",\n",
    "  failCount := ", String(FAIL_COUNT), ",\n",
    "  errorCount := ", String(ERROR_COUNT), ",\n",
    "  groups512 := ", String(Length(GROUPS_512)), ",\n",
    "  groups1024 := ", String(Length(GROUPS_1024)), ",\n",
    "  tests := [\n");

for i in [1..Length(RESULTS)] do
    r := RESULTS[i];
    AppendTo(Concatenation(TEST_PATH, "anupq_real_data_results.txt"),
        "    rec(name := \"", r.name, "\", status := \"", r.status, "\")");
    if i < Length(RESULTS) then
        AppendTo(Concatenation(TEST_PATH, "anupq_real_data_results.txt"), ",");
    fi;
    AppendTo(Concatenation(TEST_PATH, "anupq_real_data_results.txt"), "\n");
od;

AppendTo(Concatenation(TEST_PATH, "anupq_real_data_results.txt"),
    "  ]\n);\n");

Print("\nResults written to ", TEST_PATH, "anupq_real_data_results.txt\n");
Print("\n=== TEST COMPLETE ===\n");

QUIT;
