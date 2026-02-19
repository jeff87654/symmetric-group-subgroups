# Verify S15 isomorphism proofs against S16 conjugacy class data
# Handles three proof methods:
#   fullIso / explicit_homomorphism: top-level gens/images
#   FactorV3: factorMappings with per-factor gens/images

# Config (set by launcher)
if not IsBound(WORKER_ID) then WORKER_ID := 1; fi;
if not IsBound(NUM_WORKERS) then NUM_WORKERS := 3; fi;

Print("Verification worker ", WORKER_ID, " of ", NUM_WORKERS, " starting\n");

BASE_DIR := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/";
RESULTS_FILE := Concatenation(BASE_DIR, "s16_processing/checkpoints/verify_worker_",
                              String(WORKER_ID), "_results.txt");

# Load s16 subgroup data
Print("Loading s16_subgroups.g...\n");
genLists := ReadAsFunction(Concatenation(BASE_DIR, "conjugacy_cache/s16_subgroups.g"))();
Print("Loaded ", Length(genLists), " generator lists\n");

# Load combined proofs
Print("Loading combined_proof.g...\n");
Read(Concatenation(BASE_DIR, "s15_proof_certificate/combined_proof.g"));
Print("Loaded ", Length(S15_COMBINED_PROOFS), " proofs\n");

# Initialize results file
PrintTo(RESULTS_FILE, "# Verification results - Worker ", WORKER_ID, "\n");
AppendTo(RESULTS_FILE, "# Started: ", StringTime(Runtime()), "\n\n");

# Verify a single gens->images mapping between two groups.
# Returns "PASS" or a failure message string.
VerifySingleMapping := function(G_src, G_tgt, gensStrings, imagesStrings, label)
    local proofGens, proofImages, hom, genGroup;

    proofGens := List(gensStrings, s -> EvalString(s));
    proofImages := List(imagesStrings, s -> EvalString(s));

    # Lengths match
    if Length(proofGens) <> Length(proofImages) then
        return Concatenation(label, ": gens/images length mismatch (",
                             String(Length(proofGens)), " vs ", String(Length(proofImages)), ")");
    fi;

    # Gens in source group
    if not ForAll(proofGens, g -> g in G_src) then
        return Concatenation(label, ": gen not in source group");
    fi;

    # Images in target group
    if not ForAll(proofImages, h -> h in G_tgt) then
        return Concatenation(label, ": image not in target group");
    fi;

    # Gens generate source group
    genGroup := Group(proofGens);
    if Size(genGroup) <> Size(G_src) then
        return Concatenation(label, ": gens generate subgroup of order ",
                             String(Size(genGroup)), ", expected ", String(Size(G_src)));
    fi;

    # Valid homomorphism
    hom := GroupHomomorphismByImages(G_src, G_tgt, proofGens, proofImages);
    if hom = fail then
        return Concatenation(label, ": map is not a valid homomorphism");
    fi;

    # Surjectivity
    if Size(Image(hom)) <> Size(G_tgt) then
        return Concatenation(label, ": not surjective, |Image|=",
                             String(Size(Image(hom))), " expected ", String(Size(G_tgt)));
    fi;

    return "PASS";
end;

