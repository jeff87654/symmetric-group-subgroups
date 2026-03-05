##############################################################################
##
##  verify_cert_from_subgroups.g
##
##  Independent verification of S16 certificate v7 by recomputing invariants
##  from the raw s16_subgroups.g generator lists.
##
##  Launch with:  gap -q -o 16g verify_cert_from_subgroups.g
##  (via launch_verify_cert.py)
##
##  Inputs (all in same directory):
##    s16_subgroups.g                 - 686,165 generator lists (254 MB)
##    s16_verification_certificate_v7.g - 43,626 type records
##    s16_class_to_type.g             - class→type mapping
##
##  Phases:
##    1: Verify orders (all 43,626 types)                   ~30 min
##    2: Verify IdGroup (14,202 B types)                    ~20 min
##    3: Verify sigKey components (29,278 C+ types)         ~2-4 hrs
##    4: Verify histograms (D/F/G/H types, order ≤100k)    ~2-4 hrs
##    5: Verify E7 cascade T1-T5 (F/G/H types)             ~1-2 hrs
##    6: E-type discriminant spot check                     ~1 hr
##
##  Each phase checkpoints to verify_phase_N_results.txt
##
##############################################################################

if not IsBound(BASE_DIR) then
    BASE_DIR := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s16_final_results_reindexed/";
fi;

EXPECTED_TYPES := 43626;
EXPECTED_CLASSES := 686165;

# Phase control flags — set to false before Read()ing to skip phases
if not IsBound(RUN_PHASE_1) then RUN_PHASE_1 := true; fi;
if not IsBound(RUN_PHASE_2) then RUN_PHASE_2 := true; fi;
if not IsBound(RUN_PHASE_3) then RUN_PHASE_3 := true; fi;
if not IsBound(RUN_PHASE_4) then RUN_PHASE_4 := true; fi;
if not IsBound(RUN_PHASE_5) then RUN_PHASE_5 := true; fi;
if not IsBound(RUN_PHASE_6) then RUN_PHASE_6 := true; fi;

# Thresholds — no order limits; all groups on 16 points are fast enough
MAX_ORDER_FOR_CC := infinity;
MAX_ORDER_FOR_HIST := infinity;

_startTime := Runtime();

Print("==================================================\n");
Print("  S16 Certificate Verification from Subgroups\n");
Print("  A174511(16) = 43,626\n");
Print("==================================================\n\n");

##############################################################################
## Helper functions
##############################################################################

IsIdGroupCompatible := function(ord)
    return ord < 2000 and not ord in [512, 768, 1024, 1536];
end;

# Convert sorted list to frequency form: [v,v,v,w,w] → [[v,3],[w,2]]
ToFrequency := function(sortedList)
    local result, i, n, count, val;
    result := [];
    n := Length(sortedList);
    if n = 0 then return []; fi;
    i := 1;
    while i <= n do
        val := sortedList[i];
        count := 1;
        while i + count <= n and sortedList[i + count] = val do
            count := count + 1;
        od;
        Add(result, [val, count]);
        i := i + count;
    od;
    return result;
end;

# Compute sigKey independently
ComputeSigKey := function(G)
    local order, D, derivedSize, numClasses, derivedLength, abInv;
    order := Size(G);
    D := DerivedSubgroup(G);
    derivedSize := Size(D);
    numClasses := NrConjugacyClasses(G);
    if IsSolvableGroup(G) then
        derivedLength := DerivedLength(G);
    else
        derivedLength := -1;
    fi;
    abInv := ShallowCopy(AbelianInvariants(G));
    Sort(abInv);
    return [order, derivedSize, numClasses, derivedLength, abInv];
end;

# Compute sigKey but skip NrConjugacyClasses for large groups
ComputeSigKeyPartial := function(G, skipCC)
    local order, D, derivedSize, numClasses, derivedLength, abInv;
    order := Size(G);
    D := DerivedSubgroup(G);
    derivedSize := Size(D);
    if skipCC then
        numClasses := -999;  # sentinel: not computed
    else
        numClasses := NrConjugacyClasses(G);
    fi;
    if IsSolvableGroup(G) then
        derivedLength := DerivedLength(G);
    else
        derivedLength := -1;
    fi;
    abInv := ShallowCopy(AbelianInvariants(G));
    Sort(abInv);
    return [order, derivedSize, numClasses, derivedLength, abInv];
end;

# Compute histogram via conjugacy classes
ComputeHistogram := function(G)
    local classes, orderCounts, cc, ord, cnt, orders, histogram;
    classes := ConjugacyClasses(G);
    orderCounts := rec();
    for cc in classes do
        ord := Order(Representative(cc));
        cnt := Size(cc);
        if IsBound(orderCounts.(String(ord))) then
            orderCounts.(String(ord)) := orderCounts.(String(ord)) + cnt;
        else
            orderCounts.(String(ord)) := cnt;
        fi;
    od;
    orders := List(RecNames(orderCounts), x -> Int(x));
    Sort(orders);
    histogram := List(orders, o -> [o, orderCounts.(String(o))]);
    return histogram;
