##############################################################################
##
##  verify_a174511_14.g
##
##  Self-contained verification that A174511(14) = 7,766
##  (Number of isomorphism types of subgroups of S_14)
##
##  Inputs (in s14_final/):
##    s14_subgroups.g       - 75,154 conjugacy class representatives
##    proof_all_remapped.g  - 7,523 isomorphism proofs
##
##  Input (in s14_final/verification/):
##    type_fingerprints.g   - 7,766 type records with minimal invariant values
##
##  Phases:
##    A: Verify fingerprint invariants (7,766 representative groups)
##    B: Verify isomorphism proofs + IdGroup unions -> upper bound
##    C: Verify non-isomorphism from fingerprint data -> lower bound
##    D: Verify pairwise non-conjugacy of all 75,154 classes (optional)
##
##  Proof structure:
##    Phase A verifies that all invariant values in the fingerprint file
##    are correct by recomputing them from the raw generators.
##    Phase B verifies the isomorphism proofs and computes IdGroup for
##    all 64,467 small groups, building a union-find that yields 7,766
##    types (upper bound). Phase C checks that every pair of large types
##    sharing the same order is distinguished by a verified invariant
##    (lower bound). Phase D (optional) confirms that the 75,154 classes
##    are pairwise non-conjugate in S14, proving A000638(14) = 75,154.
##
##  Fingerprint fields (cheap to expensive):
##    derivedSize, nrCC, derivedLength, abelianInvariants,
##    exponent, centerSize,
##    nrInvolutions, nrElementsOfOrder3, nrElementsOfOrder4,
##    nrElementsOfOrder6,
##    classSizes, chiefFactorSizes, derivedSeriesSizes,
##    nilpotencyClass, numNormalSubs, frattiniSize,
##    autGroupOrder, subgroupOrderProfile
##
##############################################################################

BASE_DIR := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s14_final/";
OUT_DIR := Concatenation(BASE_DIR, "verification/");

EXPECTED_CLASSES := 75154;
EXPECTED_TYPES := 7766;
EXPECTED_IDG_TYPES := 4602;
EXPECTED_LARGE_TYPES := 3164;
EXPECTED_PROOFS := 7523;

RUN_PHASE_D := true;  # Optional: pairwise non-conjugacy (proves A000638(14) = 75,154)

IsIdGroupCompatible := function(ord)
    return ord < 2000 and not ord in [512, 768, 1024, 1536];
end;

_startTime := Runtime();

Print("==================================================\n");
Print("  A174511(14) Verification\n");
Print("==================================================\n\n");

##############################################################################
## Load input files
##############################################################################

Print("Loading s14_subgroups.g...\n");
_loadFunc := ReadAsFunction(Concatenation(BASE_DIR, "s14_subgroups.g"));
subgens := _loadFunc();
Unbind(_loadFunc);
if Length(subgens) <> EXPECTED_CLASSES then
    Print("FATAL: expected ", EXPECTED_CLASSES, " groups, got ",
          Length(subgens), "\n");
    QuitGap(1);
fi;
Print("  Loaded ", Length(subgens), " generator lists\n");

Print("Loading proof_all_remapped.g...\n");
Read(Concatenation(BASE_DIR, "proof_all_remapped.g"));
if Length(FV_ALL_PROOFS) <> EXPECTED_PROOFS then
    Print("FATAL: expected ", EXPECTED_PROOFS, " proofs, got ",
          Length(FV_ALL_PROOFS), "\n");
    QuitGap(1);
fi;
Print("  Loaded ", Length(FV_ALL_PROOFS), " proofs\n");

Print("Loading type_fingerprints.g...\n");
Read(Concatenation(OUT_DIR, "type_fingerprints.g"));
if Length(S14_TYPE_INFO) <> EXPECTED_TYPES then
    Print("FATAL: expected ", EXPECTED_TYPES, " types, got ",
          Length(S14_TYPE_INFO), "\n");
    QuitGap(1);
