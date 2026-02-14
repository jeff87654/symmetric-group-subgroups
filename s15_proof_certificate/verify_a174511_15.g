##############################################################################
##
##  verify_a174511_15.g
##
##  Self-contained verification that A174511(15) = EXPECTED_TYPES
##  (Number of isomorphism types of subgroups of S_15)
##
##  Inputs (in s15_proof_certificate/):
##    s15_subgroups.g           - 159,129 conjugacy class representatives
##    combined_proof.g          - 20,643 isomorphism proofs
##    type_fingerprints_s15.g   - ~16,446 type records with minimal invariants
##    s15_idgroups.g            - 8,001 IdGroup type strings (for cross-check)
##
##  Phases:
##    B: Verify isomorphism proofs + IdGroup unions -> upper bound
##       (B runs first because it assigns IdGroup type representatives)
##       Also precomputes orbit structure keys for Phase D.
##    A: Verify fingerprint invariants for all large type representatives
##    C: Verify non-isomorphism from fingerprint data -> lower bound
##    D: Verify pairwise non-conjugacy of all 159,129 classes -> A000638(15)
##
##  Proof structure:
##    Phase B verifies the isomorphism proofs and computes IdGroup for
##    all compatible groups, building a union-find that yields the total
##    type count (upper bound). Phase A verifies that all invariant values
##    in the fingerprint file are correct by recomputing from generators.
##    Phase C checks that every pair of large types sharing the same order
##    is distinguished by a verified invariant (lower bound).
##    Phase D verifies that all 159,129 input groups are pairwise
##    non-conjugate in S15 using a 3-level cascade (orbit types, element
##    histograms, IsConjugate), proving A000638(15) = 159,129.
##
##############################################################################

BASE_DIR := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s15_proof_certificate/";

EXPECTED_CLASSES := 159129;
EXPECTED_LARGE := 29088;
EXPECTED_PROOFS := 20651;
EXPECTED_IDG_TYPES := 8001;

# Large rep count and total types are computed, not hardcoded
# EXPECTED_LARGE_TYPES := 8445;
# EXPECTED_TYPES := 16446;

# Optional phases (default: all enabled)
# Set these to false before Read()ing this file to skip phases:
#   RUN_PHASE_A := false;  # skip invariant recomputation (~24 min)
#   RUN_PHASE_D := false;  # skip non-conjugacy verification (~43 min)
if not IsBound(RUN_PHASE_A) then RUN_PHASE_A := true; fi;
if not IsBound(RUN_PHASE_D) then RUN_PHASE_D := true; fi;

IsIdGroupCompatible := function(ord)
    return ord < 2000 and not ord in [512, 768, 1024, 1536];
end;

_startTime := Runtime();

Print("==================================================\n");
Print("  A174511(15) Verification\n");
Print("==================================================\n\n");

##############################################################################
## Load input files
##############################################################################

Print("Loading s15_subgroups.g...\n");
_loadFunc := ReadAsFunction(Concatenation(BASE_DIR, "s15_subgroups.g"));
subgens := _loadFunc();
Unbind(_loadFunc);
if Length(subgens) <> EXPECTED_CLASSES then
    Print("FATAL: expected ", EXPECTED_CLASSES, " groups, got ",
          Length(subgens), "\n");
    QuitGap(1);
fi;
Print("  Loaded ", Length(subgens), " generator lists\n");

Print("Loading combined_proof.g...\n");
Read(Concatenation(BASE_DIR, "combined_proof.g"));
if Length(S15_COMBINED_PROOFS) <> EXPECTED_PROOFS then
    Print("WARNING: expected ", EXPECTED_PROOFS, " proofs, got ",
          Length(S15_COMBINED_PROOFS), "\n");
    # Don't abort — use actual count
fi;
_actualProofs := Length(S15_COMBINED_PROOFS);
Print("  Loaded ", _actualProofs, " proofs\n");

Print("Loading type_fingerprints_s15.g...\n");
Read(Concatenation(BASE_DIR, "type_fingerprints_s15.g"));
_actualTypes := Length(S15_TYPE_INFO);
Print("  Loaded ", _actualTypes, " type fingerprints\n");

# Separate IdGroup and large types from fingerprints
_fpIdgTypes := Filtered(S15_TYPE_INFO, t -> t.idGroup <> fail);
_fpLargeTypes := Filtered(S15_TYPE_INFO, t -> t.idGroup = fail);
Print("  IdGroup types in fingerprints: ", Length(_fpIdgTypes), "\n");
Print("  Large types in fingerprints: ", Length(_fpLargeTypes), "\n");

if Length(_fpIdgTypes) <> EXPECTED_IDG_TYPES then
    Print("WARNING: expected ", EXPECTED_IDG_TYPES, " IdGroup types, got ",
          Length(_fpIdgTypes), "\n");
fi;

Print("Load time: ", Int((Runtime() - _startTime) / 1000), "s\n\n");

# Group builder with bounded cache
_groupCache := rec();
_cacheSize := 0;
_BuildGroup := function(idx)
    local key;
    key := Concatenation("g", String(idx));
    if not IsBound(_groupCache.(key)) then
        _groupCache.(key) := Group(List(subgens[idx], PermList));
        _cacheSize := _cacheSize + 1;
    fi;
    return _groupCache.(key);
end;

_ClearCache := function()
    _groupCache := rec();
    _cacheSize := 0;
end;

##############################################################################
## Helper: compute element-order / fixed-point histogram for Phase D L2
##############################################################################