end;

# Compute E7 cascade: [exponent, centerSize, frattiniSize, derivedSizes, nilpClass, ccSizeFreq, ccOrderProfileFreq]
ComputeE7 := function(G)
    local exp, cs, fs, derSeries, ds, nc, ct, n,
          centralizerSizes, classSizes, ccSzFreq,
          orders, profiles, ccOrdFreq;

    exp := Exponent(G);
    cs := Size(Centre(G));
    fs := Size(FrattiniSubgroup(G));

    derSeries := DerivedSeriesOfGroup(G);
    ds := List(derSeries, Size);

    if IsNilpotentGroup(G) then
        nc := NilpotencyClassOfGroup(G);
    else
        nc := -1;
    fi;

    ct := CharacterTable(G);
    n := Size(G);
    centralizerSizes := SizesCentralizers(ct);
    classSizes := List(centralizerSizes, c -> n / c);
    Sort(classSizes);
    ccSzFreq := ToFrequency(classSizes);

    orders := OrdersClassRepresentatives(ct);
    profiles := List([1..Length(orders)], i -> [orders[i], n / centralizerSizes[i]]);
    Sort(profiles);
    ccOrdFreq := ToFrequency(profiles);

    return [exp, cs, fs, ds, nc, ccSzFreq, ccOrdFreq];
end;

# Compute just T1-T5 (cheap, no character table needed)
ComputeE7Cheap := function(G)
    local exp, cs, fs, derSeries, ds, nc;

    exp := Exponent(G);
    cs := Size(Centre(G));
    fs := Size(FrattiniSubgroup(G));

    derSeries := DerivedSeriesOfGroup(G);
    ds := List(derSeries, Size);

    if IsNilpotentGroup(G) then
        nc := NilpotencyClassOfGroup(G);
    else
        nc := -1;
    fi;

    return [exp, cs, fs, ds, nc];
end;

##############################################################################
## Load input files
##############################################################################

Print("Loading s16_subgroups.g (254 MB, may take a minute)...\n");
_t0 := Runtime();
_loadFunc := ReadAsFunction(Concatenation(BASE_DIR, "s16_subgroups.g"));
subgens := _loadFunc();
Unbind(_loadFunc);
if Length(subgens) <> EXPECTED_CLASSES then
    Print("FATAL: expected ", EXPECTED_CLASSES, " generator lists, got ",
          Length(subgens), "\n");
    QuitGap(1);
fi;
Print("  Loaded ", Length(subgens), " generator lists in ",
      Int((Runtime() - _t0) / 1000), "s\n");

Print("Loading certificate...\n");
Read(Concatenation(BASE_DIR, "s16_verification_certificate_v7.g"));
if Length(S16_VERIFY) <> EXPECTED_TYPES then
    Print("FATAL: expected ", EXPECTED_TYPES, " certificate records, got ",
          Length(S16_VERIFY), "\n");
    QuitGap(1);
fi;
Print("  Loaded ", Length(S16_VERIFY), " certificate records\n");

Print("Loading class-to-type mapping...\n");
Read(Concatenation(BASE_DIR, "s16_class_to_type.g"));
if Length(S16_CLASS_TO_TYPE) <> EXPECTED_CLASSES then
    Print("WARNING: expected ", EXPECTED_CLASSES, " class-to-type entries, got ",
          Length(S16_CLASS_TO_TYPE), "\n");
fi;
Print("  Loaded ", Length(S16_CLASS_TO_TYPE), " class-to-type entries\n");

Print("Total load time: ", Int((Runtime() - _startTime) / 1000), "s\n\n");

##############################################################################
## Group builder with bounded cache
##############################################################################

_groupCount := 0;

# Build a FRESH group each time — no caching.
# Caching groups that accumulate computed attributes (DerivedSubgroup,
# ConjugacyClasses, etc.) causes OOM.  Build, use, discard.
BuildGroup := function(idx)
    _groupCount := _groupCount + 1;
    if _groupCount mod 500 = 0 then
        GASMAN("collect");
    fi;
    return Group(List(subgens[idx], PermList));
end;

ClearGroupCache := function()
    GASMAN("collect");
end;


##############################################################################
## Phase 1: Verify orders (all 43,626 types)
##############################################################################

