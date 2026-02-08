# Factor Comparison Test Suite
# Tests for direct product decomposition and factor-level isomorphism testing
# Can run in either Cygwin or WSL
#
# Test Sections:
#   Part 1: Pure Direct Products (no semidirect factors)
#   Part 2: Single Semidirect Factor
#   Part 3: Multiple Semidirect Factors (bucket 54 bug case)
#   Part 3b: Pure Factor Mismatch with Semidirect (Concern 1 regression)
#          - Catches bug where leftover pure factors are ignored when
#            semidirect factors exist
#   Part 3c: Greedy Matching Robustness (Concern 2)
#          - Tests various factor matching scenarios to ensure algorithm
#            handles permuted factor orders correctly
#   Part 4: Buggy Algorithm Regression Test
#   Part 5: Edge Cases
#
# Concerns addressed:
#   Concern 1: Pure factor mismatch ignored when semidirect factors exist
#   Concern 2: Greedy matching may fail to find valid matching (theoretical)
#
# Cygwin path format (change to /mnt/c/... for WSL)
BASE_PATH := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/Partition/tests/";

Print("\n");
Print("============================================================\n");
Print("=== Factor Comparison Test Suite ============================\n");
Print("============================================================\n\n");

# Test counters
PASS_COUNT := 0;;
FAIL_COUNT := 0;;
RESULTS := [];;

#-------------------------------------------------------------------
# Helper Functions (Implementing the Fixed Algorithm)
#-------------------------------------------------------------------

# Build invariant record for a group (simulating what the real code does)
# Stores generators for ALL direct product factors in factorGens (positional)
BuildInvariantRecord := function(G)
    local factors, f, desc, invRec, combined, i, gens;

    invRec := rec(
        order := Size(G),
        isDirectProduct := false,
        factors := [],
        factorOrders := [],
        numFactors := 1
    );

    # Try to decompose into direct factors
    factors := DirectFactorsOfGroup(G);
    if Length(factors) > 1 then
        invRec.isDirectProduct := true;
        invRec.numFactors := Length(factors);

        # Build combined list for co-sorting: [order, name, gens]
        combined := [];
        for i in [1..Length(factors)] do
            desc := StructureDescription(factors[i]);
            gens := GeneratorsOfGroup(factors[i]);
            Add(combined, [Size(factors[i]), desc, gens]);
        od;

        # Sort by (order, name) for canonical ordering
        Sort(combined, function(a, b)
            if a[1] <> b[1] then return a[1] < b[1]; fi;
            return a[2] < b[2];
        end);

        invRec.factorOrders := List(combined, x -> x[1]);
        invRec.factors := List(combined, x -> x[2]);
        invRec.factorGens := List(combined, x -> x[3]);
    else
        invRec.factors := [StructureDescription(G)];
    fi;

    return invRec;
end;

# FIXED CompareByFactorsV3: compares ALL factors via bipartite matching
CompareByFactorsV3_FIXED := function(rec1, rec2)
    local pairs1, pairs2, matched, i, j, g1, g2, foundMatch, result;

    if not rec1.isDirectProduct or not rec2.isDirectProduct then
        return fail;
    fi;

    # Must have same number of factors
    if rec1.numFactors <> rec2.numFactors then
        return false;
    fi;

    # Quick check: sorted factor orders must match
    if rec1.factorOrders <> rec2.factorOrders then
        return false;
    fi;

    # Get all factor groups
    if not IsBound(rec1.factorGens) or not IsBound(rec2.factorGens) then
        return fail;
    fi;

    pairs1 := rec1.factorGens;
    pairs2 := rec2.factorGens;

    if Length(pairs1) = 0 or Length(pairs2) = 0 then return fail; fi;
    if Length(pairs1) <> Length(pairs2) then return false; fi;

    # Bipartite matching of ALL factors
    matched := [];
    for i in [1..Length(pairs1)] do
        g1 := Group(pairs1[i]);
        foundMatch := false;

        for j in [1..Length(pairs2)] do
            if j in matched then continue; fi;
            g2 := Group(pairs2[j]);

            # Size check first (fast)
            if Size(g1) <> Size(g2) then continue; fi;

            # Isomorphism test on the FACTOR
            result := CALL_WITH_CATCH(IsomorphismGroups, [g1, g2]);
            if result[1] = true and result[2] <> fail then
                Add(matched, j);
                foundMatch := true;
                break;
            fi;
        od;

        if not foundMatch then
            return false;
        fi;
    od;

    return true;