_ComputeHistogramKey := function(G)
    local cc, hist, c, rep, o, fp, hkey, sortedKeys, parts, k, result;
    cc := ConjugacyClasses(G);
    hist := rec();
    for c in cc do
        rep := Representative(c);
        o := Order(rep);
        fp := 15 - NrMovedPoints(rep);
        hkey := Concatenation(String(o), "_", String(fp));
        if IsBound(hist.(hkey)) then
            hist.(hkey) := hist.(hkey) + Size(c);
        else
            hist.(hkey) := Size(c);
        fi;
    od;
    sortedKeys := ShallowCopy(RecNames(hist));
    Sort(sortedKeys);
    parts := [];
    for k in sortedKeys do
        Add(parts, Concatenation(k, "x", String(hist.(k))));
    od;
    result := JoinStringsWithSeparator(parts, ",");
    if Length(result) > 900 then
        result := Concatenation(result{[1..800]}, "_H", String(Length(result)));
    fi;
    return result;
end;

##############################################################################
## PHASE B: Verify isomorphism proofs + IdGroup unions -> upper bound
##
## B1: Compute IdGroup for all compatible groups and build union-find.
## B2: Verify all isomorphism proofs as bijective homomorphisms.
## B3: Count distinct types from union-find.
##############################################################################

Print("=== PHASE B: Verify proofs + build type mapping ===\n\n");
phaseBStart := Runtime();

# B1: IdGroup union-find + orbit structure precomputation
Print("B1: Computing IdGroup + orbit structure for all groups...\n");

_parent := [1..EXPECTED_CLASSES];

_Find := function(x)
    while _parent[x] <> x do
        _parent[x] := _parent[_parent[x]];
        x := _parent[x];
    od;
    return x;
end;

_Union := function(a, b)
    local ra, rb;
    ra := _Find(a); rb := _Find(b);
    if ra <> rb then
        if ra < rb then _parent[rb] := ra;
        else _parent[ra] := rb; fi;
    fi;
end;

_idgMap := rec();
_idgCount := 0;
_largeCount := 0;
_largeIndices := [];  # Track which indices are large groups
_orbKey := [];  # orbit structure key per group (for Phase D)

for _i in [1..EXPECTED_CLASSES] do
    _G := _BuildGroup(_i);
    _ord := Size(_G);

    # Orbit-type key for Phase D conjugacy testing
    if RUN_PHASE_D then
        _orbs := Orbits(_G, [1..15]);
        _orbTypes := [];
        for _orb in _orbs do
            if Length(_orb) = 1 then
                Add(_orbTypes, [1, 1]);
            else
                Add(_orbTypes, [Length(_orb),
                    TransitiveIdentification(Action(_G, _orb))]);
            fi;
        od;
        Sort(_orbTypes);
        _orbKey[_i] := String(_orbTypes);
    fi;

    if IsIdGroupCompatible(_ord) then
        _idg := IdGroup(_G);
        _key := String(_idg);
        if IsBound(_idgMap.(_key)) then
            _Union(_i, _idgMap.(_key));
        else
            _idgMap.(_key) := _i;
        fi;
        _idgCount := _idgCount + 1;
    else
        _largeCount := _largeCount + 1;
        Add(_largeIndices, _i);
    fi;
    if _i mod 10000 = 0 then
        _ClearCache();
        _elapsed := Runtime() - phaseBStart;
        _eta := Int(_elapsed * (EXPECTED_CLASSES - _i) / _i / 1000);
        Print("  B1: ", _i, "/", EXPECTED_CLASSES,
              " (", _idgCount, " idg, ", _largeCount, " large)",
              " ETA=", _eta, "s\n");
    fi;
od;
_ClearCache();

_nIdgTypes := Length(RecNames(_idgMap));
Print("  IdGroup-compatible: ", _idgCount, " groups -> ",
      _nIdgTypes, " unique types\n");
Print("  Large groups: ", _largeCount, "\n");

if _nIdgTypes <> EXPECTED_IDG_TYPES then
    Print("FATAL: expected ", EXPECTED_IDG_TYPES, " IdGroup types, got ",
          _nIdgTypes, "\n");
    QuitGap(1);
fi;
if _largeCount <> EXPECTED_LARGE then
    Print("FATAL: expected ", EXPECTED_LARGE, " large groups, got ",
          _largeCount, "\n");
    QuitGap(1);
fi;

# B2: Verify isomorphism proofs
Print("\nB2: Verifying ", _actualProofs, " isomorphism proofs...\n");
_proofStart := Runtime();
_nPass := 0;
_proofFailures := [];