fi;
Print("  Loaded ", Length(S14_TYPE_INFO), " type fingerprints\n");

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

# Histogram key: element-order + fixed-point count histogram as conjugacy invariant.
# Uses ConjugacyClasses(G) for efficiency (iterates reps, not all elements).
# Returns a string key for record-based sub-bucketing.
_ComputeHistogramKey := function(G)
    local cc, hist, c, rep, o, fp, hkey, sortedKeys, parts, k, result;

    cc := ConjugacyClasses(G);
    hist := rec();
    for c in cc do
        rep := Representative(c);
        o := Order(rep);
        fp := 14 - NrMovedPoints(rep);
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

    # Truncate + hash if too long for GAP record key (limit 1023)
    if Length(result) > 900 then
        result := Concatenation(result{[1..800]}, "_H", String(Length(result)));
    fi;

    return result;
end;

##############################################################################
## PHASE A: Verify fingerprint invariants for 7,766 representatives
##
## For each type, build the representative group from raw generators and
## recompute every invariant listed in its fingerprint record. Uses shared
## computation: DerivedSubgroup, ConjugacyClasses, DerivedSeriesOfGroup are
## each computed at most once per type and reused across multiple fields.
##############################################################################

Print("=== PHASE A: Verify fingerprint invariants ===\n\n");
phaseAStart := Runtime();

_nIdgVerified := 0;
_nLargeVerified := 0;
_invFailures := [];

