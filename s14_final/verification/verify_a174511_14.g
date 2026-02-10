##############################################################################
##
##  verify_a174511_14.g
##
##  Self-contained verification that A174511(14) = 7,766
##  (Number of isomorphism types of subgroups of S_14)
##
##  Inputs (relative to BASE_DIR):
##    s14_subgroups.g       - 75,154 conjugacy class representatives
##    proof_all_remapped.g  - 7,523 isomorphism proofs
##
##  Phases:
##    A: Load and validate input data
##    B: Compute invariants for all 75,154 groups
##    C: Verify all 75,154 are pairwise non-conjugate in S_14
##    D: Verify isomorphism proofs + build 75,154 -> 7,766 mapping
##    E: Verify 7,766 type representatives are pairwise non-isomorphic
##    F: Output mapping, fingerprints, and summary
##
##  Options (set before Read()ing this script):
##    SKIP_CONJUGACY := true;   # skip Phase C (non-conjugacy checks)
##    TRUST_INVARIANTS := true;  # load Phase B from phase_b_invariants.g
##
##############################################################################

BASE_DIR := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s14_final/";
OUT_DIR := Concatenation(BASE_DIR, "verification/");

# Output file paths
PHASE_B_FILE := Concatenation(OUT_DIR, "phase_b_invariants.g");
PHASE_C_FILE := Concatenation(OUT_DIR, "phase_c_nonconjugacy.txt");
PHASE_D_FILE := Concatenation(OUT_DIR, "phase_d_proof_verification.txt");
PHASE_E_FILE := Concatenation(OUT_DIR, "phase_e_noniso.txt");
MAPPING_FILE := Concatenation(OUT_DIR, "class_to_type_mapping.g");
FINGERPRINT_FILE := Concatenation(OUT_DIR, "type_fingerprints.g");
SUMMARY_FILE := Concatenation(OUT_DIR, "verification_summary.txt");

# Options (can be set before Read()ing this script)
if not IsBound(SKIP_CONJUGACY) then
    SKIP_CONJUGACY := false;
fi;
if not IsBound(TRUST_INVARIANTS) then
    TRUST_INVARIANTS := false;
fi;

# Expected constants
EXPECTED_CLASSES := 75154;
EXPECTED_PROOFS := 7523;
EXPECTED_IDGROUP_TYPES := 4602;
EXPECTED_LARGE_REPS := 3164;
EXPECTED_TOTAL := 7766;

Print("==================================================\n");
Print("  A174511(14) Self-Contained Verification Script\n");
Print("==================================================\n\n");

##############################################################################
## PHASE A: Load and validate input data
##############################################################################

Print("=== PHASE A: Load and validate input data ===\n\n");
phaseAStart := Runtime();

Print("Loading s14_subgroups.g (may take ~2 min)...\n");
subgens := ReadAsFunction(Concatenation(BASE_DIR, "s14_subgroups.g"))();;
Print("  Loaded ", Length(subgens), " generator lists\n");
if Length(subgens) <> EXPECTED_CLASSES then
    Print("FATAL: Expected ", EXPECTED_CLASSES, " but got ", Length(subgens), "\n");
    QuitGap(1);
fi;

Print("Loading proof_all_remapped.g...\n");
Read(Concatenation(BASE_DIR, "proof_all_remapped.g"));
Print("  Loaded ", Length(FV_ALL_PROOFS), " proofs\n");
if Length(FV_ALL_PROOFS) <> EXPECTED_PROOFS then
    Print("FATAL: Expected ", EXPECTED_PROOFS, " proofs but got ",
          Length(FV_ALL_PROOFS), "\n");
    QuitGap(1);
fi;

# Validate proof indices
Print("Validating proof index ranges...\n");
proofIndexOK := true;
for _p in FV_ALL_PROOFS do
    if _p.duplicate < 1 or _p.duplicate > EXPECTED_CLASSES then
        Print("ERROR: duplicate index ", _p.duplicate, " out of range\n");
        proofIndexOK := false;
    fi;
    if _p.representative < 1 or _p.representative > EXPECTED_CLASSES then
        Print("ERROR: representative index ", _p.representative, " out of range\n");
        proofIndexOK := false;
    fi;
    if _p.duplicate = _p.representative then
        Print("ERROR: self-link at index ", _p.duplicate, "\n");
        proofIndexOK := false;
    fi;
od;
if not proofIndexOK then
    Print("FATAL: Proof index validation failed\n");
    QuitGap(1);
fi;
Print("  All proof indices valid\n");

# Verify EvalString works for permutations
_evalOK := (EvalString("(1,2)") = (1,2)) and (EvalString("(1,2)(3,4)") = (1,2)(3,4));
if not _evalOK then
    Print("FATAL: EvalString does not work for permutations\n");
    QuitGap(1);
fi;
Print("  EvalString verified OK\n");

Print("Phase A complete: ", Int((Runtime() - phaseAStart)/1000), "s\n\n");

##############################################################################
## PHASE B: Compute invariants for all 75,154 groups
##############################################################################

phaseBStart := Runtime();

# Helper: check IdGroup compatibility
IsIdGroupCompatible := function(order)
    return order < 2000 and not order in [512, 768, 1024, 1536];
end;

# Storage for invariants (records indexed by group number)
allInvariants := [];
_idgCount := 0;
_largeCount := 0;

if TRUST_INVARIANTS then
    Print("=== PHASE B: Loading precomputed invariants ===\n\n");
    Print("Reading ", PHASE_B_FILE, "...\n");
    Read(PHASE_B_FILE);
    if not IsBound(PHASE_B_INVARIANTS) then
        Print("FATAL: PHASE_B_INVARIANTS not found in file\n");
        QuitGap(1);
    fi;
    if Length(PHASE_B_INVARIANTS) <> EXPECTED_CLASSES then
        Print("FATAL: Expected ", EXPECTED_CLASSES, " invariant records, got ",
              Length(PHASE_B_INVARIANTS), "\n");
        QuitGap(1);
    fi;
    allInvariants := PHASE_B_INVARIANTS;
    Unbind(PHASE_B_INVARIANTS);
    for _i in [1..EXPECTED_CLASSES] do
        if allInvariants[_i].idGroup <> fail then
            _idgCount := _idgCount + 1;
        else
            _largeCount := _largeCount + 1;
        fi;
    od;
    Print("  Loaded ", EXPECTED_CLASSES, " invariant records (",
          _idgCount, " idg, ", _largeCount, " large)\n");
    Print("Phase B (load) time: ", Int((Runtime() - phaseBStart)/1000), "s\n\n");

