# Mixed worker with proof chain library integration
# Set MIXED_WORKER_ID before reading this file
#
# For each bucket:
# 1. Compute RPF fingerprint for sub-bucketing
# 2. Within each sub-bucket, try ProofChainIso
# 3. Fallback: allquot cocycle (10 min timeout)
# 4. Last resort: session IG (no timeout)

if not IsBound(MIXED_WORKER_ID) then MIXED_WORKER_ID := 1; fi;

_MW_BASE := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s17_dedupe/";;

# Load proof chain library (all 13 quotient orders)
Read(Concatenation(_MW_BASE, "proof_chain_lib.g"));

# Load bucket assignments
Read(Concatenation(_MW_BASE, "buckets/remaining_mixed_", String(MIXED_WORKER_ID), ".g"));

# Load S17 subgroup generators
Print("Loading S17 subgroup generators...\n");
_MW_genLists := ReadAsFunction(
  Concatenation(_MW_BASE, "s17_subgroups_cycles.g"))();;
Print("Loaded ", Length(_MW_genLists), " entries\n\n");

_MW_proofFile := Concatenation(_MW_BASE, "mixed_proofs_w", String(MIXED_WORKER_ID), ".g");;
PrintTo(_MW_proofFile, Concatenation("# Mixed worker ", String(MIXED_WORKER_ID), " proofs\n\n"));;

_MW_logFile := Concatenation(_MW_BASE, "mixed_log_w", String(MIXED_WORKER_ID), ".txt");;
PrintTo(_MW_logFile, Concatenation("# Mixed worker ", String(MIXED_WORKER_ID), " log\n\n"));;

# Invariant cache file
_MW_invFile := Concatenation(_MW_BASE, "invariant_log_w", String(MIXED_WORKER_ID), ".txt");;
PrintTo(_MW_invFile, "# Invariant cache - worker ", MIXED_WORKER_ID, "\n");;
AppendTo(_MW_invFile, "# Format: index|bucketKey|nIrr|invC|rpLen|gzId|centerSize|exponent\n\n");;

# Load existing invariant cache to avoid recomputing
Print("Loading invariant cache...\n");;
_MW_invCache := rec();;
_MW_invCacheCount := 0;;
_mw_cacheFile := Concatenation(_MW_BASE, "invariant_log_master.txt");;
_mw_cacheLines := StringFile(_mw_cacheFile);;
if _mw_cacheLines <> fail then
  # Join continuation lines then parse
  _mw_cacheLines := SplitString(_mw_cacheLines, "\n\r");;
  _mw_joined := [];;
  for _mw_cl in _mw_cacheLines do
    if Length(_mw_cl) = 0 then continue; fi;
    if _mw_cl[1] in "0123456789" then
      Add(_mw_joined, _mw_cl);;
    elif Length(_mw_joined) > 0 then
      _mw_joined[Length(_mw_joined)] := Concatenation(
        _mw_joined[Length(_mw_joined)], _mw_cl);;
    fi;
  od;
  for _mw_cl in _mw_joined do
    _mw_parts := SplitString(_mw_cl, "|");;
    if Length(_mw_parts) < 8 then continue; fi;
    _mw_idx := Int(_mw_parts[1]);;
    if _mw_idx = fail then continue; fi;
    _mw_nIrr := Int(_mw_parts[3]);;
    _mw_invC := Int(_mw_parts[4]);;
    _mw_rpLen := Int(_mw_parts[5]);;
    _mw_cenSz := Int(_mw_parts[7]);;
    _mw_expo := Int(_mw_parts[8]);;
    if _mw_nIrr = fail or _mw_invC = fail or _mw_rpLen = fail then continue; fi;
    if _mw_cenSz = fail then _mw_cenSz := 0; fi;
    if _mw_expo = fail then _mw_expo := 0; fi;
    _MW_invCache.(String(_mw_idx)) := rec(
      nIrr := _mw_nIrr, invC := _mw_invC, rpLen := _mw_rpLen,
      gzId := _mw_parts[6], centerSize := _mw_cenSz,
      exponent := _mw_expo);;
    _MW_invCacheCount := _MW_invCacheCount + 1;;
  od;
fi;
Print("Loaded ", _MW_invCacheCount, " cached invariants\n\n");;