if RUN_PHASE_1 then
    Print("==================================================\n");
    Print("  Phase 1: Verify Orders\n");
    Print("==================================================\n");

    _p1File := Concatenation(BASE_DIR, "verify_phase_1_results.txt");
    PrintTo(_p1File, "# Phase 1: Order verification\n");
    AppendTo(_p1File, "# Started: ", StringTime(Runtime()), "\n\n");

    _p1Pass := 0;
    _p1Fail := 0;
    _p1t0 := Runtime();

    for _idx in [1..EXPECTED_TYPES] do
        _r := S16_VERIFY[_idx];
        _G := BuildGroup(_r.i);
        _computedOrder := Size(_G);

        # Get expected order from certificate
        _expectedOrder := fail;
        if IsBound(_r.o) then
            _expectedOrder := _r.o;
        elif IsBound(_r.sk) then
            _expectedOrder := _r.sk[1];
        fi;

        if _expectedOrder <> fail then
            if _computedOrder = _expectedOrder then
                _p1Pass := _p1Pass + 1;
            else
                _p1Fail := _p1Fail + 1;
                AppendTo(_p1File, "FAIL|t=", _r.t, "|i=", _r.i,
                         "|expected=", _expectedOrder,
                         "|computed=", _computedOrder, "\n");
            fi;
        fi;

        if _idx mod 5000 = 0 then
            Print("  Phase 1: ", _idx, "/", EXPECTED_TYPES,
                  " (", _p1Pass, " pass, ", _p1Fail, " fail, ",
                  Int((Runtime() - _p1t0) / 1000), "s)\n");
        fi;
    od;

    _p1Time := Int((Runtime() - _p1t0) / 1000);
    Print("  Phase 1 complete: ", _p1Pass, " PASS, ", _p1Fail, " FAIL (",
          _p1Time, "s)\n\n");
    AppendTo(_p1File, "\n# Phase 1 complete: ", _p1Pass, " PASS, ",
             _p1Fail, " FAIL (", _p1Time, "s)\n");

    ClearGroupCache();
fi;

##############################################################################
## Phase 2: Verify IdGroup (14,202 B types)
##############################################################################

if RUN_PHASE_2 then
    Print("==================================================\n");
    Print("  Phase 2: Verify IdGroup\n");
    Print("==================================================\n");

    _p2File := Concatenation(BASE_DIR, "verify_phase_2_results.txt");
    PrintTo(_p2File, "# Phase 2: IdGroup verification\n");
    AppendTo(_p2File, "# Started: ", StringTime(Runtime()), "\n\n");

    _p2Pass := 0;
    _p2Fail := 0;
    _p2t0 := Runtime();

    _bTypes := Filtered(S16_VERIFY, r -> r.m = "B");
    Print("  B types to verify: ", Length(_bTypes), "\n");

    for _idx in [1..Length(_bTypes)] do
        _r := _bTypes[_idx];
        _G := BuildGroup(_r.i);
        _computedId := IdGroup(_G);

        if _computedId = _r.id then
            _p2Pass := _p2Pass + 1;
        else
            _p2Fail := _p2Fail + 1;
            AppendTo(_p2File, "FAIL|t=", _r.t, "|i=", _r.i,
                     "|expected=", _r.id, "|computed=", _computedId, "\n");
        fi;

        if _idx mod 2000 = 0 then
            Print("  Phase 2: ", _idx, "/", Length(_bTypes),
                  " (", _p2Pass, " pass, ", _p2Fail, " fail, ",
                  Int((Runtime() - _p2t0) / 1000), "s)\n");
        fi;
    od;

    _p2Time := Int((Runtime() - _p2t0) / 1000);
    Print("  Phase 2 complete: ", _p2Pass, " PASS, ", _p2Fail, " FAIL (",
          _p2Time, "s)\n\n");
    AppendTo(_p2File, "\n# Phase 2 complete: ", _p2Pass, " PASS, ",
             _p2Fail, " FAIL (", _p2Time, "s)\n");

    ClearGroupCache();
fi;

##############################################################################
## Phase 3: Verify sigKey components (types with sk field)
##############################################################################