for _ti in [1..Length(S14_TYPE_INFO)] do
    _t := S14_TYPE_INFO[_ti];
    _rep := _t.representative;
    _G := _BuildGroup(_rep);

    if _ti mod 200 = 0 or _ti = 1 then
        _elapsed := Runtime() - phaseAStart;
        if _ti > 1 then
            _eta := Int(_elapsed * (EXPECTED_TYPES - _ti) / _ti / 1000);
        else
            _eta := 0;
        fi;
        Print("  Type ", _ti, "/", EXPECTED_TYPES,
              " (", _nIdgVerified, " idg, ", _nLargeVerified, " large)",
              " ETA=", _eta, "s\n");
    fi;

    # Verify order
    if Size(_G) <> _t.order then
        Add(_invFailures, Concatenation("Type ", String(_ti),
            " rep=", String(_rep), ": order mismatch, expected ",
            String(_t.order), " got ", String(Size(_G))));
        continue;
    fi;

    if _t.idGroup <> fail then
        # IdGroup type: verify IdGroup matches
        _idg := IdGroup(_G);
        if _idg <> _t.idGroup then
            Add(_invFailures, Concatenation("Type ", String(_ti),
                " rep=", String(_rep), ": IdGroup mismatch, expected ",
                String(_t.idGroup), " got ", String(_idg)));
            continue;
        fi;
        _nIdgVerified := _nIdgVerified + 1;
    else
        # Large type: verify all listed invariants using shared computation
        _ok := true;

        # Determine which shared computations are needed
        _needsDerived := IsBound(_t.derivedSize)
                      or IsBound(_t.abelianInvariants);
        _needsCC := IsBound(_t.nrCC)
                  or IsBound(_t.nrInvolutions)
                  or IsBound(_t.nrElementsOfOrder3)
                  or IsBound(_t.nrElementsOfOrder4)
                  or IsBound(_t.nrElementsOfOrder6)
                  or IsBound(_t.classSizes);
        _needsDerivedSeries := IsBound(_t.derivedLength)
                            or IsBound(_t.derivedSeriesSizes);

        # Compute shared objects once
        if _needsDerived then
            _D := DerivedSubgroup(_G);
        fi;
        if _needsCC then
            _cc := ConjugacyClasses(_G);
        fi;
        if _needsDerivedSeries then
            _ds := DerivedSeriesOfGroup(_G);
        fi;

        # derivedSize
        if _ok and IsBound(_t.derivedSize) then
            if Size(_D) <> _t.derivedSize then
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": derivedSize mismatch, expected ",
                    String(_t.derivedSize), " got ", String(Size(_D))));
                _ok := false;
            fi;
        fi;

        # nrCC
        if _ok and IsBound(_t.nrCC) then
            if Length(_cc) <> _t.nrCC then
                Add(_invFailures, Concatenation("Type ", String(_ti),
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
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": derivedLength mismatch"));
                _ok := false;
            fi;
        fi;

        # abelianInvariants
        if _ok and IsBound(_t.abelianInvariants) then
            _computed := ShallowCopy(AbelianInvariants(_G/_D));
            Sort(_computed);
            if _computed <> _t.abelianInvariants then
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": abelianInvariants mismatch"));
                _ok := false;
            fi;
        fi;

        # exponent
        if _ok and IsBound(_t.exponent) then
            if Exponent(_G) <> _t.exponent then
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": exponent mismatch"));
                _ok := false;
            fi;
        fi;

        # centerSize
        if _ok and IsBound(_t.centerSize) then
            if Size(Centre(_G)) <> _t.centerSize then
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": centerSize mismatch"));
                _ok := false;
            fi;
        fi;

        # nrInvolutions (elements of order 2)
        if _ok and IsBound(_t.nrInvolutions) then
            _computed := Sum(Filtered(_cc,
                c -> Order(Representative(c)) = 2), Size);
            if _computed <> _t.nrInvolutions then
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": nrInvolutions mismatch, expected ",
                    String(_t.nrInvolutions), " got ", String(_computed)));
                _ok := false;
            fi;
        fi;

        # nrElementsOfOrder3
        if _ok and IsBound(_t.nrElementsOfOrder3) then
            _computed := Sum(Filtered(_cc,
                c -> Order(Representative(c)) = 3), Size);
            if _computed <> _t.nrElementsOfOrder3 then
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": nrElementsOfOrder3 mismatch"));
                _ok := false;
            fi;
        fi;

        # nrElementsOfOrder4
        if _ok and IsBound(_t.nrElementsOfOrder4) then
            _computed := Sum(Filtered(_cc,
                c -> Order(Representative(c)) = 4), Size);
            if _computed <> _t.nrElementsOfOrder4 then
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": nrElementsOfOrder4 mismatch"));
                _ok := false;
            fi;
        fi;

        # nrElementsOfOrder6
        if _ok and IsBound(_t.nrElementsOfOrder6) then
            _computed := Sum(Filtered(_cc,
                c -> Order(Representative(c)) = 6), Size);
            if _computed <> _t.nrElementsOfOrder6 then
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": nrElementsOfOrder6 mismatch"));
                _ok := false;
            fi;
        fi;

        # classSizes
        if _ok and IsBound(_t.classSizes) then
            _computed := SortedList(List(_cc, Size));
            if _computed <> _t.classSizes then
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": classSizes mismatch"));
                _ok := false;
            fi;
        fi;

        # chiefFactorSizes
        if _ok and IsBound(_t.chiefFactorSizes) then
            _cs := ChiefSeries(_G);
            _computed := [];
            for _j in [1..Length(_cs)-1] do
                Add(_computed, Size(_cs[_j]) / Size(_cs[_j+1]));
            od;
            Sort(_computed);
            if _computed <> _t.chiefFactorSizes then
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": chiefFactorSizes mismatch"));
                _ok := false;
            fi;
        fi;

        # derivedSeriesSizes
        if _ok and IsBound(_t.derivedSeriesSizes) then
            _computed := List(_ds, Size);
            if _computed <> _t.derivedSeriesSizes then
                Add(_invFailures, Concatenation("Type ", String(_ti),
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
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": nilpotencyClass mismatch"));
                _ok := false;
            fi;
        fi;

        # numNormalSubs
        if _ok and IsBound(_t.numNormalSubs) then
            _computed := Length(NormalSubgroups(_G));
            if _computed <> _t.numNormalSubs then
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": numNormalSubs mismatch"));
                _ok := false;
            fi;
        fi;

        # frattiniSize
        if _ok and IsBound(_t.frattiniSize) then
            _computed := Size(FrattiniSubgroup(_G));
            if _computed <> _t.frattiniSize then
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": frattiniSize mismatch"));
                _ok := false;
            fi;
        fi;

        # autGroupOrder
        if _ok and IsBound(_t.autGroupOrder) then
            _computed := Size(AutomorphismGroup(_G));
            if _computed <> _t.autGroupOrder then
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": autGroupOrder mismatch, expected ",
                    String(_t.autGroupOrder), " got ", String(_computed)));
                _ok := false;
            fi;
        fi;

        # subgroupOrderProfile
        if _ok and IsBound(_t.subgroupOrderProfile) then
            _ccs := ConjugacyClassesSubgroups(_G);
            _computed := SortedList(
                List(_ccs, c -> [Size(Representative(c)), Size(c)]));
            if _computed <> _t.subgroupOrderProfile then
                Add(_invFailures, Concatenation("Type ", String(_ti),
                    " rep=", String(_rep), ": subgroupOrderProfile mismatch"));
                _ok := false;
            fi;
        fi;

        if _ok then
            _nLargeVerified := _nLargeVerified + 1;
        fi;
    fi;

    # Clear cache periodically
    if _ti mod 500 = 0 then
        _ClearCache();
    fi;
