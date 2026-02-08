
# Precompute conjugacy classes for S13
# This can be run in advance to speed up the main enumeration

n := 13;
cacheDir := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/conjugacy_cache/";

Print("Computing conjugacy classes for S", n, "...\n");
Print("This may take a while for large n.\n");

startTime := Runtime();

Sn := SymmetricGroup(n);
subgroupClasses := ConjugacyClassesSubgroups(Sn);
nSubgroups := Length(subgroupClasses);

elapsed := Float(Runtime() - startTime) / 1000.0;
Print("Found ", nSubgroups, " conjugacy classes in ", elapsed, " seconds\n");

# Save to file
filename := Concatenation(cacheDir, "s", String(n), "_subgroups.g");
Print("Saving to ", filename, "...\n");

output := OutputTextFile(filename, false);
SetPrintFormattingStatus(output, false);
PrintTo(output, "# Conjugacy class representatives for S", n, "\n");
PrintTo(output, "# ", nSubgroups, " subgroups\n");
PrintTo(output, "# Computed in ", elapsed, " seconds\n");
PrintTo(output, "return [\n");

for i in [1..nSubgroups] do
    H := Representative(subgroupClasses[i]);
    gens := List(GeneratorsOfGroup(H), p -> ListPerm(p, n));
    PrintTo(output, "  ", gens);
    if i < nSubgroups then
        PrintTo(output, ",");
    fi;
    PrintTo(output, "\n");

    # Progress
    if i mod 1000 = 0 then
        Print("  Saved ", i, "/", nSubgroups, " subgroups\n");
    fi;
od;

PrintTo(output, "];\n");
CloseStream(output);

Print("Done! Saved ", nSubgroups, " subgroups to ", filename, "\n");

QUIT;
