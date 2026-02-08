###############################################################################
#
# compute_s15_maxsub.g - Core GAP functions for S15 maximal subgroup approach
#
# Computes A000638(15) = 159,129 conjugacy classes of subgroups of S15
# by decomposing through maximal subgroups.
#
# Reuses all generic functions from compute_s14_maxsub.g:
#   ComputeOrbitStructure, ComputeInvariantKey, InvariantKeyToString,
#   BuildIntransitiveMaxSub, BuildWreathMaxSub, EnumerateMaximalSubgroups,
#   ComputeSubgroupsOfMaxSub, LoadMaxSubResults, DeduplicateByConjugacy,
#   SaveConjugacyClasses
#
# Adds:
#   EmbedPreviousSnSubgroups - generalized version that loads any S_{n-1}
#   cache and shifts by +1 to act on {2,...,n}
#
###############################################################################

MAXSUB_BASE := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups";
MAXSUB_OUTPUT := Concatenation(MAXSUB_BASE, "/maxsub_output_s15");
MAXSUB_CACHE := Concatenation(MAXSUB_BASE, "/conjugacy_cache");

# Load all generic functions from S14 script
Read(Concatenation(MAXSUB_BASE, "/compute_s14_maxsub.g"));

# Override output/cache paths (S14 script set them for S14)
MAXSUB_OUTPUT := Concatenation(MAXSUB_BASE, "/maxsub_output_s15");

###############################################################################
# Embed S_{n-1} subgroups into S_n as S_1 x S_{n-1}
#
# S_{n-1} subgroups act on {1,...,n-1}. In S_1 x S_{n-1},
# S_{n-1} acts on {2,...,n}. We shift each subgroup by +1 on all points.
#
# Parameters:
#   cacheFile - path to the S_{n-1} cache file (returns list of gen images)
#   n         - degree of the ambient symmetric group S_n
#   prevN     - degree of the cached symmetric group (n-1)
#   sourceLabel - label for the source (e.g., "intrans_1x14")
###############################################################################

EmbedPreviousSnSubgroups := function(cacheFile, n, prevN, sourceLabel)
    local data, results, genImages, gens, g, newGens, newGenImages,
          imgList, newImg, j, H, inv, i;

    Print("Loading S", prevN, " cache from ", cacheFile, "\n");
    data := ReadAsFunction(cacheFile)();
    Print("  Loaded ", Length(data), " S", prevN, " conjugacy class reps\n");

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
            # Pad with identity mapping if needed to reach degree n
            while Length(newImg) < n do
                Add(newImg, Length(newImg) + 1);
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
        Add(results, rec(group := H, inv := inv, source := sourceLabel));

        if i mod 2000 = 0 then
            Print("  Processed ", i, "/", Length(data), " S", prevN, " subgroups\n");
            GASMAN("collect");
        fi;
    od;

    Print("  Embedded ", Length(results), " subgroups as ", sourceLabel, " subgroups\n");
    return results;
end;

Print("compute_s15_maxsub.g loaded successfully.\n");
