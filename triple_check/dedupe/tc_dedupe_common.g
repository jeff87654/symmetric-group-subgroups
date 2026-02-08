# Triple-Check Deduplication - Shared GAP Library
# Loaded by all worker scripts via Read()
#
# Key features:
# - Group reconstruction from string generators (clean file format)
# - factorGens stores generators for ALL direct product factors (positional)
# - CompareByFactorsV3 with bipartite matching of ALL factors
# - Three dedup functions: DP-only, regular, 2-groups
# - Verbose progress logging

#===================================================================
# Logging
#===================================================================

FormattedTime := function()
    local t, mins, secs;
    t := Runtime();
    mins := Int(t / 60000);
    secs := Int((t mod 60000) / 1000);
    return Concatenation(String(mins), "m", String(secs), "s");
end;

LogProgress := function(msg)
    Print("[", FormattedTime(), "] ", msg, "\n");
end;

#===================================================================
# Group Reconstruction
#===================================================================

# Reconstruct a GAP group from a list of generator strings
ReconstructGroupFromStrings := function(genStrings)
    local gens, s, p;
    gens := [];
    for s in genStrings do
        p := EvalString(s);
        if p = fail then
            Print("WARNING: EvalString failed for: ", s, "\n");
            return fail;
        fi;
        Add(gens, p);
    od;
    if Length(gens) = 0 then return Group(()); fi;
    return Group(gens);
end;

#===================================================================
# Cached Group Access
#===================================================================

GROUP_CACHE := rec();;

# Get or construct the full group from a data record, with caching
GetGroupCached := function(dataRec)
    local key, g;
    key := String(dataRec.index);
    if not IsBound(GROUP_CACHE.(key)) then
        g := ReconstructGroupFromStrings(dataRec.generators);
        GROUP_CACHE.(key) := g;
    fi;
    return GROUP_CACHE.(key);
end;

# Evict a group from cache to free memory
EvictGroupCache := function(idx)
    local key;
    key := String(idx);
    if IsBound(GROUP_CACHE.(key)) then
        Unbind(GROUP_CACHE.(key));
    fi;
end;

#===================================================================
# Factor Helpers (factorGens stores ALL factor generators, positional)
#===================================================================

# Get ALL factor groups from a data record.
# factorGens[i] is a list of generator strings for the i-th factor.
# Returns list of [group, order] pairs, or [] if none.
GetAllFactorGroups := function(dataRec)
    local result, i, g;
    if not IsBound(dataRec.factorGens) then return []; fi;
    result := [];
    for i in [1..Length(dataRec.factorGens)] do
        g := ReconstructGroupFromStrings(dataRec.factorGens[i]);
        if g <> fail then
            Add(result, [g, Size(g)]);
        fi;
    od;
    return result;
end;

# Cache for factor groups to avoid repeated reconstruction
FACTOR_CACHE := rec();;

GetAllFactorGroupsCached := function(dataRec)
    local key;
    key := Concatenation("f", String(dataRec.index));
    if not IsBound(FACTOR_CACHE.(key)) then
        FACTOR_CACHE.(key) := GetAllFactorGroups(dataRec);
    fi;
    return FACTOR_CACHE.(key);
end;

#===================================================================
# CompareByFactorsV3 - bipartite matching of ALL factors
#===================================================================