od;

if Length(_invFailures) > 0 then
    Print("FATAL: ", Length(_invFailures),
          " fingerprint verification failures!\n");
    for _f in _invFailures do Print("  ", _f, "\n"); od;
    QuitGap(1);
fi;

Print("Phase A complete: all ", EXPECTED_TYPES,
      " fingerprints verified\n");
Print("  ", _nIdgVerified, " IdGroup types, ",
      _nLargeVerified, " large types\n");
Print("Phase A time: ", Int((Runtime() - phaseAStart) / 1000), "s\n\n");

_ClearCache();

##############################################################################
## PHASE B: Verify isomorphism proofs + IdGroup unions -> upper bound
##
## B1: Compute IdGroup for all 64,467 compatible groups and build union-find.
## B2: Verify all 7,523 isomorphism proofs as bijective homomorphisms.
## B3: Count distinct types from union-find. Must equal 7,766.
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
_orbKey := [];  # orbit structure key per class (for Phase D)

for _i in [1..EXPECTED_CLASSES] do
    _G := _BuildGroup(_i);
    _ord := Size(_G);

    # Orbit-type key: [orbSize, transitiveId] per orbit (strictly more
    # discriminating than orbit sizes alone — same sizes but different
    # transitive actions get different keys).  TransitiveIdentification is
    # a library lookup for degree ≤ 48; all our orbits are degree ≤ 14.
    _orbs := Orbits(_G, [1..14]);
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
    fi;
    if _i mod 5000 = 0 then
        _ClearCache();
        Print("  B1: ", _i, "/", EXPECTED_CLASSES,
              " (", _idgCount, " idg, ", _largeCount, " large)\n");
    fi;
od;
_ClearCache();

_nIdgTypes := Length(RecNames(_idgMap));
Print("  IdGroup-compatible: ", _idgCount, " groups -> ",
      _nIdgTypes, " unique types\n");
if _nIdgTypes <> EXPECTED_IDG_TYPES then
    Print("FATAL: expected ", EXPECTED_IDG_TYPES, " IdGroup types, got ",
          _nIdgTypes, "\n");
    QuitGap(1);
fi;
Print("  Large groups: ", _largeCount, "\n");

# B2: Verify isomorphism proofs
Print("\nB2: Verifying ", EXPECTED_PROOFS, " isomorphism proofs...\n");
_proofStart := Runtime();
_nPass := 0;
_proofFailures := [];