else
    Print("=== PHASE B: Compute invariants for all 75,154 groups ===\n\n");

    # Initialize output file
    PrintTo(PHASE_B_FILE,
        "# Phase B: Invariants for ", EXPECTED_CLASSES,
        " S14 conjugacy class reps\n");
    AppendTo(PHASE_B_FILE, "# Generated by verify_a174511_14.g\n");
    AppendTo(PHASE_B_FILE, "PHASE_B_INVARIANTS := [\n");

    for _i in [1..EXPECTED_CLASSES] do
        # Progress
        if _i mod 500 = 0 or _i = 1 then
            _elapsed := Runtime() - phaseBStart;
            if _i > 1 then
                _eta := Int(_elapsed * (EXPECTED_CLASSES - _i) / _i / 1000);
            else
                _eta := 0;
            fi;
            Print("Phase B: group ", _i, "/", EXPECTED_CLASSES,
                  " (", _idgCount, " idg, ", _largeCount, " large)",
                  " ETA=", _eta, "s\n");
        fi;

        # Build group from generator lists
        _gens := List(subgens[_i], PermList);
        _G := Group(_gens);

        _inv := rec();
        _inv.index := _i;
        _inv.order := Size(_G);

        # sigKey: [order, derivedSize, nrCC, derivedLength, abelianInvariants]
        _D := DerivedSubgroup(_G);
        _derivedSize := Size(_D);
        _inv.nrCC := NrConjugacyClasses(_G);
        if IsSolvableGroup(_G) then
            _derivedLength := DerivedLength(_G);
        else
            _derivedLength := -1;
        fi;
        _abi := ShallowCopy(AbelianInvariants(_G/_D));
        Sort(_abi);
        _inv.sigKey := [_inv.order, _derivedSize, _inv.nrCC,
                        _derivedLength, _abi];

        # Exponent
        _inv.exponent := Exponent(_G);

        # IdGroup (if compatible)
        if IsIdGroupCompatible(_inv.order) then
            _inv.idGroup := IdGroup(_G);
            _idgCount := _idgCount + 1;
        else
            _inv.idGroup := fail;
            _largeCount := _largeCount + 1;
        fi;

        allInvariants[_i] := _inv;

        # Write record to checkpoint file
        AppendTo(PHASE_B_FILE, "rec(index:=", _i,
                 ",order:=", _inv.order,
                 ",nrCC:=", _inv.nrCC,
                 ",sigKey:=", _inv.sigKey,
                 ",exponent:=", _inv.exponent,
                 ",idGroup:=", _inv.idGroup, ")");
        if _i < EXPECTED_CLASSES then
            AppendTo(PHASE_B_FILE, ",\n");
        else
            AppendTo(PHASE_B_FILE, "\n");
        fi;

        # Release group object
        Unbind(_G);
        Unbind(_D);
    od;

    AppendTo(PHASE_B_FILE, "];\n");

    Print("\nPhase B complete: ", _idgCount, " IdGroup-compatible, ",
          _largeCount, " large\n");
    Print("Phase B time: ", Int((Runtime() - phaseBStart)/1000), "s\n\n");
fi;

##############################################################################
## PHASE C: Verify non-conjugacy (all 75,154 pairwise non-conjugate in S_14)
##############################################################################

phaseCStart := Runtime();

if SKIP_CONJUGACY then
    Print("=== PHASE C: SKIPPED (SKIP_CONJUGACY = true) ===\n\n");
    _phaseCStats := rec(skipped := true);
else

Print("=== PHASE C: Verify non-conjugacy ===\n\n");
PrintTo(PHASE_C_FILE, "# Phase C: Non-conjugacy verification\n\n");

# Bucket by (order, orbProfile, efpHist) - S14-conjugacy invariants
# These are computed here (not in Phase B) to keep Phase B lightweight
Print("Computing S14-conjugacy invariants and bucketing...\n");

_bucketMap := rec();
for _i in [1..EXPECTED_CLASSES] do
    if _i mod 5000 = 0 then
        Print("  Phase C bucketing: ", _i, "/", EXPECTED_CLASSES, "\n");
    fi;
    _G := Group(List(subgens[_i], PermList));
    _orbs := Orbits(_G, [1..14]);
    _orbProfile := SortedList(List(_orbs, Length));
    _cc := ConjugacyClasses(_G);
    _efpList := [];
    for _c in _cc do
        _rep := Representative(_c);
        Add(_efpList, [Order(_rep), 14 - NrMovedPoints(_rep), Size(_c)]);
    od;
    Sort(_efpList);
    Unbind(_G);
    Unbind(_cc);

    # Build a compact key string
    _bkey := Concatenation(String(allInvariants[_i].order), "_",
                           String(_orbProfile), "_",
                           String(_efpList));
    if Length(_bkey) > 1000 then
        _bkey := Concatenation(String(allInvariants[_i].order), "_",
                               String(_orbProfile), "_",
                               String(Length(_efpList)), "_",
                               String(allInvariants[_i].nrCC));
    fi;
    if not IsBound(_bucketMap.(_bkey)) then
        _bucketMap.(_bkey) := [];
    fi;
    Add(_bucketMap.(_bkey), _i);
od;

_bucketKeys := RecNames(_bucketMap);
_nBuckets := Length(_bucketKeys);
_nSingletons := 0;
_nMulti := 0;
_nPairsToTest := 0;
_multiGroups := 0;

for _bk in _bucketKeys do
    if Length(_bucketMap.(_bk)) = 1 then
        _nSingletons := _nSingletons + 1;
    else
        _nMulti := _nMulti + 1;
        _bsize := Length(_bucketMap.(_bk));
        _nPairsToTest := _nPairsToTest + _bsize * (_bsize - 1) / 2;
        _multiGroups := _multiGroups + _bsize;
    fi;
od;

Print("  Total buckets: ", _nBuckets, "\n");
Print("  Singleton buckets: ", _nSingletons, "\n");
Print("  Multi-group buckets: ", _nMulti, " (", _multiGroups, " groups, ",
      _nPairsToTest, " pairs)\n");
AppendTo(PHASE_C_FILE, "Total buckets: ", _nBuckets, "\n");
AppendTo(PHASE_C_FILE, "Singleton buckets: ", _nSingletons, "\n");
AppendTo(PHASE_C_FILE, "Multi-group buckets: ", _nMulti, "\n");
AppendTo(PHASE_C_FILE, "Pairs to test: ", _nPairsToTest, "\n\n");

# Test all pairs within non-singleton buckets
_S14 := SymmetricGroup(14);
_conjTestCount := 0;
_conjFailures := 0;
_testedPairs := 0;

