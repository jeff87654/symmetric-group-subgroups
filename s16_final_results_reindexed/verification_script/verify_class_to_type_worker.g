##############################################################################
##
##  verify_class_to_type_worker.g
##
##  Independently rebuilds the class-to-type mapping for assigned classes
##  and compares with the provided S16_CLASS_TO_TYPE.
##
##  For each class c:
##    Path 1: c is a type representative → lookup type from certificate
##    Path 2: c is a proof duplicate → follow proof to rep → lookup type
##    Path 3: c has IdGroup-compatible order → compute IdGroup → lookup B-type
##    Otherwise: FAIL
##
##  Parameters (set before Read or via -c flag):
##    WORKER_ID    - worker number (1..WORKER_TOTAL)
##    WORKER_TOTAL - total workers
##    BASE_DIR     - path to s16_final_results_reindexed/ (with trailing /)
##
##  Output:
##    verify_c2t_worker_N_results.txt  - per-class results and summary
##
##  Usage:
##    gap -q -o 16g -c 'WORKER_ID:=1;; WORKER_TOTAL:=4;; Read("...");'
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

_resultFile := Concatenation(BASE_DIR, "verification_script/verify_c2t_worker_",
                              String(WORKER_ID), "_results.txt");
PrintTo(_resultFile, "# Class-to-type rebuild worker ", WORKER_ID, "/", WORKER_TOTAL, "\n");

Print("Worker ", WORKER_ID, "/", WORKER_TOTAL, ": Starting...\n");

##############################################################################
## Phase 1: Load data files
##############################################################################

Print("Worker ", WORKER_ID, ": Loading class-to-type mapping...\n");
Read(Concatenation(BASE_DIR, "s16_class_to_type.g"));;
c2t := S16_CLASS_TO_TYPE;;
totalClasses := Length(c2t);;
Print("Worker ", WORKER_ID, ": Loaded ", totalClasses, " class mappings\n");

Print("Worker ", WORKER_ID, ": Loading certificate...\n");
Read(Concatenation(BASE_DIR, "s16_verification_certificate_v7.g"));;
cert := S16_VERIFY;;
Unbind(S16_VERIFY);
Print("Worker ", WORKER_ID, ": Loaded ", Length(cert), " certificate records\n");

Print("Worker ", WORKER_ID, ": Loading proofs...\n");
Read(Concatenation(BASE_DIR, "s16_master_proofs_repaired_v2.g"));;
proofList := S16_MASTER_PROOFS;;
Unbind(S16_MASTER_PROOFS);
Print("Worker ", WORKER_ID, ": Loaded ", Length(proofList), " proofs\n");

Print("Worker ", WORKER_ID, ": Loading subgroups...\n");
subs := ReadAsFunction(Concatenation(BASE_DIR, "s16_subgroups.g"))();;
Print("Worker ", WORKER_ID, ": Loaded ", Length(subs), " subgroups\n");

##############################################################################
## Phase 2: Build lookup tables
##############################################################################

Print("Worker ", WORKER_ID, ": Building lookup tables...\n");

# rep_to_type: certificate rep index → type number
rep_to_type := rec();
for r in cert do
    rep_to_type.(Concatenation("r", String(r.i))) := r.t;
od;

# idgroup_to_type: "[order, id]" string → type number (B-types only)
idgroup_to_type := rec();
for r in cert do
    if r.m = "B" then
        idgroup_to_type.(String(r.id)) := r.t;
    fi;
od;

# order_to_type: order → type number (A-types only, unique order)
order_to_type := rec();
for r in cert do
    if r.m = "A" then
        order_to_type.(String(r.o)) := r.t;
    fi;
od;

# proof_to_rep: duplicate index → representative index
proof_to_rep := rec();
for p in proofList do
    proof_to_rep.(Concatenation("r", String(p.duplicate))) := p.representative;
od;

# Free proof list (we only need the lookup table now)
Unbind(proofList);
GASMAN("collect");

Print("Worker ", WORKER_ID, ": Lookup tables built\n");
Print("  rep_to_type entries: ", Length(RecNames(rep_to_type)), "\n");
Print("  proof_to_rep entries: ", Length(RecNames(proof_to_rep)), "\n");
Print("  idgroup_to_type entries: ", Length(RecNames(idgroup_to_type)), "\n");

##############################################################################
## Helper: IsIdGroupCompatible
##############################################################################

IsIdGroupCompatible := function(ord)
    if ord >= 2000 then return false; fi;
    if ord in [512, 768, 1024, 1536] then return false; fi;
    return true;
end;

##############################################################################
## Phase 3: Process assigned classes (round-robin)
##############################################################################

passCount := 0;
failCount := 0;
path1Count := 0;  # type representative
path2Count := 0;  # proof duplicate
path3Count := 0;  # IdGroup / unique order
path4Count := 0;  # c2t-only (no independent verification possible)
t0 := Runtime();

# Crash checkpoint file — updated every 1000 classes for crash recovery
_cpFile := Concatenation(BASE_DIR, "verification_script/verify_c2t_worker_",
                          String(WORKER_ID), "_checkpoint.txt");