for _i in [1..Length(FV_ALL_PROOFS)] do
    _p := FV_ALL_PROOFS[_i];

    if _i mod 200 = 0 or _i <= 5 then
        _elapsed := Runtime() - _proofStart;
        if _i > 1 then
            _eta := Int(_elapsed * (Length(FV_ALL_PROOFS) - _i) / _i / 1000);
        else
            _eta := 0;
        fi;
        Print("  Proof ", _i, "/", EXPECTED_PROOFS,
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
    _proofGens := List(_p.gens, EvalString);
    _proofImgs := List(_p.images, EvalString);

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
            ": gens don't generate G"));
        continue;
    fi;

    # Check 5: valid homomorphism
    _phi := GroupHomomorphismByImages(_G, _H, _proofGens, _proofImgs);
    if _phi = fail then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": GroupHomomorphismByImages returned fail"));
        continue;
    fi;

    # Check 6: injective
    if not IsInjective(_phi) then
        Add(_proofFailures, Concatenation("Proof ", String(_i),
            ": not injective"));
        continue;
    fi;

    # Check 7: surjective
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
    for _f in _proofFailures do Print("  ", _f, "\n"); od;
    QuitGap(1);
fi;

Print("  All ", _nPass, "/", EXPECTED_PROOFS,
      " proofs verified as bijective homomorphisms\n");

# B3: Count distinct types
Print("\nB3: Counting distinct types...\n");

_rootSet := rec();
for _i in [1..EXPECTED_CLASSES] do
    _rootSet.(String(_Find(_i))) := true;
od;
_nTypes := Length(RecNames(_rootSet));

Print("  Total types: ", _nTypes, "\n");
if _nTypes <> EXPECTED_TYPES then
    Print("FATAL: expected ", EXPECTED_TYPES, " types, got ", _nTypes, "\n");
    QuitGap(1);
fi;

Print("  UPPER BOUND VERIFIED: at most ", EXPECTED_TYPES, " types\n");
Print("Phase B time: ", Int((Runtime() - phaseBStart) / 1000), "s\n\n");

_ClearCache();

##############################################################################
## PHASE C: Verify non-isomorphism from fingerprint data -> lower bound
##
## IdGroup types are distinct by definition (different identifiers).
## Large types: bucket by order and confirm each pair is distinguished
## by some invariant whose value was verified in Phase A.
##############################################################################

Print("=== PHASE C: Verify non-isomorphism ===\n\n");
phaseCStart := Runtime();

# Separate types
_idgTypes := Filtered(S14_TYPE_INFO, t -> t.idGroup <> fail);
_largeTypes := Filtered(S14_TYPE_INFO, t -> t.idGroup = fail);

Print("  IdGroup types: ", Length(_idgTypes),
      " (distinct by definition)\n");
Print("  Large types: ", Length(_largeTypes),
      " (need invariant comparison)\n");

if Length(_idgTypes) <> EXPECTED_IDG_TYPES then
    Print("FATAL: expected ", EXPECTED_IDG_TYPES,
          " IdGroup types in fingerprints, got ", Length(_idgTypes), "\n");
    QuitGap(1);
fi;
if Length(_largeTypes) <> EXPECTED_LARGE_TYPES then
    Print("FATAL: expected ", EXPECTED_LARGE_TYPES,
          " large types in fingerprints, got ", Length(_largeTypes), "\n");
    QuitGap(1);
fi;

# Verify no overlap: IdGroup types have compatible orders,
# large types have incompatible orders
for _t in _idgTypes do
    if not IsIdGroupCompatible(_t.order) then
        Print("FATAL: IdGroup type ", _t.typeIndex,
              " has non-compatible order ", _t.order, "\n");
        QuitGap(1);
    fi;
od;
for _t in _largeTypes do
    if IsIdGroupCompatible(_t.order) then
        Print("FATAL: Large type ", _t.typeIndex,
              " has IdGroup-compatible order ", _t.order, "\n");
        QuitGap(1);
    fi;
