# Test Groups Source File for Factor Comparison Test Suite
# Format matches combined_s13_s14_original.g for cross-deduplication compatibility
#
# These groups are used to test:
#   - Concern 1: Pure factor mismatch with semidirect factors
#   - Concern 2: Greedy matching robustness
#   - Bucket 54 regression (multiple semidirect factors)
#
# Run this script to generate test_groups_generated.g with full invariants
#
# Usage: gap -q test_groups_source.g

Print("=== Generating Test Groups Source File ===\n\n");

# Output file path (Cygwin format - change to /mnt/c/... for WSL)
OUTPUT_PATH := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/Partition/tests/test_groups_generated.g";

#-------------------------------------------------------------------
# Helper Functions
#-------------------------------------------------------------------

# Compute element order histogram
ComputeHistogram := function(G)
    local orders, hist, o, count;
    orders := List(Elements(G), Order);
    hist := Collected(orders);
    Sort(hist, function(a, b) return a[1] < b[1]; end);
    return hist;
end;

# Compute sigKey: [order, derived_size, conjugacy_classes, derived_length, abelian_invariants]
ComputeSigKey := function(G)
    local order, derivedSize, conjClasses, derivedLen, abelInv;
    order := Size(G);
    derivedSize := Size(DerivedSubgroup(G));
    conjClasses := NrConjugacyClasses(G);
    if IsSolvableGroup(G) then
        derivedLen := DerivedLength(G);
    else
        derivedLen := -1;
    fi;
    abelInv := ShallowCopy(AbelianInvariants(G / DerivedSubgroup(G)));
    Sort(abelInv);
    return [order, derivedSize, conjClasses, derivedLen, abelInv];
end;

# Build full invariant record for a group
BuildTestRecord := function(G, source, index, testName)
    local rec_, factors, hist, combined, i, desc, gens;

    rec_ := rec(
        source := source,
        originalIndex := index,
        combinedIndex := index,
        index := index,
        testName := testName,
        sigKey := ComputeSigKey(G),
        order := Size(G),
        isDirectProduct := false,
        factors := [],
        factorOrders := [],
        numFactors := 1,
        histogram := [],
        maxOrder := 1,
        numOrders := 0
    );

    # Compute direct factors
    factors := DirectFactorsOfGroup(G);
    if Length(factors) > 1 then
        rec_.isDirectProduct := true;
        rec_.numFactors := Length(factors);

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

        rec_.factorOrders := List(combined, x -> x[1]);
        rec_.factors := List(combined, x -> x[2]);
        rec_.factorGens := List(combined, x -> x[3]);
    fi;

    # Compute histogram (only for small groups to avoid memory issues)
    if Size(G) <= 10000 then
        hist := ComputeHistogram(G);
        rec_.histogram := hist;
        rec_.maxOrder := Maximum(List(hist, x -> x[1]));
        rec_.numOrders := Length(hist);
    else
        rec_.histogram := [];
        rec_.maxOrder := Exponent(G);
        rec_.numOrders := 0;
    fi;

    return rec_;
end;

# Format record as GAP code string
FormatRecord := function(rec_)
    local str, keys, k, v;
    str := "rec(\n";
    str := Concatenation(str, "  source := \"", rec_.source, "\",\n");
    str := Concatenation(str, "  originalIndex := ", String(rec_.originalIndex), ",\n");
    str := Concatenation(str, "  combinedIndex := ", String(rec_.combinedIndex), ",\n");
    str := Concatenation(str, "  index := ", String(rec_.index), ",\n");
    str := Concatenation(str, "  testName := \"", rec_.testName, "\",\n");
    str := Concatenation(str, "  sigKey := ", String(rec_.sigKey), ",\n");
    str := Concatenation(str, "  order := ", String(rec_.order), ",\n");
    str := Concatenation(str, "  isDirectProduct := ", String(rec_.isDirectProduct), ",\n");
    str := Concatenation(str, "  factors := ", String(rec_.factors), ",\n");
    str := Concatenation(str, "  factorOrders := ", String(rec_.factorOrders), ",\n");
    str := Concatenation(str, "  numFactors := ", String(rec_.numFactors), ",\n");
    str := Concatenation(str, "  histogram := ", String(rec_.histogram), ",\n");
    str := Concatenation(str, "  maxOrder := ", String(rec_.maxOrder), ",\n");
    str := Concatenation(str, "  numOrders := ", String(rec_.numOrders));

    if IsBound(rec_.factorGens) then
        str := Concatenation(str, ",\n  factorGens := ", String(rec_.factorGens));
    fi;

    str := Concatenation(str, " )");
    return str;