for _bk in _bucketKeys do
    _bucket := _bucketMap.(_bk);
    if Length(_bucket) <= 1 then
        continue;
    fi;

    AppendTo(PHASE_C_FILE, "Bucket ", _bk, ": ", Length(_bucket), " groups [",
             _bucket, "]\n");

    for _j in [1..Length(_bucket)] do
        for _k in [_j+1..Length(_bucket)] do
            _idxA := _bucket[_j];
            _idxB := _bucket[_k];

            # Rebuild groups
            _GA := Group(List(subgens[_idxA], PermList));
            _GB := Group(List(subgens[_idxB], PermList));

            _isConj := IsConjugate(_S14, _GA, _GB);
            _testedPairs := _testedPairs + 1;

            if _isConj then
                _conjFailures := _conjFailures + 1;
                Print("FAIL: groups ", _idxA, " and ", _idxB,
                      " are conjugate in S14!\n");
                AppendTo(PHASE_C_FILE, "  FAIL: ", _idxA, " ~ ", _idxB,
                         " CONJUGATE\n");
            else
                AppendTo(PHASE_C_FILE, "  PASS: ", _idxA, " !~ ", _idxB, "\n");
            fi;

            Unbind(_GA);
            Unbind(_GB);

            if _testedPairs mod 50 = 0 then
                Print("  Phase C: ", _testedPairs, "/", _nPairsToTest,
                      " pairs tested, ", _conjFailures, " failures\n");
            fi;
        od;
    od;
od;

Unbind(_S14);

AppendTo(PHASE_C_FILE, "\nSummary: ", _testedPairs, " pairs tested, ",
         _conjFailures, " failures\n");

if _conjFailures > 0 then
    Print("FATAL: ", _conjFailures, " conjugate pairs found!\n");
    QuitGap(1);
fi;

Print("Phase C complete: all ", EXPECTED_CLASSES,
      " groups verified pairwise non-conjugate\n");
Print("  ", _nSingletons, " singleton buckets, ", _testedPairs,
      " pairs tested via IsConjugate\n");
Print("Phase C time: ", Int((Runtime() - phaseCStart)/1000), "s\n\n");

# Save Phase C stats for summary
_phaseCStats := rec(
    skipped := false,
    nBuckets := _nBuckets,
    nSingletons := _nSingletons,
    nMulti := _nMulti,
    nPairsToTest := _nPairsToTest,
    nTestedPairs := _testedPairs
);

fi; # end SKIP_CONJUGACY

##############################################################################
## PHASE D: Verify isomorphism proofs + build mapping
##############################################################################

Print("=== PHASE D: Verify isomorphism proofs + build mapping ===\n\n");
phaseDStart := Runtime();
PrintTo(PHASE_D_FILE, "# Phase D: Isomorphism proof verification\n\n");

# D1: Verify all 7,523 proofs
Print("D1: Verifying ", EXPECTED_PROOFS, " isomorphism proofs...\n");

_nProofPass := 0;
_proofFailures := [];

# Group cache for proof verification
_proofGroupCache := rec();

_BuildGroup := function(idx)
    local key, grp;
    key := Concatenation("g", String(idx));
    if IsBound(_proofGroupCache.(key)) then
        return _proofGroupCache.(key);
    fi;
    grp := Group(List(subgens[idx], PermList));
    _proofGroupCache.(key) := grp;
    return grp;
end;

for _i in [1..Length(FV_ALL_PROOFS)] do
    _p := FV_ALL_PROOFS[_i];

    if _i mod 200 = 0 or _i <= 5 then
        _elapsed := Runtime() - phaseDStart;
        if _i > 1 then
            _eta := Int(_elapsed * (Length(FV_ALL_PROOFS) - _i) / _i / 1000);
        else
            _eta := 0;
        fi;
        Print("  Proof ", _i, "/", Length(FV_ALL_PROOFS),
              " pass=", _nProofPass, " fail=", Length(_proofFailures),
              " ETA=", _eta, "s\n");
    fi;

    _G := _BuildGroup(_p.duplicate);
    _H := _BuildGroup(_p.representative);
    _sizeG := Size(_G);
    _sizeH := Size(_H);

    # Check 1: orders match
    if _sizeG <> _sizeH then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": order mismatch |G|=", String(_sizeG), " |H|=", String(_sizeH)));
        AppendTo(PHASE_D_FILE, "FAIL proof ", _i, ": order mismatch\n");
        continue;
    fi;

    # Parse generators and images
    _proofGens := List(_p.gens, EvalString);
    _proofImgs := List(_p.images, EvalString);

    if Length(_proofGens) <> Length(_proofImgs) then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": gens/images length mismatch"));
        AppendTo(PHASE_D_FILE, "FAIL proof ", _i, ": length mismatch\n");
        continue;
    fi;

    # Check 2: all gens in G
    if not ForAll(_proofGens, g -> g in _G) then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": generator not in G"));
        AppendTo(PHASE_D_FILE, "FAIL proof ", _i, ": gen not in G\n");
        continue;
    fi;

    # Check 3: all images in H
    if not ForAll(_proofImgs, h -> h in _H) then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": image not in H"));
        AppendTo(PHASE_D_FILE, "FAIL proof ", _i, ": image not in H\n");
        continue;
    fi;

    # Check 4: gens generate G
    _genGroup := Group(_proofGens);
    if Size(_genGroup) <> _sizeG then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": gens don't generate G"));
        AppendTo(PHASE_D_FILE, "FAIL proof ", _i, ": gens don't generate G\n");
        continue;
    fi;

    # Check 5: valid homomorphism
    _phi := GroupHomomorphismByImages(_G, _H, _proofGens, _proofImgs);
    if _phi = fail then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": GroupHomomorphismByImages returned fail, order=",
            String(_sizeG)));
        AppendTo(PHASE_D_FILE, "FAIL proof ", _i, ": hom check failed\n");
        continue;
    fi;

    # Check 6: injective (kernel is trivial)
    if not IsInjective(_phi) then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": homomorphism is not injective, order=", String(_sizeG)));
        AppendTo(PHASE_D_FILE, "FAIL proof ", _i, ": not injective\n");
        continue;
    fi;

    # Check 7: surjective (image is all of H)
    if not IsSurjective(_phi) then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": homomorphism is not surjective, order=", String(_sizeG)));
        AppendTo(PHASE_D_FILE, "FAIL proof ", _i, ": not surjective\n");
        continue;
    fi;

    _nProofPass := _nProofPass + 1;

    # Checkpoint
    if _i mod 200 = 0 then
        AppendTo(PHASE_D_FILE, "Checkpoint: ", _i, " proofs checked, ",
                 _nProofPass, " passed\n");
    fi;
od;

# Clear proof group cache
Unbind(_proofGroupCache);

AppendTo(PHASE_D_FILE, "\nD1 Summary: ", _nProofPass, "/",
         Length(FV_ALL_PROOFS), " proofs passed\n");
AppendTo(PHASE_D_FILE, "  All proofs verified as bijective homomorphisms\n");

if Length(_proofFailures) > 0 then
    Print("FATAL: ", Length(_proofFailures), " proofs failed!\n");
    for _f in _proofFailures do
        Print("  ", _f, "\n");
    od;
    QuitGap(1);