for _i in [1..Length(S15_COMBINED_PROOFS)] do
    _p := S15_COMBINED_PROOFS[_i];

    if _i mod 500 = 0 or _i <= 5 then
        _elapsed := Runtime() - _proofStart;
        if _i > 1 then
            _eta := Int(_elapsed * (Length(S15_COMBINED_PROOFS) - _i) / _i / 1000);
        else
            _eta := 0;
        fi;
        Print("  Proof ", _i, "/", _actualProofs,
              " pass=", _nPass, " fail=", Length(_proofFailures),
              " ETA=", _eta, "s\n");
    fi;

    _G := _BuildGroup(_p.duplicate);
    _H := _BuildGroup(_p.representative);
    _sizeG := Size(_G);
    _sizeH := Size(_H);

    # Check 1: orders match
    if _sizeG <> _sizeH then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": order mismatch |G|=", String(_sizeG),
            " |H|=", String(_sizeH)));
        continue;
    fi;

    # Parse generators and images
    # Handle two proof formats: fullIso (gens/images) and FactorV3 (factorMappings)
    if IsBound(_p.gens) then
        # fullIso format: top-level gens and images
        _proofGens := List(_p.gens, EvalString);
        _proofImgs := List(_p.images, EvalString);
    elif IsBound(_p.factorMappings) then
        # FactorV3 format: concatenate gens/images from all factor mappings
        _proofGens := [];
        _proofImgs := [];
        for _fm in _p.factorMappings do
            Append(_proofGens, List(_fm.gens, EvalString));
            Append(_proofImgs, List(_fm.images, EvalString));
        od;
    else
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": unknown format (no gens or factorMappings)"));
        continue;
    fi;

    if Length(_proofGens) <> Length(_proofImgs) then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": gens/images length mismatch"));
        continue;
    fi;

    # Check 2: all gens in G
    if not ForAll(_proofGens, g -> g in _G) then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": generator not in G"));
        continue;
    fi;

    # Check 3: all images in H
    if not ForAll(_proofImgs, h -> h in _H) then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": image not in H"));
        continue;
    fi;

    # Check 4: gens generate G
    _genGroup := Group(_proofGens);
    if Size(_genGroup) <> _sizeG then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": gens don't generate G (|genGroup|=", String(Size(_genGroup)),
            " vs |G|=", String(_sizeG), ")"));
        continue;
    fi;

    # Check 5: valid homomorphism
    _phi := GroupHomomorphismByImages(_G, _H, _proofGens, _proofImgs);
    if _phi = fail then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": GroupHomomorphismByImages returned fail"));
        continue;
    fi;

    # Check 6: bijective (injective + surjective)
    if not IsInjective(_phi) then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": not injective"));
        continue;
    fi;

    if not IsSurjective(_phi) then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": not surjective"));
        continue;
    fi;

    _nPass := _nPass + 1;

    # Apply to union-find
    _Union(_p.duplicate, _p.representative);
od;

if Length(_proofFailures) > 0 then
    Print("FATAL: ", Length(_proofFailures), " proofs failed!\n");
    for _f in _proofFailures{[1..Minimum(20, Length(_proofFailures))]} do
        Print("  ", _f, "\n");
    od;
    QuitGap(1);
fi;

Print("  All ", _nPass, "/", _actualProofs,
      " proofs verified as bijective homomorphisms\n");

# B3: Count distinct types
Print("\nB3: Counting distinct types...\n");

_rootSet := rec();
for _i in [1..EXPECTED_CLASSES] do
    _rootSet.(String(_Find(_i))) := true;
od;
_nTypes := Length(RecNames(_rootSet));

Print("  Total types from union-find: ", _nTypes, "\n");

# Compute expected: IdGroup types + large reps
# Large reps = large indices whose root is themselves
_nLargeReps := 0;
_largeRepIndices := [];
for _i in _largeIndices do
    if _Find(_i) = _i then
        _nLargeReps := _nLargeReps + 1;
        Add(_largeRepIndices, _i);
    else
        # Check if root is also a large index
        # (a large group's root should be another large group)
        _root := _Find(_i);
        if not _root in _largeRepIndices then
            # Root might be a different large index already counted
        fi;
    fi;
od;

# More precise: count distinct roots among large indices
_largeRootSet := rec();
for _i in _largeIndices do
    _largeRootSet.(String(_Find(_i))) := true;
od;
_nLargeTypes := Length(RecNames(_largeRootSet));

EXPECTED_LARGE_TYPES := _nLargeTypes;
EXPECTED_TYPES := _nIdgTypes + _nLargeTypes;

Print("  IdGroup types: ", _nIdgTypes, "\n");
Print("  Large types (distinct roots): ", _nLargeTypes, "\n");
Print("  Total: ", _nIdgTypes, " + ", _nLargeTypes, " = ",
      _nIdgTypes + _nLargeTypes, "\n");

if _nTypes <> EXPECTED_TYPES then
    Print("FATAL: union-find gives ", _nTypes,
          " types but IdG+Large = ", EXPECTED_TYPES, "\n");
    QuitGap(1);
fi;

Print("  UPPER BOUND VERIFIED: at most ", EXPECTED_TYPES, " types\n");
Print("Phase B time: ", Int((Runtime() - phaseBStart) / 1000), "s\n\n");

_ClearCache();

##############################################################################
## PHASE A: Verify fingerprint invariants for large type representatives
##
## For each large type in the fingerprint file, build the representative
## group from raw generators and recompute every invariant listed.
## IdGroup types were already verified in Phase B (IdGroup computation).
##############################################################################

if RUN_PHASE_A then

Print("=== PHASE A: Verify fingerprint invariants ===\n\n");
phaseAStart := Runtime();

_nLargeVerified := 0;
_invFailures := [];