od;
Print("  IdGroup/large disjointness: VERIFIED\n\n");

# Bucket large types by order
_bucketMap := rec();
for _t in _largeTypes do
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

# Invariant fields in cascade order (matching analyze_minimal_fingerprints.py)
_invFields := ["derivedSize", "nrCC", "derivedLength",
               "abelianInvariants", "exponent", "centerSize",
               "nrInvolutions", "nrElementsOfOrder3",
               "nrElementsOfOrder4", "nrElementsOfOrder6",
               "classSizes", "chiefFactorSizes", "derivedSeriesSizes",
               "nilpotencyClass", "numNormalSubs", "frattiniSize",
               "autGroupOrder", "subgroupOrderProfile"];

# Stats
_distStats := rec();
for _fld in _invFields do
    _distStats.(_fld) := 0;
od;

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
            for _fld in _invFields do
                if IsBound(_tA.(_fld)) and IsBound(_tB.(_fld)) then
                    if _tA.(_fld) <> _tB.(_fld) then
                        _distinguished := true;
                        _distStats.(_fld) := _distStats.(_fld) + 1;
                        break;
                    fi;
                fi;
            od;

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

if Length(_pairFailures) > 0 then
    Print("FATAL: ", Length(_pairFailures),
          " pairs not distinguished!\n");
    for _f in _pairFailures do Print("  ", _f, "\n"); od;
    QuitGap(1);
fi;

Print("  Singleton order buckets: ", _nSingletons, "\n");
Print("  Multi-type order buckets: ", _nMulti, " (",
      _nPairs, " pairs checked)\n");
Print("  Distinguishing invariant breakdown:\n");
for _fld in _invFields do
    if _distStats.(_fld) > 0 then
        Print("    ", _fld, ": ", _distStats.(_fld), "\n");
    fi;
od;

Print("\n  LOWER BOUND VERIFIED: at least ", EXPECTED_TYPES, " types\n");
Print("Phase C time: ", Int((Runtime() - phaseCStart) / 1000), "s\n\n");

##############################################################################
## PHASE D: Verify conjugacy class completeness (optional)
##
## Confirms A000638(14) = 75,154 by verifying that all 75,154 representatives
## are pairwise non-conjugate in S14.
##
## Algorithm (3-level cascade):
##   1. Build type buckets from Phase B's union-find (7,766 buckets)
##   2. L1: Sub-bucket by orbit types ([size, transitiveId] per orbit)
##   3. L2: Sub-bucket by element-order + fixed-point histogram (via
##          ConjugacyClasses, for groups with |G| <= MAX_HISTOGRAM_ORDER)
##   4. L3: Run IsConjugate(S14, G, H) on remaining same-histogram pairs
##   5. If ANY pair IS conjugate -> FATAL (two "distinct" classes are the same)
##############################################################################

if RUN_PHASE_D then
    Print("=== PHASE D: Verify conjugacy class completeness ===\n\n");
    phaseDStart := Runtime();

    _S14 := SymmetricGroup(14);

    # Build type buckets from union-find
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

            # ---- Level 2: Sub-bucket by element histogram (always) ----
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
                        if IsConjugate(_S14, _G, _H) then
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
    # _histLog entries: [groupOrder, L1size, histMs, pairsSaved, pairsRemaining]
    Print("\n  Histogram cost/benefit analysis (",
          Length(_histLog), " L1 sub-buckets):\n");

    # Aggregate by order range: [0,100], (100,1000], (1000,10000], (10000,+inf)
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

    Print("\n  A000638(14) = ", EXPECTED_CLASSES, " VERIFIED\n");
    Print("Phase D time: ", Int((Runtime() - phaseDStart) / 1000), "s\n\n");

    _ClearCache();
fi;

##############################################################################
## Write class-to-type mapping
##
## Maps each of the 75,154 conjugacy class indices to its type index (1..7766)
## using the union-find from Phase B and the type representatives from the
## fingerprint file.
##############################################################################

