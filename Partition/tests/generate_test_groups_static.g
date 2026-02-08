# Script to generate test_groups_static.g with full invariants
# Run this script in GAP to generate the static test file
#
# Usage: Read("generate_test_groups_static.g");

Print("Generating static test groups with full invariants...\n");

# Helper functions to compute invariants (same as used in cross-deduplication)

ComputeSigKey := function(G)
    local order, derived, derivedSize, numClasses, derivedLength, abelianInvs;
    order := Size(G);
    derived := DerivedSubgroup(G);
    derivedSize := Size(derived);
    numClasses := NrConjugacyClasses(G);
    if IsSolvableGroup(G) then
        derivedLength := DerivedLength(G);
    else
        derivedLength := -1;
    fi;
    abelianInvs := AbelianInvariants(G/derived);
    return [order, derivedSize, numClasses, derivedLength, abelianInvs];
end;

# Compute histogram using conjugacy classes (much faster than enumerating elements)
ComputeHistogram := function(G)
    local cc, orderCounts, c, o, classSize, sorted;
    cc := ConjugacyClasses(G);
    orderCounts := rec();
    for c in cc do
        o := Order(Representative(c));
        classSize := Size(c);
        if IsBound(orderCounts.(String(o))) then
            orderCounts.(String(o)) := orderCounts.(String(o)) + classSize;
        else
            orderCounts.(String(o)) := classSize;
        fi;
    od;
    sorted := List(RecNames(orderCounts), x -> [Int(x), orderCounts.(x)]);
    Sort(sorted, function(a, b) return a[1] < b[1]; end);
    return sorted;
end;

ComputeMaxOrder := function(G)
    return Exponent(G);
end;

ComputeNumOrders := function(hist)
    return Length(hist);
end;

# Try to identify direct product structure - simplified version
# Returns basic info without expensive StructureDescription
TryDirectProductFactors := function(G)
    local desc;

    # For small groups, use StructureDescription; for larger ones, skip it
    if Size(G) <= 500 then
        desc := StructureDescription(G);
        if PositionSublist(desc, " x ") <> fail then
            return rec(
                isDirectProduct := true,
                factors := SplitString(ReplacedString(desc, " ", ""), "x"),
                factorOrders := [],
                numFactors := 0,  # Will count from factors list
                structureDesc := desc
            );
        fi;
    fi;

    # For larger groups or non-products, just return basic info
    return rec(
        isDirectProduct := false,
        factors := [],
        factorOrders := [],
        numFactors := 1,
        structureDesc := ""
    );
end;

# Convert a group to a string representation of its generators
GeneratorsToString := function(G)
    local gens, genStrings, g;
    gens := GeneratorsOfGroup(G);
    genStrings := List(gens, g -> String(g));
    return genStrings;
end;

