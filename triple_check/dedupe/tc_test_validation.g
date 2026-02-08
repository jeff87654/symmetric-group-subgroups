# Triple-Check Dedupe - Test Validation
# MUST run and pass before any production deduplication
#
# Validates:
# 1. tc_dedupe_common.g loads correctly
# 2. CompareByFactorsV3 produces correct results on all test pairs
# 3. Bipartite matching handles multi-factor case (January 2026 bug)
#
# Uses test groups from test_factor_comparison.g (constructed live)

SetInfoLevel(InfoWarning, 0);;

Print("\n");
Print("============================================================\n");
Print("=== TC Dedupe Validation Suite =============================\n");
Print("============================================================\n\n");

# Load shared library
BASE_PATH := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/triple_check/dedupe/";;
Print("Loading tc_dedupe_common.g...\n");
Read(Concatenation(BASE_PATH, "tc_dedupe_common.g"));
Print("\n");

# Test counters
PASS_COUNT := 0;;
FAIL_COUNT := 0;;
RESULTS := [];;

#===================================================================
# Helper: Build a production-format record from a GAP group
# Simulates the clean file record format that tc_dedupe_common expects
#===================================================================

BuildProductionRecord := function(G, idx)
    local rec1, factors, Gperm, combined, i, desc, gens;

    # Convert to permutation group to get EvalString-compatible generators
    if not IsPermGroup(G) then
        Gperm := Image(IsomorphismPermGroup(G));
    else
        Gperm := G;
    fi;

    rec1 := rec(
        index := idx,
        order := Size(Gperm),
        isDirectProduct := false,
        factors := [],
        factorOrders := [],
        numFactors := 1,
        generators := List(GeneratorsOfGroup(Gperm), String)
    );

    # Try to decompose into direct factors
    factors := DirectFactorsOfGroup(Gperm);
    if Length(factors) > 1 then
        rec1.isDirectProduct := true;
        rec1.numFactors := Length(factors);

        # Build combined list for co-sorting: [order, name, gen_strings]
        combined := [];
        for i in [1..Length(factors)] do
            desc := StructureDescription(factors[i]);
            gens := List(GeneratorsOfGroup(factors[i]), String);
            Add(combined, [Size(factors[i]), desc, gens]);
        od;

        # Sort by (order, name) for canonical ordering
        Sort(combined, function(a, b)
            if a[1] <> b[1] then return a[1] < b[1]; fi;
            return a[2] < b[2];
        end);

        rec1.factorOrders := List(combined, x -> x[1]);
        rec1.factors := List(combined, x -> x[2]);
        rec1.factorGens := List(combined, x -> x[3]);
    else
        rec1.factors := [StructureDescription(Gperm)];
    fi;

    return rec1;
end;

#===================================================================
# Run a test
#===================================================================

RunTest := function(testRec)
    local rec1, rec2, actual, status;

    Print("Testing: ", testRec.name, "\n");

    rec1 := BuildProductionRecord(testRec.g1, 90000 + Length(RESULTS)*2);
    rec2 := BuildProductionRecord(testRec.g2, 90001 + Length(RESULTS)*2);

    Print("  G1 factors: ", rec1.factors, " DP=", rec1.isDirectProduct, "\n");
    Print("  G2 factors: ", rec2.factors, " DP=", rec2.isDirectProduct, "\n");
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
    Print("  Expected: ", testRec.expected, "\n");

    actual := CompareByFactorsV3(rec1, rec2);

    if actual = testRec.expected then
        status := "PASS";
        PASS_COUNT := PASS_COUNT + 1;
        Print("  Result: PASS\n\n");
    else
        status := "FAIL";
        FAIL_COUNT := FAIL_COUNT + 1;
        Print("  Result: ***FAIL*** (got ", actual, ", expected ", testRec.expected, ")\n\n");
    fi;

    Add(RESULTS, rec(name := testRec.name, expected := testRec.expected,
                      actual := actual, status := status));
    return status;
end;

#===================================================================
# Part 1: Pure Direct Products
#===================================================================

Print("=== Part 1: Pure Direct Products ===\n\n");

