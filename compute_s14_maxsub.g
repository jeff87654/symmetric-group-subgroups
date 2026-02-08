###############################################################################
#
# compute_s14_maxsub.g - Core GAP functions for S14 maximal subgroup approach
#
# Computes A005432(14) = 75,154 conjugacy classes of subgroups of S14
# by decomposing through maximal subgroups.
#
# Every subgroup of S14 is contained in at least one maximal subgroup.
# Maximal subgroups of S_n are:
#   - Intransitive: S_k x S_{n-k} for 1 <= k <= n/2
#   - Transitive imprimitive: S_a wr S_b where a*b = n, a >= 2, b >= 2
#   - Primitive: finitely many, available via PrimitiveGroup(n, i)
#   - A_n (index 2 in S_n)
#
###############################################################################

MAXSUB_BASE := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups";
MAXSUB_OUTPUT := Concatenation(MAXSUB_BASE, "/maxsub_output");
MAXSUB_CACHE := Concatenation(MAXSUB_BASE, "/conjugacy_cache");

###############################################################################
# Invariant key for bucketing subgroups
#
# Two subgroups with different invariant keys CANNOT be S14-conjugate.
# The orbit structure on {1,...,14} is the most discriminating invariant
# since conjugation preserves orbit structure exactly.
###############################################################################

ComputeOrbitStructure := function(H, n)
    local orbs, sizes;
    # Compute orbits on {1,...,n}
    orbs := Orbits(H, [1..n]);
    sizes := List(orbs, Length);
    Sort(sizes);
    return sizes;
end;

ComputeInvariantKey := function(H, n)
    local orbStruct, ord, nrCC, derLen, cenSize, exp, abInv, derSize;

    ord := Size(H);

    # Orbit structure - most discriminating for permutation groups
    orbStruct := ComputeOrbitStructure(H, n);

    # Number of conjugacy classes
    nrCC := NrConjugacyClasses(H);

    # Derived length (use -1 for non-solvable)
    if IsSolvable(H) then
        derLen := DerivedLength(H);
    else
        derLen := -1;
    fi;

    # Center size
    cenSize := Size(Center(H));

    # Exponent
    exp := Exponent(H);

    # Abelian invariants
    abInv := AbelianInvariants(H);

    # Derived subgroup size - very discriminating, cheap to compute
    derSize := Size(DerivedSubgroup(H));

    return [ord, orbStruct, nrCC, derLen, cenSize, exp, abInv, derSize];
end;

# Convert invariant key to string for use as record field name
InvariantKeyToString := function(key)
    return String(key);
end;

###############################################################################
# Build maximal subgroups as permutation groups on {1,...,14}
###############################################################################

# Build S_k x S_{n-k} acting on {1,...,n}
# S_k acts on {1,...,k}, S_{n-k} acts on {k+1,...,n}
BuildIntransitiveMaxSub := function(k, n)
    local gens, g;

    gens := [];

    # Generators for S_k on {1,...,k}
    if k >= 2 then
        Add(gens, (1, 2));  # transposition
        if k >= 3 then
            # k-cycle (1,2,...,k)
            g := PermList(Concatenation([2..k], [1], [k+1..n]));
            Add(gens, g);
        fi;
    fi;

    # Generators for S_{n-k} on {k+1,...,n}
    if n - k >= 2 then
        Add(gens, (k+1, k+2));  # transposition
        if n - k >= 3 then
            # (n-k)-cycle (k+1, k+2, ..., n)
            g := PermList(Concatenation([1..k], [k+2..n], [k+1]));
            Add(gens, g);
        fi;
    fi;

    if Length(gens) = 0 then
        return Group(());
    fi;

    return Group(gens);
end;

# Build S_a wr S_b acting on {1,...,a*b}
# This is the wreath product with imprimitive action
# Blocks: {1,...,a}, {a+1,...,2a}, ..., {(b-1)*a+1,...,b*a}
BuildWreathMaxSub := function(a, b)
    local W;
    W := WreathProduct(SymmetricGroup(a), SymmetricGroup(b));
    # WreathProduct in GAP already gives a permutation group on {1..a*b}
    return W;
end;

###############################################################################
# Enumerate all maximal subgroups of S_n
# Returns list of rec(group, label, type)
###############################################################################

