# validate_s16_proofs.g
# Validates ALL S16 master proofs are bijective homomorphisms
# against the actual s16_subgroups.g conjugacy class representatives.
#
# For each proof, checks:
#   1. gens are elements of subgroups[duplicate]
#   2. images are elements of subgroups[representative]
#   3. gens generate a group of the same order as subgroups[duplicate]
#   4. images generate a group of the same order as subgroups[representative]
#   5. GroupHomomorphismByImages(Group(gens), Group(images), gens, images) <> fail
#
# Combined: this guarantees a bijective homomorphism (isomorphism).

startTotal := Runtime();

LogFile := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s16_dedupe/proofs/validation_log.txt";
PrintTo(LogFile, "# S16 Proof Validation Log\n");
AppendTo(LogFile, "# Validates all proofs are bijective homomorphisms\n");
AppendTo(LogFile, "# against s16_subgroups.g\n\n");

# ---- Load subgroup data ----
Print("Loading s16_subgroups.g (254MB, may take a few minutes)...\n");
loadStart := Runtime();
subgroupData := ReadAsFunction(
  "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/conjugacy_cache/s16_subgroups.g")();
nSubgroups := Length(subgroupData);
Print("  Loaded ", nSubgroups, " subgroups in ",
      QuoInt(Runtime()-loadStart, 1000), "s\n");

# Helper: construct a permutation group from generator image lists
MakeGroup := function(genImageLists)
  local perms;
  if Length(genImageLists) = 0 then
    return Group(());
  fi;
  perms := List(genImageLists, PermList);
  return Group(perms);
end;

# ---- Load proofs ----
Print("Loading master proofs...\n");
loadStart := Runtime();
Read("/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s16_dedupe/proofs/s16_master_proofs_repaired_v2.g");

nProofs := 0;
if IsBound(S16_MASTER_PROOFS) then
  nProofs := Length(S16_MASTER_PROOFS);
  Print("  Loaded ", nProofs, " proofs in ",
        QuoInt(Runtime()-loadStart, 1000), "s\n\n");
else
  Print("FATAL: Failed to load S16_MASTER_PROOFS\n");
  AppendTo(LogFile, "FATAL: Failed to load S16_MASTER_PROOFS\n");
fi;

# ---- Validation counters ----
nPassed := 0;
nFailed := 0;
failures := [];
methodPassed := rec();
methodFailed := rec();

TrackMethod := function(method, passed)
  if passed then
    if not IsBound(methodPassed.(method)) then
      methodPassed.(method) := 0;
    fi;
    methodPassed.(method) := methodPassed.(method) + 1;
  else
    if not IsBound(methodFailed.(method)) then
      methodFailed.(method) := 0;
    fi;
    methodFailed.(method) := methodFailed.(method) + 1;
  fi;
end;

# ---- Main validation function ----
ValidateProof := function(proof)
  local G, H, gens, images, allGens, allImages, fm, g,
        hom, Gproof, Hproof, sG, sH;

  # Bounds check
  if proof.duplicate < 1 or proof.duplicate > nSubgroups then
    return "FAIL: duplicate index out of range";
  fi;
  if proof.representative < 1 or proof.representative > nSubgroups then
    return "FAIL: representative index out of range";
  fi;

  # Construct the actual groups from subgroup data
  G := MakeGroup(subgroupData[proof.duplicate]);
  H := MakeGroup(subgroupData[proof.representative]);

  sG := Size(G);
  sH := Size(H);
  if sG <> sH then
    return Concatenation("FAIL: groups have different orders (",
                         String(sG), " vs ", String(sH), ")");
  fi;

  # Parse gens and images from the proof
  if IsBound(proof.factorMappings) then
    # FactorV3 format: combine all factor mappings
    allGens := [];
    allImages := [];
    for fm in proof.factorMappings do
      Append(allGens, List(fm.gens, EvalString));
      Append(allImages, List(fm.images, EvalString));
    od;
    gens := allGens;
    images := allImages;
  elif IsBound(proof.gens) and IsBound(proof.images) then
    # Standard format: top-level gens/images
    gens := List(proof.gens, EvalString);
    images := List(proof.images, EvalString);
  else
    return "FAIL: proof has neither gens/images nor factorMappings";
  fi;

  if Length(gens) <> Length(images) then
    return Concatenation("FAIL: gens/images length mismatch (",
                         String(Length(gens)), " vs ",
                         String(Length(images)), ")");
  fi;

  if Length(gens) = 0 then
    if sG = 1 then
      return "PASS";  # trivial group, trivial isomorphism
    fi;
    return "FAIL: empty generators for non-trivial group";
  fi;

  # Check 1: all gens are elements of the duplicate group
  for g in gens do
    if not g in G then
      return "FAIL: generator not in duplicate group";
    fi;
  od;

  # Check 2: all images are elements of the representative group
  for g in images do
    if not g in H then
      return "FAIL: image not in representative group";
    fi;
  od;

  # Check 3: gens generate the full duplicate group
  Gproof := Group(gens);
  if Size(Gproof) <> sG then
    return Concatenation("FAIL: gens generate order ",
                         String(Size(Gproof)), " expected ", String(sG));
  fi;

  # Check 4: images generate the full representative group
  Hproof := Group(images);
  if Size(Hproof) <> sH then
    return Concatenation("FAIL: images generate order ",
                         String(Size(Hproof)), " expected ", String(sH));
  fi;

  # Check 5: the mapping extends to a valid group homomorphism
  hom := GroupHomomorphismByImages(Gproof, Hproof, gens, images);
  if hom = fail then
    return "FAIL: GroupHomomorphismByImages returned fail (not a homomorphism)";
  fi;

  # All checks passed => bijective homomorphism
  return "PASS";
