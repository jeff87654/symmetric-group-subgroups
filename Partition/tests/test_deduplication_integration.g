# Deduplication Integration Test Suite
# Tests the full deduplication workflow with known ground truth
# Can run in either Cygwin or WSL

BASE_PATH := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/Partition/tests/";

Print("\n");
Print("============================================================\n");
Print("=== Deduplication Integration Test Suite ====================\n");
Print("============================================================\n\n");

# Test counters
PASS_COUNT := 0;;
FAIL_COUNT := 0;;
RESULTS := [];;

#-------------------------------------------------------------------
# Helper Functions
#-------------------------------------------------------------------

# Compute sigKey for a group (the invariant signature for bucketing)
ComputeSigKey := function(G)
    local derived, derivedLen, abInv;

    derived := DerivedSubgroup(G);

    # Derived length (positive for solvable, -1 for non-solvable)
    if IsSolvableGroup(G) then
        derivedLen := DerivedLength(G);
    else
        derivedLen := -1;
    fi;

    abInv := ShallowCopy(AbelianInvariants(G / derived));
    Sort(abInv);

    return [
        Size(G),                    # order
        Size(derived),              # derived_size
        NrConjugacyClasses(G),      # conjugacy_classes
        derivedLen,                 # derived_length (or -1)
        abInv                       # abelian_invariants of G/G'
    ];
end;

# Deduplicate a list of groups using IsomorphismGroups
DeduplicateBucket := function(groups)
    local unique, i, j, isNew;

    if Length(groups) <= 1 then return groups; fi;

    unique := [groups[1]];
    for i in [2..Length(groups)] do
        isNew := true;
        for j in [1..Length(unique)] do
            if IsomorphismGroups(groups[i], unique[j]) <> fail then
                isNew := false;
                break;
            fi;
        od;
        if isNew then Add(unique, groups[i]); fi;
    od;

    return unique;
end;

# Run a bucket test
RunBucketTest := function(testRec)
    local reps, status, resultRec;

    Print("Testing: ", testRec.name, "\n");
    Print("  Input: ", Length(testRec.groups), " groups\n");
    Print("  Expected reps: ", testRec.expectedReps, "\n");

    reps := DeduplicateBucket(testRec.groups);

    if Length(reps) = testRec.expectedReps then
        status := "PASS";
        PASS_COUNT := PASS_COUNT + 1;
        Print("  Actual reps: ", Length(reps), " - PASS\n");
    else
        status := "FAIL";
        FAIL_COUNT := FAIL_COUNT + 1;
        Print("  Actual reps: ", Length(reps), " - FAIL\n");
    fi;
    Print("\n");

    resultRec := rec(
        name := testRec.name,
        expected := testRec.expectedReps,
        actual := Length(reps),
        status := status
    );
    Add(RESULTS, resultRec);

    return reps;
end;

#-------------------------------------------------------------------
# Part 1: Basic Bucket Deduplication
#-------------------------------------------------------------------

Print("=== Part 1: Basic Bucket Deduplication ===\n\n");

# Test with SmallGroups where we know the ground truth via IdGroup
TEST_BUCKETS := [
    rec(name := "All same group (5 copies)",
        groups := List([1..5], i -> SmallGroup(24, 12)),
        expectedReps := 1),

    rec(name := "All distinct (order 8)",
        groups := [SmallGroup(8, 1), SmallGroup(8, 2), SmallGroup(8, 3),
                   SmallGroup(8, 4), SmallGroup(8, 5)],
        expectedReps := 5),

    rec(name := "3 isomorphism classes",
        groups := [
            SmallGroup(24, 12), SmallGroup(24, 12),  # Class A (2 copies)
            SmallGroup(24, 3), SmallGroup(24, 3), SmallGroup(24, 3),  # Class B (3 copies)
            SmallGroup(24, 5)  # Class C (1 copy)
        ],
        expectedReps := 3),

    rec(name := "Single group",
        groups := [SymmetricGroup(4)],
        expectedReps := 1),

    rec(name := "Empty bucket",
        groups := [],
        expectedReps := 0),
];;

for test in TEST_BUCKETS do
    if Length(test.groups) = 0 then
        # Special case for empty
        if Length(DeduplicateBucket(test.groups)) = 0 then
            Print("Testing: ", test.name, " - PASS\n\n");
            PASS_COUNT := PASS_COUNT + 1;
            Add(RESULTS, rec(name := test.name, expected := 0, actual := 0, status := "PASS"));
        fi;
    else
        RunBucketTest(test);
    fi;
od;

#-------------------------------------------------------------------
# Part 2: Cross-Deduplication Simulation
#-------------------------------------------------------------------

Print("=== Part 2: Cross-Deduplication Simulation ===\n\n");

# Simulate S(n) vs S(n-1) cross-deduplication
CrossDeduplicate := function(s_n_groups, s_n_minus_1_groups)
    local newGroups, g, j, isNew;

    newGroups := [];
    for g in s_n_groups do
        isNew := true;
        for j in [1..Length(s_n_minus_1_groups)] do
            if IsomorphismGroups(g, s_n_minus_1_groups[j]) <> fail then
                isNew := false;
                break;
            fi;
        od;
        if isNew then Add(newGroups, g); fi;
    od;

    return newGroups;