# Returns: true (isomorphic), false (not isomorphic), fail (cannot determine)
CompareByFactorsV3 := function(rec1, rec2)
    local pairs1, pairs2, matched, i, j, g1, g2, foundMatch, result;

    # Both must be direct products to use factor comparison
    if not rec1.isDirectProduct or not rec2.isDirectProduct then
        return fail;
    fi;

    # Must have same number of factors
    if rec1.numFactors <> rec2.numFactors then
        return false;
    fi;

    # Quick check: sorted factor orders must match
    # (factorOrders are already co-sorted with factorGens)
    if rec1.factorOrders <> rec2.factorOrders then
        return false;
    fi;

    # Get all factor groups
    pairs1 := GetAllFactorGroupsCached(rec1);
    pairs2 := GetAllFactorGroupsCached(rec2);

    if Length(pairs1) = 0 or Length(pairs2) = 0 then return fail; fi;
    if Length(pairs1) <> Length(pairs2) then return false; fi;

    # Bipartite matching of ALL factors
    matched := [];
    for i in [1..Length(pairs1)] do
        g1 := pairs1[i][1];
        foundMatch := false;

        for j in [1..Length(pairs2)] do
            if j in matched then continue; fi;
            g2 := pairs2[j][1];

            # Size check first (fast)
            if Size(g1) <> Size(g2) then continue; fi;

            # Isomorphism test
            result := CALL_WITH_CATCH(IsomorphismGroups, [g1, g2]);
            if result[1] = true and result[2] <> fail then
                Add(matched, j);
                foundMatch := true;
                break;
            fi;
        od;

        if not foundMatch then return false; fi;
    od;

    return true;
end;

#===================================================================
# Deduplication Functions
#===================================================================

# Deduplicate a bucket of DP-only groups (fast path: CompareByFactorsV3 only)
# Falls back to full IsomorphismGroups only if CompareByFactorsV3 returns fail
DeduplicateBucketDP := function(indices, dataByIndex)
    local reps, i, j, found, rec1, rec2, g1, g2, factorResult, startT, elapsed;

    if Length(indices) = 0 then return []; fi;
    if Length(indices) = 1 then return [indices[1]]; fi;

    reps := [indices[1]];
    for i in [2..Length(indices)] do
        found := false;
        rec1 := dataByIndex.(indices[i]);
        startT := Runtime();

        for j in [1..Length(reps)] do
            rec2 := dataByIndex.(reps[j]);

            # Try factor comparison (should work for all DP groups)
            factorResult := CompareByFactorsV3(rec1, rec2);
            if factorResult = true then
                found := true;
                if Length(indices) <= 50 then
                    elapsed := Runtime() - startT;
                    Print("    Group ", i, "/", Length(indices),
                          " (idx=", indices[i], "): DUPLICATE of rep ",
                          j, " (idx=", reps[j], ") via FactorV3 (",
                          elapsed, "ms)\n");
                fi;
                break;
            elif factorResult = false then
                continue;
            fi;

            # Unexpected: DP group but FactorV3 returned fail
            # Fall back to full isomorphism test
            g1 := GetGroupCached(rec1);
            g2 := GetGroupCached(rec2);
            if IsomorphismGroups(g1, g2) <> fail then
                found := true;
                if Length(indices) <= 50 then
                    elapsed := Runtime() - startT;
                    Print("    Group ", i, "/", Length(indices),
                          " (idx=", indices[i], "): DUPLICATE of rep ",
                          j, " (idx=", reps[j], ") via fullIso (",
                          elapsed, "ms)\n");
                fi;
                break;
            fi;
        od;

        if not found then
            Add(reps, indices[i]);
            if Length(indices) <= 50 then
                elapsed := Runtime() - startT;
                Print("    Group ", i, "/", Length(indices),
                      " (idx=", indices[i], "): NEW REP (total: ",
                      Length(reps), ") (", elapsed, "ms)\n");
            fi;
        fi;
    od;
    return reps;
end;