EnumerateMaximalSubgroups := function(n)
    local maxsubs, k, a, b, nrPrim, i, G;

    maxsubs := [];

    # Intransitive maximal subgroups: S_k x S_{n-k} for 1 <= k <= n/2
    for k in [1..Int(n/2)] do
        Add(maxsubs, rec(
            group := BuildIntransitiveMaxSub(k, n),
            label := Concatenation("intrans_", String(k), "x", String(n-k)),
            type := "intransitive",
            params := [k, n-k]
        ));
    od;

    # Transitive imprimitive: S_a wr S_b where a*b = n, a >= 2, b >= 2
    for a in [2..n-1] do
        if n mod a = 0 then
            b := n / a;
            if b >= 2 then
                Add(maxsubs, rec(
                    group := BuildWreathMaxSub(a, b),
                    label := Concatenation("wreath_", String(a), "wr", String(b)),
                    type := "wreath",
                    params := [a, b]
                ));
            fi;
        fi;
    od;

    # Primitive maximal subgroups
    nrPrim := NrPrimitiveGroups(n);
    for i in [1..nrPrim] do
        G := PrimitiveGroup(n, i);
        # Skip S_n and A_n themselves - we handle those separately
        if Size(G) < Factorial(n) and Size(G) < Factorial(n)/2 then
            Add(maxsubs, rec(
                group := G,
                label := Concatenation("primitive_", String(i)),
                type := "primitive",
                params := [n, i]
            ));
        fi;
    od;

    return maxsubs;
end;

###############################################################################
# Worker function: compute conjugacy classes of a maximal subgroup
# Saves results incrementally to checkpoint file
###############################################################################

ComputeSubgroupsOfMaxSub := function(M, label, outputFile, n)
    local ccs, reps, i, H, gens, inv, genImages, g, startTime, elapsed;

    startTime := Runtime();
    Print("=== Computing subgroups of ", label, " ===\n");
    Print("  Order: ", Size(M), "\n");
    Print("  Degree: ", LargestMovedPoint(M), "\n");

    # Initialize output file
    PrintTo(outputFile, "# Subgroups of maximal subgroup: ", label, "\n");
    AppendTo(outputFile, "# Order of maxsub: ", Size(M), "\n");
    AppendTo(outputFile, "# Started: ", StringTime(Runtime()), "\n");
    AppendTo(outputFile, "maxsub_results := [\n");

    # Compute conjugacy classes of subgroups
    Print("  Computing ConjugacyClassesSubgroups...\n");
    ccs := ConjugacyClassesSubgroups(M);
    Print("  Found ", Length(ccs), " conjugacy classes within ", label, "\n");

    elapsed := Runtime() - startTime;
    Print("  Lattice computation took ", Int(elapsed/1000), " seconds\n");

    # Extract representatives and save with invariants
    reps := List(ccs, Representative);
    Print("  Saving ", Length(reps), " representatives...\n");

    for i in [1..Length(reps)] do
        H := reps[i];
        gens := GeneratorsOfGroup(H);

        # Convert generators to image lists for storage
        genImages := [];
        for g in gens do
            Add(genImages, ListPerm(g, n));
        od;

        # Compute invariant key
        inv := ComputeInvariantKey(H, n);

        # Write to checkpoint file
        if i > 1 then
            AppendTo(outputFile, ",\n");
        fi;
        AppendTo(outputFile, "  rec(gens := ", genImages,
                 ", inv := ", inv,
                 ", source := \"", label, "\")");

        # Progress and GC
        if i mod 500 = 0 then
            Print("    Saved ", i, "/", Length(reps), " (",
                  Int(100*i/Length(reps)), "%)\n");
            GASMAN("collect");
        fi;
    od;

    AppendTo(outputFile, "\n];\n");

    elapsed := Runtime() - startTime;
    Print("  Complete: ", Length(reps), " subgroups saved in ",
          Int(elapsed/1000), " seconds\n\n");

    return Length(reps);
end;

###############################################################################
# Load subgroups from a worker output file
###############################################################################