end;

TEST_CROSS := [
    rec(name := "New group not in S(n-1)",
        s_n_minus_1 := [SmallGroup(24, 12), SmallGroup(24, 3)],
        s_n := [SmallGroup(24, 5)],  # Different from both
        expectedNew := 1),

    rec(name := "Duplicate of S(n-1) group",
        s_n_minus_1 := [SmallGroup(24, 12)],
        s_n := [SmallGroup(24, 12)],  # Same!
        expectedNew := 0),

    rec(name := "Mixed: some new, some duplicates",
        s_n_minus_1 := [SmallGroup(24, 12), SmallGroup(24, 3)],
        s_n := [SmallGroup(24, 12), SmallGroup(24, 5), SmallGroup(24, 3)],
        expectedNew := 1),  # Only SmallGroup(24, 5) is new

    rec(name := "All new",
        s_n_minus_1 := [SmallGroup(24, 12)],
        s_n := [SmallGroup(24, 3), SmallGroup(24, 5), SmallGroup(24, 7)],
        expectedNew := 3),
];;

for test in TEST_CROSS do
    Print("Testing: ", test.name, "\n");
    Print("  S(n-1) size: ", Length(test.s_n_minus_1), "\n");
    Print("  S(n) size: ", Length(test.s_n), "\n");
    Print("  Expected new: ", test.expectedNew, "\n");

    newGroups := CrossDeduplicate(test.s_n, test.s_n_minus_1);

    if Length(newGroups) = test.expectedNew then
        Print("  Actual new: ", Length(newGroups), " - PASS\n\n");
        PASS_COUNT := PASS_COUNT + 1;
        Add(RESULTS, rec(name := test.name, expected := test.expectedNew,
            actual := Length(newGroups), status := "PASS"));
    else
        Print("  Actual new: ", Length(newGroups), " - FAIL\n\n");
        FAIL_COUNT := FAIL_COUNT + 1;
        Add(RESULTS, rec(name := test.name, expected := test.expectedNew,
            actual := Length(newGroups), status := "FAIL"));
    fi;
od;

#-------------------------------------------------------------------
# Part 3: SigKey Consistency Test
#-------------------------------------------------------------------

Print("=== Part 3: SigKey Consistency Test ===\n\n");

Print("Verifying that isomorphic groups have identical sigKeys...\n\n");

# Isomorphic groups MUST have the same sigKey
sigkey_tests := [
    [SmallGroup(24, 12), SmallGroup(24, 12), true],
    [SymmetricGroup(4), SmallGroup(24, 12), true],  # S4 = SmallGroup(24,12)
    [SmallGroup(24, 12), SmallGroup(24, 3), false],  # Different groups
    [DihedralGroup(8), SmallGroup(8, 3), true],  # D8 = SmallGroup(8,3)
];;

sigkey_pass := 0;;
sigkey_fail := 0;;

for test in sigkey_tests do
    g1 := test[1];
    g2 := test[2];
    shouldMatch := test[3];

    sigKey1 := ComputeSigKey(g1);
    sigKey2 := ComputeSigKey(g2);

    if (sigKey1 = sigKey2) = shouldMatch then
        sigkey_pass := sigkey_pass + 1;
        Print("  ", StructureDescription(g1), " vs ", StructureDescription(g2), ": ");
        if shouldMatch then Print("match expected - PASS\n");
        else Print("differ expected - PASS\n"); fi;
    else
        sigkey_fail := sigkey_fail + 1;
        Print("  ", StructureDescription(g1), " vs ", StructureDescription(g2), ": FAIL\n");
        Print("    sigKey1 = ", sigKey1, "\n");
        Print("    sigKey2 = ", sigKey2, "\n");
    fi;
od;

Print("\nSigKey tests: ", sigkey_pass, " passed, ", sigkey_fail, " failed\n\n");
PASS_COUNT := PASS_COUNT + sigkey_pass;
FAIL_COUNT := FAIL_COUNT + sigkey_fail;

#-------------------------------------------------------------------
# Part 4: Invariant Filtering Test
#-------------------------------------------------------------------

Print("=== Part 4: Invariant Filtering Test ===\n\n");

Print("Verifying that non-isomorphic groups can be distinguished by invariants...\n\n");

# Compute extended fingerprint
ComputeFingerprint := function(G)
    local derived, frattini;
    derived := DerivedSubgroup(G);
    frattini := FrattiniSubgroup(G);

    return rec(
        order := Size(G),
        derivedSize := Size(derived),
        centerSize := Size(Center(G)),
        conjugacyClasses := NrConjugacyClasses(G),
        exponent := Exponent(G),
        frattiniSize := Size(frattini),
        derivedLength := DerivedLength(G),
        abelianInvariants := AbelianInvariants(G/derived)
    );
end;