fi;

Print("D1 complete: ", _nProofPass, "/", Length(FV_ALL_PROOFS),
      " proofs verified as bijective homomorphisms\n");

# D2: Build union-find mapping

Print("\nD2: Building union-find mapping...\n");

# parent[i] = root representative for group i
_parent := [1..EXPECTED_CLASSES];

# Find with path compression
_Find := function(x)
    local root, tmp;
    root := x;
    while _parent[root] <> root do
        root := _parent[root];
    od;
    while _parent[x] <> root do
        tmp := _parent[x];
        _parent[x] := root;
        x := tmp;
    od;
    return root;
end;

# Union: always point to smaller index
_Union := function(a, b)
    local ra, rb;
    ra := _Find(a);
    rb := _Find(b);
    if ra <> rb then
        if ra < rb then
            _parent[rb] := ra;
        else
            _parent[ra] := rb;
        fi;
    fi;
end;

# Step 1: Union groups with same IdGroup
Print("  Unioning by IdGroup...\n");
_idGroupMap := rec();  # "[order, id]" -> smallest index

for _i in [1..EXPECTED_CLASSES] do
    _inv := allInvariants[_i];
    if _inv.idGroup <> fail then
        _idKey := String(_inv.idGroup);
        if IsBound(_idGroupMap.(_idKey)) then
            _Union(_i, _idGroupMap.(_idKey));
        else
            _idGroupMap.(_idKey) := _i;
        fi;
    fi;
od;

_nIdGroupTypes := Length(RecNames(_idGroupMap));
Print("  IdGroup types found: ", _nIdGroupTypes, "\n");

# Step 2: Apply verified isomorphism proofs for large groups
Print("  Applying ", Length(FV_ALL_PROOFS), " isomorphism proofs...\n");

for _p in FV_ALL_PROOFS do
    _Union(_p.duplicate, _p.representative);
od;

# D3: Count distinct roots
Print("\nD3: Counting distinct types...\n");

_roots := [];
for _i in [1..EXPECTED_CLASSES] do
    AddSet(_roots, _Find(_i));
od;
_nTypes := Length(_roots);

Print("  Total distinct types: ", _nTypes, "\n");

# Verify IdGroup/large split
_idgRoots := [];
_largeRoots := [];
for _r in _roots do
    if allInvariants[_r].idGroup <> fail then
        AddSet(_idgRoots, _r);
    else
        AddSet(_largeRoots, _r);
    fi;
od;

# Some IdGroup roots may have been unioned to a large root or vice versa.
# Recount properly: a "type" is IdGroup if ANY member has a valid IdGroup.
_idgTypeSet := rec();  # "[o,id]" -> root
_largeRootSet := [];

for _i in [1..EXPECTED_CLASSES] do
    _root := _Find(_i);
    _inv := allInvariants[_i];
    if _inv.idGroup <> fail then
        _idKey := String(_inv.idGroup);
        if not IsBound(_idgTypeSet.(_idKey)) then
            _idgTypeSet.(_idKey) := _root;
        fi;
    fi;
od;

_nIdTypes := Length(RecNames(_idgTypeSet));

# Large types: roots that have no IdGroup member
_idgRootValues := [];
for _k in RecNames(_idgTypeSet) do
    AddSet(_idgRootValues, _idgTypeSet.(_k));
od;

_nLargeTypes := 0;
for _r in _roots do
    if not _r in _idgRootValues then
        _nLargeTypes := _nLargeTypes + 1;
        Add(_largeRootSet, _r);
    fi;
od;

Print("  IdGroup types: ", _nIdTypes, "\n");
Print("  Large group types: ", _nLargeTypes, "\n");
Print("  Total: ", _nIdTypes + _nLargeTypes, "\n");

AppendTo(PHASE_D_FILE, "\nD3 Summary:\n");
AppendTo(PHASE_D_FILE, "  IdGroup types: ", _nIdTypes, "\n");
AppendTo(PHASE_D_FILE, "  Large group types: ", _nLargeTypes, "\n");
AppendTo(PHASE_D_FILE, "  Total types: ", _nIdTypes + _nLargeTypes, "\n");

if _nIdTypes <> EXPECTED_IDGROUP_TYPES then
    Print("WARNING: Expected ", EXPECTED_IDGROUP_TYPES, " IdGroup types, got ",
          _nIdTypes, "\n");
fi;
if _nLargeTypes <> EXPECTED_LARGE_REPS then
    Print("WARNING: Expected ", EXPECTED_LARGE_REPS, " large types, got ",
          _nLargeTypes, "\n");
fi;
if _nIdTypes + _nLargeTypes <> EXPECTED_TOTAL then
    Print("FATAL: Expected ", EXPECTED_TOTAL, " total types, got ",
          _nIdTypes + _nLargeTypes, "\n");
    QuitGap(1);
fi;

Print("Phase D complete: ", _nTypes, " types confirmed\n");
Print("Phase D time: ", Int((Runtime() - phaseDStart)/1000), "s\n\n");

##############################################################################
## PHASE E: Verify non-isomorphism of 7,766 types
##############################################################################

Print("=== PHASE E: Verify non-isomorphism of ", EXPECTED_TOTAL, " types ===\n\n");
phaseEStart := Runtime();
PrintTo(PHASE_E_FILE, "# Phase E: Non-isomorphism verification\n\n");

# E1: IdGroup types are distinct by definition
Print("E1: ", _nIdTypes, " IdGroup types are distinct by definition\n");
AppendTo(PHASE_E_FILE, "E1: ", _nIdTypes,
         " IdGroup types distinct by IdGroup identifier\n\n");

# E3 (early): Verify no overlap between IdGroup types and large types
Print("E3: Verifying IdGroup/large type disjointness...\n");
_overlapCount := 0;
for _r in _largeRootSet do
    _ord := allInvariants[_r].order;
    if IsIdGroupCompatible(_ord) then
        Print("  ERROR: Large rep ", _r, " has IdGroup-compatible order ", _ord, "\n");
        _overlapCount := _overlapCount + 1;
    fi;
od;
if _overlapCount = 0 then
    Print("  Confirmed: all large reps have order >= 2000 or in {512,768,1024,1536}\n");
else
    Print("WARNING: ", _overlapCount, " large reps with IdGroup-compatible order\n");
fi;
AppendTo(PHASE_E_FILE, "E3: ", _overlapCount,
         " overlaps between IdGroup and large types\n\n");

# E2: Large group representatives must be pairwise non-isomorphic
Print("\nE2: Verifying ", _nLargeTypes,
      " large group reps pairwise non-isomorphic...\n");

# Bucket large reps by (sigKey, exponent) from Phase B
_largeBucketMap := rec();
for _r in _largeRootSet do
    _inv := allInvariants[_r];
    _lbkey := Concatenation(String(_inv.sigKey), "_",
                            String(_inv.exponent));
    if not IsBound(_largeBucketMap.(_lbkey)) then
        _largeBucketMap.(_lbkey) := [];
    fi;
    Add(_largeBucketMap.(_lbkey), _r);