LoadMaxSubResults := function(filename, n)
    local results, data, entry, H, gens, g, imgList, inv, i, count;

    Read(filename);

    # maxsub_results should now be defined
    if not IsBound(maxsub_results) then
        Print("ERROR: No maxsub_results found in ", filename, "\n");
        return [];
    fi;

    count := Length(maxsub_results);
    results := [];
    for i in [1..count] do
        entry := maxsub_results[i];
        # Reconstruct group from generator images
        gens := [];
        for imgList in entry.gens do
            Add(gens, PermList(imgList));
        od;

        if Length(gens) = 0 then
            H := Group(());
        else
            H := Group(gens);
        fi;

        # Extend invariant key if old format (7 fields) - just add derived subgroup size
        if Length(entry.inv) < 8 then
            inv := ShallowCopy(entry.inv);
            Add(inv, Size(DerivedSubgroup(H)));
        else
            inv := entry.inv;
        fi;

        Add(results, rec(group := H, inv := inv, source := entry.source));

        if i mod 5000 = 0 then
            Print("    Loaded ", i, "/", count, "\n");
            GASMAN("collect");
        fi;
    od;

    # Clear the global variable
    Unbind(maxsub_results);
    GASMAN("collect");

    return results;
end;

###############################################################################
# Deduplication: remove S_n-conjugates using invariant bucketing
#
# Algorithm:
# 1. Bucket all subgroups by invariant key
# 2. Singleton buckets: unique representative, add directly
# 3. Multi-group buckets: test pairwise S_n-conjugacy
###############################################################################

DeduplicateByConjugacy := function(allSubs, n)
    local Sn, buckets, entry, key, reps, bucketKey, bucket, bucketReps,
          H, found, rep, count, totalBuckets, singletons,
          multiGroups, startTime, bucketNum, elapsed, totalTests,
          bucketKeys, sizes, perm, i, checkpointFile, bucketStartTime,
          totalGroupsInMulti, groupsProcessed;

    startTime := Runtime();
    Sn := SymmetricGroup(n);

    Print("=== Deduplication Phase ===\n");
    Print("  Total subgroups from all workers: ", Length(allSubs), "\n");

    # Step 1: Bucket by invariant key
    Print("  Bucketing by invariant key...\n");
    buckets := rec();
    for entry in allSubs do
        key := InvariantKeyToString(entry.inv);
        if not IsBound(buckets.(key)) then
            buckets.(key) := [];
        fi;
        Add(buckets.(key), entry.group);
    od;

    totalBuckets := Length(RecNames(buckets));
    bucketKeys := RecNames(buckets);
    Print("  ", totalBuckets, " distinct invariant buckets\n");

    # Count singletons vs multi-group buckets and total groups in multi-buckets
    singletons := 0;
    multiGroups := 0;
    totalGroupsInMulti := 0;
    for bucketKey in bucketKeys do
        if Length(buckets.(bucketKey)) = 1 then
            singletons := singletons + 1;
        else
            multiGroups := multiGroups + 1;
            totalGroupsInMulti := totalGroupsInMulti + Length(buckets.(bucketKey));
        fi;
    od;
    Print("  Singleton buckets (no conjugacy test needed): ", singletons, "\n");
    Print("  Multi-group buckets (need conjugacy testing): ", multiGroups, "\n");
    Print("  Total groups in multi-group buckets: ", totalGroupsInMulti, "\n");

    # Sort bucket keys by bucket size (smallest first for fast progress)
    sizes := List(bucketKeys, k -> Length(buckets.(k)));
    perm := Sortex(sizes);
    bucketKeys := Permuted(bucketKeys, perm);

    # Report largest buckets
    Print("\n  Largest 20 buckets:\n");
    for i in [Maximum(1, Length(bucketKeys)-19)..Length(bucketKeys)] do
        Print("    ", Length(buckets.(bucketKeys[i])),
              " groups: ", bucketKeys[i], "\n");
    od;
    Print("\n");

    # Checkpoint file for incremental saving
    checkpointFile := Concatenation(
        "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/maxsub_output/dedup_checkpoint.g");

    # Step 2: Process each bucket
    reps := [];
    bucketNum := 0;
    count := 0;
    totalTests := 0;
    groupsProcessed := 0;

    for bucketKey in bucketKeys do
        bucket := buckets.(bucketKey);
        bucketNum := bucketNum + 1;

        if Length(bucket) = 1 then
            # Singleton - guaranteed unique
            Add(reps, bucket[1]);
            count := count + 1;
        else
            # Multi-group: pairwise S_n-conjugacy test within bucket
            bucketStartTime := Runtime();

            if Length(bucket) > 20 then
                Print("  Bucket ", bucketNum, "/", totalBuckets,
                      ": ", Length(bucket), " groups, key=", bucketKey, "\n");
            fi;

            bucketReps := [];
            for H in bucket do
                found := false;
                for rep in bucketReps do
                    totalTests := totalTests + 1;
                    if RepresentativeAction(Sn, H, rep) <> fail then
                        found := true;
                        break;
                    fi;
                od;
                if not found then
                    Add(bucketReps, H);
                fi;
            od;

            groupsProcessed := groupsProcessed + Length(bucket);

            if Length(bucket) > 20 then
                elapsed := Runtime() - bucketStartTime;
                Print("    -> ", Length(bucketReps), " unique in ",
                      Int(elapsed/1000), "s (",
                      Length(bucket) - Length(bucketReps), " duplicates)\n");
            fi;

            Append(reps, bucketReps);
            count := count + Length(bucketReps);
        fi;

        # Periodic progress every 500 buckets
        if bucketNum mod 500 = 0 then
            elapsed := Runtime() - startTime;
            Print("  Progress: ", bucketNum, "/", totalBuckets,
                  " buckets, ", count, " unique, ",
                  totalTests, " conjugacy tests, ",
                  groupsProcessed, "/", totalGroupsInMulti, " groups processed (",
                  Int(elapsed/1000), "s)\n");
            GASMAN("collect");
        fi;
    od;

    elapsed := Runtime() - startTime;
    Print("\n  Deduplication complete: ", count, " unique conjugacy classes\n");
    Print("  Total conjugacy tests: ", totalTests, "\n");
    Print("  Time: ", Int(elapsed/1000), " seconds\n");

    return reps;
