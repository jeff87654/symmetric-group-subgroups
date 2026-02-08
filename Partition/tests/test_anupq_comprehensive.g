# ANUPQ 2-Group Comprehensive Test Suite
# Tests for IsIsomorphicPGroup correctness on 2-groups (orders 512, 1024)
# MUST run in WSL - ANUPQ crashes on Cygwin with "iostream dead" errors

# WSL path format
BASE_PATH := "/mnt/c/Users/jeffr/Downloads/Symmetric Groups/Partition/tests/";

LoadPackage("anupq");;

Print("\n");
Print("============================================================\n");
Print("=== ANUPQ 2-Group Comprehensive Test Suite ==================\n");
Print("============================================================\n\n");

# Test counters
PASS_COUNT := 0;;
FAIL_COUNT := 0;;
ERROR_COUNT := 0;;
RESULTS := [];;

# Safe wrapper for ANUPQ with timeout/error handling
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

# Run a single test case
RunTest := function(testRec)
    local g1, g2, actual, status, resultRec;

    Print("Testing: ", testRec.name, "\n");
    Print("  Order: ", Size(testRec.g1), "\n");
    Print("  Expected: ", testRec.expected, "\n");

    # Run the test
    actual := SafeIsIsomorphicPGroup(testRec.g1, testRec.g2);

    if actual = "ERROR" then
        status := "ERROR";
        ERROR_COUNT := ERROR_COUNT + 1;
        Print("  Result: ERROR (ANUPQ failed)\n");
    elif actual = testRec.expected then
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
# Part 1: Known Isomorphic 2-Groups (Positive Tests)
#-------------------------------------------------------------------

Print("=== Part 1: Isomorphic 2-Groups (Positive Tests) ===\n\n");

TEST_ISOMORPHIC := [
    # Trivial case: same SmallGroup
    rec(name := "Same SmallGroup(512, 1)",
        g1 := SmallGroup(512, 1),
        g2 := SmallGroup(512, 1),
        expected := true),

    # Trivial case: same SmallGroup different instance
    rec(name := "Same SmallGroup(512, 2042)",
        g1 := SmallGroup(512, 2042),
        g2 := SmallGroup(512, 2042),
        expected := true),

    # Extra-special groups
    rec(name := "Extra-special 512 (+ type) via SmallGroup",
        g1 := ExtraspecialGroup(512, "+"),
        g2 := SmallGroup(512, 496360),
        expected := true),

    # Dihedral groups
    rec(name := "Dihedral D512 two ways",
        g1 := DihedralGroup(512),
        g2 := SmallGroup(512, 2042),
        expected := true),

    # Direct products
    rec(name := "C256 x C2 = C256 x C2",
        g1 := DirectProduct(CyclicGroup(256), CyclicGroup(2)),
        g2 := DirectProduct(CyclicGroup(2), CyclicGroup(256)),
        expected := true),

    rec(name := "D8 x D8 x C8 both orders",
        g1 := DirectProduct(DihedralGroup(8), DihedralGroup(8), CyclicGroup(8)),
        g2 := DirectProduct(CyclicGroup(8), DihedralGroup(8), DihedralGroup(8)),
        expected := true),

    # Order 1024 - beyond SmallGroups but construction known
    rec(name := "C512 x C2 = C512 x C2",
        g1 := DirectProduct(CyclicGroup(512), CyclicGroup(2)),
        g2 := DirectProduct(CyclicGroup(2), CyclicGroup(512)),
        expected := true),

    rec(name := "D8 x SmallGroup(128, 1) = D8 x SmallGroup(128, 1)",
        g1 := DirectProduct(DihedralGroup(8), SmallGroup(128, 1)),
        g2 := DirectProduct(SmallGroup(128, 1), DihedralGroup(8)),
        expected := true),
];;

for test in TEST_ISOMORPHIC do
    RunTest(test);
od;