end;

# BUGGY VERSION: Only compares first factor (for regression test)
CompareByFactorsV3_BUGGY := function(rec1, rec2)
    local pairs1, pairs2, g1, g2, result;

    if not rec1.isDirectProduct or not rec2.isDirectProduct then
        return fail;
    fi;

    if not IsBound(rec1.factorGens) or not IsBound(rec2.factorGens) then
        return fail;
    fi;

    pairs1 := rec1.factorGens;
    pairs2 := rec2.factorGens;

    if Length(pairs1) = 0 or Length(pairs2) = 0 then return fail; fi;

    # THE BUG: Only compare FIRST factor, ignore others!
    g1 := Group(pairs1[1]);
    g2 := Group(pairs2[1]);

    if Size(g1) <> Size(g2) then return false; fi;

    result := CALL_WITH_CATCH(IsomorphismGroups, [g1, g2]);
    if result[1] = true and result[2] <> fail then
        return true;
    else
        return false;
    fi;
end;

# Run a single test case
RunTest := function(testRec)
    local rec1, rec2, actual, status, resultRec;

    Print("Testing: ", testRec.name, "\n");
    Print("  Groups: order ", Size(testRec.g1), " and ", Size(testRec.g2), "\n");
    Print("  Expected: ", testRec.expected, "\n");

    # Build invariant records
    rec1 := BuildInvariantRecord(testRec.g1);
    rec2 := BuildInvariantRecord(testRec.g2);

    Print("  G1 factors: ", rec1.factors, "\n");
    Print("  G2 factors: ", rec2.factors, "\n");
    if IsBound(rec1.factorGens) then
        Print("  G1 factorGens count: ", Length(rec1.factorGens), "\n");
    else
        Print("  G1 factorGens: (none)\n");
    fi;
    if IsBound(rec2.factorGens) then
        Print("  G2 factorGens count: ", Length(rec2.factorGens), "\n");
    else
        Print("  G2 factorGens: (none)\n");
    fi;

    # Run the FIXED algorithm
    actual := CompareByFactorsV3_FIXED(rec1, rec2);

    if actual = testRec.expected then
        status := "PASS";
        PASS_COUNT := PASS_COUNT + 1;
        Print("  Result: PASS\n");
    else
        status := "FAIL";
        FAIL_COUNT := FAIL_COUNT + 1;
        Print("  Result: FAIL (got ", actual, ")\n");
    fi;
    Print("\n");

    resultRec := rec(
        name := testRec.name,
        expected := testRec.expected,
        actual := actual,
        status := status
    );
    Add(RESULTS, resultRec);

    return status;
end;

#-------------------------------------------------------------------
# Part 1: Pure Direct Products (No Semidirect Factors)
#-------------------------------------------------------------------

Print("=== Part 1: Pure Direct Products ===\n\n");