# Helper: get fingerprint from cache or compute fresh
_MW_GetFingerprint := function(idx, G, bucketKey)
  local fp, idxStr, cached;
  idxStr := String(idx);;
  if IsBound(_MW_invCache.(idxStr)) then
    cached := _MW_invCache.(idxStr);;
    return rec(nIrr := cached.nIrr, invC := cached.invC,
               rpLen := cached.rpLen, gzId := cached.gzId,
               centerSize := cached.centerSize, exponent := cached.exponent,
               fromCache := true);
  fi;
  # Compute fresh
  fp := ProofChainFingerprint(G);;
  fp.centerSize := Size(Center(G));;
  fp.exponent := Exponent(G);;
  fp.fromCache := false;;
  # Log to cache file
  AppendTo(_MW_invFile, idx, "|", bucketKey, "|",
    fp.nIrr, "|", fp.invC, "|", fp.rpLen, "|", fp.gzId, "|",
    fp.centerSize, "|", fp.exponent, "\n");;
  return fp;
end;;

# Allquot fallback
_MW_GetQuotients := function(G)
  local cen, invols, result, z, blocks, act, Q, ker;
  cen := Center(G);
  invols := Filtered(Elements(cen), x -> Order(x) = 2);
  result := [];
  for z in invols do
    blocks := List(Orbits(Group([z]), MovedPoints(G)), Set);
    act := ActionHomomorphism(G, blocks, OnSets);
    Q := Image(act);
    ker := Kernel(act);
    Add(result, rec(invol:=z, act:=act, quot:=Q, ker:=ker,
                    kerElts:=Elements(ker)));
  od;
  return result;
end;

# Allquot variant that uses proof chain on quotients instead of IG
_MW_SolveAllQuotChain := function(G_dup, G_rep, gens, repQuots, timeLimit)
  local dupQuots, dq, rq, baseImages, kerElts, nKer,
        combo, j, k, h, imgs, ig, gb, nGens, t0,
        dupSpdr, dupQSmall, dupMatch, repSpdr, repQSmall, repMatch,
        dupProof, repProof, autQ, autList, alphaIso, aIdx, alpha,
        hS17, hRep, hRepS17, quotOrder, groups;
  nGens := Length(gens); t0 := Runtime();
  dupQuots := _MW_GetQuotients(G_dup);
  for dq in dupQuots do
    if Runtime()-t0 > timeLimit then return fail; fi;
    for rq in repQuots do
      if Runtime()-t0 > timeLimit then return fail; fi;
      if Size(dq.quot) <> Size(rq.quot) then continue; fi;
      quotOrder := Size(dq.quot);
      if not IsBound(_PCL_Groups.(String(quotOrder))) then continue; fi;
      groups := _PCL_Groups.(String(quotOrder));

      # SPDR + S16 class lookup instead of IG
      dupSpdr := SmallerDegreePermutationRepresentation(dq.quot);
      dupQSmall := Image(dupSpdr);
      dupMatch := _PCL_FindClass(dupQSmall, quotOrder);
      if dupMatch = fail then continue; fi;

      repSpdr := SmallerDegreePermutationRepresentation(rq.quot);
      repQSmall := Image(repSpdr);
      repMatch := _PCL_FindClass(repQSmall, quotOrder);
      if repMatch = fail then continue; fi;

      if dupMatch.type <> repMatch.type then continue; fi;

      # Chain through proofs
      dupProof := _PCL_ApplyProof(dupMatch.classIdx, quotOrder);
      repProof := _PCL_ApplyProof(repMatch.classIdx, quotOrder);
      if dupProof = fail and repProof = fail then
        if dupMatch.classIdx = repMatch.classIdx then
          dupProof := rec(hom:=IdentityMapping(
            groups.(Concatenation("g", String(dupMatch.classIdx)))),
            repIdx:=dupMatch.classIdx);
          repProof := dupProof;
        else continue; fi;
      elif dupProof = fail then
        if repProof.repIdx = dupMatch.classIdx then
          dupProof := rec(hom:=IdentityMapping(
            groups.(Concatenation("g", String(dupMatch.classIdx)))),
            repIdx:=dupMatch.classIdx);
        else continue; fi;
      elif repProof = fail then
        if dupProof.repIdx = repMatch.classIdx then
          repProof := rec(hom:=IdentityMapping(
            groups.(Concatenation("g", String(repMatch.classIdx)))),
            repIdx:=repMatch.classIdx);
        else continue; fi;
      fi;
      if dupProof.repIdx <> repProof.repIdx then continue; fi;

      kerElts := rq.kerElts; nKer := Length(kerElts);

      # Aut twists
      autQ := AutomorphismGroup(repQSmall);
      autList := [IdentityMapping(repQSmall)];
      Append(autList, GeneratorsOfGroup(autQ));
      for aIdx in GeneratorsOfGroup(autQ) do
        for alpha in GeneratorsOfGroup(autQ) do
          Add(autList, aIdx * alpha); od; od;
      autList := Set(autList);

      for alphaIso in autList do
        if Runtime()-t0 > timeLimit then return fail; fi;
        baseImages := [];
        for j in [1..nGens] do
          h := Image(dupSpdr, Image(dq.act, gens[j]));
          hS17 := h^dupMatch.sigma;
          hRep := Image(dupProof.hom, hS17);
          hRepS17 := PreImagesRepresentative(repProof.hom, hRep);
          h := hRepS17^(repMatch.sigma^-1);
          h := Image(alphaIso, h);
          if not h in repQSmall then break; fi;
          h := PreImagesRepresentative(repSpdr, h);
          Add(baseImages, PreImagesRepresentative(rq.act, h));
        od;
        if Length(baseImages) <> nGens then continue; fi;

        combo := ListWithIdenticalEntries(nGens, 1);
        while true do
          if Runtime()-t0 > timeLimit then break; fi;
          imgs := [];
          for k in [1..nGens] do Add(imgs, baseImages[k]*kerElts[combo[k]]); od;
          ig := Group(imgs);
          if Size(ig) = Size(G_rep) and IsSubgroup(G_rep, ig) then
            gb := GroupHomomorphismByImages(G_dup, G_rep, gens, imgs);
            if gb <> fail then return rec(images:=imgs, method:="allQuotChain",
              dt:=Runtime()-t0); fi;
          fi;
          j := nGens;
          while j >= 1 do combo[j]:=combo[j]+1;
            if combo[j]<=nKer then break; fi; combo[j]:=1; j:=j-1; od;
          if j = 0 then break; fi;
        od;
      od;
    od;
  od;
  return fail;
