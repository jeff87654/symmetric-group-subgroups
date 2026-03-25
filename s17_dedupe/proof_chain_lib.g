# proof_chain_lib.g — Fast nonsolvable isomorphism via S16 proof chain
# Load once at worker startup, then call ProofChainIso(G_dup, G_rep, gens)
#
# Supports quotient orders: 2160, 2880, 3840, 4320, 5760, 6480, 7200, 7680
# Covers parent orders: 4320, 5760, 7680, 8640, 11520, 12960, 14400, 15360
#
# Usage:
#   Read("proof_chain_lib.g");        # loads S16 tables (~30s)
#   result := ProofChainIso(G_dup, G_rep, gens_dup, 600000);
#   if result <> fail then
#     # result.images, result.method, result.dt available
#   fi;

# ============================================================
# 1. Load S16 class lookup tables
# ============================================================
_PCL_BASE := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s17_dedupe/";;

# Supported quotient orders and their file naming conventions
# 58 quotient orders covering parent orders 4320 - 23224320
_PCL_ORDERS := [2160, 2880, 3360, 3600, 3840, 4320, 5760, 6480, 6720,
                7200, 7680, 8640, 9072, 9720, 10800, 11520, 12960,
                14400, 15360, 17280, 19440, 21600, 23040, 25920,
                29160, 30720, 34560, 38880, 43200, 46080, 51840,
                64800, 69120, 77760, 86400, 90720, 92160, 103680,
                120960, 129600, 138240, 155520, 172800, 181440,
                207360, 259200, 276480, 362880, 544320, 725760,
                806400, 1088640, 1451520, 2177280, 2903040,
                4354560, 5806080, 11612160];;
_PCL_Groups := rec();;
_PCL_Proofs := rec();;
_PCL_Gens := rec();;

Print("ProofChainLib: Loading S16 class tables for ", Length(_PCL_ORDERS), " orders...\n");
for _ord in _PCL_ORDERS do
  if _ord = 3840 then
    # Order 3840 uses legacy file names
    Read(Concatenation(_PCL_BASE, "s16_typerep_classes_full.g"));
    Read(Concatenation(_PCL_BASE, "s16_class_proofs_complete.g"));
    Read(Concatenation(_PCL_BASE, "s17_chain_groups_complete.g"));
    _PCL_Proofs.(String(_ord)) := S16_CLASS_PROOFS;;
    _PCL_Gens.(String(_ord)) := S17_CHAIN_GENS_FULL;;
  elif _ord = 7680 then
    Read(Concatenation(_PCL_BASE, "s16_typerep_classes_7680.g"));
    Read(Concatenation(_PCL_BASE, "s16_class_proofs_7680.g"));
    Read(Concatenation(_PCL_BASE, "s17_chain_groups_7680.g"));
    _PCL_Proofs.(String(_ord)) := S16_CLASS_PROOFS_7680;;
    _PCL_Gens.(String(_ord)) := S17_CHAIN_GENS_7680;;
  else
    Read(Concatenation(_PCL_BASE, "s16_typerep_classes_", String(_ord), ".g"));
    Read(Concatenation(_PCL_BASE, "s16_class_proofs_", String(_ord), ".g"));
    Read(Concatenation(_PCL_BASE, "s17_chain_groups_", String(_ord), ".g"));
    _PCL_Proofs.(String(_ord)) := ValueGlobal(Concatenation("S16_CLASS_PROOFS_", String(_ord)));;
    _PCL_Gens.(String(_ord)) := ValueGlobal(Concatenation("S17_CHAIN_GENS_", String(_ord)));;
  fi;
  Print("  Order ", _ord, " loaded\n");
od;