TEST_PURE_DIRECT := [
    rec(name := "C2 x S4 = S4 x C2 (reordered)",
        g1 := DirectProduct(CyclicGroup(2), SymmetricGroup(4)),
        g2 := DirectProduct(SymmetricGroup(4), CyclicGroup(2)),
        expected := true),

    rec(name := "C2 x C2 x C4 = C4 x C2 x C2 (reordered)",
        g1 := DirectProduct(CyclicGroup(2), CyclicGroup(2), CyclicGroup(4)),
        g2 := DirectProduct(CyclicGroup(4), CyclicGroup(2), CyclicGroup(2)),
        expected := true),

    rec(name := "A4 x A4 = A4 x A4",
        g1 := DirectProduct(AlternatingGroup(4), AlternatingGroup(4)),
        g2 := DirectProduct(AlternatingGroup(4), AlternatingGroup(4)),
        expected := true),

    rec(name := "C2 x S4 vs C3 x S4 (different)",
        g1 := DirectProduct(CyclicGroup(2), SymmetricGroup(4)),
        g2 := DirectProduct(CyclicGroup(3), SymmetricGroup(4)),
        expected := false),

    rec(name := "C2 x C2 vs C4 (different abelian)",
        g1 := DirectProduct(CyclicGroup(2), CyclicGroup(2)),
        g2 := CyclicGroup(4),
        expected := fail),  # C4 is not a direct product, so algorithm returns fail
];;

for test in TEST_PURE_DIRECT do
    RunTest(test);
od;

#-------------------------------------------------------------------
# Part 2: Single Semidirect Factor
#-------------------------------------------------------------------

Print("=== Part 2: Single Semidirect Factor ===\n\n");

# D8 = (C4 : C2), Q8 is also order 8 but different structure
# SmallGroup(8, 3) = D8, SmallGroup(8, 4) = Q8

TEST_SINGLE_SEMI := [
    rec(name := "D8 x C3 = D8 x C3 (same semidirect factor)",
        g1 := DirectProduct(SmallGroup(8, 3), CyclicGroup(3)),
        g2 := DirectProduct(SmallGroup(8, 3), CyclicGroup(3)),
        expected := true),

    rec(name := "D8 x C3 vs Q8 x C3 (different semidirect factor)",
        g1 := DirectProduct(SmallGroup(8, 3), CyclicGroup(3)),
        g2 := DirectProduct(SmallGroup(8, 4), CyclicGroup(3)),
        expected := false),

    rec(name := "D8 x C5 vs D8 x C7 (same semi, different pure)",
        g1 := DirectProduct(SmallGroup(8, 3), CyclicGroup(5)),
        g2 := DirectProduct(SmallGroup(8, 3), CyclicGroup(7)),
        expected := false),

    # Larger semidirect factors
    rec(name := "SmallGroup(24, 12) x C2 = SmallGroup(24, 12) x C2",
        g1 := DirectProduct(SmallGroup(24, 12), CyclicGroup(2)),
        g2 := DirectProduct(CyclicGroup(2), SmallGroup(24, 12)),
        expected := true),
];;

for test in TEST_SINGLE_SEMI do
    RunTest(test);
od;

#-------------------------------------------------------------------
# Part 3: Multiple Semidirect Factors (THE CRITICAL BUG CASE)
#-------------------------------------------------------------------

Print("=== Part 3: Multiple Semidirect Factors (Bug Case) ===\n\n");

# This is the pattern that caused bucket 54 bug:
# Groups with TWO semidirect factors where one matches but other doesn't

# SmallGroup(32, 6) = (C2^4) : C2  (different from SmallGroup(32, 7) = (C4 x C4) : C2)
# SmallGroup(72, 40) = (S3 x S3) : C2

TEST_MULTI_SEMI := [
    rec(name := "TWO SEMI SAME: ((C2^4):C2) x ((S3xS3):C2) twice",
        g1 := DirectProduct(SmallGroup(32, 6), SmallGroup(72, 40)),
        g2 := DirectProduct(SmallGroup(32, 6), SmallGroup(72, 40)),
        expected := true),

    rec(name := "TWO SEMI ONE DIFFERS: ((C2^4):C2) vs ((C4^2):C2) same S3xS3:C2",
        g1 := DirectProduct(SmallGroup(32, 6), SmallGroup(72, 40)),
        g2 := DirectProduct(SmallGroup(32, 7), SmallGroup(72, 40)),
        expected := false),  # THE BUG CASE - buggy algorithm says true!

    rec(name := "TWO SEMI BOTH DIFFER",
        g1 := DirectProduct(SmallGroup(32, 6), SmallGroup(72, 40)),
        g2 := DirectProduct(SmallGroup(32, 7), SmallGroup(72, 41)),
        expected := false),

    # Different pure factors (same semidirect)
    rec(name := "Same semi, different pure factor",
        g1 := DirectProduct(SmallGroup(32, 6), CyclicGroup(3)),
        g2 := DirectProduct(SmallGroup(32, 6), CyclicGroup(5)),
        expected := false),
];;