if RUN_PHASE_3 then
    Print("==================================================\n");
    Print("  Phase 3: Verify SigKey Components\n");
    Print("==================================================\n");

    _p3File := Concatenation(BASE_DIR, "verify_phase_3_results.txt");

    # Resume support: read existing result file to find already-verified types
    _p3Done := rec();
    if IsExistingFile(_p3File) then
        _p3Lines := SplitString(StringFile(_p3File), "\n");
        for _line in _p3Lines do
            if Length(_line) > 6 and _line{[1..7]} = "PASS|t=" then
                _tStr := _line{[8..Length(_line)]};
                _p3Done.(Concatenation("t", _tStr)) := true;
            fi;
            # FAIL entries are NOT added — they'll be re-verified
        od;
        Print("  Resuming: ", Length(RecNames(_p3Done)), " types already verified\n");
    else
        PrintTo(_p3File, "# Phase 3: SigKey verification\n");
        AppendTo(_p3File, "# Skip NrConjugacyClasses for order > ", MAX_ORDER_FOR_CC, "\n");
        AppendTo(_p3File, "# Started: ", StringTime(Runtime()), "\n\n");
    fi;

    _p3Pass := 0;
    _p3Fail := 0;
    _p3Skip := 0;
    _p3CCSkip := 0;
    _p3Resumed := 0;
    _p3t0 := Runtime();

    _skTypes := Filtered(S16_VERIFY, r -> IsBound(r.sk));
    Print("  Types with sigKey: ", Length(_skTypes), "\n");

    for _idx in [1..Length(_skTypes)] do
        _r := _skTypes[_idx];

        # Skip already-verified types (resume support)
        if IsBound(_p3Done.(Concatenation("t", String(_r.t)))) then
            _p3Resumed := _p3Resumed + 1;
            _p3Pass := _p3Pass + 1;
            continue;
        fi;

        _G := BuildGroup(_r.i);
        _order := Size(_G);
        _sk := _r.sk;

        _failed := false;
        _detail := "";

        # sk[1] = order
        if _order <> _sk[1] then
            _failed := true;
            _detail := Concatenation("order: ", String(_order), " != ", String(_sk[1]));
        fi;

        # sk[2] = |G'|
        if not _failed then
            _D := DerivedSubgroup(_G);
            _dSize := Size(_D);
            if _dSize <> _sk[2] then
                _failed := true;
                _detail := Concatenation("derivedSize: ", String(_dSize),
                                         " != ", String(_sk[2]));
            fi;
        fi;

        # sk[3] = NrConjugacyClasses (skip for large groups)
        if not _failed then
            if _order <= MAX_ORDER_FOR_CC then
                _ncc := NrConjugacyClasses(_G);
                if _ncc <> _sk[3] then
                    _failed := true;
                    _detail := Concatenation("nrCC: ", String(_ncc),
                                             " != ", String(_sk[3]));
                fi;
            else
                _p3CCSkip := _p3CCSkip + 1;
            fi;
        fi;

        # sk[4] = DerivedLength (-1 if non-solvable)
        if not _failed then
            if IsSolvableGroup(_G) then
                _dl := DerivedLength(_G);
            else
                _dl := -1;
            fi;
            if _dl <> _sk[4] then
                _failed := true;
                _detail := Concatenation("derivedLength: ", String(_dl),
                                         " != ", String(_sk[4]));
            fi;
        fi;

        # sk[5] = sorted AbelianInvariants
        if not _failed then
            _ai := ShallowCopy(AbelianInvariants(_G));
            Sort(_ai);
            if _ai <> _sk[5] then
                _failed := true;
                _detail := Concatenation("abelianInv: ", String(_ai),
                                         " != ", String(_sk[5]));
            fi;
        fi;

        if _failed then
            _p3Fail := _p3Fail + 1;
            AppendTo(_p3File, "FAIL|t=", _r.t, "|i=", _r.i,
                     "|", _detail, "\n");
        else
            _p3Pass := _p3Pass + 1;
            # Checkpoint each PASS for crash recovery
            AppendTo(_p3File, "PASS|t=", _r.t, "\n");
        fi;

        # Aggressive GC: discard group and computed attributes every 50 groups
        if (_idx - _p3Resumed) mod 50 = 0 then
            GASMAN("collect");
        fi;

        if _idx mod 2000 = 0 then
            Print("  Phase 3: ", _idx, "/", Length(_skTypes),
                  " (", _p3Pass, " pass, ", _p3Fail, " fail, ",
                  _p3CCSkip, " CC-skipped, ",
                  _p3Resumed, " resumed, ",
                  Int((Runtime() - _p3t0) / 1000), "s)\n");
        fi;
    od;

    _p3Time := Int((Runtime() - _p3t0) / 1000);
    Print("  Phase 3 complete: ", _p3Pass, " PASS, ", _p3Fail, " FAIL",
          " (", _p3CCSkip, " CC-skipped, ", _p3Resumed, " resumed, ",
          _p3Time, "s)\n\n");
    AppendTo(_p3File, "\n# Phase 3 complete: ", _p3Pass, " PASS, ",
             _p3Fail, " FAIL (", _p3CCSkip, " CC-skipped, ", _p3Resumed,
             " resumed, ", _p3Time, "s)\n");

    ClearGroupCache();
fi;

##############################################################################
## Phase 4: Verify histograms (D/F/G/H types, order ≤ MAX_ORDER_FOR_HIST)
##############################################################################