end;

#-------------------------------------------------------------------
# Define All Test Groups
#-------------------------------------------------------------------

Print("Building test groups...\n");

TEST_GROUPS := [];
idx := 0;

# Part 1: Pure Direct Products
idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Part1_C2_x_S4",
    group := DirectProduct(CyclicGroup(2), SymmetricGroup(4))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Part1_S4_x_C2",
    group := DirectProduct(SymmetricGroup(4), CyclicGroup(2))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Part1_C2_x_C2_x_C4",
    group := DirectProduct(CyclicGroup(2), CyclicGroup(2), CyclicGroup(4))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Part1_A4_x_A4",
    group := DirectProduct(AlternatingGroup(4), AlternatingGroup(4))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Part1_C3_x_S4",
    group := DirectProduct(CyclicGroup(3), SymmetricGroup(4))
));

# Part 2: Single Semidirect Factor
idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Part2_D8_x_C3",
    group := DirectProduct(SmallGroup(8, 3), CyclicGroup(3))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Part2_Q8_x_C3",
    group := DirectProduct(SmallGroup(8, 4), CyclicGroup(3))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Part2_D8_x_C5",
    group := DirectProduct(SmallGroup(8, 3), CyclicGroup(5))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Part2_D8_x_C7",
    group := DirectProduct(SmallGroup(8, 3), CyclicGroup(7))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Part2_SG24_12_x_C2",
    group := DirectProduct(SmallGroup(24, 12), CyclicGroup(2))
));

# Part 3: Multiple Semidirect Factors (Bucket 54 pattern)
idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Part3_SG32_6_x_SG72_40",
    group := DirectProduct(SmallGroup(32, 6), SmallGroup(72, 40))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Part3_SG32_7_x_SG72_40",
    group := DirectProduct(SmallGroup(32, 7), SmallGroup(72, 40))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Part3_SG32_7_x_SG72_41",
    group := DirectProduct(SmallGroup(32, 7), SmallGroup(72, 41))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Part3_SG32_6_x_C3",
    group := DirectProduct(SmallGroup(32, 6), CyclicGroup(3))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Part3_SG32_6_x_C5",
    group := DirectProduct(SmallGroup(32, 6), CyclicGroup(5))
));

# Part 3b: Concern 1 - Pure factor mismatch with semidirect
idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern1_C2_x_C3_x_D8",
    group := DirectProduct(CyclicGroup(2), CyclicGroup(3), SmallGroup(8, 3))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern1_C2_x_C5_x_D8",
    group := DirectProduct(CyclicGroup(2), CyclicGroup(5), SmallGroup(8, 3))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern1_C2_x_C2_x_C3_x_D8",
    group := DirectProduct(CyclicGroup(2), CyclicGroup(2), CyclicGroup(3), SmallGroup(8, 3))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern1_C2_x_C2_x_C7_x_D8",
    group := DirectProduct(CyclicGroup(2), CyclicGroup(2), CyclicGroup(7), SmallGroup(8, 3))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern1_C3_x_D8_x_Q8",
    group := DirectProduct(CyclicGroup(3), SmallGroup(8, 3), SmallGroup(8, 4))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern1_C5_x_D8_x_Q8",
    group := DirectProduct(CyclicGroup(5), SmallGroup(8, 3), SmallGroup(8, 4))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern1_C2_x_C3_x_Q8",
    group := DirectProduct(CyclicGroup(2), CyclicGroup(3), SmallGroup(8, 4))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern1_C3_x_D8",
    group := DirectProduct(CyclicGroup(3), SmallGroup(8, 3))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern1_C5_x_D8",
    group := DirectProduct(CyclicGroup(5), SmallGroup(8, 3))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern1_C3_x_C5_x_D8",
    group := DirectProduct(CyclicGroup(3), CyclicGroup(5), SmallGroup(8, 3))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern1_C7_x_C11_x_D8",
    group := DirectProduct(CyclicGroup(7), CyclicGroup(11), SmallGroup(8, 3))
));

# Additional Concern 1: Isomorphic pair for factor reordering
idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern1_C3_x_C2_x_D8",
    group := DirectProduct(CyclicGroup(3), CyclicGroup(2), SmallGroup(8, 3))
));

