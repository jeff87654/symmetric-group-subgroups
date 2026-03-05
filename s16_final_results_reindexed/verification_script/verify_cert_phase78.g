##############################################################################
##
##  verify_cert_phase78.g
##
##  Independent verification of S16 certificate phases 7 & 8:
##    Phase 7: F/G discrimination via CharacterTable invariants
##    Phase 8: H pair non-isomorphism via IsomorphismGroups
##
##  Groups are built from s16_subgroups.g (independent of s16_large_invariants).
##
##  Worker script — set WORKER_ID, WORKER_TOTAL before Read()ing.
##
##  Usage: gap -q -o 16g -c 'WORKER_ID:=1;; WORKER_TOTAL:=4;; Read("...");'
##
##  Output:
##    verify_phase_7_worker_N_results.txt  (F/G verification)
##    verify_phase_8_worker_N_results.txt  (H pair non-isomorphism)
##
##############################################################################

if not IsBound(WORKER_ID) then
    WORKER_ID := 1;
fi;
if not IsBound(WORKER_TOTAL) then
    WORKER_TOTAL := 1;
fi;

if not IsBound(BASE_DIR) then
    BASE_DIR := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s16_final_results_reindexed/";
fi;

_p7File := Concatenation(BASE_DIR, "verify_phase_7_worker_",
                         String(WORKER_ID), "_results.txt");
_p8File := Concatenation(BASE_DIR, "verify_phase_8_worker_",
                         String(WORKER_ID), "_results.txt");
_logFile := Concatenation(BASE_DIR, "verify_phase78_worker_",
                          String(WORKER_ID), "_log.txt");

##############################################################################
## Resume support: detect already-verified entries
##############################################################################

_p7Done := rec();  # set of type IDs already verified in Phase 7
_p8Done := rec();  # set of pair keys already verified in Phase 8

if IsExistingFile(_p7File) then
    _existLines := SplitString(StringFile(_p7File), "\n");
    for _line in _existLines do
        if Length(_line) > 4 and _line{[1..4]} = "PASS" then
            # Extract type id from "PASS|F|t=NNNN|..." or "PASS|G|t=NNNN|..."
            _tPos := PositionSublist(_line, "|t=");
            if _tPos <> fail then
                _tEnd := _tPos + 3;
                while _tEnd <= Length(_line) and _line[_tEnd] <> '|' do
                    _tEnd := _tEnd + 1;
                od;
                _tKey := _line{[_tPos+3.._tEnd-1]};
                _p7Done.(Concatenation("t", _tKey)) := true;
            fi;
        fi;
    od;
    Print("Worker ", WORKER_ID, ": Resuming Phase 7 with ",
          Length(RecNames(_p7Done)), " already verified\n");
else
    PrintTo(_p7File, "# Phase 7: F/G CharacterTable verification - worker ",
            WORKER_ID, "\n");
fi;

if IsExistingFile(_p8File) then
    _existLines := SplitString(StringFile(_p8File), "\n");
    for _line in _existLines do
        if Length(_line) > 4 and _line{[1..4]} = "PASS" then
            # Extract pair key from "PASS|H|t=AAA,BBB|..."
            _tPos := PositionSublist(_line, "|t=");
            if _tPos <> fail then
                _tEnd := _tPos + 3;
                while _tEnd <= Length(_line) and _line[_tEnd] <> '|' do
                    _tEnd := _tEnd + 1;
                od;
                _pairKey := _line{[_tPos+3.._tEnd-1]};
                _p8Done.(Concatenation("p", _pairKey)) := true;
            fi;
        fi;
    od;
    Print("Worker ", WORKER_ID, ": Resuming Phase 8 with ",
          Length(RecNames(_p8Done)), " already verified\n");
else
    PrintTo(_p8File, "# Phase 8: H pair non-isomorphism - worker ",
            WORKER_ID, "\n");
fi;

if IsExistingFile(_logFile) then
    AppendTo(_logFile, "\n# Resumed: ", StringTime(Runtime()), "\n");
else
    PrintTo(_logFile, "# Phase 7-8 verification - worker ",
            WORKER_ID, "/", WORKER_TOTAL, "\n");