od;

_lbKeys := RecNames(_largeBucketMap);
_lnSingletons := 0;
_lnMulti := 0;
_lnPairs := 0;

for _lbk in _lbKeys do
    if Length(_largeBucketMap.(_lbk)) = 1 then
        _lnSingletons := _lnSingletons + 1;
    else
        _lnMulti := _lnMulti + 1;
        _bs := Length(_largeBucketMap.(_lbk));
        _lnPairs := _lnPairs + _bs * (_bs - 1) / 2;
    fi;
od;

Print("  Large invariant buckets: singletons=", _lnSingletons,
      " multi=", _lnMulti, " pairs=", _lnPairs, "\n");
AppendTo(PHASE_E_FILE, "E2: Large rep buckets: ", _lnSingletons,
         " singletons, ", _lnMulti, " multi (", _lnPairs, " pairs)\n\n");

# Stats for summary
_e2Stats := rec(
    singletons := _lnSingletons,
    byCenterSize := 0,
    byElemOrdProfile := 0,
    byClassSizes := 0,
    byChiefFactors := 0,
    byDerivedSeries := 0,
    byNilpotency := 0,
    byNormalSubs := 0,
    byFrattini := 0,
    byAutGroup := 0,
    bySubgroupProfile := 0,
    byIsomorphismGroups := 0,
    byPowerMap := 0,
    failures := 0
);

# Group cache for Phase E (bounded)
_phaseECache := rec();
_phaseECacheSize := 0;

_GetGroupE := function(idx)
    local key, grp;
    key := Concatenation("g", String(idx));
    if IsBound(_phaseECache.(key)) then
        return _phaseECache.(key);
    fi;
    grp := Group(List(subgens[idx], PermList));
    _phaseECache.(key) := grp;
    _phaseECacheSize := _phaseECacheSize + 1;
    # Evict if cache too large
    if _phaseECacheSize > 200 then
        _phaseECache := rec();
        _phaseECache.(key) := grp;
        _phaseECacheSize := 1;
    fi;
    return grp;
end;

# Helper functions for invariants (computed on demand, cached in allInvariants)

_GetCenterSize := function(idx)
    local G;
    if IsBound(allInvariants[idx].centerSize) then
        return allInvariants[idx].centerSize;
    fi;
    G := _GetGroupE(idx);
    allInvariants[idx].centerSize := Size(Centre(G));
    return allInvariants[idx].centerSize;
end;

_GetElemOrdProfile := function(idx)
    local G, cc, ordCounts, c, ord, key, ordKeys;
    if IsBound(allInvariants[idx].elemOrdProfile) then
        return allInvariants[idx].elemOrdProfile;
    fi;
    G := _GetGroupE(idx);
    cc := ConjugacyClasses(G);
    ordCounts := rec();
    for c in cc do
        ord := Order(Representative(c));
        key := String(ord);
        if IsBound(ordCounts.(key)) then
            ordCounts.(key) := ordCounts.(key) + Size(c);
        else
            ordCounts.(key) := Size(c);
        fi;
    od;
    ordKeys := List(RecNames(ordCounts), Int);
    Sort(ordKeys);
    allInvariants[idx].elemOrdProfile := List(ordKeys,
        o -> [o, ordCounts.(String(o))]);
    return allInvariants[idx].elemOrdProfile;
end;

_GetClassSizes := function(idx)
    local G, cc, cs;
    if IsBound(allInvariants[idx].classSizes) then
        return allInvariants[idx].classSizes;
    fi;
    G := _GetGroupE(idx);
    cc := ConjugacyClasses(G);
    cs := List(cc, Size);
    Sort(cs);
    allInvariants[idx].classSizes := cs;
    return cs;
end;

_GetChiefFactorSizes := function(idx)
    local G, chief, cfSizes;
    if IsBound(allInvariants[idx].chiefFactorSizes) then
        return allInvariants[idx].chiefFactorSizes;
    fi;
    G := _GetGroupE(idx);
    chief := ChiefSeries(G);
    cfSizes := [];
    if Length(chief) > 1 then
        cfSizes := List([1..Length(chief)-1],
                        i -> Size(chief[i]) / Size(chief[i+1]));
    fi;
    Sort(cfSizes);
    allInvariants[idx].chiefFactorSizes := cfSizes;
    return cfSizes;
end;

_GetDerivedSeriesSizes := function(idx)
    local G, ds;
    if IsBound(allInvariants[idx].derivedSeriesSizes) then
        return allInvariants[idx].derivedSeriesSizes;
    fi;
    G := _GetGroupE(idx);
    ds := DerivedSeriesOfGroup(G);
    allInvariants[idx].derivedSeriesSizes := List(ds, Size);
    return allInvariants[idx].derivedSeriesSizes;
end;

_GetNilpotencyClass := function(idx)
    local G;
    if IsBound(allInvariants[idx].nilpotencyClass) then
        return allInvariants[idx].nilpotencyClass;
    fi;
    G := _GetGroupE(idx);
    if IsNilpotentGroup(G) then
        allInvariants[idx].nilpotencyClass := NilpotencyClassOfGroup(G);
    else
        allInvariants[idx].nilpotencyClass := -1;
    fi;
    return allInvariants[idx].nilpotencyClass;
end;

_GetNumNormalSubs := function(idx)
    local G;
    if IsBound(allInvariants[idx].numNormalSubs) then
        return allInvariants[idx].numNormalSubs;
    fi;
    G := _GetGroupE(idx);
    allInvariants[idx].numNormalSubs := Length(NormalSubgroups(G));
    return allInvariants[idx].numNormalSubs;
end;

_GetFrattiniSize := function(idx)
    local G;
    if IsBound(allInvariants[idx].frattiniSize) then
        return allInvariants[idx].frattiniSize;
    fi;
    G := _GetGroupE(idx);
    allInvariants[idx].frattiniSize := Size(FrattiniSubgroup(G));
    return allInvariants[idx].frattiniSize;
end;

_GetAutGroupOrder := function(idx)
    local G;
    if IsBound(allInvariants[idx].autGroupOrder) then
        return allInvariants[idx].autGroupOrder;
    fi;
    G := _GetGroupE(idx);
    allInvariants[idx].autGroupOrder := Size(AutomorphismGroup(G));
    return allInvariants[idx].autGroupOrder;
end;

_GetSubgroupOrderProfile := function(idx)
    local G, ccs, prof;
    if IsBound(allInvariants[idx].subgroupOrderProfile) then
        return allInvariants[idx].subgroupOrderProfile;
    fi;
    G := _GetGroupE(idx);
    ccs := ConjugacyClassesSubgroups(G);
    prof := List(ccs, c -> [Size(Representative(c)), Size(c)]);
    Sort(prof);
    allInvariants[idx].subgroupOrderProfile := prof;
    return prof;