tests := [
    rec(name := "P1: C2 x S4 = S4 x C2 (reordered)",
        g1 := DirectProduct(CyclicGroup(2), SymmetricGroup(4)),
        g2 := DirectProduct(SymmetricGroup(4), CyclicGroup(2)),
        expected := true),

    rec(name := "P1: C2 x C2 x C4 = C4 x C2 x C2",
        g1 := DirectProduct(CyclicGroup(2), CyclicGroup(2), CyclicGroup(4)),
        g2 := DirectProduct(CyclicGroup(4), CyclicGroup(2), CyclicGroup(2)),
        expected := true),

    rec(name := "P1: A4 x A4 = A4 x A4",
        g1 := DirectProduct(AlternatingGroup(4), AlternatingGroup(4)),
        g2 := DirectProduct(AlternatingGroup(4), AlternatingGroup(4)),
        expected := true),

    rec(name := "P1: C2 x S4 vs C3 x S4 (different)",
        g1 := DirectProduct(CyclicGroup(2), SymmetricGroup(4)),
        g2 := DirectProduct(CyclicGroup(3), SymmetricGroup(4)),
        expected := false),
];;

for t in tests do RunTest(t); od;

#===================================================================
# Part 2: Single Semidirect Factor
#===================================================================

Print("=== Part 2: Single Semidirect Factor ===\n\n");

tests := [
    rec(name := "P2: D8 x C3 = D8 x C3",
        g1 := DirectProduct(SmallGroup(8, 3), CyclicGroup(3)),
        g2 := DirectProduct(SmallGroup(8, 3), CyclicGroup(3)),
        expected := true),

    rec(name := "P2: D8 x C3 vs Q8 x C3 (different semi)",
        g1 := DirectProduct(SmallGroup(8, 3), CyclicGroup(3)),
        g2 := DirectProduct(SmallGroup(8, 4), CyclicGroup(3)),
        expected := false),

    rec(name := "P2: D8 x C5 vs D8 x C7 (different pure)",
        g1 := DirectProduct(SmallGroup(8, 3), CyclicGroup(5)),
        g2 := DirectProduct(SmallGroup(8, 3), CyclicGroup(7)),
        expected := false),

    rec(name := "P2: SG(24,12) x C2 = C2 x SG(24,12)",
        g1 := DirectProduct(SmallGroup(24, 12), CyclicGroup(2)),
        g2 := DirectProduct(CyclicGroup(2), SmallGroup(24, 12)),
        expected := true),
];;

for t in tests do RunTest(t); od;

#===================================================================
# Part 3: Multiple Semidirect Factors (THE CRITICAL BUG CASE)
#===================================================================

Print("=== Part 3: Multiple Semidirect Factors (Bug Case) ===\n\n");

tests := [
    rec(name := "P3: TWO SEMI SAME: (C2^4:C2) x (S3xS3:C2) twice",
        g1 := DirectProduct(SmallGroup(32, 6), SmallGroup(72, 40)),
        g2 := DirectProduct(SmallGroup(32, 6), SmallGroup(72, 40)),
        expected := true),

    rec(name := "P3: TWO SEMI ONE DIFFERS: (C2^4:C2) vs (C4^2:C2) + same S3xS3:C2",
        g1 := DirectProduct(SmallGroup(32, 6), SmallGroup(72, 40)),
        g2 := DirectProduct(SmallGroup(32, 7), SmallGroup(72, 40)),
        expected := false),  # THE BUG CASE

    rec(name := "P3: TWO SEMI BOTH DIFFER",
        g1 := DirectProduct(SmallGroup(32, 6), SmallGroup(72, 40)),
        g2 := DirectProduct(SmallGroup(32, 7), SmallGroup(72, 41)),
        expected := false),

    rec(name := "P3: Same semi, different pure",
        g1 := DirectProduct(SmallGroup(32, 6), CyclicGroup(3)),
        g2 := DirectProduct(SmallGroup(32, 6), CyclicGroup(5)),
        expected := false),
];;

for t in tests do RunTest(t); od;

#===================================================================
# Part 3b: Pure Factor Mismatch with Semidirect (Concern 1)
#===================================================================

Print("=== Part 3b: Pure Factor Mismatch + Semidirect (Concern 1) ===\n\n");

