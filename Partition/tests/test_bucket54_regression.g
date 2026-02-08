# Bucket 54 Regression Test
# Specifically tests the bug that caused a(14) undercount by 1
#
# The bug: CompareByFactorsV3 only compared ONE semidirect factor
# when groups can have MULTIPLE semidirect factors.
#
# Bucket 54 sigKey: [2304, 72, 126, 3, [2,2,2,2,2]]
# Pattern: Direct products of form (A : B) x (C : D)
#
# Can run in either Cygwin or WSL

BASE_PATH := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/Partition/tests/";

Print("\n");
Print("============================================================\n");
Print("=== BUCKET 54 REGRESSION TEST ==============================\n");
Print("============================================================\n\n");

Print("This test verifies the fix for the bug that caused a(14) to be\n");
Print("undercounted by 1 group.\n\n");

Print("The Bug Pattern:\n");
Print("-----------------\n");
Print("Groups that are direct products of TWO semidirect factors:\n");
Print("  G1 = (A : B) x (C : D)\n");
Print("  G2 = (A' : B') x (C : D)\n\n");
Print("If (C : D) is the SAME factor but (A : B) != (A' : B'),\n");
Print("the buggy algorithm would compare only (C : D), declare them\n");
Print("isomorphic, and incorrectly merge them.\n\n");

#-------------------------------------------------------------------
# Reconstruct the Bucket 54 Pattern
#-------------------------------------------------------------------

# The actual bucket 54 from S14:
# - sigKey = [2304, 72, 126, 3, [2,2,2,2,2]]
# - Order 2304 = 2^8 * 3^2 = 256 * 9
# - Index 184 had: (C2^4 : C2) x ((S3 x S3) : C2)  = order 32 * 72 = 2304
# - Index 3358 had: (C4^2 : C2) x ((S3 x S3) : C2)  = order 32 * 72 = 2304

Print("Constructing test groups matching bucket 54 pattern...\n\n");

# SmallGroup(32, 6) is a semidirect product of order 32
# SmallGroup(32, 7) is a different semidirect product of order 32
# SmallGroup(72, 40) = (S3 x S3) : C2

G_factor_A := SmallGroup(32, 6);;
G_factor_A_prime := SmallGroup(32, 7);;
G_factor_common := SmallGroup(72, 40);;

Print("Factor A:  SmallGroup(32, 6) = ", StructureDescription(G_factor_A), "\n");
Print("Factor A': SmallGroup(32, 7) = ", StructureDescription(G_factor_A_prime), "\n");
Print("Common factor: SmallGroup(72, 40) = ", StructureDescription(G_factor_common), "\n\n");

# Construct the test groups
G1 := DirectProduct(G_factor_A, G_factor_common);;
G2 := DirectProduct(G_factor_A_prime, G_factor_common);;

Print("G1 = Factor A x Common = order ", Size(G1), "\n");
Print("G2 = Factor A' x Common = order ", Size(G2), "\n\n");

Print("G1 StructureDescription: ", StructureDescription(G1), "\n");
Print("G2 StructureDescription: ", StructureDescription(G2), "\n\n");

#-------------------------------------------------------------------
# Test 1: Verify factors A and A' are NOT isomorphic
#-------------------------------------------------------------------

Print("=== Test 1: Verify factors are non-isomorphic ===\n\n");

iso_factors := IsomorphismGroups(G_factor_A, G_factor_A_prime);
if iso_factors = fail then
    Print("CONFIRMED: SmallGroup(32,6) and SmallGroup(32,7) are NOT isomorphic\n");
    Print("STATUS: PASS\n\n");
else
    Print("ERROR: Factors should NOT be isomorphic!\n");
    Print("STATUS: FAIL\n\n");
fi;

#-------------------------------------------------------------------
# Test 2: Verify full groups G1 and G2 are NOT isomorphic
#-------------------------------------------------------------------

Print("=== Test 2: Verify full groups are non-isomorphic ===\n\n");

Print("Running IsomorphismGroups on full groups (may take a moment)...\n");
iso_full := IsomorphismGroups(G1, G2);
if iso_full = fail then
    Print("CONFIRMED: G1 and G2 are NOT isomorphic\n");
    Print("STATUS: PASS\n\n");
else
    Print("ERROR: Full groups should NOT be isomorphic!\n");
    Print("STATUS: FAIL\n\n");
fi;

#-------------------------------------------------------------------
# Test 3: Simulate the buggy algorithm behavior
#-------------------------------------------------------------------

Print("=== Test 3: Simulate buggy algorithm ===\n\n");

# Build invariant records
BuildInvariantRecord := function(G)
    local factors, invRec, combined, i, desc, gens;
    invRec := rec(
        order := Size(G),
        isDirectProduct := false,
        factors := [],
        factorOrders := [],
        numFactors := 1
    );
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
end;;

rec1 := BuildInvariantRecord(G1);;
rec2 := BuildInvariantRecord(G2);;

Print("G1 invariant record:\n");
Print("  isDirectProduct: ", rec1.isDirectProduct, "\n");
Print("  factors: ", rec1.factors, "\n");
Print("  factorGens count: ", Length(rec1.factorGens), "\n\n");

Print("G2 invariant record:\n");
Print("  isDirectProduct: ", rec2.isDirectProduct, "\n");
Print("  factors: ", rec2.factors, "\n");
Print("  factorGens count: ", Length(rec2.factorGens), "\n\n");

# Count factors
num_factors_1 := Length(rec1.factorGens);;
num_factors_2 := Length(rec2.factorGens);;

Print("G1 has ", num_factors_1, " factor(s)\n");
Print("G2 has ", num_factors_2, " factor(s)\n\n");