for test in TEST_MULTI_SEMI do
    RunTest(test);
od;

#-------------------------------------------------------------------
# Part 3b: Pure Factor Mismatch with Semidirect Factors (Concern 1)
#-------------------------------------------------------------------

Print("=== Part 3b: Pure Factor Mismatch with Semidirect (Concern 1) ===\n\n");

# These tests catch the bug where pure factors are ignored when
# semidirect factors exist. The counterexample pattern:
#   rec1.factors = ["C2", "C3", "A:B"]
#   rec2.factors = ["C2", "C5", "A:B"]
# After canceling C2, we have ["C3", "A:B"] vs ["C5", "A:B"]
# Buggy code might only compare A:B and ignore C3 vs C5 mismatch.

TEST_PURE_MISMATCH_WITH_SEMI := [
    # Pattern: shared pure factor + different pure factor + same semidirect
    rec(name := "Concern1: C2 x C3 x D8 vs C2 x C5 x D8 (pure mismatch)",
        g1 := DirectProduct(CyclicGroup(2), CyclicGroup(3), SmallGroup(8, 3)),
        g2 := DirectProduct(CyclicGroup(2), CyclicGroup(5), SmallGroup(8, 3)),
        expected := false),

    # Multiple shared pure factors, one differs
    rec(name := "Concern1: C2 x C2 x C3 x D8 vs C2 x C2 x C7 x D8",
        g1 := DirectProduct(CyclicGroup(2), CyclicGroup(2), CyclicGroup(3), SmallGroup(8, 3)),
        g2 := DirectProduct(CyclicGroup(2), CyclicGroup(2), CyclicGroup(7), SmallGroup(8, 3)),
        expected := false),

    # Two semidirect factors + differing pure factor
    rec(name := "Concern1: C3 x D8 x Q8 vs C5 x D8 x Q8 (two semi, pure differs)",
        g1 := DirectProduct(CyclicGroup(3), SmallGroup(8, 3), SmallGroup(8, 4)),
        g2 := DirectProduct(CyclicGroup(5), SmallGroup(8, 3), SmallGroup(8, 4)),
        expected := false),

    # All pure factors cancel, semidirect differs (should still work)
    rec(name := "Concern1: C2 x C3 x D8 vs C2 x C3 x Q8 (pure same, semi differs)",
        g1 := DirectProduct(CyclicGroup(2), CyclicGroup(3), SmallGroup(8, 3)),
        g2 := DirectProduct(CyclicGroup(2), CyclicGroup(3), SmallGroup(8, 4)),
        expected := false),

    # No common pure factors at all, semidirect same
    rec(name := "Concern1: C3 x D8 vs C5 x D8 (no common pure, semi same)",
        g1 := DirectProduct(CyclicGroup(3), SmallGroup(8, 3)),
        g2 := DirectProduct(CyclicGroup(5), SmallGroup(8, 3)),
        expected := false),

    # Edge case: only pure factors differ, no cancellation possible
    rec(name := "Concern1: C3 x C5 x D8 vs C7 x C11 x D8 (all pure differ)",
        g1 := DirectProduct(CyclicGroup(3), CyclicGroup(5), SmallGroup(8, 3)),
        g2 := DirectProduct(CyclicGroup(7), CyclicGroup(11), SmallGroup(8, 3)),
        expected := false),

    # Positive case: everything matches after cancellation
    rec(name := "Concern1 positive: C2 x C3 x D8 = C3 x C2 x D8 (reordered)",
        g1 := DirectProduct(CyclicGroup(2), CyclicGroup(3), SmallGroup(8, 3)),
        g2 := DirectProduct(CyclicGroup(3), CyclicGroup(2), SmallGroup(8, 3)),
        expected := true),
];;