end;

_GetPowerMapStructure := function(idx)
    local G, cc, result, c, rep, o, p, img, imgClass, pair;
    if IsBound(allInvariants[idx].powerMapStructure) then
        return allInvariants[idx].powerMapStructure;
    fi;
    G := _GetGroupE(idx);
    cc := ConjugacyClasses(G);
    result := [];
    for c in cc do
        rep := Representative(c);
        o := Order(rep);
        for p in Filtered(PrimeDivisors(o), x -> x <= o) do
            img := rep^p;
            imgClass := First([1..Length(cc)], j -> img in cc[j]);
            pair := [o, Size(c), p, Order(img), Size(cc[imgClass])];
            Add(result, pair);
        od;
    od;
    Sort(result);
    allInvariants[idx].powerMapStructure := result;
    return result;
end;

# Invariant cascade for distinguishing a pair
_DistinguishPair := function(idxA, idxB)
    local vA, vB;

    # Level 1: centerSize
    vA := _GetCenterSize(idxA);
    vB := _GetCenterSize(idxB);
    if vA <> vB then
        _e2Stats.byCenterSize := _e2Stats.byCenterSize + 1;
        return "centerSize";
    fi;

    # Level 2: elemOrdProfile
    vA := _GetElemOrdProfile(idxA);
    vB := _GetElemOrdProfile(idxB);
    if vA <> vB then
        _e2Stats.byElemOrdProfile := _e2Stats.byElemOrdProfile + 1;
        return "elemOrdProfile";
    fi;

    # Level 3: classSizes
    vA := _GetClassSizes(idxA);
    vB := _GetClassSizes(idxB);
    if vA <> vB then
        _e2Stats.byClassSizes := _e2Stats.byClassSizes + 1;
        return "classSizes";
    fi;

    # Level 4: chiefFactorSizes
    vA := _GetChiefFactorSizes(idxA);
    vB := _GetChiefFactorSizes(idxB);
    if vA <> vB then
        _e2Stats.byChiefFactors := _e2Stats.byChiefFactors + 1;
        return "chiefFactorSizes";
    fi;

    # Level 5: derivedSeriesSizes
    vA := _GetDerivedSeriesSizes(idxA);
    vB := _GetDerivedSeriesSizes(idxB);
    if vA <> vB then
        _e2Stats.byDerivedSeries := _e2Stats.byDerivedSeries + 1;
        return "derivedSeriesSizes";
    fi;

    # Level 6: nilpotencyClass
    vA := _GetNilpotencyClass(idxA);
    vB := _GetNilpotencyClass(idxB);
    if vA <> vB then
        _e2Stats.byNilpotency := _e2Stats.byNilpotency + 1;
        return "nilpotencyClass";
    fi;

    # Level 7: numNormalSubs
    vA := _GetNumNormalSubs(idxA);
    vB := _GetNumNormalSubs(idxB);
    if vA <> vB then
        _e2Stats.byNormalSubs := _e2Stats.byNormalSubs + 1;
        return "numNormalSubs";
    fi;

    # Level 8: frattiniSize
    vA := _GetFrattiniSize(idxA);
    vB := _GetFrattiniSize(idxB);
    if vA <> vB then
        _e2Stats.byFrattini := _e2Stats.byFrattini + 1;
        return "frattiniSize";
    fi;

    # Level 9: autGroupOrder
    Print("    -> autGroupOrder for (", idxA, ",", idxB,
          ") order=", allInvariants[idxA].order, "\n");
    vA := _GetAutGroupOrder(idxA);
    vB := _GetAutGroupOrder(idxB);
    if vA <> vB then
        _e2Stats.byAutGroup := _e2Stats.byAutGroup + 1;
        return "autGroupOrder";
    fi;

    # Level 10: subgroupOrderProfile
    Print("    -> subgroupOrderProfile for (", idxA, ",", idxB, ")\n");
    vA := _GetSubgroupOrderProfile(idxA);
    vB := _GetSubgroupOrderProfile(idxB);
    if vA <> vB then
        _e2Stats.bySubgroupProfile := _e2Stats.bySubgroupProfile + 1;
        return "subgroupOrderProfile";
    fi;

    # Level 11: powerMapStructure
    Print("    -> powerMapStructure for (", idxA, ",", idxB, ")\n");
    vA := _GetPowerMapStructure(idxA);
    vB := _GetPowerMapStructure(idxB);
    if vA <> vB then
        _e2Stats.byPowerMap := _e2Stats.byPowerMap + 1;
        return "powerMapStructure";
    fi;

    # Level 12: IsomorphismGroups (ultimate fallback)
    Print("    -> IsomorphismGroups for (", idxA, ",", idxB, ")\n");
    vA := _GetGroupE(idxA);
    vB := _GetGroupE(idxB);
    if IsomorphismGroups(vA, vB) = fail then
        _e2Stats.byIsomorphismGroups := _e2Stats.byIsomorphismGroups + 1;
        return "IsomorphismGroups";
    fi;

    # FAILURE: groups appear isomorphic
    _e2Stats.failures := _e2Stats.failures + 1;
    return fail;
end;

# Process all non-singleton large buckets
_e2PairsDone := 0;
_e2Failures := [];
# Record distinguishing info for each pair (for fingerprints)
_pairDistinguisher := rec();

for _lbk in _lbKeys do
    _lbucket := _largeBucketMap.(_lbk);
    if Length(_lbucket) <= 1 then
        continue;
    fi;

    AppendTo(PHASE_E_FILE, "Bucket: ", Length(_lbucket), " reps, order=",
             allInvariants[_lbucket[1]].order, "\n");

    for _j in [1..Length(_lbucket)] do
        for _k in [_j+1..Length(_lbucket)] do
            _idxA := _lbucket[_j];
            _idxB := _lbucket[_k];
            _e2PairsDone := _e2PairsDone + 1;

            _dist := _DistinguishPair(_idxA, _idxB);

            if _dist = fail then
                Print("FAIL: large reps ", _idxA, " and ", _idxB,
                      " appear isomorphic!\n");
                Add(_e2Failures, [_idxA, _idxB]);
                AppendTo(PHASE_E_FILE, "  FAIL: ", _idxA, " ~ ", _idxB,
                         " ISOMORPHIC!\n");
            else
                AppendTo(PHASE_E_FILE, "  PASS: ", _idxA, " !~ ", _idxB,
                         " via ", _dist, "\n");
                # Store distinguisher for the pair
                _pdKey := Concatenation("p", String(_idxA), "_", String(_idxB));
                if Length(_pdKey) <= 1000 then
                    _pairDistinguisher.(_pdKey) := _dist;
                fi;
            fi;

            if _e2PairsDone mod 20 = 0 then
                Print("  E2 progress: ", _e2PairsDone, "/", _lnPairs,
                      " pairs\n");
            fi;
        od;
    od;