Print("Writing class-to-type mapping...\n");
_mapStart := Runtime();

# Build root -> typeIndex lookup from fingerprint representatives
_rootToType := rec();
for _ti in [1..Length(S14_TYPE_INFO)] do
    _rep := S14_TYPE_INFO[_ti].representative;
    _root := String(_Find(_rep));
    _rootToType.(_root) := _ti;
od;

# Verify every root has a type
_unmapped := 0;
for _i in [1..EXPECTED_CLASSES] do
    _root := String(_Find(_i));
    if not IsBound(_rootToType.(_root)) then
        _unmapped := _unmapped + 1;
    fi;
od;
if _unmapped > 0 then
    Print("WARNING: ", _unmapped, " classes have no type mapping!\n");
fi;

# Write mapping file
_mapFile := Concatenation(OUT_DIR, "class_to_type.g");
PrintTo(_mapFile,
    "##\n",
    "## class_to_type.g\n",
    "##\n",
    "## AUTO-GENERATED by verify_a174511_14.g\n",
    "##\n",
    "## CLASS_TO_TYPE[i] = type index (1..7766) for conjugacy class i\n",
    "## Type details are in S14_TYPE_INFO[typeIndex] from type_fingerprints.g\n",
    "##\n\n",
    "CLASS_TO_TYPE := [\n");

for _i in [1..EXPECTED_CLASSES] do
    _root := String(_Find(_i));
    _ti := _rootToType.(_root);
    if _i < EXPECTED_CLASSES then
        AppendTo(_mapFile, _ti, ",\n");
    else
        AppendTo(_mapFile, _ti, "\n");
    fi;
od;
AppendTo(_mapFile, "];\n");

# Print type size distribution summary
_typeSizes := List([1..EXPECTED_TYPES], i -> 0);
for _i in [1..EXPECTED_CLASSES] do
    _root := String(_Find(_i));
    _ti := _rootToType.(_root);
    _typeSizes[_ti] := _typeSizes[_ti] + 1;
od;
Sort(_typeSizes);

Print("  Written to ", _mapFile, "\n");
Print("  Type size distribution: min=", _typeSizes[1],
      " median=", _typeSizes[Int(EXPECTED_TYPES/2)],
      " max=", _typeSizes[EXPECTED_TYPES], "\n");
Print("  Mapping time: ", Int((Runtime() - _mapStart) / 1000), "s\n\n");

##############################################################################
## Summary
##############################################################################

_totalTime := Runtime() - _startTime;

Print("==================================================\n");
Print("  VERIFICATION COMPLETE\n");
Print("==================================================\n\n");
Print("  A174511(14) = ", EXPECTED_TYPES, "\n");
if RUN_PHASE_D then
    Print("  A000638(14) = ", EXPECTED_CLASSES, "\n");
fi;
Print("\n");
Print("  Phase A: ", EXPECTED_TYPES, "/", EXPECTED_TYPES,
      " fingerprint invariants verified\n");
Print("  Phase B: ", EXPECTED_PROOFS, "/", EXPECTED_PROOFS,
      " proofs verified, ", EXPECTED_IDG_TYPES,
      " IdGroup types, union-find = ", EXPECTED_TYPES, " types\n");
Print("  Phase C: ", EXPECTED_LARGE_TYPES,
      " large types pairwise distinguished, ",
      EXPECTED_IDG_TYPES, " IdGroup types disjoint\n");
if RUN_PHASE_D then
    Print("  Phase D: ", EXPECTED_CLASSES,
          " classes pairwise non-conjugate (",
          _nConjTests, " IsConjugate tests, ",
          _nOrbitTypeSplit, " L1 orbit-type elim, ",
          _nHistogramSplit, " L2 histogram elim)\n");
fi;
Print("\n  Total time: ", Int(_totalTime / 1000), "s\n");

QUIT;