# Build group caches for all orders
Print("ProofChainLib: Building class group caches...\n");
_PCL_TotalGroups := 0;;
for _ord in _PCL_ORDERS do
  _PCL_Groups.(String(_ord)) := rec();;
  for _k in RecNames(_PCL_Gens.(String(_ord))) do
    _PCL_Groups.(String(_ord)).(_k) := Group(_PCL_Gens.(String(_ord)).(_k));;
    _PCL_TotalGroups := _PCL_TotalGroups + 1;;
  od;
od;

Print("ProofChainLib: Ready (", _PCL_TotalGroups, " class groups across ",
      Length(_PCL_ORDERS), " orders)\n\n");

# ============================================================
# 2. Helper functions
# ============================================================

_PCL_InvolutionCount := function(G)
  local n, c; n := 0;
  for c in ConjugacyClasses(G) do
    if Order(Representative(c)) = 2 then n := n + Size(c); fi; od;
  return n;
end;

# RowPowerFingerprint for sub-bucketing
_PCL_RowPowerFingerprint := function(ct)
  local irrs, primes, fps, chi, fp, p, pm, vals;
  irrs := Irr(ct);
  primes := PrimeDivisors(Size(ct));
  fps := [];
  for chi in irrs do
    fp := [];
    for p in primes do
      pm := PowerMap(ct, p);
      vals := List([1..Length(pm)], j -> chi[pm[j]]);
      Sort(vals);
      Add(fp, [p, vals]);
    od;
    Sort(fp);
    Add(fps, fp);
  od;
  Sort(fps);
  return fps;
end;

_PCL_RPHash := function(rpFp)
  local s, entry, p_entry, v;
  s := "";
  for entry in rpFp do
    for p_entry in entry do
      Append(s, String(p_entry[1])); Append(s, ":");
      for v in p_entry[2] do Append(s, String(v)); Append(s, ","); od;
      Append(s, ";");
    od;
    Append(s, "|");
  od;
  return s;
end;

# Compute type fingerprint for a group (for sub-bucketing)
ProofChainFingerprint := function(G)
  local ct, nIrr, invC, rpH, cen, blocks, act, Q, gzId;
  ct := CharacterTable(G);
  nIrr := Length(Irr(ct));
  invC := _PCL_InvolutionCount(G);
  rpH := _PCL_RPHash(_PCL_RowPowerFingerprint(ct));
  # G/Z(G) IdGroup — catches types that RPF misses
  cen := Center(G);
  gzId := [0, 0];
  if Size(cen) > 1 then
    blocks := List(Orbits(cen, [1..LargestMovedPoint(G)]), Set);
    act := ActionHomomorphism(G, blocks, OnSets);
    Q := Image(act);
    if Size(Q) < 2000 and not Size(Q) in [512, 768, 1024, 1536] then
      gzId := IdGroup(Q);
    else
      gzId := [Size(Q), NrConjugacyClasses(Q)];
    fi;
  fi;
  return rec(nIrr := nIrr, invC := invC, rpLen := Length(rpH), rpH := rpH,
             gzId := gzId);
end;

# ============================================================
# 3. S16 class finding
# ============================================================

_PCL_FindClass := function(Q_small, targetOrder)
  local nrCC, ccKey, groups, possTypes, t, tKey, classes, prefix,
        j, gKey, G_s17, maxDeg, sigma, ordStr;
  nrCC := NrConjugacyClasses(Q_small);
  ordStr := String(targetOrder);

  if not IsBound(_PCL_Groups.(ordStr)) then return fail; fi;
  groups := _PCL_Groups.(ordStr);

  # Determine prefix and ccKey based on order
  if targetOrder = 3840 then
    ccKey := Concatenation("TYPES_CC", String(nrCC));
    prefix := "TYPE_";
  else
    ccKey := Concatenation("TYPES", ordStr, "_CC", String(nrCC));
    prefix := Concatenation("TYPE", ordStr, "_");
  fi;

  if not IsBoundGlobal(ccKey) then return fail; fi;
  possTypes := ValueGlobal(ccKey);

  for t in possTypes do
    tKey := Concatenation(prefix, String(t), "_CLASSES");
    if not IsBoundGlobal(tKey) then continue; fi;
    classes := ValueGlobal(tKey);
    for j in [1..Length(classes)] do
      gKey := Concatenation("g", String(classes[j]));
      if not IsBound(groups.(gKey)) then continue; fi;
      G_s17 := groups.(gKey);
      if Size(G_s17) <> Size(Q_small) then continue; fi;
      maxDeg := Maximum(LargestMovedPoint(Q_small), LargestMovedPoint(G_s17));
      sigma := RepresentativeAction(SymmetricGroup(maxDeg), Q_small, G_s17);
      if sigma <> fail then
        return rec(classIdx := classes[j], type := t, sigma := sigma,
                   targetOrder := targetOrder);
      fi;
    od;
  od;
  return fail;