od;

if Length(_e2Failures) > 0 then
    Print("FATAL: ", Length(_e2Failures), " large rep pairs appear isomorphic!\n");
    QuitGap(1);
fi;

AppendTo(PHASE_E_FILE, "\nE2 Summary: ", _e2PairsDone, " pairs tested\n");
AppendTo(PHASE_E_FILE, "  centerSize: ", _e2Stats.byCenterSize, "\n");
AppendTo(PHASE_E_FILE, "  elemOrdProfile: ", _e2Stats.byElemOrdProfile, "\n");
AppendTo(PHASE_E_FILE, "  classSizes: ", _e2Stats.byClassSizes, "\n");
AppendTo(PHASE_E_FILE, "  chiefFactorSizes: ", _e2Stats.byChiefFactors, "\n");
AppendTo(PHASE_E_FILE, "  derivedSeriesSizes: ", _e2Stats.byDerivedSeries, "\n");
AppendTo(PHASE_E_FILE, "  nilpotencyClass: ", _e2Stats.byNilpotency, "\n");
AppendTo(PHASE_E_FILE, "  numNormalSubs: ", _e2Stats.byNormalSubs, "\n");
AppendTo(PHASE_E_FILE, "  frattiniSize: ", _e2Stats.byFrattini, "\n");
AppendTo(PHASE_E_FILE, "  autGroupOrder: ", _e2Stats.byAutGroup, "\n");
AppendTo(PHASE_E_FILE, "  subgroupOrderProfile: ", _e2Stats.bySubgroupProfile, "\n");
AppendTo(PHASE_E_FILE, "  powerMapStructure: ", _e2Stats.byPowerMap, "\n");
AppendTo(PHASE_E_FILE, "  IsomorphismGroups: ", _e2Stats.byIsomorphismGroups, "\n");

Print("\nPhase E complete: all ", EXPECTED_TOTAL,
      " types verified pairwise non-isomorphic\n");
Print("  Cascade stats: center=", _e2Stats.byCenterSize,
      " elemOrd=", _e2Stats.byElemOrdProfile,
      " classSizes=", _e2Stats.byClassSizes,
      " chiefFactors=", _e2Stats.byChiefFactors,
      " derivedSeries=", _e2Stats.byDerivedSeries,
      " nilpotency=", _e2Stats.byNilpotency,
      " normalSubs=", _e2Stats.byNormalSubs,
      " frattini=", _e2Stats.byFrattini,
      " aut=", _e2Stats.byAutGroup,
      " subProfile=", _e2Stats.bySubgroupProfile,
      " powerMap=", _e2Stats.byPowerMap,
      " iso=", _e2Stats.byIsomorphismGroups, "\n");
Print("Phase E time: ", Int((Runtime() - phaseEStart)/1000), "s\n\n");

##############################################################################
## PHASE F: Output mapping, fingerprints, and summary
##############################################################################

Print("=== PHASE F: Output results ===\n\n");
phaseFStart := Runtime();

# F1: class_to_type_mapping.g
Print("F1: Writing class-to-type mapping...\n");

# Assign type indices: sort roots, map root -> type index
Sort(_roots);
_rootToType := rec();
for _i in [1..Length(_roots)] do
    _rootToType.(String(_roots[_i])) := _i;
od;

PrintTo(MAPPING_FILE, "# Class-to-type mapping for S14\n");
AppendTo(MAPPING_FILE, "# S14_CLASS_TO_TYPE[i] = type index (1..",
         Length(_roots), ") for conjugacy class i\n\n");
AppendTo(MAPPING_FILE, "S14_CLASS_TO_TYPE := [\n");

for _i in [1..EXPECTED_CLASSES] do
    _root := _Find(_i);
    _typeIdx := _rootToType.(String(_root));
    if _i < EXPECTED_CLASSES then
        AppendTo(MAPPING_FILE, _typeIdx, ",\n");
    else
        AppendTo(MAPPING_FILE, _typeIdx, "\n");
    fi;
od;
AppendTo(MAPPING_FILE, "];\n");

Print("  Written ", EXPECTED_CLASSES, " entries\n");

# F2: type_fingerprints.g
Print("F2: Writing type fingerprints...\n");

PrintTo(FINGERPRINT_FILE, "# Type fingerprints for S14\n");
AppendTo(FINGERPRINT_FILE, "# ", Length(_roots), " types total\n\n");
AppendTo(FINGERPRINT_FILE, "S14_TYPE_INFO := [\n");

for _i in [1..Length(_roots)] do
    _rep := _roots[_i];
    _inv := allInvariants[_rep];

    AppendTo(FINGERPRINT_FILE, "  rec(typeIndex:=", _i,
             ", representative:=", _rep,
             ", order:=", _inv.order);

    if _inv.idGroup <> fail then
        AppendTo(FINGERPRINT_FILE, ", idGroup:=\"", String(_inv.idGroup), "\"");
        AppendTo(FINGERPRINT_FILE, ", fingerprint:=\"IdGroup\"");
    else
        AppendTo(FINGERPRINT_FILE, ", idGroup:=fail");
        AppendTo(FINGERPRINT_FILE, ", sigKey:=", String(_inv.sigKey));
        # Determine fingerprint description
        _fpDesc := "sigKey_unique";
        if IsBound(_inv.autGroupOrder) then
            AppendTo(FINGERPRINT_FILE, ", autGroupOrder:=", _inv.autGroupOrder);
            _fpDesc := "sigKey+autGroupOrder";
        fi;
        if IsBound(_inv.subgroupOrderProfile) then
            _fpDesc := "sigKey+subgroupOrderProfile";
        fi;
        AppendTo(FINGERPRINT_FILE, ", fingerprint:=\"", _fpDesc, "\"");
    fi;

    if _i < Length(_roots) then
        AppendTo(FINGERPRINT_FILE, "),\n");
    else
        AppendTo(FINGERPRINT_FILE, ")\n");
    fi;
od;
AppendTo(FINGERPRINT_FILE, "];\n");

Print("  Written ", Length(_roots), " type fingerprints\n");

# F3: verification_summary.txt
Print("F3: Writing verification summary...\n");

_totalTime := Runtime() - phaseAStart;

PrintTo(SUMMARY_FILE, "A174511(14) = ", EXPECTED_TOTAL, "  VERIFIED\n\n");
AppendTo(SUMMARY_FILE, "Input: ", EXPECTED_CLASSES,
         " conjugacy class representatives of subgroups of S_14\n");
if TRUST_INVARIANTS then
    AppendTo(SUMMARY_FILE,
        "Phase B invariants: TRUSTED (loaded from precomputed file)\n");