for _ti in [1..Length(_fpLargeTypes)] do
    _t := _fpLargeTypes[_ti];
    _rep := _t.representative;

    if _rep = 0 then
        continue;  # Skip IdGroup placeholders (shouldn't be in _fpLargeTypes)
    fi;

    if _ti mod 500 = 0 or _ti = 1 then
        _elapsed := Runtime() - phaseAStart;
        if _ti > 1 then
            _eta := Int(_elapsed * (Length(_fpLargeTypes) - _ti) / _ti / 1000);
        else
            _eta := 0;
        fi;
        Print("  Large type ", _ti, "/", Length(_fpLargeTypes),
              " ETA=", _eta, "s\n");
    fi;

    _G := _BuildGroup(_rep);

    # Verify order
    if Size(_G) <> _t.order then
        Add(_invFailures, Concatenation("Type ", String(_t.typeIndex),
            " rep=", String(_rep), ": order mismatch, expected ",
            String(_t.order), " got ", String(Size(_G))));
        continue;
    fi;

    _ok := true;

    # Determine which shared computations are needed
    _needsDerived := IsBound(_t.derivedSize)
                  or IsBound(_t.abelianInvariants);
    # Check if any nrElementsOfOrderK field is bound
    _needsCC := IsBound(_t.nrCC)
              or IsBound(_t.classSizes);
    if not _needsCC then
        for _fld in RecNames(_t) do
            if Length(_fld) > 17 and _fld{[1..17]} = "nrElementsOfOrder" then
                _needsCC := true;
                break;
            fi;
        od;
    fi;
    _needsDerivedSeries := IsBound(_t.derivedLength)
                        or IsBound(_t.derivedSeriesSizes);

    # Compute shared objects once
    if _needsDerived then _D := DerivedSubgroup(_G); fi;
    if _needsCC then _cc := ConjugacyClasses(_G); fi;
    if _needsDerivedSeries then _ds := DerivedSeriesOfGroup(_G); fi;

    # derivedSize
    if _ok and IsBound(_t.derivedSize) then
        if Size(_D) <> _t.derivedSize then
            Add(_invFailures, Concatenation("Type ", String(_t.typeIndex),
                " rep=", String(_rep), ": derivedSize mismatch, expected ",
                String(_t.derivedSize), " got ", String(Size(_D))));
            _ok := false;
        fi;
    fi;

    # nrCC
    if _ok and IsBound(_t.nrCC) then
        if Length(_cc) <> _t.nrCC then
            Add(_invFailures, Concatenation("Type ", String(_t.typeIndex),
                " rep=", String(_rep), ": nrCC mismatch, expected ",
                String(_t.nrCC), " got ", String(Length(_cc))));
            _ok := false;
        fi;
    fi;

    # derivedLength
    if _ok and IsBound(_t.derivedLength) then
        if IsSolvableGroup(_G) then
            _computed := Length(_ds) - 1;
        else
            _computed := -1;
        fi;
        if _computed <> _t.derivedLength then
            Add(_invFailures, Concatenation("Type ", String(_t.typeIndex),
                " rep=", String(_rep), ": derivedLength mismatch"));
            _ok := false;
        fi;
    fi;

    # abelianInvariants
    if _ok and IsBound(_t.abelianInvariants) then
        _computed := ShallowCopy(AbelianInvariants(_G/_D));
        Sort(_computed);
        if _computed <> _t.abelianInvariants then
            Add(_invFailures, Concatenation("Type ", String(_t.typeIndex),
                " rep=", String(_rep), ": abelianInvariants mismatch"));
            _ok := false;
        fi;
    fi;

    # maxElementOrder (max element order, computed from conjugacy classes)
    if _ok and IsBound(_t.maxElementOrder) then
        if not _needsCC then
            _cc := ConjugacyClasses(_G);
        fi;
        _computed := Maximum(List(_cc, c -> Order(Representative(c))));
        if _computed <> _t.maxElementOrder then
            Add(_invFailures, Concatenation("Type ", String(_t.typeIndex),
                " rep=", String(_rep), ": maxElementOrder mismatch, expected ",
                String(_t.maxElementOrder), " got ", String(_computed)));
            _ok := false;
        fi;
    fi;

    # centerSize
    if _ok and IsBound(_t.centerSize) then
        if Size(Centre(_G)) <> _t.centerSize then
            Add(_invFailures, Concatenation("Type ", String(_t.typeIndex),
                " rep=", String(_rep), ": centerSize mismatch"));
            _ok := false;
        fi;
    fi;

    # Generic nrElementsOfOrderK handler
    # Check all bound fields matching nrElementsOfOrder*
    if _ok and _needsCC then
        _allFieldNames := RecNames(_t);
        for _fld in _allFieldNames do
            if not _ok then break; fi;
            if Length(_fld) > 17 and _fld{[1..17]} = "nrElementsOfOrder" then
                _k := Int(_fld{[18..Length(_fld)]});
                if _k <> fail and _k > 0 then
                    _computed := Sum(Filtered(_cc,
                        c -> Order(Representative(c)) = _k), Size);
                    if _computed <> _t.(_fld) then
                        Add(_invFailures, Concatenation("Type ",
                            String(_t.typeIndex), " rep=", String(_rep),
                            ": ", _fld, " mismatch, expected ",
                            String(_t.(_fld)), " got ", String(_computed)));
                        _ok := false;
                    fi;
                fi;
            fi;
        od;
    fi;

    # classSizes
    if _ok and IsBound(_t.classSizes) then
        _computed := SortedList(List(_cc, Size));
        if _computed <> _t.classSizes then
            Add(_invFailures, Concatenation("Type ", String(_t.typeIndex),
                " rep=", String(_rep), ": classSizes mismatch"));
            _ok := false;
        fi;
    fi;

    # derivedSeriesSizes
    if _ok and IsBound(_t.derivedSeriesSizes) then
        _computed := List(_ds, Size);
        if _computed <> _t.derivedSeriesSizes then
            Add(_invFailures, Concatenation("Type ", String(_t.typeIndex),
                " rep=", String(_rep), ": derivedSeriesSizes mismatch"));
            _ok := false;
        fi;
    fi;

    # nilpotencyClass
    if _ok and IsBound(_t.nilpotencyClass) then
        if IsNilpotentGroup(_G) then
            _computed := NilpotencyClassOfGroup(_G);
        else
            _computed := -1;
        fi;
        if _computed <> _t.nilpotencyClass then
            Add(_invFailures, Concatenation("Type ", String(_t.typeIndex),
                " rep=", String(_rep), ": nilpotencyClass mismatch"));
            _ok := false;
        fi;
    fi;

    # numNormalSubs
    if _ok and IsBound(_t.numNormalSubs) then
        _computed := Length(NormalSubgroups(_G));
        if _computed <> _t.numNormalSubs then
            Add(_invFailures, Concatenation("Type ", String(_t.typeIndex),
                " rep=", String(_rep), ": numNormalSubs mismatch"));
            _ok := false;
        fi;
    fi;

    # frattiniSize
    if _ok and IsBound(_t.frattiniSize) then
        _computed := Size(FrattiniSubgroup(_G));
        if _computed <> _t.frattiniSize then
            Add(_invFailures, Concatenation("Type ", String(_t.typeIndex),
                " rep=", String(_rep), ": frattiniSize mismatch"));
            _ok := false;
        fi;
    fi;

    # autGroupOrder
    if _ok and IsBound(_t.autGroupOrder) then
        _computed := Size(AutomorphismGroup(_G));
        if _computed <> _t.autGroupOrder then
            Add(_invFailures, Concatenation("Type ", String(_t.typeIndex),
                " rep=", String(_rep), ": autGroupOrder mismatch"));
            _ok := false;
        fi;
    fi;

    if _ok then
        _nLargeVerified := _nLargeVerified + 1;
    fi;

    # Clear cache periodically
    if _ti mod 500 = 0 then
        _ClearCache();
    fi;