end;

# ============================================================
# 4. Proof application
# ============================================================

_PCL_ApplyProof := function(classIdx, targetOrder)
  local proofs, groups, proofKey, proof, gKey, repGKey, imgs, hom, proofGens, ordStr;
  ordStr := String(targetOrder);

  if not IsBound(_PCL_Proofs.(ordStr)) or not IsBound(_PCL_Groups.(ordStr)) then return fail; fi;
  proofs := _PCL_Proofs.(ordStr);
  groups := _PCL_Groups.(ordStr);

  proofKey := Concatenation("c", String(classIdx));
  if not IsBound(proofs.(proofKey)) then return fail; fi;
  proof := proofs.(proofKey);
  gKey := Concatenation("g", String(classIdx));
  repGKey := Concatenation("g", String(proof.rep));
  if not IsBound(groups.(gKey)) or not IsBound(groups.(repGKey)) then return fail; fi;
  if IsString(proof.images[1]) then imgs := List(proof.images, EvalString);
  else imgs := proof.images; fi;
  if IsString(proof.gens[1]) then proofGens := List(proof.gens, EvalString);
  else proofGens := proof.gens; fi;
  hom := GroupHomomorphismByImages(groups.(gKey), groups.(repGKey), proofGens, imgs);
  if hom = fail then return fail; fi;
  return rec(hom := hom, repIdx := proof.rep, repGroup := groups.(repGKey));
end;

# ============================================================
# 5. Main solver: ProofChainIso
# ============================================================

