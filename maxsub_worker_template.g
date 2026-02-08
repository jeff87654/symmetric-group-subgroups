###############################################################################
#
# maxsub_worker_template.g - Template for individual maximal subgroup workers
#
# This script is parameterized by variables that must be set BEFORE Read():
#   WORKER_TYPE    - "intransitive", "wreath", "primitive", or "s1xs13"
#   WORKER_PARAMS  - type-specific parameters (list)
#   WORKER_OUTPUT  - output file path (string)
#   WORKER_N       - degree (14)
#
# Example usage:
#   WORKER_TYPE := "intransitive";
#   WORKER_PARAMS := [3, 11];
#   WORKER_OUTPUT := "/cygdrive/c/.../maxsub_output/intrans_3x11.g";
#   WORKER_N := 14;
#   Read("/cygdrive/c/.../maxsub_worker_template.g");
#
###############################################################################

# Load core functions
Read(Concatenation(MAXSUB_BASE, "/compute_s14_maxsub.g"));

Print("Worker started: type=", WORKER_TYPE, ", params=", WORKER_PARAMS, "\n");
Print("Output: ", WORKER_OUTPUT, "\n\n");

startTime := Runtime();
n := WORKER_N;
workerDone := false;

###############################################################################
# Build the maximal subgroup based on type
###############################################################################

if WORKER_TYPE = "intransitive" then
    k := WORKER_PARAMS[1];
    Print("Building S_", k, " x S_", n-k, " on {1,...,", n, "}...\n");
    M := BuildIntransitiveMaxSub(k, n);
    workerLabel := Concatenation("intrans_", String(k), "x", String(n-k));

elif WORKER_TYPE = "wreath" then
    a := WORKER_PARAMS[1];
    b := WORKER_PARAMS[2];
    Print("Building S_", a, " wr S_", b, "...\n");
    M := BuildWreathMaxSub(a, b);
    workerLabel := Concatenation("wreath_", String(a), "wr", String(b));

elif WORKER_TYPE = "primitive" then
    primIdx := WORKER_PARAMS[1];
    Print("Loading PrimitiveGroup(", n, ", ", primIdx, ")...\n");
    M := PrimitiveGroup(n, primIdx);
    workerLabel := Concatenation("primitive_", String(primIdx));

elif WORKER_TYPE = "s1xs13" then
    # Special case: use cached S13 subgroups
    Print("Loading S13 cache and embedding as S1 x S13...\n");
    cacheFile := Concatenation(MAXSUB_CACHE, "/s13_subgroups.g");
    embeddedSubs := EmbedS13SubgroupsAsS1xS13(cacheFile, n);

    # Write directly to output - no need to compute subgroup lattice
    PrintTo(WORKER_OUTPUT, "# Subgroups of S1 x S13 (from S13 cache)\n");
    AppendTo(WORKER_OUTPUT, "# Count: ", Length(embeddedSubs), "\n");
    AppendTo(WORKER_OUTPUT, "maxsub_results := [\n");

    for i in [1..Length(embeddedSubs)] do
        entry := embeddedSubs[i];
        gens := GeneratorsOfGroup(entry.group);
        genImages := [];
        for g in gens do
            Add(genImages, ListPerm(g, n));
        od;

        if i > 1 then
            AppendTo(WORKER_OUTPUT, ",\n");
        fi;
        AppendTo(WORKER_OUTPUT, "  rec(gens := ", genImages,
                 ", inv := ", entry.inv,
                 ", source := \"intrans_1x13\")");

        if i mod 2000 = 0 then
            Print("  Written ", i, "/", Length(embeddedSubs), "\n");
            GASMAN("collect");
        fi;
    od;

    AppendTo(WORKER_OUTPUT, "\n];\n");

    elapsed := Runtime() - startTime;
    Print("\n=== S1 x S13 worker complete ===\n");
    Print("  Subgroups: ", Length(embeddedSubs), "\n");
    Print("  Time: ", Int(elapsed/1000), " seconds\n");
    AppendTo(WORKER_OUTPUT, "# Complete: ", Length(embeddedSubs),
             " subgroups in ", Int(elapsed/1000), " seconds\n");
    workerDone := true;

else
    Print("ERROR: Unknown worker type: ", WORKER_TYPE, "\n");
    workerDone := true;
fi;

###############################################################################
# Standard path: compute subgroup lattice and save
###############################################################################

if not workerDone then
    Print("Maximal subgroup: ", workerLabel, "\n");
    Print("  Order: ", Size(M), "\n");
    if LargestMovedPoint(M) > 0 then
        Print("  Moved points: ", NrMovedPoints(M), "\n");
    fi;

    count := ComputeSubgroupsOfMaxSub(M, workerLabel, WORKER_OUTPUT, n);

    elapsed := Runtime() - startTime;
    AppendTo(WORKER_OUTPUT, "# Complete: ", count,
             " subgroups in ", Int(elapsed/1000), " seconds\n");

    Print("\n=== Worker ", workerLabel, " complete ===\n");
    Print("  Subgroups: ", count, "\n");
    Print("  Total time: ", Int(elapsed/1000), " seconds\n");
fi;

QUIT;