for test in TEST_PURE_MISMATCH_WITH_SEMI do
    RunTest(test);
od;

#-------------------------------------------------------------------
# Part 3c: Greedy Matching Robustness (Concern 2)
#-------------------------------------------------------------------

Print("=== Part 3c: Greedy Matching Robustness (Concern 2) ===\n\n");

# Test cases for greedy matching behavior.
# Note: For isomorphism matching, greedy is actually complete due to
# transitivity (if A≅X and A≅Y, then X≅Y, so B≅X implies B≅Y).
# These tests verify the algorithm handles various matching scenarios.

# SmallGroup(8, 3) = D8, SmallGroup(8, 4) = Q8
# SmallGroup(16, 7) = D16, SmallGroup(16, 9) = QD16 (quasi-dihedral)

TEST_GREEDY_MATCHING := [
    # Two identical semidirect factors - any matching works
    rec(name := "Greedy: D8 x D8 = D8 x D8 (identical factors)",
        g1 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 3)),
        g2 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 3)),
        expected := true),

    # Two different semidirect factors - unique matching required
    rec(name := "Greedy: D8 x Q8 = Q8 x D8 (swapped order)",
        g1 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 4)),
        g2 := DirectProduct(SmallGroup(8, 4), SmallGroup(8, 3)),
        expected := true),

    # Three semidirect factors with mixed uniqueness
    rec(name := "Greedy: D8 x D8 x Q8 = Q8 x D8 x D8 (one unique, two same)",
        g1 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 3), SmallGroup(8, 4)),
        g2 := DirectProduct(SmallGroup(8, 4), SmallGroup(8, 3), SmallGroup(8, 3)),
        expected := true),

    # Four factors - stress test matching
    rec(name := "Greedy: D8 x Q8 x D16 x Q8 = Q8 x D16 x D8 x Q8 (4 factors)",
        g1 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 4), SmallGroup(16, 7), SmallGroup(8, 4)),
        g2 := DirectProduct(SmallGroup(8, 4), SmallGroup(16, 7), SmallGroup(8, 3), SmallGroup(8, 4)),
        expected := true),

    # Partial match failure - one factor has no match
    rec(name := "Greedy negative: D8 x D8 vs D8 x Q8 (one differs)",
        g1 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 3)),
        g2 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 4)),
        expected := false),

    # All factors different
    rec(name := "Greedy negative: D8 x D16 vs Q8 x QD16 (all differ)",
        g1 := DirectProduct(SmallGroup(8, 3), SmallGroup(16, 7)),
        g2 := DirectProduct(SmallGroup(8, 4), SmallGroup(16, 9)),
        expected := false),

    # Same structure descriptions but from different constructions
    # (tests that isomorphism test works, not just string matching)
    rec(name := "Greedy: DihedralGroup(8) x Q8 = SmallGroup(8,3) x SmallGroup(8,4)",
        g1 := DirectProduct(DihedralGroup(8), QuaternionGroup(8)),
        g2 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 4)),
        expected := true),
];;

for test in TEST_GREEDY_MATCHING do
    RunTest(test);
od;

#-------------------------------------------------------------------
# Part 4: Buggy Algorithm Regression Test
#-------------------------------------------------------------------

Print("=== Part 4: Buggy Algorithm Regression Test ===\n\n");

# Demonstrate that the buggy algorithm gives WRONG answer when the
# common factor happens to be first. With co-sorted factorGens, we need
# factors of the SAME order for the bug to manifest (so both appear at
# the same position and the common one may come first).
#
# Use D8 x D8 vs Q8 x D8 - both factors are order 8. If the common
# D8 happens to sort first (by name), the buggy algorithm compares only
# that one and returns true.

Print("Testing buggy algorithm on same-order factors case...\n\n");