ProofChainIso := function(G_dup, G_rep, gens, timeLimit)
  local order, quotientOrder, cen, invols, z, blocks, act, Q, spdr, Q_small,
        dupMatch, repQuotData, rd, dupProof, repProof, groups,
        autQ, autList, alphaIso, aIdx, alpha,
        kerElts, nKer, baseImages, combo, j, k, h,
        hS17, hRep, hRepS17, imgs, ig, gb, nGens, t0, match;

  order := Size(G_dup);
  nGens := Length(gens);
  t0 := Runtime();

  # Determine quotient target order (order / 2)
  quotientOrder := order / 2;

  # Check if we have S16 data for this quotient order
  if IsBound(_PCL_Groups.(String(quotientOrder))) then
    groups := _PCL_Groups.(String(quotientOrder));
    _PCL_useIdGroup := false;
  elif quotientOrder < 2000 and not quotientOrder in [512, 768, 1024, 1536] then
    # IdGroup range! Use IdGroup-based matching instead of S16 class lookup
    groups := fail;
    _PCL_useIdGroup := true;
  else
    return fail;
  fi;

  # Precompute rep quotient data
  cen := Center(G_rep);
  invols := Filtered(Elements(cen), x -> Order(x) = 2);
  repQuotData := [];
  for z in invols do
    blocks := List(Orbits(Group([z]), MovedPoints(G_rep)), Set);
    act := ActionHomomorphism(G_rep, blocks, OnSets);
    Q := Image(act);
    match := fail;
    if Size(Q) = quotientOrder then
      spdr := SmallerDegreePermutationRepresentation(Q);
      Q_small := Image(spdr);
      if _PCL_useIdGroup then
        match := rec(idGroup := IdGroup(Q_small), type := IdGroup(Q_small),
                     classIdx := 0, sigma := fail);
      else
        match := _PCL_FindClass(Q_small, quotientOrder);
      fi;
      Add(repQuotData, rec(invol:=z, act:=act, Q:=Q, spdr:=spdr,
                           Q_small:=Q_small, match:=match));
    else
      Add(repQuotData, rec(invol:=z, act:=act, Q:=Q, match:=fail));
    fi;
  od;

  # Try each dup involution
  cen := Center(G_dup);
  invols := Filtered(Elements(cen), x -> Order(x) = 2);

  for z in invols do
    if Runtime()-t0 > timeLimit then return fail; fi;
    blocks := List(Orbits(Group([z]), MovedPoints(G_dup)), Set);
    act := ActionHomomorphism(G_dup, blocks, OnSets);
    Q := Image(act);
    if Size(Q) <> quotientOrder then continue; fi;
    spdr := SmallerDegreePermutationRepresentation(Q);
    Q_small := Image(spdr);
    if _PCL_useIdGroup then
      dupMatch := rec(idGroup := IdGroup(Q_small), type := IdGroup(Q_small),
                      classIdx := 0, sigma := fail);
    else
      dupMatch := _PCL_FindClass(Q_small, quotientOrder);
    fi;
    if dupMatch = fail then continue; fi;

    for rd in repQuotData do
      if rd.match = fail then continue; fi;
      if rd.match.type <> dupMatch.type then continue; fi;

      if _PCL_useIdGroup then
        # IdGroup mode: use IsomorphismGroups on small quotients (fast!)
        # or RepresentativeAction if same degree
        _pcl_isoQ := IsomorphismGroups(Q_small, rd.Q_small);
        if _pcl_isoQ = fail then continue; fi;

        kerElts := Elements(Kernel(rd.act));
        nKer := Length(kerElts);

        # Try with Aut twists
        autQ := AutomorphismGroup(rd.Q_small);
        autList := [IdentityMapping(rd.Q_small)];
        Append(autList, GeneratorsOfGroup(autQ));
        for aIdx in GeneratorsOfGroup(autQ) do
          for alpha in GeneratorsOfGroup(autQ) do
            Add(autList, aIdx * alpha); od; od;
        autList := Set(autList);

        for alphaIso in autList do
          if Runtime()-t0 > timeLimit then return fail; fi;
          baseImages := [];
          for j in [1..nGens] do
            h := Image(spdr, Image(act, gens[j]));
            h := Image(CompositionMapping(alphaIso, _pcl_isoQ), h);
            if not h in rd.Q_small then break; fi;
            h := PreImagesRepresentative(rd.spdr, h);
            Add(baseImages, PreImagesRepresentative(rd.act, h));
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
              if gb <> fail then return rec(images:=imgs, method:="idGroupCocycle",
                dt:=Runtime()-t0); fi;
            fi;
            j := nGens;
            while j >= 1 do combo[j]:=combo[j]+1;
              if combo[j]<=nKer then break; fi; combo[j]:=1; j:=j-1; od;
            if j = 0 then break; fi;
          od;
        od;
        continue;  # try next rd
      fi;

      # S16 class mode: build proof chain
      dupProof := _PCL_ApplyProof(dupMatch.classIdx, quotientOrder);
      repProof := _PCL_ApplyProof(rd.match.classIdx, quotientOrder);

      # Handle type reps (identity mapping)
      if dupProof = fail and repProof = fail then
        if dupMatch.classIdx = rd.match.classIdx then
          dupProof := rec(hom:=IdentityMapping(
            groups.(Concatenation("g", String(dupMatch.classIdx)))),
            repIdx:=dupMatch.classIdx,
            repGroup:=groups.(Concatenation("g", String(dupMatch.classIdx))));
          repProof := dupProof;
        else continue; fi;
      elif dupProof = fail then
        if repProof.repIdx = dupMatch.classIdx then
          dupProof := rec(hom:=IdentityMapping(
            groups.(Concatenation("g", String(dupMatch.classIdx)))),
            repIdx:=dupMatch.classIdx,
            repGroup:=groups.(Concatenation("g", String(dupMatch.classIdx))));
        else continue; fi;
      elif repProof = fail then
        if dupProof.repIdx = rd.match.classIdx then
          repProof := rec(hom:=IdentityMapping(
            groups.(Concatenation("g", String(rd.match.classIdx)))),
            repIdx:=rd.match.classIdx,
            repGroup:=groups.(Concatenation("g", String(rd.match.classIdx))));
        else continue; fi;
      fi;
      if dupProof.hom = fail or repProof.hom = fail then continue; fi;
      if dupProof.repIdx <> repProof.repIdx then continue; fi;

      # Aut twists
      autQ := AutomorphismGroup(rd.Q_small);
      autList := [IdentityMapping(rd.Q_small)];
      Append(autList, GeneratorsOfGroup(autQ));
      for aIdx in GeneratorsOfGroup(autQ) do
        for alpha in GeneratorsOfGroup(autQ) do
          Add(autList, aIdx * alpha); od; od;
      for aIdx in GeneratorsOfGroup(autQ){[1..Minimum(3,Length(GeneratorsOfGroup(autQ)))]} do
        for alpha in GeneratorsOfGroup(autQ) do
          for alphaIso in GeneratorsOfGroup(autQ) do
            Add(autList, aIdx * alpha * alphaIso); od; od; od;
      autList := Set(autList);

      kerElts := Elements(Kernel(rd.act));
      nKer := Length(kerElts);

      for alphaIso in autList do
        if Runtime()-t0 > timeLimit then return fail; fi;
        baseImages := [];
        for j in [1..nGens] do
          h := Image(spdr, Image(act, gens[j]));
          hS17 := h^dupMatch.sigma;
          hRep := Image(dupProof.hom, hS17);
          hRepS17 := PreImagesRepresentative(repProof.hom, hRep);
          h := hRepS17^(rd.match.sigma^-1);
          h := Image(alphaIso, h);
          if not h in rd.Q_small then break; fi;
          h := PreImagesRepresentative(rd.spdr, h);
          Add(baseImages, PreImagesRepresentative(rd.act, h));
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
            if gb <> fail then
              return rec(images := imgs, method := "proofChain",
                         dt := Runtime()-t0);
            fi;
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

