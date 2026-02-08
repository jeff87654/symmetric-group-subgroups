
# Precompute S14 conjugacy classes with aggressive garbage collection
# Working memory limited to 2^34 (16GB), total allowed 50GB

Print("Starting S14 conjugacy class precomputation...\n");
Print("Setting up aggressive garbage collection...\n");

# Show garbage collection messages
SetGasmanMessageStatus("full");

# Enable info messages for subgroup lattice computation
SetInfoLevel(InfoGroup, 2);
SetInfoLevel(InfoLattice, 2);

# Force garbage collection before starting
GASMAN("collect");
Print("Initial memory: ", GasmanStatistics(), "\n");

Print("Computing conjugacy classes of subgroups of S14...\n");
Print("This will take a long time. Progress will be shown via Info messages.\n");
Print("Note: GAP uses a cyclic extension algorithm - it builds subgroups level by level.\n");

# Compute with periodic GC
startTime := Runtime();
G := SymmetricGroup(14);
Print("Created S14, elapsed: ", Runtime() - startTime, " ms\n");
Print("Order of S14: ", Size(G), " = 14! = ", Factorial(14), "\n");
GASMAN("collect");

# Compute conjugacy classes - this is the long step
Print("\n=== Starting conjugacy class computation ===\n");
Print("Using LowIndexSubgroupsFpGroup approach for progress...\n");
ccs := ConjugacyClassesSubgroups(G);
Print("\n=== Computation complete ===\n");
Print("Computed ", Length(ccs), " conjugacy classes\n");
GASMAN("collect");

# Extract representatives and save
Print("Extracting representatives...\n");
reps := List(ccs, Representative);
Print("Got ", Length(reps), " representatives\n");
GASMAN("collect");

# Save to file
Print("Saving to file: /cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/conjugacy_cache/s14_subgroups.g\n");
output := OutputTextFile("/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/conjugacy_cache/s14_subgroups.g", false);
SetPrintFormattingStatus(output, false);
PrintTo(output, "# S14 conjugacy class representatives\n");
PrintTo(output, "# Generated with aggressive GC\n");
PrintTo(output, "return [\n");
for i in [1..Length(reps)] do
    H := reps[i];
    if i > 1 then
        PrintTo(output, ",\n");
    fi;
    PrintTo(output, "Group(", GeneratorsOfGroup(H), ")");
    if i mod 1000 = 0 then
        Print("  Saved ", i, "/", Length(reps), " subgroups\n");
        GASMAN("collect");
    fi;
od;
PrintTo(output, "\n];\n");
CloseStream(output);

endTime := Runtime();
Print("\nCompleted in ", (endTime - startTime) / 1000.0, " seconds\n");
Print("Saved ", Length(reps), " subgroups to ", "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/conjugacy_cache/s14_subgroups.g", "\n");
QUIT;