else
    AppendTo(SUMMARY_FILE,
        "Phase B invariants: RECOMPUTED from scratch\n");
fi;
AppendTo(SUMMARY_FILE, "\n");

AppendTo(SUMMARY_FILE, "=== Non-conjugacy (Phase C) ===\n");
if _phaseCStats.skipped then
    AppendTo(SUMMARY_FILE, "SKIPPED (SKIP_CONJUGACY = true)\n\n");
else
    AppendTo(SUMMARY_FILE, "All ", EXPECTED_CLASSES,
             " groups verified pairwise non-conjugate in S_14\n");
    AppendTo(SUMMARY_FILE, "  ", _phaseCStats.nSingletons,
             " singleton invariant buckets\n");
    AppendTo(SUMMARY_FILE, "  ", _phaseCStats.nMulti,
             " multi-group buckets with ", _phaseCStats.nTestedPairs,
             " pairs tested via IsConjugate, all non-conjugate\n\n");
fi;

AppendTo(SUMMARY_FILE, "=== Upper bound (at most ", EXPECTED_TOTAL,
         " types) ===\n");
AppendTo(SUMMARY_FILE, "  ", _idgCount, " groups classified by IdGroup -> ",
         _nIdTypes, " unique types\n");
AppendTo(SUMMARY_FILE, "  ", _largeCount,
         " large groups linked by ", EXPECTED_PROOFS,
         " verified isomorphism proofs -> ", _nLargeTypes, " reps\n");
AppendTo(SUMMARY_FILE, "  ", _nProofPass, "/", EXPECTED_PROOFS,
         " proofs verified as bijective homomorphisms (injective + surjective)\n");
AppendTo(SUMMARY_FILE, "  Total: ", _nIdTypes, " + ", _nLargeTypes,
         " = ", _nIdTypes + _nLargeTypes, "\n\n");

AppendTo(SUMMARY_FILE, "=== Lower bound (at least ", EXPECTED_TOTAL,
         " types) ===\n");
AppendTo(SUMMARY_FILE, "  ", _nIdTypes,
         " IdGroup types: distinct by IdGroup identifier\n");
AppendTo(SUMMARY_FILE, "  ", _nLargeTypes,
         " large group reps: pairwise non-isomorphic\n");
AppendTo(SUMMARY_FILE, "    * ", _e2Stats.singletons,
         " singleton invariant buckets (unique by sigKey+exponent)\n");
AppendTo(SUMMARY_FILE, "    * ", _e2Stats.byCenterSize,
         " pairs distinguished by centerSize\n");
AppendTo(SUMMARY_FILE, "    * ", _e2Stats.byElemOrdProfile,
         " pairs distinguished by elemOrdProfile\n");
AppendTo(SUMMARY_FILE, "    * ", _e2Stats.byClassSizes,
         " pairs distinguished by classSizes\n");
AppendTo(SUMMARY_FILE, "    * ", _e2Stats.byChiefFactors,
         " pairs distinguished by chiefFactorSizes\n");
AppendTo(SUMMARY_FILE, "    * ", _e2Stats.byDerivedSeries,
         " pairs distinguished by derivedSeriesSizes\n");
AppendTo(SUMMARY_FILE, "    * ", _e2Stats.byNilpotency,
         " pairs distinguished by nilpotencyClass\n");
AppendTo(SUMMARY_FILE, "    * ", _e2Stats.byNormalSubs,
         " pairs distinguished by numNormalSubs\n");
AppendTo(SUMMARY_FILE, "    * ", _e2Stats.byFrattini,
         " pairs distinguished by frattiniSize\n");
AppendTo(SUMMARY_FILE, "    * ", _e2Stats.byAutGroup,
         " pairs distinguished by autGroupOrder\n");
AppendTo(SUMMARY_FILE, "    * ", _e2Stats.bySubgroupProfile,
         " pairs distinguished by subgroupOrderProfile\n");
AppendTo(SUMMARY_FILE, "    * ", _e2Stats.byPowerMap,
         " pairs distinguished by powerMapStructure\n");
AppendTo(SUMMARY_FILE, "    * ", _e2Stats.byIsomorphismGroups,
         " pairs distinguished by IsomorphismGroups\n");
AppendTo(SUMMARY_FILE, "  No overlap between IdGroup types and large group types",
         " (disjoint order ranges)\n\n");

AppendTo(SUMMARY_FILE, "=== Timing ===\n");
AppendTo(SUMMARY_FILE, "  Phase A (load): ",
         Int((phaseBStart - phaseAStart)/1000), "s\n");
AppendTo(SUMMARY_FILE, "  Phase B (invariants): ",
         Int((phaseCStart - phaseBStart)/1000), "s\n");
AppendTo(SUMMARY_FILE, "  Phase C (non-conjugacy): ",
         Int((phaseDStart - phaseCStart)/1000), "s\n");
AppendTo(SUMMARY_FILE, "  Phase D (proofs+mapping): ",
         Int((phaseEStart - phaseDStart)/1000), "s\n");
AppendTo(SUMMARY_FILE, "  Phase E (non-isomorphism): ",
         Int((phaseFStart - phaseEStart)/1000), "s\n");
AppendTo(SUMMARY_FILE, "  Phase F (output): ",
         Int((Runtime() - phaseFStart)/1000), "s\n");
AppendTo(SUMMARY_FILE, "  Total: ", Int(_totalTime/1000), "s\n");

Print("Phase F complete\n");
Print("Phase F time: ", Int((Runtime() - phaseFStart)/1000), "s\n\n");

##############################################################################
## FINAL SUMMARY
##############################################################################

Print("==================================================\n");
Print("  VERIFICATION COMPLETE\n");
Print("==================================================\n\n");
Print("  A174511(14) = ", _nIdTypes + _nLargeTypes, "  (expected: ",
      EXPECTED_TOTAL, ")\n\n");

if _nIdTypes + _nLargeTypes = EXPECTED_TOTAL then
    Print("  *** VERIFIED: A174511(14) = ", EXPECTED_TOTAL, " ***\n\n");
else
    Print("  *** MISMATCH: got ", _nIdTypes + _nLargeTypes,
          " expected ", EXPECTED_TOTAL, " ***\n\n");
fi;

Print("  IdGroup types: ", _nIdTypes, "\n");
Print("  Large group types: ", _nLargeTypes, "\n");
Print("  Total time: ", Int(_totalTime/1000), "s\n\n");
Print("  Output files:\n");
Print("    ", SUMMARY_FILE, "\n");
Print("    ", MAPPING_FILE, "\n");
Print("    ", FINGERPRINT_FILE, "\n");
Print("    ", PHASE_C_FILE, "\n");
Print("    ", PHASE_D_FILE, "\n");
Print("    ", PHASE_E_FILE, "\n");

QUIT;