#-------------------------------------------------------------------
# Part 2: Known Non-Isomorphic 2-Groups (Negative Tests)
#-------------------------------------------------------------------

Print("=== Part 2: Non-Isomorphic 2-Groups (Negative Tests) ===\n\n");

TEST_NONISOMORPHIC := [
    # Different SmallGroup IDs - clearly distinct
    rec(name := "SmallGroup(512, 1) vs SmallGroup(512, 2)",
        g1 := SmallGroup(512, 1),
        g2 := SmallGroup(512, 2),
        expected := false),

    # Dihedral vs Quaternion (same order, different structure)
    rec(name := "D8 x C64 vs Q8 x C64",
        g1 := DirectProduct(DihedralGroup(8), CyclicGroup(64)),
        g2 := DirectProduct(QuaternionGroup(8), CyclicGroup(64)),
        expected := false),

    # Different abelian groups (discriminated by exponent)
    rec(name := "C512 vs C256 x C2",
        g1 := CyclicGroup(512),
        g2 := DirectProduct(CyclicGroup(256), CyclicGroup(2)),
        expected := false),

    # Same order, same exponent, different structure
    rec(name := "C2^9 vs C4 x C2^7",
        g1 := DirectProduct(CyclicGroup(2), CyclicGroup(2), CyclicGroup(2),
                           CyclicGroup(2), CyclicGroup(2), CyclicGroup(2),
                           CyclicGroup(2), CyclicGroup(2), CyclicGroup(2)),
        g2 := DirectProduct(CyclicGroup(4), CyclicGroup(2), CyclicGroup(2),
                           CyclicGroup(2), CyclicGroup(2), CyclicGroup(2),
                           CyclicGroup(2), CyclicGroup(2)),
        expected := false),

    # Groups with same invariants but different - the hardest case
    rec(name := "SmallGroup(512, 100) vs SmallGroup(512, 101)",
        g1 := SmallGroup(512, 100),
        g2 := SmallGroup(512, 101),
        expected := false),

    # Order 1024 non-isomorphic pairs
    rec(name := "C2 x SmallGroup(512, 100) vs C2 x SmallGroup(512, 101)",
        g1 := DirectProduct(CyclicGroup(2), SmallGroup(512, 100)),
        g2 := DirectProduct(CyclicGroup(2), SmallGroup(512, 101)),
        expected := false),

    rec(name := "C4 x C256 vs C2 x C512",
        g1 := DirectProduct(CyclicGroup(4), CyclicGroup(256)),
        g2 := DirectProduct(CyclicGroup(2), CyclicGroup(512)),
        expected := false),
];;

for test in TEST_NONISOMORPHIC do
    RunTest(test);
od;

#-------------------------------------------------------------------
# Part 3: Edge Cases for ANUPQ
#-------------------------------------------------------------------

Print("=== Part 3: ANUPQ Edge Cases ===\n\n");

# Test with groups that have many generators (potential overflow)
Print("Testing high generator count handling...\n\n");

# Construct order-512 group with many generators via direct product
G_many_gens := DirectProduct(
    DirectProduct(CyclicGroup(2), CyclicGroup(2), CyclicGroup(2), CyclicGroup(2)),
    DirectProduct(CyclicGroup(2), CyclicGroup(2), CyclicGroup(2), CyclicGroup(2)),
    CyclicGroup(2)
);;
Print("Constructed group with ", Length(GeneratorsOfGroup(G_many_gens)), " generators\n");

TEST_EDGE := [
    rec(name := "High generator count - same group",
        g1 := G_many_gens,
        g2 := G_many_gens,
        expected := true),

    rec(name := "High generator count - vs C2^9",
        g1 := G_many_gens,
        g2 := AbelianGroup([2,2,2,2,2,2,2,2,2]),
        expected := true),  # Both are C2^9
];;

for test in TEST_EDGE do
    RunTest(test);
od;

# Test discriminating by exponent
Print("Testing exponent discrimination...\n\n");