# Deduplicate a bucket of regular groups (CompareByFactorsV3 + IsomorphismGroups fallback)
DeduplicateBucket := function(indices, dataByIndex)
    local reps, i, j, found, rec1, rec2, g1, g2, factorResult, startT, elapsed;

    if Length(indices) = 0 then return []; fi;
    if Length(indices) = 1 then return [indices[1]]; fi;

    reps := [indices[1]];
    for i in [2..Length(indices)] do
        found := false;
        rec1 := dataByIndex.(indices[i]);
        startT := Runtime();

        for j in [1..Length(reps)] do
            rec2 := dataByIndex.(reps[j]);

            # Try factor comparison first (fast path for DP pairs)
            factorResult := CompareByFactorsV3(rec1, rec2);
            if factorResult = true then
                found := true;
                if Length(indices) <= 30 then
                    elapsed := Runtime() - startT;
                    Print("    Group ", i, "/", Length(indices),
                          " (idx=", indices[i], "): DUPLICATE of rep ",
                          j, " via FactorV3 (", elapsed, "ms)\n");
                fi;
                break;
            elif factorResult = false then
                continue;
            fi;

            # Fall back to full isomorphism test
            g1 := GetGroupCached(rec1);
            g2 := GetGroupCached(rec2);
            if IsomorphismGroups(g1, g2) <> fail then
                found := true;
                if Length(indices) <= 30 then
                    elapsed := Runtime() - startT;
                    Print("    Group ", i, "/", Length(indices),
                          " (idx=", indices[i], "): DUPLICATE of rep ",
                          j, " via fullIso (", elapsed, "ms)\n");
                fi;
                break;
            fi;
        od;

        if not found then
            Add(reps, indices[i]);
            if Length(indices) <= 30 then
                elapsed := Runtime() - startT;
                Print("    Group ", i, "/", Length(indices),
                      " (idx=", indices[i], "): NEW REP (total: ",
                      Length(reps), ") (", elapsed, "ms)\n");
            fi;
        fi;
    od;
    return reps;
end;

# Deduplicate a bucket of 2-groups using ANUPQ
DeduplicateBucket2Groups := function(indices, dataByIndex)
    local reps, i, j, found, rec1, rec2, g1, g2, factorResult,
          exp1, exp2, pc1, pc2, startT, elapsed;

    if Length(indices) = 0 then return []; fi;
    if Length(indices) = 1 then return [indices[1]]; fi;

    reps := [indices[1]];
    for i in [2..Length(indices)] do
        found := false;
        rec1 := dataByIndex.(indices[i]);
        g1 := GetGroupCached(rec1);
        exp1 := Exponent(g1);
        startT := Runtime();

        for j in [1..Length(reps)] do
            rec2 := dataByIndex.(reps[j]);

            # Try factor comparison first (fast path for DP pairs)
            factorResult := CompareByFactorsV3(rec1, rec2);
            if factorResult = true then
                found := true;
                if Length(indices) <= 30 then
                    elapsed := Runtime() - startT;
                    Print("    Group ", i, "/", Length(indices),
                          " (idx=", indices[i], "): DUPLICATE via FactorV3 (",
                          elapsed, "ms)\n");
                fi;
                break;
            elif factorResult = false then
                continue;
            fi;

            # Exponent check (fast discriminant)
            g2 := GetGroupCached(rec2);
            exp2 := Exponent(g2);
            if exp1 <> exp2 then continue; fi;

            # Fall back to ANUPQ p-group isomorphism test
            pc1 := Image(IsomorphismPcGroup(g1));
            pc2 := Image(IsomorphismPcGroup(g2));
            if IsIsomorphicPGroup(pc1, pc2) then
                found := true;
                if Length(indices) <= 30 then
                    elapsed := Runtime() - startT;
                    Print("    Group ", i, "/", Length(indices),
                          " (idx=", indices[i], "): DUPLICATE via ANUPQ (",
                          elapsed, "ms)\n");
                fi;
                break;
            fi;
        od;

        if not found then
            Add(reps, indices[i]);
            if Length(indices) <= 30 then
                elapsed := Runtime() - startT;
                Print("    Group ", i, "/", Length(indices),
                      " (idx=", indices[i], "): NEW REP (total: ",
                      Length(reps), ") (", elapsed, "ms)\n");
            fi;
        fi;
    od;
    return reps;
end;

Print("tc_dedupe_common.g loaded successfully\n");