# Part 3c: Concern 2 - Greedy matching robustness
idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern2_D8_x_D8",
    group := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 3))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern2_D8_x_Q8",
    group := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 4))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern2_Q8_x_D8",
    group := DirectProduct(SmallGroup(8, 4), SmallGroup(8, 3))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern2_D8_x_D8_x_Q8",
    group := DirectProduct(SmallGroup(8, 3), SmallGroup(8, 3), SmallGroup(8, 4))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern2_Q8_x_D8_x_D8",
    group := DirectProduct(SmallGroup(8, 4), SmallGroup(8, 3), SmallGroup(8, 3))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern2_C2_x_C3_x_D8_x_Q8",
    group := DirectProduct(CyclicGroup(2), CyclicGroup(3), SmallGroup(8, 3), SmallGroup(8, 4))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern2_C3_x_Q8_x_C2_x_D8",
    group := DirectProduct(CyclicGroup(3), SmallGroup(8, 4), CyclicGroup(2), SmallGroup(8, 3))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern2_D8_x_D16",
    group := DirectProduct(SmallGroup(8, 3), SmallGroup(16, 7))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern2_Q8_x_QD16",
    group := DirectProduct(SmallGroup(8, 4), SmallGroup(16, 9))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Concern2_Dihedral8_x_Quaternion8",
    group := DirectProduct(DihedralGroup(8), QuaternionGroup(8))
));

# Edge cases
idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Edge_S5_nonsplit",
    group := SymmetricGroup(5)
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Edge_S4_x_trivial",
    group := DirectProduct(SymmetricGroup(4), CyclicGroup(1))
));

idx := idx + 1;
Add(TEST_GROUPS, rec(
    name := "Edge_S4_alone",
    group := SymmetricGroup(4)
));

Print("Created ", Length(TEST_GROUPS), " test groups\n\n");

#-------------------------------------------------------------------
# Generate Output File
#-------------------------------------------------------------------

Print("Computing invariants and writing output...\n");

# Write header
PrintTo(OUTPUT_PATH,
    "# Test Groups for Factor Comparison Test Suite\n",
    "# Generated by test_groups_source.g\n",
    "# Total: ", String(Length(TEST_GROUPS)), " groups\n",
    "#\n",
    "# Groups organized by test concern:\n",
    "#   Part1_*: Pure direct products\n",
    "#   Part2_*: Single semidirect factor\n",
    "#   Part3_*: Multiple semidirect factors (bucket 54 pattern)\n",
    "#   Concern1_*: Pure factor mismatch with semidirect\n",
    "#   Concern2_*: Greedy matching robustness\n",
    "#   Edge_*: Edge cases\n",
    "#\n",
    "# Fields: source, originalIndex, combinedIndex, index, testName, sigKey, order,\n",
    "#         isDirectProduct, factors, factorOrders, numFactors,\n",
    "#         histogram, maxOrder, numOrders, factorGens (for DPs)\n\n",
    "TEST_GROUPS_GENERATED := [\n");

# Process each group
for i in [1..Length(TEST_GROUPS)] do
    grp := TEST_GROUPS[i];
    Print("  [", i, "/", Length(TEST_GROUPS), "] ", grp.name, " (order ", Size(grp.group), ")...\n");

    # Convert to permutation group so generators are permutation strings
    permG := Image(IsomorphismPermGroup(grp.group));
    rec_ := BuildTestRecord(permG, "TEST", i, grp.name);
    recStr := FormatRecord(rec_);

    if i < Length(TEST_GROUPS) then
        AppendTo(OUTPUT_PATH, recStr, ",\n");
    else
        AppendTo(OUTPUT_PATH, recStr, "\n");
    fi;
od;

AppendTo(OUTPUT_PATH, "];\n\n");

# Write group construction expressions for reference
AppendTo(OUTPUT_PATH,
    "# Group construction expressions (for reference/reconstruction)\n",
    "TEST_GROUP_CONSTRUCTORS := rec(\n");

for i in [1..Length(TEST_GROUPS)] do
    grp := TEST_GROUPS[i];
    if i < Length(TEST_GROUPS) then
        AppendTo(OUTPUT_PATH, "  ", grp.name, " := ", String(i), ",\n");
    else
        AppendTo(OUTPUT_PATH, "  ", grp.name, " := ", String(i), "\n");
    fi;
od;

AppendTo(OUTPUT_PATH, ");\n");

Print("\n=== COMPLETE ===\n");
Print("Generated ", Length(TEST_GROUPS), " test group records\n");
Print("Output written to: ", OUTPUT_PATH, "\n");

QUIT;