FingerprintsMatch := function(f1, f2)
    return f1.order = f2.order and
           f1.derivedSize = f2.derivedSize and
           f1.centerSize = f2.centerSize and
           f1.conjugacyClasses = f2.conjugacyClasses and
           f1.exponent = f2.exponent and
           f1.frattiniSize = f2.frattiniSize and
           f1.derivedLength = f2.derivedLength and
           f1.abelianInvariants = f2.abelianInvariants;
end;

# Test pairs: non-isomorphic groups that might be confused
invariant_tests := [
    # D8 vs Q8: same order, different structure
    rec(g1 := DihedralGroup(8), g2 := QuaternionGroup(8),
        desc := "D8 vs Q8"),

    # C4 vs C2xC2: same order, different exponent
    rec(g1 := CyclicGroup(4), g2 := DirectProduct(CyclicGroup(2), CyclicGroup(2)),
        desc := "C4 vs C2xC2"),

    # Two different SmallGroups of order 24
    rec(g1 := SmallGroup(24, 3), g2 := SmallGroup(24, 5),
        desc := "SmallGroup(24,3) vs SmallGroup(24,5)"),
];;

inv_distinguished := 0;;
inv_same := 0;;

for test in invariant_tests do
    f1 := ComputeFingerprint(test.g1);
    f2 := ComputeFingerprint(test.g2);

    Print("  ", test.desc, ":\n");
    if not FingerprintsMatch(f1, f2) then
        inv_distinguished := inv_distinguished + 1;
        Print("    Distinguished by fingerprint - GOOD\n");

        # Show which invariant differs
        if f1.exponent <> f2.exponent then Print("      (differs in exponent)\n"); fi;
        if f1.centerSize <> f2.centerSize then Print("      (differs in center size)\n"); fi;
        if f1.derivedSize <> f2.derivedSize then Print("      (differs in derived size)\n"); fi;
        if f1.conjugacyClasses <> f2.conjugacyClasses then Print("      (differs in conjugacy classes)\n"); fi;
        if f1.frattiniSize <> f2.frattiniSize then Print("      (differs in Frattini size)\n"); fi;
    else
        inv_same := inv_same + 1;
        Print("    Same fingerprint - need IsomorphismGroups\n");
    fi;
od;

Print("\nInvariant filtering: ", inv_distinguished, " pairs distinguished, ",
      inv_same, " pairs need full comparison\n\n");

#-------------------------------------------------------------------
# Part 5: Bucket with Order Profile
#-------------------------------------------------------------------

Print("=== Part 5: Order Profile Test ===\n\n");

# Order profile = histogram of element orders
ComputeOrderProfile := function(G)
    local profile, e, ord;
    profile := rec();
    for e in G do
        ord := Order(e);
        if IsBound(profile.(String(ord))) then
            profile.(String(ord)) := profile.(String(ord)) + 1;
        else
            profile.(String(ord)) := 1;
        fi;
    od;
    return profile;
end;

# Test: groups that are hard to distinguish without order profile
Print("Testing order profile discrimination...\n\n");

# C4 x C2 vs C8: both order 8, need order profile to distinguish quickly
G_c4c2 := DirectProduct(CyclicGroup(4), CyclicGroup(2));;
G_c8 := CyclicGroup(8);;

profile1 := ComputeOrderProfile(G_c4c2);;
profile2 := ComputeOrderProfile(G_c8);;

Print("C4 x C2 order profile: ", profile1, "\n");
Print("C8 order profile: ", profile2, "\n");

if profile1 <> profile2 then
    Print("Distinguished by order profile - PASS\n\n");
    PASS_COUNT := PASS_COUNT + 1;
    Add(RESULTS, rec(name := "Order profile discrimination",
        expected := "different", actual := "different", status := "PASS"));
else
    Print("Same order profile - FAIL\n\n");
    FAIL_COUNT := FAIL_COUNT + 1;
    Add(RESULTS, rec(name := "Order profile discrimination",
        expected := "different", actual := "same", status := "FAIL"));
fi;

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
PrintTo(Concatenation(BASE_PATH, "integration_results.txt"),
    "INTEGRATION_TEST_RESULTS := rec(\n",
    "  passCount := ", String(PASS_COUNT), ",\n",
    "  failCount := ", String(FAIL_COUNT), ",\n",
    "  tests := [\n");

for i in [1..Length(RESULTS)] do
    r := RESULTS[i];
    AppendTo(Concatenation(BASE_PATH, "integration_results.txt"),
        "    rec(name := \"", r.name, "\", status := \"", r.status, "\")");
    if i < Length(RESULTS) then
        AppendTo(Concatenation(BASE_PATH, "integration_results.txt"), ",");
    fi;
    AppendTo(Concatenation(BASE_PATH, "integration_results.txt"), "\n");
od;

AppendTo(Concatenation(BASE_PATH, "integration_results.txt"),
    "  ]\n);\n");

Print("\nResults written to ", BASE_PATH, "integration_results.txt\n");
Print("\n=== TEST COMPLETE ===\n");

QUIT;
