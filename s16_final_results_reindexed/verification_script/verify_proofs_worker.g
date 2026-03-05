##############################################################################
##
##  verify_proofs_worker.g
##
##  Proof validation worker for A174511(16) verification.
##
##  For each proof in S16_MASTER_PROOFS, verifies:
##    A) Size(Group(proof.gens)) == Size(G_dup)
##    B) Each proof gen is in G_dup
##    C) GroupHomomorphismByImages(G_proof, G_rep, gens, images) <> fail
##
##  Parameters (set before Read or via -c flag):
##    WORKER_ID    - worker number (1..WORKER_TOTAL)
##    WORKER_TOTAL - total workers
##    BASE_DIR     - path to s16_final_results_reindexed/ (with trailing /)
##
##  Output:
##    verify_proof_worker_N_results.txt  - per-proof PASS/FAIL lines
##    verify_proof_worker_N_dups.txt     - duplicate indices (one per line)
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

_resultFile := Concatenation(BASE_DIR, "verification_script/verify_proof_worker_",
                              String(WORKER_ID), "_results.txt");
_dupFile := Concatenation(BASE_DIR, "verification_script/verify_proof_worker_",
                           String(WORKER_ID), "_dups.txt");

PrintTo(_resultFile, "# Proof verification worker ", WORKER_ID, "/", WORKER_TOTAL, "\n");
PrintTo(_dupFile, "# Duplicate indices verified by worker ", WORKER_ID, "\n");

Print("Worker ", WORKER_ID, "/", WORKER_TOTAL, ": Loading subgroups...\n");
subs := ReadAsFunction(Concatenation(BASE_DIR, "s16_subgroups.g"))();;
Print("Worker ", WORKER_ID, ": Loaded ", Length(subs), " subgroups\n");

Print("Worker ", WORKER_ID, ": Loading proofs...\n");
Read(Concatenation(BASE_DIR, "s16_master_proofs_repaired_v2.g"));;
proofs := S16_MASTER_PROOFS;;
Unbind(S16_MASTER_PROOFS);
Print("Worker ", WORKER_ID, ": Loaded ", Length(proofs), " proofs\n");

# Contiguous chunk assignment
N := Length(proofs);
chunkSize := Int(N / WORKER_TOTAL);
startIdx := (WORKER_ID - 1) * chunkSize + 1;
if WORKER_ID = WORKER_TOTAL then
    endIdx := N;
else
    endIdx := WORKER_ID * chunkSize;
fi;

Print("Worker ", WORKER_ID, ": Processing proofs ", startIdx, " to ", endIdx,
      " (", endIdx - startIdx + 1, " proofs)\n");

# Group object cache
groupCache := rec();

GetGroup := function(idx)
    local key, entry, gens;
    key := Concatenation("g", String(idx));
    if IsBound(groupCache.(key)) then
        return groupCache.(key);
    fi;
    entry := subs[idx];
    if Length(entry) = 0 then
        groupCache.(key) := Group(());
    else
        gens := List(entry, PermList);
        groupCache.(key) := Group(gens);
    fi;
    return groupCache.(key);
end;

sizeFail := 0;
containFail := 0;
homoFail := 0;
passCount := 0;
factorV3Count := 0;
t0 := Runtime();