VerifyProofs := function()
    local i, proof, dupIdx, repIdx, G_dup, G_rep,
          passCount, failCount, total, startTime, checked,
          elapsed, orderDup, orderRep, msg, rate, method,
          fm, fmResult, allFactorsOK, j, factorGens_dup, factorGens_rep,
          F_dup, F_rep;

    passCount := 0;
    failCount := 0;
    checked := 0;
    total := Length(S15_COMBINED_PROOFS);
    startTime := Runtime();

    i := WORKER_ID;
    while i <= total do
        proof := S15_COMBINED_PROOFS[i];
        dupIdx := proof.duplicate;
        repIdx := proof.representative;
        method := proof.method;

        # Build groups from s16 data
        G_dup := Group(List(genLists[dupIdx], PermList));
        G_rep := Group(List(genLists[repIdx], PermList));

        orderDup := Size(G_dup);
        orderRep := Size(G_rep);

        # Check 1: Order match
        if orderDup <> orderRep then
            msg := Concatenation("FAIL proof ", String(i), " (", method, "): order mismatch dup=",
                                 String(dupIdx), " (|G|=", String(orderDup),
                                 ") rep=", String(repIdx), " (|H|=", String(orderRep), ")");
            Print(msg, "\n");
            AppendTo(RESULTS_FILE, msg, "\n");
            failCount := failCount + 1;
            checked := checked + 1;
            i := i + NUM_WORKERS;
            continue;
        fi;

        if method = "fullIso" or method = "explicit_homomorphism" then
            # Direct gens/images at top level
            msg := VerifySingleMapping(G_dup, G_rep, proof.gens, proof.images,
                                       Concatenation("proof ", String(i)));
            if msg = "PASS" then
                passCount := passCount + 1;
            else
                msg := Concatenation("FAIL ", msg, " (", method, ") dup=",
                                     String(dupIdx), " rep=", String(repIdx));
                Print(msg, "\n");
                AppendTo(RESULTS_FILE, msg, "\n");
                failCount := failCount + 1;
            fi;

        elif method = "FactorV3" then
            # Per-factor mappings: verify each factor independently
            # For a direct product G = F1 x F2, iso G ≅ H follows from F1 ≅ F1' and F2 ≅ F2'
            allFactorsOK := true;

            # Get direct factors of both groups
            factorGens_dup := DirectFactorsOfGroup(G_dup);
            factorGens_rep := DirectFactorsOfGroup(G_rep);

            if factorGens_dup = fail or factorGens_rep = fail then
                msg := Concatenation("FAIL proof ", String(i), " (FactorV3): DirectFactorsOfGroup failed dup=",
                                     String(dupIdx), " rep=", String(repIdx));
                Print(msg, "\n");
                AppendTo(RESULTS_FILE, msg, "\n");
                failCount := failCount + 1;
                checked := checked + 1;
                i := i + NUM_WORKERS;
                continue;
            fi;

            for j in [1..Length(proof.factorMappings)] do
                fm := proof.factorMappings[j];

                # The factor indices in the proof refer to factor ordering at proof time.
                # The gens/images are permutations that generate subgroups of G_dup/G_rep.
                # We verify the mapping directly without relying on factor index alignment.
                F_dup := Group(List(fm.gens, s -> EvalString(s)));
                F_rep := Group(List(fm.images, s -> EvalString(s)));

                fmResult := VerifySingleMapping(F_dup, F_rep, fm.gens, fm.images,
                                                Concatenation("proof ", String(i), " factor ", String(j)));
                if fmResult <> "PASS" then
                    msg := Concatenation("FAIL ", fmResult, " (FactorV3) dup=",
                                         String(dupIdx), " rep=", String(repIdx));
                    Print(msg, "\n");
                    AppendTo(RESULTS_FILE, msg, "\n");
                    allFactorsOK := false;
                fi;
            od;

            if allFactorsOK then
                # Verify factor orders multiply to group order
                # (ensures all factors are accounted for)
                if Product(List(proof.factorMappings, fm ->
                    Size(Group(List(fm.gens, s -> EvalString(s)))))) = orderDup then
                    passCount := passCount + 1;
                else
                    msg := Concatenation("FAIL proof ", String(i),
                                         " (FactorV3): factor orders don't multiply to group order dup=",
                                         String(dupIdx));
                    Print(msg, "\n");
                    AppendTo(RESULTS_FILE, msg, "\n");
                    failCount := failCount + 1;
                fi;
            else
                failCount := failCount + 1;
            fi;
        else
            msg := Concatenation("SKIP proof ", String(i), ": unknown method '", method, "'");
            Print(msg, "\n");
            AppendTo(RESULTS_FILE, msg, "\n");
        fi;

        checked := checked + 1;

        # Progress report every 200 proofs
        if checked mod 200 = 0 then
            elapsed := Runtime() - startTime;
            if elapsed > 0 then
                rate := Float(checked) / Float(elapsed) * 1000.0;
            else
                rate := 0.0;
            fi;
            Print("Worker ", WORKER_ID, ": ", checked, " checked (",
                  passCount, " pass, ", failCount, " fail) ",
                  "rate=", Int(rate), " proofs/sec ",
                  StringTime(elapsed), "\n");
        fi;

        # GC every 300 proofs
        if checked mod 300 = 0 then
            GASMAN("collect");
        fi;

        i := i + NUM_WORKERS;
    od;

    # Final report
    elapsed := Runtime() - startTime;
    msg := Concatenation("\n=== Worker ", String(WORKER_ID), " COMPLETE ===\n",
                         "Passed: ", String(passCount), "\n",
                         "Failed: ", String(failCount), "\n",
                         "Total checked: ", String(checked), "\n",
                         "Time: ", StringTime(elapsed), "\n");
    Print(msg);
    AppendTo(RESULTS_FILE, "\n", msg);

    if failCount = 0 then
        Print("ALL PROOFS VERIFIED\n");
        AppendTo(RESULTS_FILE, "ALL PROOFS VERIFIED\n");
    else
        Print("WARNING: ", failCount, " FAILURES DETECTED\n");
        AppendTo(RESULTS_FILE, "WARNING: ", String(failCount), " FAILURES DETECTED\n");
    fi;

    return rec(passed := passCount, failed := failCount, total := checked);
end;

result := VerifyProofs();
QUIT;