end;

_MW_SolveAllQuot := function(G_dup, G_rep, gens, repQuots, timeLimit)
  local dupQuots, dq, rq, iso, baseImages, kerElts, nKer,
        combo, j, k, h, imgs, ig, gb, nGens, t0;
  nGens := Length(gens); t0 := Runtime();
  dupQuots := _MW_GetQuotients(G_dup);
  for dq in dupQuots do
    if Runtime()-t0 > timeLimit then return fail; fi;
    for rq in repQuots do
      if Runtime()-t0 > timeLimit then return fail; fi;
      if Size(dq.quot) <> Size(rq.quot) then continue; fi;
      iso := IsomorphismGroups(dq.quot, rq.quot);
      if iso = fail then continue; fi;
      kerElts := rq.kerElts; nKer := Length(kerElts);
      baseImages := [];
      for j in [1..nGens] do
        h := Image(iso, Image(dq.act, gens[j]));
        Add(baseImages, PreImagesRepresentative(rq.act, h));
      od;
      combo := ListWithIdenticalEntries(nGens, 1);
      while true do
        if Runtime()-t0 > timeLimit then return fail; fi;
        imgs := [];
        for k in [1..nGens] do Add(imgs, baseImages[k]*kerElts[combo[k]]); od;
        ig := Group(imgs);
        if Size(ig) = Size(G_rep) and IsSubgroup(G_rep, ig) then
          gb := GroupHomomorphismByImages(G_dup, G_rep, gens, imgs);
          if gb <> fail then return rec(images:=imgs, method:="allQuotCocycle",
            dt:=Runtime()-t0); fi;
        fi;
        j := nGens;
        while j >= 1 do combo[j]:=combo[j]+1;
          if combo[j]<=nKer then break; fi; combo[j]:=1; j:=j-1; od;
        if j = 0 then break; fi;
      od;
    od;
  od;
  return fail;
end;