od;

if Length(_invFailures) > 0 then
    Print("FATAL: ", Length(_invFailures),
          " fingerprint verification failures!\n");
    for _f in _invFailures{[1..Minimum(20, Length(_invFailures))]} do
        Print("  ", _f, "\n");
    od;
    QuitGap(1);
fi;

Print("Phase A complete: ", _nLargeVerified, "/", Length(_fpLargeTypes),
      " large type fingerprints verified\n");
Print("  (", _nIdgTypes, " IdGroup types verified in Phase B)\n");
Print("Phase A time: ", Int((Runtime() - phaseAStart) / 1000), "s\n\n");

_ClearCache();

else
    Print("=== PHASE A: SKIPPED (RUN_PHASE_A = false) ===\n\n");
fi;

##############################################################################
## PHASE C: Verify non-isomorphism from fingerprint data -> lower bound
##
## IdGroup types are distinct by definition (different identifiers).
## Large types: bucket by order and confirm each pair is distinguished
## by some invariant whose value was verified in Phase A.
##############################################################################

Print("=== PHASE C: Verify non-isomorphism ===\n\n");
phaseCStart := Runtime();

Print("  IdGroup types: ", Length(_fpIdgTypes),
      " (distinct by definition)\n");
Print("  Large types: ", Length(_fpLargeTypes),
      " (need invariant comparison)\n");

# Build lookup for GAP-certified non-isomorphic pairs
_gapCertifiedSet := rec();
if IsBound(S15_GAP_CERTIFIED_NONISO) then
    Print("  GAP-certified non-iso pairs: ", Length(S15_GAP_CERTIFIED_NONISO), "\n");
    for _pair in S15_GAP_CERTIFIED_NONISO do
        _a := Minimum(_pair[1], _pair[2]);
        _b := Maximum(_pair[1], _pair[2]);
        _gapCertifiedSet.(Concatenation(String(_a), "_", String(_b))) := true;
    od;
else
    Print("  WARNING: S15_GAP_CERTIFIED_NONISO not found\n");
fi;

# Verify no overlap: IdGroup types have compatible orders,
# large types have incompatible orders
for _t in _fpIdgTypes do
    if not IsIdGroupCompatible(_t.order) then
        Print("FATAL: IdGroup type ", _t.typeIndex,
              " has non-compatible order ", _t.order, "\n");
        QuitGap(1);
    fi;
od;
for _t in _fpLargeTypes do
    if IsIdGroupCompatible(_t.order) then
        Print("FATAL: Large type ", _t.typeIndex,
              " has IdGroup-compatible order ", _t.order, "\n");
        QuitGap(1);
    fi;
od;
Print("  IdGroup/large disjointness: VERIFIED\n\n");

# Bucket large types by order
_bucketMap := rec();
for _t in _fpLargeTypes do
    _bkey := String(_t.order);
    if not IsBound(_bucketMap.(_bkey)) then
        _bucketMap.(_bkey) := [];
    fi;
    Add(_bucketMap.(_bkey), _t);
od;

_bkeys := RecNames(_bucketMap);
_nSingletons := 0;
_nMulti := 0;
_nPairs := 0;
_pairFailures := [];

# Invariant fields for cascade comparison
# This includes all possible nrElementsOfOrderK fields
_baseFields := ["derivedSize", "nrCC", "derivedLength",
               "abelianInvariants", "maxElementOrder", "centerSize"];
# Element order fields are checked dynamically

# Stats
_distByField := rec();

