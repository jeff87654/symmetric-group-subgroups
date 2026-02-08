# Ground Truth Test Cases for Deduplication Verification
# =========================================================
#
# These are known test cases with verified ground truth.
# Any correct deduplication implementation MUST pass all of these.
#
# Usage: Load this file, then call RunGroundTruthTests()

# Ground truth pairs: [group1, group2, expected_isomorphic]
# - true: groups ARE isomorphic
# - false: groups are NOT isomorphic

GROUND_TRUTH_CASES := rec(

    # ============================================================
    # CATEGORY 1: Pure Direct Products
    # ============================================================
    pure_direct := [
        rec(
            name := "C2 x S4 reordered",
            g1 := DirectProduct(CyclicGroup(2), SymmetricGroup(4)),
            g2 := DirectProduct(SymmetricGroup(4), CyclicGroup(2)),
            expected := true,
            category := "pure_direct"
        ),
        rec(
            name := "C2 x C2 x C4 reordered",
            g1 := DirectProduct(CyclicGroup(2), CyclicGroup(2), CyclicGroup(4)),
            g2 := DirectProduct(CyclicGroup(4), CyclicGroup(2), CyclicGroup(2)),
            expected := true,
            category := "pure_direct"
        ),
        rec(
            name := "C4 vs C2xC2 - different structure",
            g1 := CyclicGroup(4),
            g2 := DirectProduct(CyclicGroup(2), CyclicGroup(2)),
            expected := false,
            category := "pure_direct"
        )
    ],

    # ============================================================
    # CATEGORY 2: Single Semidirect Factor
    # ============================================================
    single_semi := [
        rec(
            name := "D8 x C3 same",
            g1 := DirectProduct(DihedralGroup(8), CyclicGroup(3)),
            g2 := DirectProduct(DihedralGroup(8), CyclicGroup(3)),
            expected := true,
            category := "single_semi"
        ),
        rec(
            name := "D8 vs Q8 - different semidirect",
            g1 := DirectProduct(DihedralGroup(8), CyclicGroup(3)),
            g2 := DirectProduct(QuaternionGroup(8), CyclicGroup(3)),
            expected := false,
            category := "single_semi"
        )
    ],

    # ============================================================
    # CATEGORY 3: Multiple Semidirect Factors (CRITICAL - Bug Case)
    # ============================================================
    multi_semi := [
        rec(
            name := "BUCKET54_CRITICAL: Two semi factors, one differs",
            g1 := DirectProduct(SmallGroup(32, 6), SmallGroup(72, 40)),
            g2 := DirectProduct(SmallGroup(32, 7), SmallGroup(72, 40)),
            expected := false,
            category := "multi_semi_critical",
            notes := "This is the exact bug pattern that caused a(14) undercount"
        ),
        rec(
            name := "Two semi factors, both same",
            g1 := DirectProduct(SmallGroup(32, 6), SmallGroup(72, 40)),
            g2 := DirectProduct(SmallGroup(32, 6), SmallGroup(72, 40)),
            expected := true,
            category := "multi_semi"
        ),
        rec(
            name := "Two semi factors, both differ",
            g1 := DirectProduct(SmallGroup(32, 6), SmallGroup(72, 40)),
            g2 := DirectProduct(SmallGroup(32, 7), SmallGroup(72, 41)),
            expected := false,
            category := "multi_semi"
        )
    ],

    # ============================================================
    # CATEGORY 4: 2-Groups (for ANUPQ testing)
    # ============================================================
    two_groups := [
        rec(
            name := "D8 vs Q8",
            g1 := DihedralGroup(8),
            g2 := QuaternionGroup(8),
            expected := false,
            category := "2group"
        ),
        rec(
            name := "C4 x C4 vs C2 x C8",
            g1 := DirectProduct(CyclicGroup(4), CyclicGroup(4)),
            g2 := DirectProduct(CyclicGroup(2), CyclicGroup(8)),
            expected := false,
            category := "2group"
        ),
        rec(
            name := "SmallGroup(32,6) vs SmallGroup(32,7)",
            g1 := SmallGroup(32, 6),
            g2 := SmallGroup(32, 7),
            expected := false,
            category := "2group"
        )
    ],

    # ============================================================
    # CATEGORY 5: Non-solvable groups
    # ============================================================
    non_solvable := [
        rec(
            name := "A5 x C2 same",
            g1 := DirectProduct(AlternatingGroup(5), CyclicGroup(2)),
            g2 := DirectProduct(AlternatingGroup(5), CyclicGroup(2)),
            expected := true,
            category := "non_solvable"
        ),
        rec(
            name := "A5 vs S5",
            g1 := AlternatingGroup(5),
            g2 := SymmetricGroup(5),
            expected := false,
            category := "non_solvable"
        )
    ],

    # ============================================================
    # CATEGORY 6: Edge Cases
    # ============================================================
    edge_cases := [
        rec(
            name := "Trivial group",
            g1 := TrivialGroup(),
            g2 := TrivialGroup(),
            expected := true,
            category := "edge"
        ),
        rec(
            name := "Same group object",
            g1 := SymmetricGroup(4),
            g2 := SymmetricGroup(4),
            expected := true,
            category := "edge"
        )
    ]
);