end;

# ---- Run validation (only if proofs loaded) ----
if nProofs > 0 then

Print("=== Starting validation of ", nProofs, " proofs ===\n\n");
startValidation := Runtime();

nSkipped := 0;
for i in [1..nProofs] do
  if not IsBound(S16_MASTER_PROOFS[i]) then
    nSkipped := nSkipped + 1;
    continue;
  fi;
  proof := S16_MASTER_PROOFS[i];
  result := ValidateProof(proof);

  if result = "PASS" then
    nPassed := nPassed + 1;
    TrackMethod(proof.method, true);
  else
    nFailed := nFailed + 1;
    TrackMethod(proof.method, false);
    Add(failures, rec(index := i,
                      duplicate := proof.duplicate,
                      representative := proof.representative,
                      method := proof.method,
                      error := result));
    AppendTo(LogFile, Concatenation(
      "FAIL #", String(i),
      " dup=", String(proof.duplicate),
      " rep=", String(proof.representative),
      " method=", proof.method,
      " ", result, "\n"));
    Print("  FAIL #", i, " dup=", proof.duplicate,
          " rep=", proof.representative,
          " [", proof.method, "] ", result, "\n");
  fi;

  # Progress report every 1000 proofs
  if i mod 1000 = 0 then
    elapsed := Runtime() - startValidation;
    if elapsed > 100 then
      rate := Float(i) * 1000.0 / Float(elapsed);
      eta := Float(nProofs - i) / rate;
      Print("  [", i, "/", nProofs, "] passed=", nPassed,
            " failed=", nFailed, " | ",
            QuoInt(elapsed, 1000), "s elapsed",
            " ~", Int(rate), "/s ETA ~", Int(eta), "s\n");
    else
      Print("  [", i, "/", nProofs, "] passed=", nPassed,
            " failed=", nFailed, "\n");
    fi;
  fi;
od;

# ---- Summary ----
elapsed := Runtime() - startValidation;
totalElapsed := Runtime() - startTotal;

Print("\n");
Print("================================================\n");
Print("         VALIDATION COMPLETE\n");
Print("================================================\n");
Print("Total list length: ", nProofs, "\n");
Print("Bound entries:    ", nPassed + nFailed, "\n");
Print("Unbound (skipped): ", nSkipped, "\n");
Print("Passed:           ", nPassed, "\n");
Print("Failed:           ", nFailed, "\n");
Print("Validation time:  ", QuoInt(elapsed, 1000), "s\n");
Print("Total time:       ", QuoInt(totalElapsed, 1000), "s\n");

# Per-method breakdown
Print("\n--- Results by method ---\n");
allMethods := Set(Concatenation(RecNames(methodPassed), RecNames(methodFailed)));
for m in allMethods do
  p := 0; f := 0;
  if IsBound(methodPassed.(m)) then p := methodPassed.(m); fi;
  if IsBound(methodFailed.(m)) then f := methodFailed.(m); fi;
  if f > 0 then
    Print("  ", m, ": ", p, " passed, ", f, " FAILED\n");
  else
    Print("  ", m, ": ", p, " passed\n");
  fi;
od;

# Write summary to log
AppendTo(LogFile, "\n================================================\n");
AppendTo(LogFile, "         VALIDATION COMPLETE\n");
AppendTo(LogFile, "================================================\n");
AppendTo(LogFile, Concatenation("Total list length: ", String(nProofs), "\n"));
AppendTo(LogFile, Concatenation("Bound entries:    ", String(nPassed + nFailed), "\n"));
AppendTo(LogFile, Concatenation("Unbound (skipped): ", String(nSkipped), "\n"));
AppendTo(LogFile, Concatenation("Passed:           ", String(nPassed), "\n"));
AppendTo(LogFile, Concatenation("Failed:           ", String(nFailed), "\n"));
AppendTo(LogFile, Concatenation("Validation time:  ",
                                String(QuoInt(elapsed, 1000)), "s\n"));
AppendTo(LogFile, Concatenation("Total time:       ",
                                String(QuoInt(totalElapsed, 1000)), "s\n"));

AppendTo(LogFile, "\n--- Results by method ---\n");
for m in allMethods do
  p := 0; f := 0;
  if IsBound(methodPassed.(m)) then p := methodPassed.(m); fi;
  if IsBound(methodFailed.(m)) then f := methodFailed.(m); fi;
  AppendTo(LogFile, Concatenation("  ", m, ": ",
           String(p), " passed, ", String(f), " failed\n"));
od;

if nFailed > 0 then
  Print("\n--- All failures ---\n");
  AppendTo(LogFile, "\n--- All failures ---\n");
  for ff in failures do
    Print("  #", ff.index, " dup=", ff.duplicate,
          " rep=", ff.representative,
          " [", ff.method, "] ", ff.error, "\n");
    AppendTo(LogFile, Concatenation(
      "  #", String(ff.index),
      " dup=", String(ff.duplicate),
      " rep=", String(ff.representative),
      " [", ff.method, "] ", ff.error, "\n"));
  od;
else
  Print("\nAll ", nProofs, " proofs validated successfully!\n");
  AppendTo(LogFile, Concatenation(
    "\nAll ", String(nProofs), " proofs validated successfully!\n"));
fi;

Print("\nLog written to: validation_log.txt\n");

fi;  # end if nProofs > 0

QUIT;