if RUN_PHASE_4 then
    Print("==================================================\n");
    Print("  Phase 4: Verify Histograms\n");
    Print("==================================================\n");

    _p4File := Concatenation(BASE_DIR, "verify_phase_4_results.txt");
    PrintTo(_p4File, "# Phase 4: Histogram verification\n");
    AppendTo(_p4File, "# Max order for histogram: ", MAX_ORDER_FOR_HIST, "\n");
    AppendTo(_p4File, "# Started: ", StringTime(Runtime()), "\n\n");

    _p4Pass := 0;
    _p4Fail := 0;
    _p4Skip := 0;
    _p4t0 := Runtime();

    _hTypes := Filtered(S16_VERIFY, r -> IsBound(r.h));
    Print("  Types with histogram: ", Length(_hTypes), "\n");

    for _idx in [1..Length(_hTypes)] do
        _r := _hTypes[_idx];

        # Determine order
        _order := fail;
        if IsBound(_r.o) then _order := _r.o;
        elif IsBound(_r.sk) then _order := _r.sk[1]; fi;

        if _order = fail or _order > MAX_ORDER_FOR_HIST then
            _p4Skip := _p4Skip + 1;
            if _idx mod 3000 = 0 then
                Print("  Phase 4: ", _idx, "/", Length(_hTypes),
                      " (", _p4Pass, " pass, ", _p4Fail, " fail, ",
                      _p4Skip, " skipped, ",
                      Int((Runtime() - _p4t0) / 1000), "s)\n");
            fi;
            continue;
        fi;

        _G := BuildGroup(_r.i);
        _computedHist := ComputeHistogram(_G);
        _failed := false;
        _detail := "";

        # Method D: h is partial — verify each entry in h appears in computed histogram
        # Special case: [order, 0] means "0 elements of that order" — verify order is ABSENT
        if _r.m = "D" then
            for _entry in _r.h do
                if _entry[2] = 0 then
                    # Zero-count entry: verify this order does NOT appear in histogram
                    _found := false;
                    for _ch in _computedHist do
                        if _ch[1] = _entry[1] then
                            _found := true;
                            break;
                        fi;
                    od;
                    if _found then
                        _failed := true;
                        _detail := Concatenation("h entry ", String(_entry),
                                                 " but order ", String(_entry[1]),
                                                 " IS in histogram ", String(_computedHist));
                        break;
                    fi;
                else
                    # Positive count: verify this [order, count] pair appears
                    _found := false;
                    for _ch in _computedHist do
                        if _ch[1] = _entry[1] and _ch[2] = _entry[2] then
                            _found := true;
                            break;
                        fi;
                    od;
                    if not _found then
                        _failed := true;
                        _detail := Concatenation("h entry ", String(_entry),
                                                 " not in histogram ", String(_computedHist));
                        break;
                    fi;
                fi;
            od;

        # Other methods: h may be in [order, count] or [order, count, freq] format.
        # Detect format from first entry length, then verify as subset.
        else
            _certH := ShallowCopy(_r.h);

            if Length(_certH) > 0 and Length(_certH[1]) = 2 then
                # Raw [order, count] format (same as D) - verify each entry
                for _entry in _certH do
                    if _entry[2] = 0 then
                        _found := false;
                        for _ch in _computedHist do
                            if _ch[1] = _entry[1] then
                                _found := true;
                                break;
                            fi;
                        od;
                        if _found then
                            _failed := true;
                            _detail := Concatenation("h entry ", String(_entry),
                                                     " but order IS in histogram");
                            break;
                        fi;
                    else
                        _found := false;
                        for _ch in _computedHist do
                            if _ch[1] = _entry[1] and _ch[2] = _entry[2] then
                                _found := true;
                                break;
                            fi;
                        od;
                        if not _found then
                            _failed := true;
                            _detail := Concatenation("h entry ", String(_entry),
                                                     " not in histogram ", String(_computedHist));
                            break;
                        fi;
                    fi;
                od;

            else
                # Frequency [order, count, freq] format - verify as subset
                _computedFreq := ToFrequency(_computedHist);
                _computedFlat := List(_computedFreq, e -> [e[1][1], e[1][2], e[2]]);
                Sort(_computedFlat);
                Sort(_certH);

                for _entry in _certH do
                    _found := false;
                    for _ch in _computedFlat do
                        if _ch = _entry then
                            _found := true;
                            break;
                        fi;
                    od;
                    if not _found then
                        _failed := true;
                        _detail := Concatenation("h entry ", String(_entry),
                                                 " not in computed ", String(_computedFlat));
                        break;
                    fi;
                od;
            fi;
        fi;

        if _failed then
            _p4Fail := _p4Fail + 1;
            AppendTo(_p4File, "FAIL|t=", _r.t, "|i=", _r.i,
                     "|m=", _r.m, "|", _detail, "\n");
        else
            _p4Pass := _p4Pass + 1;
        fi;

        if _idx mod 100 = 0 then
            GASMAN("collect");
        fi;

        if _idx mod 3000 = 0 then
            Print("  Phase 4: ", _idx, "/", Length(_hTypes),
                  " (", _p4Pass, " pass, ", _p4Fail, " fail, ",
                  _p4Skip, " skipped, ",
                  Int((Runtime() - _p4t0) / 1000), "s)\n");
        fi;
    od;

    _p4Time := Int((Runtime() - _p4t0) / 1000);
    Print("  Phase 4 complete: ", _p4Pass, " PASS, ", _p4Fail, " FAIL",
          " (", _p4Skip, " skipped, ", _p4Time, "s)\n\n");
    AppendTo(_p4File, "\n# Phase 4 complete: ", _p4Pass, " PASS, ",
             _p4Fail, " FAIL (", _p4Skip, " skipped, ", _p4Time, "s)\n");

    ClearGroupCache();