# Create the test groups
TEST_GROUP_DEFINITIONS := [
    # Part 1: Pure Direct Products
    rec(name := "Part1_C2_x_S4", group := DirectProduct(CyclicGroup(IsPermGroup, 2), SymmetricGroup(4)), description := "C2 x S4 - pure direct product"),
    rec(name := "Part1_S4_x_C2", group := DirectProduct(SymmetricGroup(4), CyclicGroup(IsPermGroup, 2)), description := "S4 x C2 - reordered, should match Part1_C2_x_S4"),
    rec(name := "Part1_C2_x_C2_x_C4", group := DirectProduct(CyclicGroup(IsPermGroup, 2), CyclicGroup(IsPermGroup, 2), CyclicGroup(IsPermGroup, 4)), description := "C2 x C2 x C4 - pure abelian product"),
    rec(name := "Part1_A4_x_A4", group := DirectProduct(AlternatingGroup(4), AlternatingGroup(4)), description := "A4 x A4 - non-abelian pure product"),
    rec(name := "Part1_C3_x_S4", group := DirectProduct(CyclicGroup(IsPermGroup, 3), SymmetricGroup(4)), description := "C3 x S4 - differs from C2 x S4"),

    # Part 2: Single Semidirect Factor
    rec(name := "Part2_D8_x_C3", group := DirectProduct(DihedralGroup(IsPermGroup, 8), CyclicGroup(IsPermGroup, 3)), description := "D8 x C3 - semidirect x pure"),
    rec(name := "Part2_Q8_x_C3", group := DirectProduct(QuaternionGroup(8), CyclicGroup(IsPermGroup, 3)), description := "Q8 x C3 - different semidirect, same pure"),
    rec(name := "Part2_D8_x_C5", group := DirectProduct(DihedralGroup(IsPermGroup, 8), CyclicGroup(IsPermGroup, 5)), description := "D8 x C5 - same semidirect, different pure"),
    rec(name := "Part2_D8_x_C7", group := DirectProduct(DihedralGroup(IsPermGroup, 8), CyclicGroup(IsPermGroup, 7)), description := "D8 x C7 - same semidirect, different pure"),
    rec(name := "Part2_SG24_12_x_C2", group := DirectProduct(SmallGroup(24, 12), CyclicGroup(IsPermGroup, 2)), description := "SmallGroup(24,12) x C2 - larger semidirect"),

    # Part 3: Multiple Semidirect Factors (Bucket 54 Pattern)
    rec(name := "Part3_SG32_6_x_SG72_40", group := DirectProduct(SmallGroup(32, 6), SmallGroup(72, 40)), description := "(C2^4:C2) x ((S3xS3):C2) - bucket 54 pattern A"),
    rec(name := "Part3_SG32_7_x_SG72_40", group := DirectProduct(SmallGroup(32, 7), SmallGroup(72, 40)), description := "(C4^2:C2) x ((S3xS3):C2) - bucket 54 pattern B (differs in first factor)"),
    rec(name := "Part3_SG32_7_x_SG72_41", group := DirectProduct(SmallGroup(32, 7), SmallGroup(72, 41)), description := "(C4^2:C2) x different72 - both factors differ"),
    rec(name := "Part3_SG32_6_x_C3", group := DirectProduct(SmallGroup(32, 6), CyclicGroup(IsPermGroup, 3)), description := "(C2^4:C2) x C3 - semidirect + pure"),
    rec(name := "Part3_SG32_6_x_C5", group := DirectProduct(SmallGroup(32, 6), CyclicGroup(IsPermGroup, 5)), description := "(C2^4:C2) x C5 - same semidirect, different pure"),

    # Part 3b: Concern 1 - Pure Factor Mismatch with Semidirect
    rec(name := "Concern1_C2_x_C3_x_D8", group := DirectProduct(CyclicGroup(IsPermGroup, 2), CyclicGroup(IsPermGroup, 3), DihedralGroup(IsPermGroup, 8)), description := "C2 x C3 x D8 - base case for Concern 1"),
    rec(name := "Concern1_C2_x_C5_x_D8", group := DirectProduct(CyclicGroup(IsPermGroup, 2), CyclicGroup(IsPermGroup, 5), DihedralGroup(IsPermGroup, 8)), description := "C2 x C5 x D8 - C3 vs C5 mismatch after C2 cancels"),
    rec(name := "Concern1_C2_x_C2_x_C3_x_D8", group := DirectProduct(CyclicGroup(IsPermGroup, 2), CyclicGroup(IsPermGroup, 2), CyclicGroup(IsPermGroup, 3), DihedralGroup(IsPermGroup, 8)), description := "C2 x C2 x C3 x D8 - multiple shared pure factors"),
    rec(name := "Concern1_C2_x_C2_x_C7_x_D8", group := DirectProduct(CyclicGroup(IsPermGroup, 2), CyclicGroup(IsPermGroup, 2), CyclicGroup(IsPermGroup, 7), DihedralGroup(IsPermGroup, 8)), description := "C2 x C2 x C7 x D8 - differs in C3 vs C7"),
    rec(name := "Concern1_C3_x_D8_x_Q8", group := DirectProduct(CyclicGroup(IsPermGroup, 3), DihedralGroup(IsPermGroup, 8), QuaternionGroup(8)), description := "C3 x D8 x Q8 - two semidirect + one pure"),
    rec(name := "Concern1_C5_x_D8_x_Q8", group := DirectProduct(CyclicGroup(IsPermGroup, 5), DihedralGroup(IsPermGroup, 8), QuaternionGroup(8)), description := "C5 x D8 x Q8 - differs in C3 vs C5"),
    rec(name := "Concern1_C2_x_C3_x_Q8", group := DirectProduct(CyclicGroup(IsPermGroup, 2), CyclicGroup(IsPermGroup, 3), QuaternionGroup(8)), description := "C2 x C3 x Q8 - same pure as #16, different semi (D8 vs Q8)"),
    rec(name := "Concern1_C3_x_D8", group := DirectProduct(CyclicGroup(IsPermGroup, 3), DihedralGroup(IsPermGroup, 8)), description := "C3 x D8 - no common pure factors"),
    rec(name := "Concern1_C5_x_D8", group := DirectProduct(CyclicGroup(IsPermGroup, 5), DihedralGroup(IsPermGroup, 8)), description := "C5 x D8 - no common pure factors (vs C3 x D8)"),
    rec(name := "Concern1_C3_x_C5_x_D8", group := DirectProduct(CyclicGroup(IsPermGroup, 3), CyclicGroup(IsPermGroup, 5), DihedralGroup(IsPermGroup, 8)), description := "C3 x C5 x D8 - all pure factors differ from next"),
    rec(name := "Concern1_C7_x_C11_x_D8", group := DirectProduct(CyclicGroup(IsPermGroup, 7), CyclicGroup(IsPermGroup, 11), DihedralGroup(IsPermGroup, 8)), description := "C7 x C11 x D8 - all pure factors differ"),
    rec(name := "Concern1_C3_x_C2_x_D8", group := DirectProduct(CyclicGroup(IsPermGroup, 3), CyclicGroup(IsPermGroup, 2), DihedralGroup(IsPermGroup, 8)), description := "C3 x C2 x D8 - reordered, should match #16"),

    # Part 3c: Concern 2 - Greedy Matching Robustness
    rec(name := "Concern2_D8_x_D8", group := DirectProduct(DihedralGroup(IsPermGroup, 8), DihedralGroup(IsPermGroup, 8)), description := "D8 x D8 - identical factors (any matching works)"),
    rec(name := "Concern2_D8_x_Q8", group := DirectProduct(DihedralGroup(IsPermGroup, 8), QuaternionGroup(8)), description := "D8 x Q8 - two different factors"),
    rec(name := "Concern2_Q8_x_D8", group := DirectProduct(QuaternionGroup(8), DihedralGroup(IsPermGroup, 8)), description := "Q8 x D8 - swapped order, should match #29"),
    rec(name := "Concern2_D8_x_D8_x_Q8", group := DirectProduct(DihedralGroup(IsPermGroup, 8), DihedralGroup(IsPermGroup, 8), QuaternionGroup(8)), description := "D8 x D8 x Q8 - one unique, two identical"),
    rec(name := "Concern2_Q8_x_D8_x_D8", group := DirectProduct(QuaternionGroup(8), DihedralGroup(IsPermGroup, 8), DihedralGroup(IsPermGroup, 8)), description := "Q8 x D8 x D8 - reordered, should match #31"),
    rec(name := "Concern2_D8_x_Q8_x_C3", group := DirectProduct(DihedralGroup(IsPermGroup, 8), QuaternionGroup(8), CyclicGroup(IsPermGroup, 3)), description := "D8 x Q8 x C3 - 3 factors stress test"),
    rec(name := "Concern2_Q8_x_C3_x_D8", group := DirectProduct(QuaternionGroup(8), CyclicGroup(IsPermGroup, 3), DihedralGroup(IsPermGroup, 8)), description := "Q8 x C3 x D8 - reordered, should match #33"),
    rec(name := "Concern2_D8_x_Q8_single", group := DirectProduct(DihedralGroup(IsPermGroup, 8), QuaternionGroup(8)), description := "D8 x Q8 - one differs from D8 x D8"),
    rec(name := "Concern2_D8_x_D16", group := DirectProduct(DihedralGroup(IsPermGroup, 8), DihedralGroup(IsPermGroup, 16)), description := "D8 x D16 - all factors differ from next"),
    rec(name := "Concern2_Q8_x_QD16", group := DirectProduct(QuaternionGroup(8), SmallGroup(16, 8)), description := "Q8 x QD16 - all factors differ"),
    rec(name := "Concern2_Dihedral8_x_Quaternion8", group := DirectProduct(DihedralGroup(IsPermGroup, 8), QuaternionGroup(8)), description := "DihedralGroup(8) x QuaternionGroup(8) - different constructor, should match #29"),

    # Edge Cases
    rec(name := "Edge_S5_nonsplit", group := SymmetricGroup(5), description := "S5 - not a direct product"),
    rec(name := "Edge_S4_x_trivial", group := DirectProduct(SymmetricGroup(4), Group(())), description := "S4 x C1 - trivial factor"),
    rec(name := "Edge_S4_alone", group := SymmetricGroup(4), description := "S4 alone - for comparison with S4 x C1")
];

