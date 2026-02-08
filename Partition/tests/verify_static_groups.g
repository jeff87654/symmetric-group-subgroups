# Verify that test_groups_static.g loads correctly
Read("/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/Partition/tests/test_groups_static.g");

Print("\n========================================\n");
Print("Verification of test_groups_static.g\n");
Print("========================================\n\n");

# Check that all groups are valid
allValid := true;
for i in [1..Length(TEST_GROUPS_STATIC)] do
    entry := TEST_GROUPS_STATIC[i];
    G := entry.group;
    if not IsGroup(G) then
        Print("ERROR: Group ", i, " (", entry.name, ") is not a valid group\n");
        allValid := false;
        continue;
    fi;
    if Size(G) <> entry.order then
        Print("ERROR: Group ", i, " (", entry.name, ") order mismatch: ", Size(G), " vs ", entry.order, "\n");
        allValid := false;
    fi;
od;

if allValid then
    Print("All ", Length(TEST_GROUPS_STATIC), " groups loaded successfully!\n\n");
fi;

# Test a few isomorphisms
Print("Testing expected isomorphic pairs:\n");
for pair in EXPECTED_ISOMORPHIC_PAIRS do
    G1 := TEST_GROUPS_STATIC[pair[1]].group;
    G2 := TEST_GROUPS_STATIC[pair[2]].group;
    iso := IsomorphismGroups(G1, G2) <> fail;
    if iso then
        Print("  [", pair[1], ",", pair[2], "]: PASS (isomorphic as expected)\n");
    else
        Print("  [", pair[1], ",", pair[2], "]: FAIL (should be isomorphic)\n");
    fi;
od;

Print("\nTesting expected non-isomorphic pairs:\n");
for pair in EXPECTED_NONISOMORPHIC_PAIRS do
    G1 := TEST_GROUPS_STATIC[pair[1]].group;
    G2 := TEST_GROUPS_STATIC[pair[2]].group;
    iso := IsomorphismGroups(G1, G2) <> fail;
    if not iso then
        Print("  [", pair[1], ",", pair[2], "]: PASS (non-isomorphic as expected)\n");
    else
        Print("  [", pair[1], ",", pair[2], "]: FAIL (should not be isomorphic)\n");
    fi;
od;

Print("\n========================================\n");
Print("Verification complete\n");
Print("========================================\n");