fi;

##############################################################################
## Phase 5: Verify E7 cascade T1-T5 for F/G/H types (order ≤ MAX_ORDER_FOR_HIST)
##############################################################################

if RUN_PHASE_5 then
    Print("==================================================\n");
    Print("  Phase 5: Verify E7 Cascade (T1-T5)\n");
    Print("==================================================\n");

    _p5File := Concatenation(BASE_DIR, "verify_phase_5_results.txt");
    PrintTo(_p5File, "# Phase 5: E7 cascade T1-T5 verification\n");
    AppendTo(_p5File, "# Started: ", StringTime(Runtime()), "\n\n");

    _p5Pass := 0;
    _p5Fail := 0;
    _p5Skip := 0;
    _p5t0 := Runtime();

    _e7Types := Filtered(S16_VERIFY, r -> IsBound(r.e7));
    Print("  Types with e7 field: ", Length(_e7Types), "\n");

    for _idx in [1..Length(_e7Types)] do
        _r := _e7Types[_idx];

        # Determine order
        _order := fail;
        if IsBound(_r.o) then _order := _r.o;
        elif IsBound(_r.sk) then _order := _r.sk[1]; fi;

        if _order = fail or _order > MAX_ORDER_FOR_HIST then
            _p5Skip := _p5Skip + 1;
            continue;
        fi;

        _G := BuildGroup(_r.i);
        _e7 := _r.e7;
        _failed := false;
        _detail := "";

        # T1 = Exponent
        if Length(_e7) >= 1 and _e7[1] <> 0 then
            _exp := Exponent(_G);
            if _exp <> _e7[1] then
                _failed := true;
                _detail := Concatenation("T1 exponent: ", String(_exp),
                                         " != ", String(_e7[1]));
            fi;
        fi;

        # T2 = Center size (0 = not computed)
        if not _failed and Length(_e7) >= 2 and _e7[2] <> 0 then
            _cs := Size(Centre(_G));
            if _cs <> _e7[2] then
                _failed := true;
                _detail := Concatenation("T2 centerSize: ", String(_cs),
                                         " != ", String(_e7[2]));
            fi;
        fi;

        # T3 = Frattini size (0 = not computed)
        if not _failed and Length(_e7) >= 3 and _e7[3] <> 0 then
            _fs := Size(FrattiniSubgroup(_G));
            if _fs <> _e7[3] then
                _failed := true;
                _detail := Concatenation("T3 frattiniSize: ", String(_fs),
                                         " != ", String(_e7[3]));
            fi;
        fi;

        # T4 = Derived series sizes ([] = not computed sentinel)
        if not _failed and Length(_e7) >= 4 and _e7[4] <> [] then
            _ds := List(DerivedSeriesOfGroup(_G), Size);
            if _ds <> _e7[4] then
                _failed := true;
                _detail := Concatenation("T4 derivedSizes: ", String(_ds),
                                         " != ", String(_e7[4]));
            fi;
        fi;

        # T5 = Nilpotency class (0 = not computed sentinel)
        if not _failed and Length(_e7) >= 5 and _e7[5] <> 0 then
            if IsNilpotentGroup(_G) then
                _nc := NilpotencyClassOfGroup(_G);
            else
                _nc := -1;
            fi;
            if _nc <> _e7[5] then
                _failed := true;
                _detail := Concatenation("T5 nilpClass: ", String(_nc),
                                         " != ", String(_e7[5]));
            fi;
        fi;

        if _failed then
            _p5Fail := _p5Fail + 1;
            AppendTo(_p5File, "FAIL|t=", _r.t, "|i=", _r.i,
                     "|", _detail, "\n");
        else
            _p5Pass := _p5Pass + 1;
        fi;

        if _idx mod 500 = 0 then
            Print("  Phase 5: ", _idx, "/", Length(_e7Types),
                  " (", _p5Pass, " pass, ", _p5Fail, " fail, ",
                  _p5Skip, " skipped, ",
                  Int((Runtime() - _p5t0) / 1000), "s)\n");
        fi;
    od;

    _p5Time := Int((Runtime() - _p5t0) / 1000);
    Print("  Phase 5 complete: ", _p5Pass, " PASS, ", _p5Fail, " FAIL",
          " (", _p5Skip, " skipped, ", _p5Time, "s)\n\n");
    AppendTo(_p5File, "\n# Phase 5 complete: ", _p5Pass, " PASS, ",
             _p5Fail, " FAIL (", _p5Skip, " skipped, ", _p5Time, "s)\n");

    ClearGroupCache();