end;

###############################################################################
# Save final results in the conjugacy_cache format
###############################################################################

SaveConjugacyClasses := function(reps, n, outputFile, elapsed)
    local i, H, gens, g, genImages, imgList;

    Print("Saving ", Length(reps), " conjugacy classes to ", outputFile, "\n");

    PrintTo(outputFile, "# Conjugacy class representatives for S", n, "\n");
    AppendTo(outputFile, "# ", Length(reps), " subgroups\n");
    AppendTo(outputFile, "# Computed via maximal subgroup decomposition\n");
    AppendTo(outputFile, "# Computation time: ", Int(elapsed/1000), " seconds\n");
    AppendTo(outputFile, "return [\n");

    for i in [1..Length(reps)] do
        H := reps[i];
        gens := GeneratorsOfGroup(H);

        # Convert generators to image lists
        genImages := [];
        for g in gens do
            Add(genImages, ListPerm(g, n));
        od;

        if i > 1 then
            AppendTo(outputFile, ",\n");
        fi;
        AppendTo(outputFile, "  ", genImages);

        if i mod 5000 = 0 then
            Print("  Saved ", i, "/", Length(reps), "\n");
        fi;
    od;

    AppendTo(outputFile, "\n];\n");
    Print("  Save complete.\n");
end;

###############################################################################
# Embed S13 subgroups into S14 (for the S_1 x S_13 worker)
#
# S13 subgroups act on {1,...,13}. In S_1 x S_13, S_13 acts on {2,...,14}.
# We shift each S13 subgroup by +1 on all points.
###############################################################################

EmbedS13SubgroupsAsS1xS13 := function(cacheFile, n)
    local data, results, genImages, gens, g, newGens, newGenImages,
          imgList, newImg, j, H, inv, i;

    Print("Loading S13 cache from ", cacheFile, "\n");
    data := ReadAsFunction(cacheFile)();
    Print("  Loaded ", Length(data), " S13 conjugacy class reps\n");

    results := [];

    for i in [1..Length(data)] do
        genImages := data[i];

        # Shift each generator: point p -> p+1
        newGenImages := [];
        for imgList in genImages do
            newImg := [1];  # Point 1 is fixed (S_1 factor)
            for j in [1..Length(imgList)] do
                Add(newImg, imgList[j] + 1);
            od;
            Add(newGenImages, newImg);
        od;

        # Reconstruct as permutation group
        newGens := List(newGenImages, PermList);
        if Length(newGens) = 0 then
            H := Group(());
        else
            H := Group(newGens);
        fi;

        inv := ComputeInvariantKey(H, n);
        Add(results, rec(group := H, inv := inv, source := "intrans_1x13"));

        if i mod 2000 = 0 then
            Print("  Processed ", i, "/", Length(data), " S13 subgroups\n");
            GASMAN("collect");
        fi;
    od;

    Print("  Embedded ", Length(results), " subgroups as S1xS13 subgroups\n");
    return results;
end;

Print("compute_s14_maxsub.g loaded successfully.\n");