tests := [
    rec(name := "C1: C2 x C3 x D8 vs C2 x C5 x D8 (pure mismatch)",
        g1 := DirectProduct(CyclicGroup(2), CyclicGroup(3), SmallGroup(8, 3)),
        g2 := DirectProduct(CyclicGroup(2), CyclicGroup(5), SmallGroup(8, 3)),
        expected := false),

    rec(name := "C1: C3 x D8 x Q8 vs C5 x D8 x Q8 (two semi, pure differs)",
        g1 := DirectProduct(CyclicGroup(3), SmallGroup(8, 3), SmallGroup(8, 4)),
        g2 := DirectProduct(CyclicGroup(5), SmallGroup(8, 3), SmallGroup(8, 4)),
        expected := false),

    rec(name := "C1: C2 x C3 x D8 vs C2 x C3 x Q8 (pure same, semi differs)",
        g1 := DirectProduct(CyclicGroup(2), CyclicGroup(3), SmallGroup(8, 3)),
        g2 := DirectProduct(CyclicGroup(2), CyclicGroup(3), SmallGroup(8, 4)),
        expected := false),

    rec(name := "C1 positive: C2 x C3 x D8 = C3 x C2 x D8 (reordered)",
        g1 := DirectProduct(CyclicGroup(2), CyclicGroup(3), SmallGroup(8, 3)),
        g2 := DirectProduct(CyclicGroup(3), CyclicGroup(2), SmallGroup(8, 3)),
        expected := true),
];;

for t in tests do RunTest(t); od;

#===================================================================
# Part 3c: Greedy Matching Robustness (Concern 2)
#===================================================================

Print("=== Part 3c: Greedy Matching (Concern 2) ===\n\n");

tests := [
    rec(name := "C2: D8 x D8 = D8 x D8 (identical factors)",
        g1 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 3)),
        g2 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 3)),
        expected := true),

    rec(name := "C2: D8 x Q8 = Q8 x D8 (swapped)",
        g1 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 4)),
        g2 := DirectProduct(SmallGroup(8, 4), SmallGroup(8, 3)),
        expected := true),

    rec(name := "C2: D8 x D8 x Q8 = Q8 x D8 x D8",
        g1 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 3), SmallGroup(8, 4)),
        g2 := DirectProduct(SmallGroup(8, 4), SmallGroup(8, 3), SmallGroup(8, 3)),
        expected := true),

    rec(name := "C2: D8 x D8 vs D8 x Q8 (one differs)",
        g1 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 3)),
        g2 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 4)),
        expected := false),

    rec(name := "C2: DihedralGroup(8) x Q8 = SG(8,3) x SG(8,4)",
        g1 := DirectProduct(DihedralGroup(8), QuaternionGroup(8)),
        g2 := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 4)),
        expected := true),
];;

for t in tests do RunTest(t); od;

#===================================================================
# Part 4: Edge Cases
#===================================================================

Print("=== Part 4: Edge Cases ===\n\n");

tests := [
    rec(name := "Edge: Non-direct-product (S5 vs S5)",
        g1 := SymmetricGroup(5),
        g2 := SymmetricGroup(5),
        expected := fail),

    rec(name := "Edge: DP with non-DP",
        g1 := DirectProduct(CyclicGroup(2), SymmetricGroup(4)),
        g2 := SymmetricGroup(5),
        expected := fail),
];;

for t in tests do RunTest(t); od;

#===================================================================
# Part 5: Same-Name Semidirect Factors (SD Collision Tests)
#
# Tests for the case where two non-isomorphic groups have the
# SAME StructureDescription. When these appear as direct factors,
# the old ambiguousFactorGens record-key collision caused only one
# factor's generators to be stored (now resolved by factorGens format).
#
# CompareByFactorsV3 must still return correct results.
#
# Key collision pairs used:
#   SmallGroup(20, 1) and SmallGroup(20, 3): both SD = "C5 : C4"
#   SmallGroup(36, 7) and SmallGroup(36, 9): both SD = "(C3 x C3) : C4"
#===================================================================

Print("=== Part 5: Same-Name Semidirect Factors (SD Collisions) ===\n\n");