fi;
AppendTo(_logFile, "# Started: ", StringTime(Runtime()), "\n\n");

##############################################################################
## Helper functions
##############################################################################

# Convert sorted list to frequency form: [v,v,v,w,w] -> [[v,3],[w,2]]
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

# RowPowerFingerprint: CharacterTable -> fingerprint via prime power maps
RowPowerFingerprint := function(ct)
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

# Serialize RowPowerFingerprint to a comparable string
RPHashString := function(rpFp)
    local s, entry, vals, p_entry;
    s := "";
    for entry in rpFp do
        for p_entry in entry do
            Append(s, String(p_entry[1]));
            Append(s, ":");
            for vals in p_entry[2] do
                Append(s, String(vals));
                Append(s, ",");
            od;
            Append(s, ";");
        od;
        Append(s, "|");
    od;
    return s;
end;

# Extract a single CT invariant by name
ExtractCTInvariant := function(ct, invariantName)
    local irrs, nClasses;
    irrs := Irr(ct);
    nClasses := NrConjugacyClasses(ct);

    if invariantName = "degrees" then
        return ToFrequency(SortedList(List(irrs, chi -> chi[1])));
    elif invariantName = "centralizers" then
        return ToFrequency(SortedList(SizesCentralizers(ct)));
    elif invariantName = "kernelSizes" then
        return ToFrequency(SortedList(List(irrs, function(chi)
            return Length(Filtered([1..nClasses], j -> chi[j] = chi[1]));
        end)));
    elif invariantName = "fsIndicators" then
        return ToFrequency(SortedList(ShallowCopy(Indicator(ct, 2))));
    else
        Error("Unknown CT invariant: ", invariantName);
    fi;
end;

# Extract composite CT invariant (e.g., "kernelSizes,fsIndicators")
ExtractCompositeCTInvariant := function(ct, compositeField)
    local fields, result, f;
    fields := SplitString(compositeField, ",");
    result := [];
    for f in fields do
        if f = "rpHash" then
            Add(result, RPHashString(RowPowerFingerprint(ct)));
        else
            Add(result, ExtractCTInvariant(ct, f));
        fi;
    od;
    return result;
end;

# Build peer-grouping key from certificate record: (sk, h, e7)
PeerKey := function(r)
    local s;
    s := String(r.sk);
    if IsBound(r.h) then
        s := Concatenation(s, "|", String(r.h));
    fi;
    if IsBound(r.e7) then
        s := Concatenation(s, "|E7:", String(r.e7));
    fi;
    return s;
end;

##############################################################################
## Load input files
##############################################################################

AppendTo(_logFile, "Loading s16_subgroups.g (254 MB)...\n");
Print("Worker ", WORKER_ID, ": Loading s16_subgroups.g...\n");
_t0 := Runtime();
_loadFunc := ReadAsFunction(Concatenation(BASE_DIR, "s16_subgroups.g"));
subgens := _loadFunc();
Unbind(_loadFunc);
AppendTo(_logFile, "  Loaded ", Length(subgens), " generator lists in ",
         Int((Runtime() - _t0) / 1000), "s\n");
Print("Worker ", WORKER_ID, ": Loaded ", Length(subgens),
      " generators in ", Int((Runtime() - _t0) / 1000), "s\n");

AppendTo(_logFile, "Loading certificate...\n");
Read(Concatenation(BASE_DIR, "s16_verification_certificate_v7.g"));
AppendTo(_logFile, "  Loaded ", Length(S16_VERIFY), " records\n");

GASMAN("collect");

##############################################################################
## Group builder
##############################################################################

_groupCount := 0;

BuildGroup := function(idx)
    _groupCount := _groupCount + 1;
    if _groupCount mod 500 = 0 then
        GASMAN("collect");
    fi;
    return Group(List(subgens[idx], PermList));
end;

##############################################################################
## Phase 7: Select F/G records for this worker
##############################################################################

AppendTo(_logFile, "\n--- Phase 7: F/G discrimination ---\n");
Print("Worker ", WORKER_ID, ": Phase 7 - selecting F/G records...\n");