# These should be distinguishable by exponent alone
G_exp8 := DirectProduct(CyclicGroup(8), AbelianGroup([2,2,2,2,2,2]));;  # Exponent 8
G_exp4 := DirectProduct(CyclicGroup(4), CyclicGroup(4), AbelianGroup([2,2,2,2,2]));;  # Exponent 4

Print("G_exp8 exponent: ", Exponent(G_exp8), "\n");
Print("G_exp4 exponent: ", Exponent(G_exp4), "\n\n");

TEST_EXPONENT := [
    rec(name := "Different exponents (8 vs 4)",
        g1 := G_exp8,
        g2 := G_exp4,
        expected := false),
];;

for test in TEST_EXPONENT do
    RunTest(test);
od;

#-------------------------------------------------------------------
# Part 4: Order 1024 Stress Tests (No SmallGroups Available)
#-------------------------------------------------------------------

Print("=== Part 4: Order 1024 Stress Tests ===\n\n");

# Construct several distinct order-1024 groups
G1024_1 := DirectProduct(CyclicGroup(1024));;
G1024_2 := DirectProduct(CyclicGroup(512), CyclicGroup(2));;
G1024_3 := DirectProduct(CyclicGroup(256), CyclicGroup(4));;
G1024_4 := DirectProduct(DihedralGroup(8), SmallGroup(128, 1));;
G1024_5 := DirectProduct(QuaternionGroup(8), SmallGroup(128, 1));;

Print("Constructed 5 order-1024 groups for testing\n\n");

TEST_1024 := [
    rec(name := "Order 1024: C1024 vs C512 x C2",
        g1 := G1024_1,
        g2 := G1024_2,
        expected := false),

    rec(name := "Order 1024: C512 x C2 vs C256 x C4",
        g1 := G1024_2,
        g2 := G1024_3,
        expected := false),

    rec(name := "Order 1024: D8 x C128 vs Q8 x C128",
        g1 := G1024_4,
        g2 := G1024_5,
        expected := false),

    # Same group twice
    rec(name := "Order 1024: C512 x C2 = C2 x C512",
        g1 := G1024_2,
        g2 := DirectProduct(CyclicGroup(2), CyclicGroup(512)),
        expected := true),
];;

for test in TEST_1024 do
    RunTest(test);
od;

#-------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------

Print("\n");
Print("============================================================\n");
Print("=== SUMMARY ==============================================\n");
Print("============================================================\n\n");

Print("Total tests: ", PASS_COUNT + FAIL_COUNT + ERROR_COUNT, "\n");
Print("Passed: ", PASS_COUNT, "\n");
Print("Failed: ", FAIL_COUNT, "\n");
Print("Errors: ", ERROR_COUNT, "\n");
Print("\n");

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

# Write results to JSON-like format
PrintTo(Concatenation(BASE_PATH, "anupq_results.txt"),
    "ANUPQ_TEST_RESULTS := rec(\n",
    "  passCount := ", String(PASS_COUNT), ",\n",
    "  failCount := ", String(FAIL_COUNT), ",\n",
    "  errorCount := ", String(ERROR_COUNT), ",\n",
    "  tests := [\n");

for i in [1..Length(RESULTS)] do
    r := RESULTS[i];
    AppendTo(Concatenation(BASE_PATH, "anupq_results.txt"),
        "    rec(name := \"", r.name, "\", status := \"", r.status, "\")");
    if i < Length(RESULTS) then
        AppendTo(Concatenation(BASE_PATH, "anupq_results.txt"), ",");
    fi;
    AppendTo(Concatenation(BASE_PATH, "anupq_results.txt"), "\n");
od;

AppendTo(Concatenation(BASE_PATH, "anupq_results.txt"),
    "  ]\n);\n");

Print("\nResults written to ", BASE_PATH, "anupq_results.txt\n");
Print("\n=== TEST COMPLETE ===\n");

QUIT;