# SmallGroup(8,3)=D8="D8", SmallGroup(8,4)=Q8="Q8"
# After co-sorting by (order, name): D8 < Q8 alphabetically
# G1 = D8 x D8: factorGens sorted = [D8_gens, D8_gens] (both "D8")
# G2 = D8 x Q8: factorGens sorted = [D8_gens, Q8_gens] ("D8" then "Q8")
# Buggy compares only factorGens[1]: D8 vs D8 -> isomorphic -> returns TRUE (WRONG!)

G_bug1 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 3));;
G_bug2 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 4));;

rec1 := BuildInvariantRecord(G_bug1);;
rec2 := BuildInvariantRecord(G_bug2);;

Print("G1: D8 x D8\n");
Print("G2: D8 x Q8\n");
Print("Expected: NOT isomorphic (false)\n\n");

buggy_result := CompareByFactorsV3_BUGGY(rec1, rec2);;
fixed_result := CompareByFactorsV3_FIXED(rec1, rec2);;

Print("Buggy algorithm result: ", buggy_result, "\n");
Print("Fixed algorithm result: ", fixed_result, "\n");

if buggy_result = true and fixed_result = false then
    Print("\n>>> REGRESSION TEST CONFIRMED: Buggy algorithm incorrectly returns TRUE\n");
    Print(">>> Only comparing first factor misses the D8 vs Q8 difference!\n");
else
    Print("\n>>> WARNING: Results don't match expected pattern\n");
    Print(">>> Buggy expected true (wrong), Fixed expected false (correct)\n");
fi;

Print("\n");

#-------------------------------------------------------------------
# Part 5: Edge Cases
#-------------------------------------------------------------------

Print("=== Part 5: Edge Cases ===\n\n");

TEST_EDGE := [
    # Not a direct product
    rec(name := "Non-direct-product group",
        g1 := SymmetricGroup(5),
        g2 := SymmetricGroup(5),
        expected := fail),  # Algorithm returns fail for non-DP

    # Trivial direct product
    rec(name := "G x trivial = G",
        g1 := DirectProduct(SymmetricGroup(4), CyclicGroup(1)),
        g2 := SymmetricGroup(4),
        expected := fail),  # Different structure
];;

for test in TEST_EDGE do
    result := RunTest(test);
od;

#-------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------

Print("\n");
Print("============================================================\n");
Print("=== SUMMARY ==============================================\n");
Print("============================================================\n\n");

Print("Total tests: ", PASS_COUNT + FAIL_COUNT, "\n");
Print("Passed: ", PASS_COUNT, "\n");
Print("Failed: ", FAIL_COUNT, "\n");
Print("\n");

if FAIL_COUNT = 0 then
    Print("ALL TESTS PASSED!\n");
else
    Print("SOME TESTS FAILED\n\n");
    Print("Failed tests:\n");
    for r in RESULTS do
        if r.status <> "PASS" then
            Print("  - ", r.name, "\n");
        fi;
    od;
fi;

# Write results
PrintTo(Concatenation(BASE_PATH, "factor_results.txt"),
    "FACTOR_TEST_RESULTS := rec(\n",
    "  passCount := ", String(PASS_COUNT), ",\n",
    "  failCount := ", String(FAIL_COUNT), ",\n",
    "  buggyVsFixed := rec(\n",
    "    buggy := ", String(buggy_result), ",\n",
    "    fixed := ", String(fixed_result), "\n",
    "  ),\n",
    "  tests := [\n");

for i in [1..Length(RESULTS)] do
    r := RESULTS[i];
    AppendTo(Concatenation(BASE_PATH, "factor_results.txt"),
        "    rec(name := \"", r.name, "\", status := \"", r.status, "\")");
    if i < Length(RESULTS) then
        AppendTo(Concatenation(BASE_PATH, "factor_results.txt"), ",");
    fi;
    AppendTo(Concatenation(BASE_PATH, "factor_results.txt"), "\n");
od;

AppendTo(Concatenation(BASE_PATH, "factor_results.txt"),
    "  ]\n);\n");

Print("\nResults written to ", BASE_PATH, "factor_results.txt\n");
Print("\n=== TEST COMPLETE ===\n");

QUIT;