# Collect ALL F/G/H records (needed for peer index)
_allFGH := Filtered(S16_VERIFY, r -> r.m in ["F", "G", "H"]);
AppendTo(_logFile, "  Total F/G/H records: ", Length(_allFGH), "\n");

# Round-robin partition: this worker takes every WORKER_TOTAL-th F/G record
_myFGRecords := [];
_fgCount := 0;
for _r in S16_VERIFY do
    if _r.m in ["F", "G"] then
        _fgCount := _fgCount + 1;
        if (_fgCount - 1) mod WORKER_TOTAL = (WORKER_ID - 1) then
            Add(_myFGRecords, _r);
        fi;
    fi;
od;
AppendTo(_logFile, "  This worker: ", Length(_myFGRecords), " F/G records\n");
Print("Worker ", WORKER_ID, ": ", Length(_myFGRecords), " F/G records to verify\n");

##############################################################################
## Phase 7: Build peer index by (sk, h, e7)
##############################################################################

AppendTo(_logFile, "  Building peer index...\n");

_peerIndex := NewDictionary("", true);
for _r in _allFGH do
    _pk := PeerKey(_r);
    _existing := LookupDictionary(_peerIndex, _pk);
    if _existing = fail then
        _existing := [];
        AddDictionary(_peerIndex, _pk, _existing);
    fi;
    Add(_existing, _r);
od;

# Free _allFGH — peer data is in _peerIndex
_allFGH := [];
GASMAN("collect");

##############################################################################
## Phase 7: Verify F/G records
##############################################################################

AppendTo(_logFile, "  Verifying F/G records...\n");

_p7Pass := 0;
_p7Fail := 0;
_p7t0 := Runtime();

for _idx in [1..Length(_myFGRecords)] do
    _r := _myFGRecords[_idx];
    _ti := _r.t;
    _rep := _r.i;
    _method := _r.m;

    # Resume: skip already-verified types
    if IsBound(_p7Done.(Concatenation("t", String(_ti)))) then
        _p7Pass := _p7Pass + 1;
        continue;
    fi;

    _t0 := Runtime();

    # Build group from s16_subgroups.g
    _G := BuildGroup(_rep);
    _ct := CharacterTable(_G);
    _ctTime := Runtime() - _t0;

    # Find peers (same sk + h + e7, excluding self, only F/G/H methods)
    _pk := PeerKey(_r);
    _allInBucket := LookupDictionary(_peerIndex, _pk);
    if _allInBucket = fail then
        _allInBucket := [];
    fi;

    _peers := [];
    for _pr in _allInBucket do
        if _pr.t <> _ti then
            Add(_peers, _pr);
        fi;
    od;

    if _method = "F" then
        _ctField := _r.ct;
        _isComposite := PositionSublist(_ctField, ",") <> fail;

        if _isComposite then
            _myInv := ExtractCompositeCTInvariant(_ct, _ctField);
        else
            _myInv := ExtractCTInvariant(_ct, _ctField);
        fi;

        _isUnique := true;
        for _pr in _peers do
            # Build peer group from s16_subgroups.g
            _prG := BuildGroup(_pr.i);
            _prCT := CharacterTable(_prG);

            if _isComposite then
                _prInv := ExtractCompositeCTInvariant(_prCT, _ctField);
            else
                _prInv := ExtractCTInvariant(_prCT, _ctField);
            fi;

            if _myInv = _prInv then
                _isUnique := false;
                AppendTo(_logFile, "  FAIL type ", _ti, ": peer ", _pr.t,
                         " has same ", _ctField, "\n");
            fi;

            _prG := 0; _prCT := 0;
        od;

        _totalTime := Runtime() - _t0;
        if _isUnique then
            AppendTo(_p7File, "PASS|F|t=", _ti, "|i=", _rep,
                     "|ct=", _ctField,
                     "|peers=", Length(_peers),
                     "|time=", _totalTime, "ms\n");
            _p7Pass := _p7Pass + 1;
        else
            AppendTo(_p7File, "FAIL|F|t=", _ti, "|i=", _rep,
                     "|ct=", _ctField, "|collision\n");
            _p7Fail := _p7Fail + 1;
        fi;

    elif _method = "G" then
        _myRP := RPHashString(RowPowerFingerprint(_ct));

        _isUnique := true;
        for _pr in _peers do
            _prG := BuildGroup(_pr.i);
            _prCT := CharacterTable(_prG);
            _prRP := RPHashString(RowPowerFingerprint(_prCT));

            if _myRP = _prRP then
                _isUnique := false;
                AppendTo(_logFile, "  FAIL type ", _ti, ": peer ", _pr.t,
                         " has same RowPowerFingerprint\n");
            fi;

            _prG := 0; _prCT := 0;
        od;

        _totalTime := Runtime() - _t0;
        if _isUnique then
            AppendTo(_p7File, "PASS|G|t=", _ti, "|i=", _rep,
                     "|peers=", Length(_peers),
                     "|time=", _totalTime, "ms\n");
            _p7Pass := _p7Pass + 1;
        else
            AppendTo(_p7File, "FAIL|G|t=", _ti, "|i=", _rep,
                     "|rp_collision\n");
            _p7Fail := _p7Fail + 1;
        fi;
    fi;

    # Clean up
    _G := 0; _ct := 0;
    if _idx mod 10 = 0 then
        GASMAN("collect");
        AppendTo(_logFile, "  [Phase 7: ", _idx, "/", Length(_myFGRecords),
                 " done: ", _p7Pass, " pass, ", _p7Fail, " fail, ",
                 Int((Runtime() - _p7t0) / 1000), "s]\n");
        Print("Worker ", WORKER_ID, ": Phase 7: ", _idx, "/",
              Length(_myFGRecords), " (", _p7Pass, " pass, ",
              _p7Fail, " fail)\n");
    fi;