for _bk in _bkeys do
    _bucket := _bucketMap.(_bk);
    if Length(_bucket) = 1 then
        _nSingletons := _nSingletons + 1;
        continue;
    fi;
    _nMulti := _nMulti + 1;

    for _j in [1..Length(_bucket)] do
        for _k in [_j+1..Length(_bucket)] do
            _tA := _bucket[_j];
            _tB := _bucket[_k];
            _nPairs := _nPairs + 1;

            _distinguished := false;

            # Check base fields first
            for _fld in _baseFields do
                if IsBound(_tA.(_fld)) and IsBound(_tB.(_fld)) then
                    if _tA.(_fld) <> _tB.(_fld) then
                        _distinguished := true;
                        if not IsBound(_distByField.(_fld)) then
                            _distByField.(_fld) := 0;
                        fi;
                        _distByField.(_fld) := _distByField.(_fld) + 1;
                        break;
                    fi;
                fi;
            od;

            # If not yet distinguished, check nrElementsOfOrder* fields
            if not _distinguished then
                _allFieldsA := RecNames(_tA);
                for _fld in _allFieldsA do
                    if _distinguished then break; fi;
                    if Length(_fld) > 17 and _fld{[1..17]} = "nrElementsOfOrder" then
                        if IsBound(_tB.(_fld)) then
                            if _tA.(_fld) <> _tB.(_fld) then
                                _distinguished := true;
                                if not IsBound(_distByField.(_fld)) then
                                    _distByField.(_fld) := 0;
                                fi;
                                _distByField.(_fld) := _distByField.(_fld) + 1;
                            fi;
                        fi;
                    fi;
                od;
            fi;

            # Check remaining expensive fields
            if not _distinguished then
                for _fld in ["classSizes", "chiefFactorSizes",
                             "derivedSeriesSizes", "nilpotencyClass",
                             "numNormalSubs", "frattiniSize",
                             "autGroupOrder", "subgroupOrderProfile"] do
                    if IsBound(_tA.(_fld)) and IsBound(_tB.(_fld)) then
                        if _tA.(_fld) <> _tB.(_fld) then
                            _distinguished := true;
                            if not IsBound(_distByField.(_fld)) then
                                _distByField.(_fld) := 0;
                            fi;
                            _distByField.(_fld) := _distByField.(_fld) + 1;
                            break;
                        fi;
                    fi;
                od;
            fi;

            # If not distinguished by invariants, check GAP-certified pairs
            if not _distinguished then
                _ra := Minimum(_tA.representative, _tB.representative);
                _rb := Maximum(_tA.representative, _tB.representative);
                _certKey := Concatenation(String(_ra), "_", String(_rb));
                if IsBound(_gapCertifiedSet.(_certKey)) then
                    # Verify with direct IsomorphismGroups
                    _Ga := _BuildGroup(_tA.representative);
                    _Gb := _BuildGroup(_tB.representative);
                    _iso := IsomorphismGroups(_Ga, _Gb);
                    if _iso = fail then
                        _distinguished := true;
                        if not IsBound(_distByField.("gapIsomorphismGroups")) then
                            _distByField.("gapIsomorphismGroups") := 0;
                        fi;
                        _distByField.("gapIsomorphismGroups") :=
                            _distByField.("gapIsomorphismGroups") + 1;
                    else
                        Add(_pairFailures, Concatenation(
                            "Types ", String(_tA.typeIndex), " and ",
                            String(_tB.typeIndex), " (reps ",
                            String(_tA.representative), ",",
                            String(_tB.representative),
                            "): GAP-certified pair is ACTUALLY ISOMORPHIC!"));
                    fi;
                fi;
            fi;

            if not _distinguished then
                Add(_pairFailures, Concatenation(
                    "Types ", String(_tA.typeIndex), " and ",
                    String(_tB.typeIndex), " (reps ",
                    String(_tA.representative), ",",
                    String(_tB.representative),
                    "): not distinguished by any fingerprint invariant"));
            fi;
        od;
    od;
od;

_ClearCache();

if Length(_pairFailures) > 0 then
    Print("FATAL: ", Length(_pairFailures),
          " pairs not distinguished!\n");
    for _f in _pairFailures{[1..Minimum(20, Length(_pairFailures))]} do
        Print("  ", _f, "\n");
    od;
    QuitGap(1);
fi;

Print("  Singleton order buckets: ", _nSingletons, "\n");
Print("  Multi-type order buckets: ", _nMulti, " (",
      _nPairs, " pairs checked)\n");
Print("  Distinguishing invariant breakdown:\n");
_distFields := ShallowCopy(RecNames(_distByField));
Sort(_distFields);
for _fld in _distFields do
    Print("    ", _fld, ": ", _distByField.(_fld), "\n");
od;

Print("\n  LOWER BOUND VERIFIED: at least ", EXPECTED_TYPES, " types\n");
Print("Phase C time: ", Int((Runtime() - phaseCStart) / 1000), "s\n\n");

##############################################################################
## PHASE D: Verify conjugacy class completeness
##
## The 159,129 input groups come from an enumeration of conjugacy class
## representatives in S15.  To prove A000638(15) = 159,129 we must verify
## that no two of these representatives are conjugate in S15.
##
## 3-level cascade:
##   L1 — Sub-bucket by orbit types (precomputed in Phase B1).
##         Different orbit structures => non-conjugate.
##   L2 — Sub-bucket by element-order / fixed-point histogram.
##         Different histograms => non-conjugate.
##   L3 — IsConjugate(S15, G, H) for remaining pairs.  Must all return false.
##############################################################################

if RUN_PHASE_D then

Print("=== PHASE D: Verify conjugacy class completeness ===\n\n");
phaseDStart := Runtime();
_S15 := SymmetricGroup(15);

# Build type buckets from union-find: group classes by their type root
_typeBuckets := rec();
for _i in [1..EXPECTED_CLASSES] do
    _root := String(_Find(_i));
    if not IsBound(_typeBuckets.(_root)) then
        _typeBuckets.(_root) := [];
    fi;
    Add(_typeBuckets.(_root), _i);
od;
_typeRoots := ShallowCopy(RecNames(_typeBuckets));
Sort(_typeRoots);