# ============================================================
# 6. Sub-bucketing for workers
# ============================================================

# Given a list of groups in a bucket, sub-bucket by RPF fingerprint
# Returns: list of sub-bucket records, each with indices and type rep
SubBucketByRPF := function(indices, groups)
  local result, fpCache, ii, G, fp, key, found, jj;
  result := [];
  fpCache := [];
  for ii in [1..Length(indices)] do
    G := groups[ii];
    fp := ProofChainFingerprint(G);
    key := Concatenation(String(fp.nIrr), "_", String(fp.invC), "_", String(fp.rpLen));
    found := false;
    for jj in [1..Length(result)] do
      if result[jj].key = key then
        Add(result[jj].indices, indices[ii]);
        Add(result[jj].groups, G);
        found := true;
        break;
      fi;
    od;
    if not found then
      Add(result, rec(key := key, indices := [indices[ii]], groups := [G],
                       fp := fp));
    fi;
  od;
  return result;
end;

Print("ProofChainLib: Library loaded. Functions available:\n");
Print("  ProofChainIso(G_dup, G_rep, gens, timeLimit) -> rec or fail\n");
Print("  ProofChainFingerprint(G) -> rec(nIrr, invC, rpLen, rpH)\n");
Print("  SubBucketByRPF(indices, groups) -> list of sub-buckets\n\n");