tests := [
    # 5.1: H x H vs H x H (identical, same-name factors within each group)
    rec(name := "P5.1: SG(20,1)xSG(20,1) = SG(20,1)xSG(20,1) (identical same-name)",
        g1 := DirectProduct(SmallGroup(20, 1), SmallGroup(20, 1)),
        g2 := DirectProduct(SmallGroup(20, 1), SmallGroup(20, 1)),
        expected := true),

    # 5.2: H1 x H1 vs H2 x H2 (different groups, same SD for all factors)
    rec(name := "P5.2: SG(20,1)xSG(20,1) vs SG(20,3)xSG(20,3) (both 'C5:C4' but different)",
        g1 := DirectProduct(SmallGroup(20, 1), SmallGroup(20, 1)),
        g2 := DirectProduct(SmallGroup(20, 3), SmallGroup(20, 3)),
        expected := false),

    # 5.3: H1 x H2 vs H1 x H2 (same mixed group)
    rec(name := "P5.3: SG(20,1)xSG(20,3) = SG(20,1)xSG(20,3) (same mixed pair)",
        g1 := DirectProduct(SmallGroup(20, 1), SmallGroup(20, 3)),
        g2 := DirectProduct(SmallGroup(20, 1), SmallGroup(20, 3)),
        expected := true),

    # 5.4: H1 x H2 vs H2 x H1 (swapped order, same group)
    rec(name := "P5.4: SG(20,1)xSG(20,3) vs SG(20,3)xSG(20,1) (swapped)",
        g1 := DirectProduct(SmallGroup(20, 1), SmallGroup(20, 3)),
        g2 := DirectProduct(SmallGroup(20, 3), SmallGroup(20, 1)),
        expected := true),

    # 5.5: H1 x H1 vs H1 x H2 (one factor differs)
    rec(name := "P5.5: SG(20,1)xSG(20,1) vs SG(20,1)xSG(20,3) (one factor differs)",
        g1 := DirectProduct(SmallGroup(20, 1), SmallGroup(20, 1)),
        g2 := DirectProduct(SmallGroup(20, 1), SmallGroup(20, 3)),
        expected := false),

    # 5.6: Different collision pair, larger groups
    rec(name := "P5.6: SG(36,7)xSG(36,7) vs SG(36,9)xSG(36,9) (both '(C3xC3):C4')",
        g1 := DirectProduct(SmallGroup(36, 7), SmallGroup(36, 7)),
        g2 := DirectProduct(SmallGroup(36, 9), SmallGroup(36, 9)),
        expected := false),

    # 5.7: Same-name collision with an additional pure factor
    rec(name := "P5.7: SG(20,1)xSG(20,1)xC3 vs SG(20,3)xSG(20,3)xC3 (pure + same-name)",
        g1 := DirectProduct(SmallGroup(20, 1), SmallGroup(20, 1), CyclicGroup(3)),
        g2 := DirectProduct(SmallGroup(20, 3), SmallGroup(20, 3), CyclicGroup(3)),
        expected := false),
];;

for t in tests do RunTest(t); od;

#===================================================================
# Summary
#===================================================================

Print("\n");
Print("============================================================\n");
Print("=== VALIDATION SUMMARY ====================================\n");
Print("============================================================\n\n");

Print("Total tests: ", PASS_COUNT + FAIL_COUNT, "\n");
Print("Passed: ", PASS_COUNT, "\n");
Print("Failed: ", FAIL_COUNT, "\n\n");

if FAIL_COUNT = 0 then
    Print("*** ALL TESTS PASSED - VALIDATION SUCCESSFUL ***\n\n");
    Print("Production deduplication is safe to proceed.\n");
else
    Print("*** VALIDATION FAILED ***\n\n");
    Print("DO NOT proceed with production deduplication!\n");
    Print("Failed tests:\n");
    for r in RESULTS do
        if r.status <> "PASS" then
            Print("  - ", r.name, " (expected ", r.expected, ", got ", r.actual, ")\n");
        fi;
    od;
fi;

# Write result file for launcher to check
PrintTo(Concatenation(BASE_PATH, "validation_result.txt"),
    "VALIDATION_RESULT := rec(\n",
    "  passCount := ", String(PASS_COUNT), ",\n",
    "  failCount := ", String(FAIL_COUNT), ",\n",
    "  totalTests := ", String(PASS_COUNT + FAIL_COUNT), ",\n",
    "  passed := ", String(FAIL_COUNT = 0), "\n",
    ");\n");

Print("\nResults written to ", BASE_PATH, "validation_result.txt\n");
Print("\n=== VALIDATION COMPLETE ===\n");

QUIT;