od;

_p7Time := Int((Runtime() - _p7t0) / 1000);
AppendTo(_p7File, "\n# Phase 7 complete: ", _p7Pass, " PASS, ",
         _p7Fail, " FAIL (", _p7Time, "s)\n");
AppendTo(_logFile, "\nPhase 7 complete: ", _p7Pass, " PASS, ",
         _p7Fail, " FAIL (", _p7Time, "s)\n");
Print("Worker ", WORKER_ID, ": Phase 7 done: ", _p7Pass, " PASS, ",
      _p7Fail, " FAIL (", _p7Time, "s)\n");

GASMAN("collect");

##############################################################################
## Phase 8: H pair non-isomorphism
##############################################################################

AppendTo(_logFile, "\n--- Phase 8: H pair non-isomorphism ---\n");
Print("Worker ", WORKER_ID, ": Phase 8 - H pair non-isomorphism...\n");

# Collect H records, group by PeerKey -> pairs within each bucket
_hRecords := Filtered(S16_VERIFY, r -> r.m = "H");
AppendTo(_logFile, "  Total H records: ", Length(_hRecords), "\n");

# Group H records by PeerKey
_hBuckets := NewDictionary("", true);
for _r in _hRecords do
    _pk := PeerKey(_r);
    _existing := LookupDictionary(_hBuckets, _pk);
    if _existing = fail then
        _existing := [];
        AddDictionary(_hBuckets, _pk, _existing);
    fi;
    Add(_existing, _r);
od;

# Build list of all H pairs (unordered: only i < j to avoid duplicates)
_hPairs := [];
for _r in _hRecords do
    _pk := PeerKey(_r);
    _bucket := LookupDictionary(_hBuckets, _pk);
    for _pr in _bucket do
        if _pr.t > _r.t then
            Add(_hPairs, [_r, _pr]);
        fi;
    od;
od;

# Deduplicate: each pair appears once because we check r.t < pr.t
# Sort for deterministic ordering
Sort(_hPairs, function(a, b) return a[1].t < b[1].t or
    (a[1].t = b[1].t and a[2].t < b[2].t); end);

AppendTo(_logFile, "  Total H pairs: ", Length(_hPairs), "\n");
Print("Worker ", WORKER_ID, ": ", Length(_hPairs), " H pairs total\n");