# Generate the static file content
# Use absolute path to ensure file is created in the right place
outputFile := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/Partition/tests/test_groups_static_generated.g";
PrintTo(outputFile, "# Static Test Groups for Factor Comparison Test Suite\n");
AppendTo(outputFile, "# Generated with full invariants matching combined_s13_s14_original.g format\n");
AppendTo(outputFile, "# These groups can be loaded directly for testing without computing invariants\n");
AppendTo(outputFile, "#\n");
AppendTo(outputFile, "# Usage: Read(\"test_groups_static.g\");\n");
AppendTo(outputFile, "#        G := TEST_GROUPS_STATIC[1].group;\n");
AppendTo(outputFile, "#\n");
AppendTo(outputFile, "# Fields per group:\n");
AppendTo(outputFile, "#   index, name, description - identification\n");
AppendTo(outputFile, "#   group - Group object with permutation generators\n");
AppendTo(outputFile, "#   generators - string list of generators\n");
AppendTo(outputFile, "#   order - group order\n");
AppendTo(outputFile, "#   sigKey - [order, derivedSize, numClasses, derivedLength, abelianInvs]\n");
AppendTo(outputFile, "#   isDirectProduct, factors, factorOrders, numFactors - direct product info\n");
AppendTo(outputFile, "#   histogram - element order histogram [[order, count], ...]\n");
AppendTo(outputFile, "#   maxOrder - maximum element order (exponent)\n");
AppendTo(outputFile, "#   numOrders - number of distinct element orders\n");
AppendTo(outputFile, "#\n");
AppendTo(outputFile, "# Groups organized by test concern:\n");
AppendTo(outputFile, "#   Part1_*: Pure direct products\n");
AppendTo(outputFile, "#   Part2_*: Single semidirect factor\n");
AppendTo(outputFile, "#   Part3_*: Multiple semidirect factors (bucket 54 pattern)\n");
AppendTo(outputFile, "#   Concern1_*: Pure factor mismatch with semidirect\n");
AppendTo(outputFile, "#   Concern2_*: Greedy matching robustness\n");
AppendTo(outputFile, "#   Edge_*: Edge cases\n");
AppendTo(outputFile, "\n");
AppendTo(outputFile, "Print(\"Loading static test groups with full invariants...\\n\");\n");
AppendTo(outputFile, "\n");
AppendTo(outputFile, "TEST_GROUPS_STATIC := [\n");