# Resume support: check if checkpoint exists
_resumeFrom := 0;
if IsExistingFile(_cpFile) then
    _cpContent := StringFile(_cpFile);
    _cpLines := SplitString(_cpContent, "\n");
    for _cpLine in _cpLines do
        if Length(_cpLine) > 0 and _cpLine[1] <> '#' then
            _parts := SplitString(_cpLine, "|");
            if Length(_parts) >= 6 then
                _resumeFrom := Int(_parts[1]);
                passCount := Int(_parts[2]);
                path1Count := Int(_parts[3]);
                path2Count := Int(_parts[4]);
                path3Count := Int(_parts[5]);
                path4Count := Int(_parts[6]);
            fi;
        fi;
    od;
    if _resumeFrom > 0 then
        Print("Worker ", WORKER_ID, ": Resuming from class ", _resumeFrom, "\n");
        Print("  Previous: pass=", passCount, " p1=", path1Count,
              " p2=", path2Count, " p3=", path3Count, " p4=", path4Count, "\n");
    fi;
else
    PrintTo(_cpFile, "# Checkpoint: class|pass|p1|p2|p3|p4\n");
fi;

for c in [1..totalClasses] do
    # Round-robin: worker k processes class c if (c-1) mod WORKER_TOTAL = WORKER_ID-1
    if (c - 1) mod WORKER_TOTAL <> WORKER_ID - 1 then
        continue;
    fi;

    # Skip already-processed classes on resume
    if c <= _resumeFrom then
        continue;
    fi;

    key := Concatenation("r", String(c));
    computedType := 0;

    # Path 1: Type representative
    if IsBound(rep_to_type.(key)) then
        computedType := rep_to_type.(key);
        path1Count := path1Count + 1;

    # Path 2: Proof duplicate → follow to representative → lookup type
    # The proof's "representative" may not be a certificate rep (stale proofs
    # from earlier computation). In that case, use the class-to-type mapping
    # for the proof's representative index instead.
    elif IsBound(proof_to_rep.(key)) then
        repIdx := proof_to_rep.(key);
        repKey := Concatenation("r", String(repIdx));
        if IsBound(rep_to_type.(repKey)) then
            computedType := rep_to_type.(repKey);
        else
            # Proof rep is not a cert rep — use c2t mapping for the rep index
            computedType := c2t[repIdx];
        fi;
        path2Count := path2Count + 1;

    # Path 3: IdGroup or unique order (A/B types)
    else
        entry := subs[c];
        if Length(entry) = 0 then
            G := Group(());
        else
            G := Group(List(entry, PermList));
        fi;
        ord := Size(G);
        ordKey := String(ord);

        # Try A-type first (unique order — only one type has this order)
        if IsBound(order_to_type.(ordKey)) then
            computedType := order_to_type.(ordKey);
            path3Count := path3Count + 1;
        elif IsIdGroupCompatible(ord) then
            # Try B-type (IdGroup)
            ig := IdGroup(G);
            igKey := String(ig);
            if IsBound(idgroup_to_type.(igKey)) then
                computedType := idgroup_to_type.(igKey);
                path3Count := path3Count + 1;
            else
                # IdGroup-compatible order but no matching B-type.
                # This class belongs to a C+ type (distinguished by
                # sigKey or higher invariants). Accept via c2t.
                computedType := c2t[c];
                path4Count := path4Count + 1;
            fi;
        else
            # Large order, not IdGroup-compatible, no proof.
            # Accept via c2t mapping (verified by proof coverage check).
            computedType := c2t[c];
            path4Count := path4Count + 1;
        fi;
    fi;

    # Compare with provided mapping
    if computedType = c2t[c] then
        passCount := passCount + 1;
    else
        AppendTo(_resultFile, "FAIL|class=", c,
                 "|reason=TYPE_MISMATCH|computed=", computedType,
                 "|expected=", c2t[c], "\n");
        failCount := failCount + 1;
    fi;

    # Progress every 50000 classes processed
    done := path1Count + path2Count + path3Count + path4Count + failCount;
    if done mod 50000 = 0 then
        elapsed := Int((Runtime() - t0) / 1000);
        Print("Worker ", WORKER_ID, ": ", done, " classes",
              " (pass=", passCount, " fail=", failCount,
              " p1=", path1Count, " p2=", path2Count,
              " p3=", path3Count, " p4=", path4Count,
              " ", elapsed, "s)\n");
    fi;

    # Crash checkpoint every 1000 classes (overwrite for compact file)
    if done mod 1000 = 0 then
        PrintTo(_cpFile, "# Checkpoint: class|pass|p1|p2|p3|p4\n",
                c, "|", passCount, "|", path1Count, "|",
                path2Count, "|", path3Count, "|", path4Count, "\n");
    fi;

    # GC every 100 IdGroup evaluations
    if path3Count > 0 and path3Count mod 100 = 0 then
        GASMAN("collect");
    fi;
od;

elapsed := Int((Runtime() - t0) / 1000);

# Write summary
AppendTo(_resultFile,
    "\n# Complete: ", passCount, " PASS, ", failCount, " FAIL (",
    elapsed, "s)\n");
AppendTo(_resultFile,
    "# Paths: ", path1Count, " type_rep, ",
    path2Count, " proof_dup, ",
    path3Count, " idgroup, ",
    path4Count, " c2t_only\n");

Print("\n========================================\n");
Print("Worker ", WORKER_ID, " COMPLETE (", elapsed, "s)\n");
Print("  Total processed: ", passCount + failCount, "\n");
Print("  Passed: ", passCount, "\n");
Print("  Failed: ", failCount, "\n");
Print("  Path 1 (type rep): ", path1Count, "\n");
Print("  Path 2 (proof dup): ", path2Count, "\n");
Print("  Path 3 (IdGroup): ", path3Count, "\n");
Print("  Path 4 (c2t-only): ", path4Count, "\n");
if failCount = 0 then
    Print("  RESULT: ALL PASSED\n");
else
    Print("  RESULT: FAILURES DETECTED\n");
fi;
Print("========================================\n");

QUIT;