# Round-robin partition for this worker
_myHPairs := [];
for _idx in [1..Length(_hPairs)] do
    if (_idx - 1) mod WORKER_TOTAL = (WORKER_ID - 1) then
        Add(_myHPairs, _hPairs[_idx]);
    fi;
od;

AppendTo(_logFile, "  This worker: ", Length(_myHPairs), " H pairs\n");
Print("Worker ", WORKER_ID, ": ", Length(_myHPairs), " H pairs for this worker\n");

_p8Pass := 0;
_p8Fail := 0;
_p8t0 := Runtime();

for _idx in [1..Length(_myHPairs)] do
    _pair := _myHPairs[_idx];
    _rA := _pair[1];
    _rB := _pair[2];

    # Resume: skip already-verified pairs
    _pairStr := Concatenation("p", String(_rA.t), ",", String(_rB.t));
    if IsBound(_p8Done.(_pairStr)) then
        _p8Pass := _p8Pass + 1;
        continue;
    fi;

    _t0 := Runtime();

    _GA := BuildGroup(_rA.i);
    _GB := BuildGroup(_rB.i);

    _iso := IsomorphismGroups(_GA, _GB);

    _pairTime := Runtime() - _t0;

    if _iso = fail then
        _p8Pass := _p8Pass + 1;
        AppendTo(_p8File, "PASS|H|t=", _rA.t, ",", _rB.t,
                 "|i=", _rA.i, ",", _rB.i,
                 "|order=", Size(_GA),
                 "|time=", _pairTime, "ms\n");
    else
        _p8Fail := _p8Fail + 1;
        AppendTo(_p8File, "FAIL|H|t=", _rA.t, ",", _rB.t,
                 "|i=", _rA.i, ",", _rB.i,
                 "|order=", Size(_GA),
                 "|ISOMORPHIC!\n");
        AppendTo(_logFile, "  FAIL: types ", _rA.t, " and ", _rB.t,
                 " ARE isomorphic! (order ", Size(_GA), ")\n");
    fi;

    # Clean up
    _GA := 0; _GB := 0; _iso := 0;
    if _idx mod 5 = 0 then
        GASMAN("collect");
    fi;

    if _idx mod 10 = 0 or _idx = Length(_myHPairs) then
        AppendTo(_logFile, "  [Phase 8: ", _idx, "/", Length(_myHPairs),
                 " done: ", _p8Pass, " pass, ", _p8Fail, " fail, ",
                 Int((Runtime() - _p8t0) / 1000), "s]\n");
        Print("Worker ", WORKER_ID, ": Phase 8: ", _idx, "/",
              Length(_myHPairs), " (", _p8Pass, " pass, ",
              _p8Fail, " fail)\n");
    fi;
od;

_p8Time := Int((Runtime() - _p8t0) / 1000);
AppendTo(_p8File, "\n# Phase 8 complete: ", _p8Pass, " PASS, ",
         _p8Fail, " FAIL (", _p8Time, "s)\n");
AppendTo(_logFile, "\nPhase 8 complete: ", _p8Pass, " PASS, ",
         _p8Fail, " FAIL (", _p8Time, "s)\n");
Print("Worker ", WORKER_ID, ": Phase 8 done: ", _p8Pass, " PASS, ",
      _p8Fail, " FAIL (", _p8Time, "s)\n");

##############################################################################
## Summary
##############################################################################

Print("\n");
Print("Worker ", WORKER_ID, " SUMMARY:\n");
Print("  Phase 7 (F/G): ", _p7Pass, " PASS, ", _p7Fail, " FAIL\n");
Print("  Phase 8 (H):   ", _p8Pass, " PASS, ", _p8Fail, " FAIL\n");
AppendTo(_logFile, "\n# Worker ", WORKER_ID, " SUMMARY:\n");
AppendTo(_logFile, "#   Phase 7 (F/G): ", _p7Pass, " PASS, ",
         _p7Fail, " FAIL\n");
AppendTo(_logFile, "#   Phase 8 (H):   ", _p8Pass, " PASS, ",
         _p8Fail, " FAIL\n");

if _p7Fail + _p8Fail > 0 then
    QuitGap(1);
else
    QuitGap(0);
fi;