# Process each group
for i in [1..Length(TEST_GROUP_DEFINITIONS)] do
    Print("Processing ", i, "/", Length(TEST_GROUP_DEFINITIONS), ": ", TEST_GROUP_DEFINITIONS[i].name, "\n");

    def := TEST_GROUP_DEFINITIONS[i];
    G := def.group;

    # Convert to permutation group if not already
    if not IsPermGroup(G) then
        G := Image(IsomorphismPermGroup(G));
    fi;

    # Compute invariants
    sigKey := ComputeSigKey(G);
    hist := ComputeHistogram(G);
    maxOrd := ComputeMaxOrder(G);
    numOrds := ComputeNumOrders(hist);
    dpInfo := TryDirectProductFactors(G);

    # Get generators as strings
    gens := GeneratorsOfGroup(G);

    # Write the record
    AppendTo(outputFile, "rec(\n");
    AppendTo(outputFile, "  index := ", i, ",\n");
    AppendTo(outputFile, "  name := \"", def.name, "\",\n");
    AppendTo(outputFile, "  description := \"", def.description, "\",\n");
    AppendTo(outputFile, "  group := Group(", gens, "),\n");
    AppendTo(outputFile, "  generators := ", List(gens, String), ",\n");
    AppendTo(outputFile, "  order := ", Size(G), ",\n");
    AppendTo(outputFile, "  sigKey := ", sigKey, ",\n");
    AppendTo(outputFile, "  isDirectProduct := ", dpInfo.isDirectProduct, ",\n");
    AppendTo(outputFile, "  factors := ", dpInfo.factors, ",\n");
    AppendTo(outputFile, "  factorOrders := ", dpInfo.factorOrders, ",\n");
    AppendTo(outputFile, "  numFactors := ", dpInfo.numFactors, ",\n");
    AppendTo(outputFile, "  histogram := ", hist, ",\n");
    AppendTo(outputFile, "  maxOrder := ", maxOrd, ",\n");
    AppendTo(outputFile, "  numOrders := ", numOrds, "\n");

    if i < Length(TEST_GROUP_DEFINITIONS) then
        AppendTo(outputFile, "),\n\n");
    else
        AppendTo(outputFile, ")\n");
    fi;