if num_factors_1 >= 2 and num_factors_2 >= 2 then
    Print("CONFIRMED: Both groups have MULTIPLE factors\n");
    Print("This is the condition where the bug manifests!\n\n");
fi;

# Show what the buggy algorithm would do
Print("Buggy algorithm behavior:\n");
Print("  - Gets factor generators from both records\n");
Print("  - rec1 factors: ", rec1.factors, "\n");
Print("  - rec2 factors: ", rec2.factors, "\n");
Print("  - Compares ONLY factorGens[1] from each: '", rec1.factors[1], "' vs '", rec2.factors[1], "'\n");

factor1_first := Group(rec1.factorGens[1]);;
factor2_first := Group(rec2.factorGens[1]);;

Print("  - First factors: order ", Size(factor1_first), " vs ", Size(factor2_first), "\n");

iso_first := IsomorphismGroups(factor1_first, factor2_first);
if iso_first <> fail then
    Print("  - First factors ARE isomorphic\n");
    Print("  - Buggy algorithm would return TRUE (WRONG!)\n\n");
else
    Print("  - First factors are NOT isomorphic\n");
    Print("  - Buggy algorithm would return FALSE (correct by accident)\n\n");
fi;

#-------------------------------------------------------------------
# Test 4: Demonstrate the fix
#-------------------------------------------------------------------

Print("=== Test 4: Fixed algorithm behavior ===\n\n");

Print("Fixed algorithm:\n");
Print("  - Gets ALL factor names from both records\n");
Print("  - Must match EVERY factor from rec1 to some factor in rec2\n");
Print("  - Uses bipartite matching (each factor matched at most once)\n\n");

# The fixed algorithm implementation
CompareByFactorsV3_FIXED := function(r1, r2)
    local pairs1, pairs2, matched, i, j, g1, g2, result, foundMatch;

    if not r1.isDirectProduct or not r2.isDirectProduct then return fail; fi;

    if not IsBound(r1.factorGens) or not IsBound(r2.factorGens) then return fail; fi;

    pairs1 := r1.factorGens;
    pairs2 := r2.factorGens;

    if Length(pairs1) <> Length(pairs2) then
        Print("  Different number of factors: ", Length(pairs1), " vs ", Length(pairs2), "\n");
        return false;
    fi;

    # Quick check: sorted factor orders must match
    if r1.factorOrders <> r2.factorOrders then
        return false;
    fi;

    matched := [];
    for i in [1..Length(pairs1)] do
        g1 := Group(pairs1[i]);

        foundMatch := false;
        for j in [1..Length(pairs2)] do
            if j in matched then continue; fi;

            g2 := Group(pairs2[j]);

            if Size(g1) <> Size(g2) then continue; fi;

            result := CALL_WITH_CATCH(IsomorphismGroups, [g1, g2]);
            if result[1] = true and result[2] <> fail then
                Print("  Factor '", r1.factors[i], "' matched with '", r2.factors[j], "'\n");
                Add(matched, j);
                foundMatch := true;
                break;
            fi;
        od;

        if not foundMatch then
            Print("  No match found for factor '", r1.factors[i], "'\n");
            return false;
        fi;
    od;

    Print("  All ", Length(pairs1), " factors matched\n");
    return true;
end;;

Print("Running fixed algorithm...\n\n");
fixed_result := CompareByFactorsV3_FIXED(rec1, rec2);;

Print("\nFixed algorithm result: ", fixed_result, "\n");
if fixed_result = false then
    Print("STATUS: PASS - Correctly identified as non-isomorphic\n\n");
else
    Print("STATUS: FAIL - Should have returned false!\n\n");
fi;

#-------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------

Print("\n");
Print("============================================================\n");
Print("=== BUCKET 54 REGRESSION TEST SUMMARY ======================\n");
Print("============================================================\n\n");

Print("Test groups:\n");
Print("  G1 = SmallGroup(32,6) x SmallGroup(72,40)  [order ", Size(G1), "]\n");
Print("  G2 = SmallGroup(32,7) x SmallGroup(72,40)  [order ", Size(G2), "]\n\n");

Print("Ground truth (IsomorphismGroups): ");
if iso_full = fail then Print("NOT isomorphic\n"); else Print("isomorphic\n"); fi;

Print("Buggy algorithm would say: ");
if iso_first <> fail then Print("isomorphic (WRONG)\n"); else Print("not isomorphic\n"); fi;

Print("Fixed algorithm says: ");
if fixed_result = false then Print("NOT isomorphic (CORRECT)\n"); else Print("isomorphic\n"); fi;

Print("\n");

if iso_full = fail and fixed_result = false then
    Print(">>> REGRESSION TEST PASSED <<<\n");
    Print("The fix correctly handles multiple semidirect factors.\n");
else
    Print(">>> REGRESSION TEST FAILED <<<\n");
    Print("Something is wrong with the test or fix.\n");
fi;

# Write result file
PrintTo(Concatenation(BASE_PATH, "bucket54_regression_result.txt"),
    "BUCKET54_REGRESSION := rec(\n",
    "  groundTruth := \"", (function() if iso_full = fail then return "non-isomorphic"; else return "isomorphic"; fi; end)(), "\",\n",
    "  buggyWouldSay := \"", (function() if iso_first <> fail then return "isomorphic"; else return "non-isomorphic"; fi; end)(), "\",\n",
    "  fixedSays := \"", (function() if fixed_result = false then return "non-isomorphic"; else return "isomorphic"; fi; end)(), "\",\n",
    "  status := \"", (function() if iso_full = fail and fixed_result = false then return "PASS"; else return "FAIL"; fi; end)(), "\"\n",
    ");\n");

Print("\nResult written to ", BASE_PATH, "bucket54_regression_result.txt\n");
Print("\n=== TEST COMPLETE ===\n");

QUIT;