# ============================================================
# Test Runner
# ============================================================

RunGroundTruthTests := function()
    local categories, cat, cases, testCase, result, passed, failed,
          totalPassed, totalFailed, categoryResults;

    Print("\n");
    Print("============================================================\n");
    Print("GROUND TRUTH TEST SUITE\n");
    Print("============================================================\n\n");

    categories := RecNames(GROUND_TRUTH_CASES);
    totalPassed := 0;
    totalFailed := 0;
    categoryResults := rec();

    for cat in categories do
        cases := GROUND_TRUTH_CASES.(cat);
        passed := 0;
        failed := 0;

        Print("--- ", cat, " ---\n");

        for testCase in cases do
            # Run the actual isomorphism test
            if testCase.expected then
                result := IsomorphismGroups(testCase.g1, testCase.g2) <> fail;
            else
                result := IsomorphismGroups(testCase.g1, testCase.g2) = fail;
            fi;

            if result then
                Print("  PASS: ", testCase.name, "\n");
                passed := passed + 1;
            else
                Print("  FAIL: ", testCase.name, "\n");
                Print("    Expected: ", testCase.expected, "\n");
                Print("    Got: ", not testCase.expected, "\n");
                if IsBound(testCase.notes) then
                    Print("    Notes: ", testCase.notes, "\n");
                fi;
                failed := failed + 1;
            fi;
        od;

        categoryResults.(cat) := rec(passed := passed, failed := failed);
        totalPassed := totalPassed + passed;
        totalFailed := totalFailed + failed;
        Print("\n");
    od;

    Print("============================================================\n");
    Print("SUMMARY\n");
    Print("============================================================\n");
    Print("Total: ", totalPassed + totalFailed, " tests\n");
    Print("Passed: ", totalPassed, "\n");
    Print("Failed: ", totalFailed, "\n");
    Print("\n");

    if totalFailed = 0 then
        Print(">>> ALL GROUND TRUTH TESTS PASSED <<<\n");
        return true;
    else
        Print(">>> SOME TESTS FAILED - DO NOT PROCEED <<<\n");
        return false;
    fi;
end;

# ============================================================
# Function to test a specific comparison function
# ============================================================

TestComparisonFunction := function(compareFunc, funcName)
    local cases, testCase, result, passed, failed, expected;

    Print("\n");
    Print("============================================================\n");
    Print("Testing: ", funcName, "\n");
    Print("============================================================\n\n");

    # Only test multi_semi cases - the critical bug pattern
    cases := GROUND_TRUTH_CASES.multi_semi;
    passed := 0;
    failed := 0;

    for testCase in cases do
        # Build fake invariant records for the comparison function
        result := compareFunc(testCase.g1, testCase.g2);

        if result = fail then
            Print("  SKIP: ", testCase.name, " (function returned fail)\n");
        elif result = testCase.expected then
            Print("  PASS: ", testCase.name, "\n");
            passed := passed + 1;
        else
            Print("  FAIL: ", testCase.name, "\n");
            Print("    Expected: ", testCase.expected, "\n");
            Print("    Got: ", result, "\n");
            failed := failed + 1;
        fi;
    od;

    Print("\nResult: ", passed, " passed, ", failed, " failed\n");
    return failed = 0;
end;

Print("Ground truth test cases loaded.\n");
Print("Run: RunGroundTruthTests() to execute all tests\n");
Print("Run: TestComparisonFunction(func, name) to test a specific function\n");