# Process one bucket
_MW_SolveBucket := function(bucketRec)
  local indices, groups, gens, order, nGroups, subBuckets,
        fpCache, ii, G, fp, key, found, jj,
        sb, repIdx, repPos, G_rep, repQuots,
        result, dupIdx, t0, nOK, nFail, method;

  indices := bucketRec.indices;
  nGroups := Length(indices);
  if nGroups <= 1 then return; fi;

  order := Size(Group(_MW_genLists[indices[1]]));
  # Parse aut size from bucket key (handle "aut=245760 sub=..." suffix)
  _mw_autPos := PositionSublist(bucketRec.key, "aut=");;
  if _mw_autPos <> fail then
    _mw_autStr := bucketRec.key{[_mw_autPos+4..Length(bucketRec.key)]};;
    _mw_spPos := Position(_mw_autStr, ' ');;
    if _mw_spPos <> fail then
      _mw_autStr := _mw_autStr{[1.._mw_spPos-1]};;
    fi;
    _mw_autSize := Int(_mw_autStr);;
    if _mw_autSize = fail then _mw_autSize := 0;; fi;
  else
    _mw_autSize := 0;;
  fi;
  Print("Bucket [", bucketRec.key, "] ", nGroups, " groups, order ", order, "\n");

  # Build groups
  groups := List(indices, idx -> Group(_MW_genLists[idx]));
  gens := List(indices, idx -> _MW_genLists[idx]);

  # Sub-bucket by RPF fingerprint
  _mw_nCached := 0;; _mw_nComputed := 0;;
  if nGroups <= 2 then
    subBuckets := [rec(indices := indices, groups := groups, gens := gens)];
    for ii in [1..nGroups] do
      fp := _MW_GetFingerprint(indices[ii], groups[ii], bucketRec.key);
      if fp.fromCache then _mw_nCached := _mw_nCached+1;
      else _mw_nComputed := _mw_nComputed+1; fi;
    od;
  else
    Print("  Computing RPF fingerprints...\n");
    subBuckets := [];
    for ii in [1..nGroups] do
      fp := _MW_GetFingerprint(indices[ii], groups[ii], bucketRec.key);
      if fp.fromCache then _mw_nCached := _mw_nCached+1;
      else _mw_nComputed := _mw_nComputed+1; fi;
      key := Concatenation(String(fp.nIrr), "_", String(fp.invC), "_", String(fp.rpLen), "_", String(fp.gzId));
      found := false;
      for jj in [1..Length(subBuckets)] do
        if subBuckets[jj].key = key then
          Add(subBuckets[jj].indices, indices[ii]);
          Add(subBuckets[jj].groups, groups[ii]);
          Add(subBuckets[jj].gens, gens[ii]);
          found := true; break;
        fi;
      od;
      if not found then
        Add(subBuckets, rec(key := key,
          indices := [indices[ii]], groups := [groups[ii]], gens := [gens[ii]]));
      fi;
    od;
    if Length(subBuckets) > 1 then
      Print("  Split into ", Length(subBuckets), " sub-buckets\n");
    fi;
  fi;
  if _mw_nCached > 0 then
    Print("  Fingerprints: ", _mw_nCached, " cached, ", _mw_nComputed, " computed\n");
  fi;

  # Solve each sub-bucket
  nOK := 0; nFail := 0;

  for sb in subBuckets do
    if Length(sb.indices) <= 1 then continue; fi;

    repIdx := sb.indices[1];
    G_rep := sb.groups[1];
    repQuots := fail;

    for ii in [2..Length(sb.indices)] do
      dupIdx := sb.indices[ii];
      t0 := Runtime();
      method := "none";
      result := fail;

      Print("  [", dupIdx, " vs ", repIdx, "] ");

      # Method 1: Proof chain (if nonsolvable with supported quotient order)
      if not IsSolvableGroup(sb.groups[ii]) then
        result := ProofChainIso(sb.groups[ii], G_rep, sb.gens[ii], 600000);
        if result <> fail then method := result.method; fi;
      fi;

      # Method 2: Allquot cocycle (10 min timeout)
      # For large aut groups, use proof chain on quotients instead of IG
      if result = fail then
        Print("allquot...");
        if repQuots = fail then repQuots := _MW_GetQuotients(G_rep); fi;
        if _mw_autSize > 10000000 and not IsSolvableGroup(sb.groups[ii]) then
          result := _MW_SolveAllQuotChain(sb.groups[ii], G_rep, sb.gens[ii], repQuots, 600000);
        else
          result := _MW_SolveAllQuot(sb.groups[ii], G_rep, sb.gens[ii], repQuots, 600000);
        fi;
        if result <> fail then method := result.method; fi;
      fi;

      # Method 3: Session IG (no timeout — last resort)
      # Center-free nonsolvable: always run IG (fast, ~40s)
      # Skip IG only for NONSOLVABLE groups with |Aut| > 10M AND nontrivial center
      if result = fail and not IsSolvableGroup(sb.groups[ii]) then
        _mw_cenSize := Size(Center(sb.groups[ii]));;
        if _mw_cenSize <= 1 then
          Print("cfIG...");  # center-free, always try IG
        elif _mw_autSize > 10000000 then
          Print("SKIPPED (|Aut|=", _mw_autSize, " |Z|=", _mw_cenSize, ")\n");
          nFail := nFail + 1;
          AppendTo(_MW_logFile, dupIdx, " SKIPPED_AUT_", _mw_autSize, " ", Runtime()-t0, "ms\n");
          continue;
        fi;
      fi;
      # For solvable groups, convert to PcGroup first (much faster)
      if result = fail then
        if IsSolvableGroup(sb.groups[ii]) then
          Print("pcIG...");
          _mw_phi_d := IsomorphismPcGroup(sb.groups[ii]);;
          _mw_phi_r := IsomorphismPcGroup(G_rep);;
          _mw_pc_d := Image(_mw_phi_d);; _mw_pc_r := Image(_mw_phi_r);;
          SpecialPcgs(_mw_pc_d);; SpecialPcgs(_mw_pc_r);;
          iso := IsomorphismGroups(_mw_pc_d, _mw_pc_r);;
          if iso <> fail then
            igGens := sb.gens[ii];;
            images := List(igGens, g ->
              PreImagesRepresentative(_mw_phi_r, Image(iso, Image(_mw_phi_d, g))));;
            ghbi := GroupHomomorphismByImages(sb.groups[ii], G_rep, igGens, images);;
            if ghbi <> fail then
              result := rec(images := images, method := "pcGroupIG",
                           dt := Runtime()-t0);
              method := "pcGroupIG";
            fi;
          fi;
        else
          Print("IG...");
          iso := IsomorphismGroups(sb.groups[ii], G_rep);
          if iso <> fail then
            igGens := GeneratorsOfGroup(sb.groups[ii]);
            images := List(igGens, g -> Image(iso, g));
            ghbi := GroupHomomorphismByImages(sb.groups[ii], G_rep, igGens, images);
            if ghbi <> fail then
              result := rec(images := images, method := "sessionIG",
                           dt := Runtime()-t0);
              method := "sessionIG";
              sb.gens[ii] := igGens;
            fi;
          fi;
        fi;
      fi;

      if result <> fail then
        nOK := nOK + 1;
        Print(method, " OK (", Runtime()-t0, "ms)\n");
        AppendTo(_MW_proofFile, "  rec(duplicate:=", dupIdx,
                ",representative:=", repIdx,
                ",method:=\"", method, "\",gens:=",
                List(sb.gens[ii], String), ",images:=",
                List(result.images, String), "),\n");
        AppendTo(_MW_logFile, dupIdx, " ", method, " ", Runtime()-t0, "ms\n");
      else
        nFail := nFail + 1;
        Print("FAILED (", Runtime()-t0, "ms)\n");
        AppendTo(_MW_logFile, dupIdx, " FAILED ", Runtime()-t0, "ms\n");
      fi;
    od;
  od;

  Print("  Bucket done: OK=", nOK, " Fail=", nFail, "\n\n");
end;

# Main loop
Print("Worker ", MIXED_WORKER_ID, ": ", Length(BUCKET_ASSIGNMENTS), " buckets\n\n");
_MW_totalOK := 0;; _MW_totalFail := 0;;

for _bkt in BUCKET_ASSIGNMENTS do
  _MW_SolveBucket(_bkt);
od;

Print("\nWorker ", MIXED_WORKER_ID, " COMPLETE\n");
AppendTo(_MW_logFile, "\nCOMPLETE\n");
QUIT;