od;

AppendTo(outputFile, "];\n\n");

# Add the expected pairs
AppendTo(outputFile, "#-------------------------------------------------------------------\n");
AppendTo(outputFile, "# Expected Test Results (for validation)\n");
AppendTo(outputFile, "#-------------------------------------------------------------------\n\n");

AppendTo(outputFile, "# Pairs that should be isomorphic (expected := true)\n");
AppendTo(outputFile, "EXPECTED_ISOMORPHIC_PAIRS := [\n");
AppendTo(outputFile, "  [1, 2],   # Part1_C2_x_S4 = Part1_S4_x_C2\n");
AppendTo(outputFile, "  [16, 27], # Concern1_C2_x_C3_x_D8 = Concern1_C3_x_C2_x_D8\n");
AppendTo(outputFile, "  [29, 30], # Concern2_D8_x_Q8 = Concern2_Q8_x_D8\n");
AppendTo(outputFile, "  [31, 32], # Concern2_D8_x_D8_x_Q8 = Concern2_Q8_x_D8_x_D8\n");
AppendTo(outputFile, "  [33, 34], # Concern2_D8_x_Q8_x_C3 = Concern2_Q8_x_C3_x_D8\n");
AppendTo(outputFile, "  [29, 38], # Concern2_D8_x_Q8 = Concern2_Dihedral8_x_Quaternion8\n");
AppendTo(outputFile, "];\n\n");

AppendTo(outputFile, "# Pairs that should NOT be isomorphic (expected := false)\n");
AppendTo(outputFile, "EXPECTED_NONISOMORPHIC_PAIRS := [\n");
AppendTo(outputFile, "  [1, 5],   # C2 x S4 vs C3 x S4\n");
AppendTo(outputFile, "  [6, 7],   # D8 x C3 vs Q8 x C3\n");
AppendTo(outputFile, "  [8, 9],   # D8 x C5 vs D8 x C7\n");
AppendTo(outputFile, "  [11, 12], # Bucket54 pattern: SG32_6 vs SG32_7\n");
AppendTo(outputFile, "  [16, 17], # Concern1: C2 x C3 x D8 vs C2 x C5 x D8\n");
AppendTo(outputFile, "  [18, 19], # Concern1: C2 x C2 x C3 x D8 vs C2 x C2 x C7 x D8\n");
AppendTo(outputFile, "  [20, 21], # Concern1: C3 x D8 x Q8 vs C5 x D8 x Q8\n");
AppendTo(outputFile, "  [16, 22], # Concern1: same pure, semi D8 vs Q8\n");
AppendTo(outputFile, "  [23, 24], # Concern1: C3 x D8 vs C5 x D8\n");
AppendTo(outputFile, "  [25, 26], # Concern1: C3 x C5 x D8 vs C7 x C11 x D8\n");
AppendTo(outputFile, "  [28, 35], # Concern2: D8 x D8 vs D8 x Q8\n");
AppendTo(outputFile, "  [36, 37], # Concern2: D8 x D16 vs Q8 x QD16\n");
AppendTo(outputFile, "];\n\n");

AppendTo(outputFile, "Print(\"Loaded \", Length(TEST_GROUPS_STATIC), \" test groups with full invariants\\n\");\n");
AppendTo(outputFile, "Print(\"Expected isomorphic pairs: \", Length(EXPECTED_ISOMORPHIC_PAIRS), \"\\n\");\n");
AppendTo(outputFile, "Print(\"Expected non-isomorphic pairs: \", Length(EXPECTED_NONISOMORPHIC_PAIRS), \"\\n\");\n");

Print("\n========================================\n");
Print("Generated: ", outputFile, "\n");
Print("Total groups: ", Length(TEST_GROUP_DEFINITIONS), "\n");
Print("\nTo use: rename test_groups_static_generated.g to test_groups_static.g\n");
Print("========================================\n");