for proofIdx in [startIdx..endIdx] do
    if not IsBound(proofs[proofIdx]) then
        continue;
    fi;
    proof := proofs[proofIdx];
    D := proof.duplicate;
    R := proof.representative;

    G_dup := GetGroup(D);
    G_rep := GetGroup(R);

    # Collect gens and images from proof
    if IsBound(proof.gens) then
        proof_gens := List(proof.gens, EvalString);
        proof_images := List(proof.images, EvalString);
    elif IsBound(proof.factorMappings) then
        factorV3Count := factorV3Count + 1;
        proof_gens := [];
        proof_images := [];
        for fm in proof.factorMappings do
            Append(proof_gens, List(fm.gens, EvalString));
            Append(proof_images, List(fm.images, EvalString));
        od;
    else
        AppendTo(_resultFile, "FAIL|proof=", proofIdx, "|dup=", D,
                 "|rep=", R, "|reason=NO_GENS\n");
        homoFail := homoFail + 1;
        continue;
    fi;

    if Length(proof_gens) = 0 then
        AppendTo(_resultFile, "FAIL|proof=", proofIdx, "|dup=", D,
                 "|rep=", R, "|reason=EMPTY_GENS\n");
        homoFail := homoFail + 1;
        continue;
    fi;

    G_proof := Group(proof_gens);

    # Phase A: Size check
    if Size(G_proof) <> Size(G_dup) then
        AppendTo(_resultFile, "FAIL|proof=", proofIdx, "|dup=", D,
                 "|rep=", R, "|reason=SIZE_FAIL",
                 "|proof_size=", Size(G_proof),
                 "|dup_size=", Size(G_dup), "\n");
        sizeFail := sizeFail + 1;
        continue;
    fi;

    # Phase B: Containment (proof gens are in the subgroup at index D)
    containOK := true;
    for g in proof_gens do
        if not (g in G_dup) then
            containOK := false;
            break;
        fi;
    od;
    if not containOK then
        AppendTo(_resultFile, "FAIL|proof=", proofIdx, "|dup=", D,
                 "|rep=", R, "|reason=CONTAIN_FAIL\n");
        containFail := containFail + 1;
        continue;
    fi;

    # Phase C: GroupHomomorphismByImages (valid bijective homomorphism)
    phi := GroupHomomorphismByImages(G_proof, G_rep, proof_gens, proof_images);
    if phi = fail then
        AppendTo(_resultFile, "FAIL|proof=", proofIdx, "|dup=", D,
                 "|rep=", R, "|reason=HOMO_FAIL\n");
        homoFail := homoFail + 1;
        continue;
    fi;

    passCount := passCount + 1;

    # Record duplicate index
    AppendTo(_dupFile, D, "\n");

    # Checkpoint and progress every 5000 proofs
    done := proofIdx - startIdx + 1;
    if done mod 5000 = 0 then
        elapsed := Int((Runtime() - t0) / 1000);
        total := endIdx - startIdx + 1;
        Print("Worker ", WORKER_ID, ": ", done, "/", total,
              " (", elapsed, "s, pass=", passCount,
              " fail=", sizeFail + containFail + homoFail, ")\n");
        AppendTo(_resultFile,
                 "# Checkpoint: ", done, "/", total,
                 " pass=", passCount,
                 " sizeFail=", sizeFail,
                 " containFail=", containFail,
                 " homoFail=", homoFail,
                 " elapsed=", elapsed, "s\n");
    fi;

    # GC every 500 groups to manage memory
    if done mod 500 = 0 then
        GASMAN("collect");
    fi;
od;

elapsed := Int((Runtime() - t0) / 1000);

# Write summary
AppendTo(_resultFile,
    "\n# Complete: ", passCount, " PASS, ",
    sizeFail, " SIZE_FAIL, ",
    containFail, " CONTAIN_FAIL, ",
    homoFail, " HOMO_FAIL (",
    elapsed, "s)\n");

Print("\n========================================\n");
Print("Worker ", WORKER_ID, " COMPLETE (", elapsed, "s)\n");
Print("  Processed: ", endIdx - startIdx + 1, "\n");
Print("  Passed: ", passCount, "\n");
Print("  Size failures: ", sizeFail, "\n");
Print("  Containment failures: ", containFail, "\n");
Print("  Homomorphism failures: ", homoFail, "\n");
Print("  FactorV3 proofs: ", factorV3Count, "\n");
if sizeFail = 0 and containFail = 0 and homoFail = 0 then
    Print("  RESULT: ALL PASSED\n");
else
    Print("  RESULT: FAILURES DETECTED\n");
fi;
Print("========================================\n");

QUIT;