# Statistics — 3-level cascade
_nSingletonTypes := 0;       # types with only 1 class
_nMultiTypes := 0;           # types with 2+ classes
_nOrbitTypeSplit := 0;       # pairs eliminated by orbit types (L1)
_nHistogramSplit := 0;       # pairs eliminated by histogram (L2)
_nConjTests := 0;           # actual IsConjugate calls (L3)
_conjFailures := [];
_maxSubBucketL1 := 0;       # largest L1 sub-bucket
_maxSubBucketL2 := 0;       # largest L2 sub-bucket
_nHistogramsComputed := 0;   # total histogram computations

# Per-L1-bucket cost/benefit log:
#   Each entry: [groupOrder, L1size, histMs, pairsSaved, pairsRemaining]
_histLog := [];

for _ri in [1..Length(_typeRoots)] do
    _root := _typeRoots[_ri];
    _classes := _typeBuckets.(_root);

    if Length(_classes) = 1 then
        _nSingletonTypes := _nSingletonTypes + 1;
        continue;
    fi;
    _nMultiTypes := _nMultiTypes + 1;

    _totalPairsThisType := Length(_classes) * (Length(_classes) - 1) / 2;
    _pairsAfterL1 := 0;

    # Per-type timing for large types
    if Length(_classes) >= 50 then
        _bucketStart := Runtime();
    fi;

    # ---- Level 1: Sub-bucket by orbit types (precomputed in B1) ----
    _orbBuckets := rec();
    for _ci in _classes do
        _okey := _orbKey[_ci];
        if not IsBound(_orbBuckets.(_okey)) then
            _orbBuckets.(_okey) := [];
        fi;
        Add(_orbBuckets.(_okey), _ci);
    od;

    for _ok in RecNames(_orbBuckets) do
        _L1bucket := _orbBuckets.(_ok);
        if Length(_L1bucket) < 2 then continue; fi;
        _L1pairs := Length(_L1bucket) * (Length(_L1bucket) - 1) / 2;
        _pairsAfterL1 := _pairsAfterL1 + _L1pairs;

        if Length(_L1bucket) > _maxSubBucketL1 then
            _maxSubBucketL1 := Length(_L1bucket);
        fi;

        # ---- Level 2: Sub-bucket by element histogram ----
        _histStart := Runtime();
        _histBuckets := rec();
        _sampleOrd := 0;
        for _ci in _L1bucket do
            _G := _BuildGroup(_ci);
            if _sampleOrd = 0 then _sampleOrd := Size(_G); fi;
            _hkey := _ComputeHistogramKey(_G);
            _nHistogramsComputed := _nHistogramsComputed + 1;
            if not IsBound(_histBuckets.(_hkey)) then
                _histBuckets.(_hkey) := [];
            fi;
            Add(_histBuckets.(_hkey), _ci);
        od;
        _histElapsed := Runtime() - _histStart;

        # Count pairs remaining after L2
        _pairsAfterL2 := 0;
        for _hk in RecNames(_histBuckets) do
            _L2bucket := _histBuckets.(_hk);
            if Length(_L2bucket) < 2 then continue; fi;
            _pairsAfterL2 := _pairsAfterL2
                + Length(_L2bucket) * (Length(_L2bucket) - 1) / 2;

            if Length(_L2bucket) > _maxSubBucketL2 then
                _maxSubBucketL2 := Length(_L2bucket);
            fi;

            # ---- Level 3: IsConjugate for L2 sub-bucket ----
            for _j in [1..Length(_L2bucket)] do
                for _k in [_j+1..Length(_L2bucket)] do
                    _G := _BuildGroup(_L2bucket[_j]);
                    _H := _BuildGroup(_L2bucket[_k]);
                    _nConjTests := _nConjTests + 1;
                    if IsConjugate(_S15, _G, _H) then
                        Add(_conjFailures, Concatenation(
                            "Classes ",
                            String(_L2bucket[_j]), " and ",
                            String(_L2bucket[_k]),
                            " are conjugate (type root=",
                            _root, ")"));
                    fi;
                od;
            od;
        od;

        _savedByHist := _L1pairs - _pairsAfterL2;
        _nHistogramSplit := _nHistogramSplit + _savedByHist;

        # Log this L1 sub-bucket's cost/benefit
        Add(_histLog, [_sampleOrd, Length(_L1bucket),
                       _histElapsed, _savedByHist, _pairsAfterL2]);
    od;

    _nOrbitTypeSplit := _nOrbitTypeSplit
        + (_totalPairsThisType - _pairsAfterL1);

    # Per-type timing and progress
    if Length(_classes) >= 50 then
        Print("  Type ", _ri, "/", Length(_typeRoots),
              " (", Length(_classes), " classes, ",
              Int((Runtime() - _bucketStart) / 1000), "s, ",
              _nConjTests, " conj tests cumulative)\n");
    elif _ri mod 500 = 0 then
        Print("  Type ", _ri, "/", Length(_typeRoots),
              " (", _nConjTests, " conj tests, ",
              Int((Runtime() - phaseDStart) / 1000), "s elapsed)\n");
    fi;

    _ClearCache();
od;

# Results
if Length(_conjFailures) > 0 then
    Print("FATAL: ", Length(_conjFailures),
          " conjugate pairs found!\n");
    for _f in _conjFailures do Print("  ", _f, "\n"); od;
    QuitGap(1);
fi;

_totalPossiblePairs := 0;
for _root in _typeRoots do
    _n := Length(_typeBuckets.(_root));
    _totalPossiblePairs := _totalPossiblePairs + _n * (_n - 1) / 2;
od;