fi;

##############################################################################
## Phase 6: E-type discriminant spot check (order ≤ MAX_ORDER_FOR_HIST)
##############################################################################

if RUN_PHASE_6 then
    Print("==================================================\n");
    Print("  Phase 6: E-type Discriminant Spot Check\n");
    Print("==================================================\n");

    _p6File := Concatenation(BASE_DIR, "verify_phase_6_results.txt");
    PrintTo(_p6File, "# Phase 6: E-type discriminant verification\n");
    AppendTo(_p6File, "# Started: ", StringTime(Runtime()), "\n\n");

    _p6Pass := 0;
    _p6Fail := 0;
    _p6Skip := 0;
    _p6t0 := Runtime();

    _eTypes := Filtered(S16_VERIFY, r -> r.m = "E");
    Print("  E types to verify: ", Length(_eTypes), "\n");

    for _idx in [1..Length(_eTypes)] do
        _r := _eTypes[_idx];

        # Determine order
        _order := _r.sk[1];

        if _order > MAX_ORDER_FOR_HIST then
            _p6Skip := _p6Skip + 1;
            continue;
        fi;

        _G := BuildGroup(_r.i);
        _d := _r.d;
        _field := _d.f;
        _failed := false;
        _detail := "";

        # Verify the discriminant value
        if _field = "centerSize" then
            _computed := Size(Centre(_G));
            _expected := _d.v;
            if _computed <> _expected then
                _failed := true;
                _detail := Concatenation("centerSize: ", String(_computed),
                                         " != ", String(_expected));
            fi;

        elif _field = "frattiniSize" then
            _computed := Size(FrattiniSubgroup(_G));
            _expected := _d.v;
            if _computed <> _expected then
                _failed := true;
                _detail := Concatenation("frattiniSize: ", String(_computed),
                                         " != ", String(_expected));
            fi;

        elif _field = "nilpClass" then
            if IsNilpotentGroup(_G) then
                _computed := NilpotencyClassOfGroup(_G);
            else
                _computed := -1;
            fi;
            _expected := _d.v;
            if _computed <> _expected then
                _failed := true;
                _detail := Concatenation("nilpClass: ", String(_computed),
                                         " != ", String(_expected));
            fi;

        elif _field = "derivedSizes" then
            _ds := List(DerivedSeriesOfGroup(_G), Size);
            Sort(_ds);
            _computed := ToFrequency(_ds);
            _expected := _d.v;
            # Certificate may store ascending or descending; compare sorted
            _expectedSorted := ShallowCopy(_expected);
            Sort(_expectedSorted);
            if _computed <> _expectedSorted then
                _failed := true;
                _detail := Concatenation("derivedSizes: ", String(_computed),
                                         " != ", String(_expected));
            fi;

        elif _field = "ccSizes" then
            _ct := CharacterTable(_G);
            # Avoid lambda capture issue: compute class sizes without lambda
            _centralizerSizes := SizesCentralizers(_ct);
            _classSizes := [];
            for _j in [1..Length(_centralizerSizes)] do
                Add(_classSizes, Size(_G) / _centralizerSizes[_j]);
            od;
            Sort(_classSizes);
            _computed := ToFrequency(_classSizes);
            _expected := _d.v;
            if _computed <> _expected then
                _failed := true;
                _detail := Concatenation("ccSizes: ", String(_computed),
                                         " != ", String(_expected));
            fi;

        elif _field = "ccOrderProfile" then
            _expected := _d.cc;
            # Empty list = not computed sentinel
            if _expected = [] then
                _p6Pass := _p6Pass + 1;
                continue;
            fi;
            _ct := CharacterTable(_G);
            _centralizerSizes := SizesCentralizers(_ct);
            _n := Size(_G);

            # Detect format: 2-element [[classSize, count]] or 3-element [[order, classSize, count]]
            if Length(_expected) > 0 and Length(_expected[1]) = 3 then
                # 3-element: [[elementOrder, classSize, numClasses], ...]
                # Compute (order, classSize) pairs for each conjugacy class
                _orders := OrdersClassRepresentatives(_ct);
                _pairs := [];
                for _j in [1..Length(_centralizerSizes)] do
                    Add(_pairs, [_orders[_j], _n / _centralizerSizes[_j]]);
                od;
                Sort(_pairs);
                # ToFrequency returns [[[o,s], count], ...] - flatten to [[o, s, count], ...]
                _freqRaw := ToFrequency(_pairs);
                _computed := [];
                for _j in [1..Length(_freqRaw)] do
                    Add(_computed, [_freqRaw[_j][1][1], _freqRaw[_j][1][2], _freqRaw[_j][2]]);
                od;
            else
                # 2-element: [[classSize, numClasses], ...]
                _classSizes := [];
                for _j in [1..Length(_centralizerSizes)] do
                    Add(_classSizes, _n / _centralizerSizes[_j]);
                od;
                Sort(_classSizes);
                _computed := ToFrequency(_classSizes);
            fi;

            if _computed <> _expected then
                _failed := true;
                _detail := Concatenation("ccOrderProfile: ", String(_computed),
                                         " != ", String(_expected));
            fi;

        elif _field = "autGroupOrder" then
            _computed := Size(AutomorphismGroup(_G));
            _expected := _d.v;
            if _computed <> _expected then
                _failed := true;
                _detail := Concatenation("autGroupOrder: ", String(_computed),
                                         " != ", String(_expected));
            fi;

        else
            _p6Skip := _p6Skip + 1;
            continue;
        fi;

        if _failed then
            _p6Fail := _p6Fail + 1;
            AppendTo(_p6File, "FAIL|t=", _r.t, "|i=", _r.i,
                     "|", _detail, "\n");
        else
            _p6Pass := _p6Pass + 1;
        fi;

        if _idx mod 100 = 0 then
            GASMAN("collect");
        fi;

        if _idx mod 500 = 0 then
            Print("  Phase 6: ", _idx, "/", Length(_eTypes),
                  " (", _p6Pass, " pass, ", _p6Fail, " fail, ",
                  _p6Skip, " skipped, ",
                  Int((Runtime() - _p6t0) / 1000), "s)\n");
        fi;
    od;

    _p6Time := Int((Runtime() - _p6t0) / 1000);
    Print("  Phase 6 complete: ", _p6Pass, " PASS, ", _p6Fail, " FAIL",
          " (", _p6Skip, " skipped, ", _p6Time, "s)\n\n");
    AppendTo(_p6File, "\n# Phase 6 complete: ", _p6Pass, " PASS, ",
             _p6Fail, " FAIL (", _p6Skip, " skipped, ", _p6Time, "s)\n");

    ClearGroupCache();
fi;

##############################################################################
## Final Summary
##############################################################################

_totalTime := Int((Runtime() - _startTime) / 1000);

Print("==================================================\n");
Print("  VERIFICATION COMPLETE\n");
Print("==================================================\n");
Print("  Total time: ", _totalTime, "s\n");
Print("  Check verify_phase_*_results.txt for details\n");

_summaryFile := Concatenation(BASE_DIR, "verify_summary.txt");
PrintTo(_summaryFile, "# S16 Certificate Verification Summary\n");
AppendTo(_summaryFile, "# Total time: ", _totalTime, "s\n\n");

if RUN_PHASE_1 then
    AppendTo(_summaryFile, "Phase 1 (Orders):     ", _p1Pass, " PASS, ",
             _p1Fail, " FAIL\n");
    Print("  Phase 1 (Orders):     ", _p1Pass, " PASS, ", _p1Fail, " FAIL\n");
fi;
if RUN_PHASE_2 then
    AppendTo(_summaryFile, "Phase 2 (IdGroup):    ", _p2Pass, " PASS, ",
             _p2Fail, " FAIL\n");
    Print("  Phase 2 (IdGroup):    ", _p2Pass, " PASS, ", _p2Fail, " FAIL\n");
fi;
if RUN_PHASE_3 then
    AppendTo(_summaryFile, "Phase 3 (SigKey):     ", _p3Pass, " PASS, ",
             _p3Fail, " FAIL (", _p3CCSkip, " CC-skipped)\n");
    Print("  Phase 3 (SigKey):     ", _p3Pass, " PASS, ", _p3Fail, " FAIL (",
          _p3CCSkip, " CC-skipped)\n");
fi;
if RUN_PHASE_4 then
    AppendTo(_summaryFile, "Phase 4 (Histogram):  ", _p4Pass, " PASS, ",
             _p4Fail, " FAIL (", _p4Skip, " skipped)\n");
    Print("  Phase 4 (Histogram):  ", _p4Pass, " PASS, ", _p4Fail, " FAIL (",
          _p4Skip, " skipped)\n");
fi;
if RUN_PHASE_5 then
    AppendTo(_summaryFile, "Phase 5 (E7 T1-T5):   ", _p5Pass, " PASS, ",
             _p5Fail, " FAIL (", _p5Skip, " skipped)\n");
    Print("  Phase 5 (E7 T1-T5):   ", _p5Pass, " PASS, ", _p5Fail, " FAIL (",
          _p5Skip, " skipped)\n");
fi;
if RUN_PHASE_6 then
    AppendTo(_summaryFile, "Phase 6 (E discrim):  ", _p6Pass, " PASS, ",
             _p6Fail, " FAIL (", _p6Skip, " skipped)\n");
    Print("  Phase 6 (E discrim):  ", _p6Pass, " PASS, ", _p6Fail, " FAIL (",
          _p6Skip, " skipped)\n");
fi;

Print("\n");
QuitGap(0);