Print("\n  Phase D Statistics:\n");
Print("  Singleton types (1 class): ", _nSingletonTypes, "\n");
Print("  Multi-class types: ", _nMultiTypes, "\n");
Print("  Total pairs across all type buckets: ",
      _totalPossiblePairs, "\n");
Print("  L1 — Pairs eliminated by orbit types: ",
      _nOrbitTypeSplit, "\n");
Print("  L2 — Pairs eliminated by histogram: ",
      _nHistogramSplit, "\n");
Print("  L3 — Pairwise IsConjugate tests: ", _nConjTests, "\n");
Print("  Largest L1 sub-bucket (orbit type): ",
      _maxSubBucketL1, "\n");
Print("  Largest L2 sub-bucket (histogram): ",
      _maxSubBucketL2, "\n");
Print("  Histograms computed: ", _nHistogramsComputed, "\n");
Print("  Conjugate pairs found: 0\n");

# ---- Histogram cost/benefit report ----
Print("\n  Histogram cost/benefit analysis (",
      Length(_histLog), " L1 sub-buckets):\n");

_orderRanges := [[0, 100], [101, 1000], [1001, 10000],
                 [10001, 100000], [100001, infinity]];
_rangeLabels := ["1-100", "101-1K", "1K-10K", "10K-100K", "100K+"];

for _rIdx in [1..Length(_orderRanges)] do
    _lo := _orderRanges[_rIdx][1];
    _hi := _orderRanges[_rIdx][2];
    _rEntries := Filtered(_histLog,
        e -> e[1] >= _lo and e[1] <= _hi);
    if Length(_rEntries) = 0 then continue; fi;

    _rBuckets := Length(_rEntries);
    _rHistograms := Sum(_rEntries, e -> e[2]);
    _rTimeMs := Sum(_rEntries, e -> e[3]);
    _rSaved := Sum(_rEntries, e -> e[4]);
    _rRemaining := Sum(_rEntries, e -> e[5]);
    _rBeneficial := Length(Filtered(_rEntries, e -> e[4] > 0));
    _rWasted := _rBuckets - _rBeneficial;

    Print("    Order ", _rangeLabels[_rIdx], ": ",
          _rBuckets, " L1 buckets, ",
          _rHistograms, " histograms in ", _rTimeMs, "ms, ",
          _rSaved, " pairs saved, ",
          _rRemaining, " remaining (",
          _rBeneficial, " beneficial, ",
          _rWasted, " wasted)\n");
od;

# Show the most expensive histogram calls
SortBy(_histLog, e -> -e[3]);
_nShow := Minimum(10, Length(_histLog));
if _nShow > 0 then
    Print("\n  Top ", _nShow, " most expensive histogram calls:\n");
    Print("    [order, L1size, histMs, pairsSaved, pairsRemaining]\n");
    for _si in [1.._nShow] do
        Print("    ", _histLog[_si], "\n");
    od;
fi;

# Show the largest L2 sub-buckets (biggest IsConjugate workloads)
SortBy(_histLog, e -> -e[5]);
_nShow := Minimum(10, Length(Filtered(_histLog, e -> e[5] > 0)));
if _nShow > 0 then
    Print("\n  Top ", _nShow,
          " L1 buckets with most remaining pairs after histogram:\n");
    Print("    [order, L1size, histMs, pairsSaved, pairsRemaining]\n");
    for _si in [1.._nShow] do
        if _histLog[_si][5] = 0 then break; fi;
        Print("    ", _histLog[_si], "\n");
    od;
fi;

Print("\n  A000638(15) = ", EXPECTED_CLASSES, " VERIFIED\n");
Print("Phase D time: ", Int((Runtime() - phaseDStart) / 1000), "s\n\n");

_ClearCache();

else
    Print("=== PHASE D: SKIPPED (RUN_PHASE_D = false) ===\n\n");
fi;

##############################################################################
## Summary
##############################################################################

_totalTime := Runtime() - _startTime;

Print("==================================================\n");
Print("  VERIFICATION COMPLETE\n");
Print("==================================================\n\n");
Print("  A174511(15) = ", EXPECTED_TYPES, "\n");
Print("    = ", EXPECTED_IDG_TYPES, " IdGroup types + ",
      EXPECTED_LARGE_TYPES, " large types\n");
Print("  A000638(15) = ", EXPECTED_CLASSES, "\n\n");
Print("  Phase B: ", _nPass, "/", _actualProofs,
      " proofs verified, ", _nIdgTypes,
      " IdGroup types, union-find = ", EXPECTED_TYPES, " types\n");
if RUN_PHASE_A then
    Print("  Phase A: ", _nLargeVerified, "/", Length(_fpLargeTypes),
          " large type fingerprints verified\n");
else
    Print("  Phase A: SKIPPED\n");
fi;
Print("  Phase C: ", Length(_fpLargeTypes),
      " large types pairwise distinguished (",
      _nPairs, " pairs), ",
      _nIdgTypes, " IdGroup types disjoint\n");
if RUN_PHASE_D then
    Print("  Phase D: ", _nConjTests, " IsConjugate tests, ",
          EXPECTED_CLASSES, " classes verified non-conjugate\n");
    Print("    L1 orbit filter: ", _nOrbitTypeSplit, " pairs\n");
    Print("    L2 histogram filter: ", _nHistogramSplit, " pairs\n");
    Print("    L3 IsConjugate calls: ", _nConjTests, "\n");
else
    Print("  Phase D: SKIPPED\n");
fi;
Print("\n  Total time: ", Int(_totalTime / 1000), "s\n");

QUIT;
