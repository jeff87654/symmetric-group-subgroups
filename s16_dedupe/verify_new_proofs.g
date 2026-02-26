# Verify new proofs from staging file before appending to master
# For each proof:
#   - Standard (gens/images): verify GroupHomomorphismByImages is bijective
#   - FactorV3 (factorMappings): verify each factor mapping is bijective
SetInfoLevel(InfoWarning, 0);;

Print("Loading staging file...\n");
Read("/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s16_dedupe/proofs/new_proofs_staging.g");

Print("Loaded ", Length(NEW_PROOFS_STAGING), " proofs to verify.\n\n");

totalPass := 0;;
totalFail := 0;;
failedProofs := [];;

VerifyStandardProof := function(proof, idx)
    local proofGens, proofImages, G1, G2, phi;

    proofGens := List(proof.gens, s -> EvalString(s));
    proofImages := List(proof.images, s -> EvalString(s));

    if Length(proofGens) <> Length(proofImages) then
        Print("FAIL proof ", idx, " (dup=", proof.duplicate, "): gens/images length mismatch\n");
        return false;
    fi;

    if Length(proofGens) = 0 then
        Print("FAIL proof ", idx, " (dup=", proof.duplicate, "): empty gens\n");
        return false;
    fi;

    G1 := Group(proofGens);
    G2 := Group(proofImages);

    if Size(G1) <> Size(G2) then
        Print("FAIL proof ", idx, " (dup=", proof.duplicate, "): order mismatch ",
              Size(G1), " vs ", Size(G2), "\n");
        return false;
    fi;

    phi := GroupHomomorphismByImages(G1, G2, proofGens, proofImages);
    if phi = fail then
        Print("FAIL proof ", idx, " (dup=", proof.duplicate, "): GHBI returned fail\n");
        return false;
    fi;

    if Size(Image(phi)) <> Size(G1) then
        Print("FAIL proof ", idx, " (dup=", proof.duplicate, "): not surjective, image order ",
              Size(Image(phi)), " expected ", Size(G1), "\n");
        return false;
    fi;

    return true;
end;;

VerifyFactorV3Proof := function(proof, idx)
    local mappings, j, fm, fGens, fImages, F1, F2, phi;

    mappings := proof.factorMappings;
    if Length(mappings) = 0 then
        Print("FAIL proof ", idx, " (dup=", proof.duplicate, "): empty factorMappings\n");
        return false;
    fi;

    for j in [1..Length(mappings)] do
        fm := mappings[j];
        fGens := List(fm.gens, s -> EvalString(s));
        fImages := List(fm.images, s -> EvalString(s));

        if Length(fGens) <> Length(fImages) then
            Print("FAIL proof ", idx, " (dup=", proof.duplicate,
                  "): factor ", j, " gens/images length mismatch\n");
            return false;
        fi;

        if Length(fGens) = 0 then
            Print("FAIL proof ", idx, " (dup=", proof.duplicate,
                  "): factor ", j, " empty gens\n");
            return false;
        fi;

        F1 := Group(fGens);
        F2 := Group(fImages);

        if Size(F1) <> Size(F2) then
            Print("FAIL proof ", idx, " (dup=", proof.duplicate,
                  "): factor ", j, " order mismatch ", Size(F1), " vs ", Size(F2), "\n");
            return false;
        fi;

        phi := GroupHomomorphismByImages(F1, F2, fGens, fImages);
        if phi = fail then
            Print("FAIL proof ", idx, " (dup=", proof.duplicate,
                  "): factor ", j, " GHBI returned fail\n");
            return false;
        fi;

        if Size(Image(phi)) <> Size(F1) then
            Print("FAIL proof ", idx, " (dup=", proof.duplicate,
                  "): factor ", j, " not surjective\n");
            return false;
        fi;
    od;

    return true;
end;;

for i in [1..Length(NEW_PROOFS_STAGING)] do
    proof := NEW_PROOFS_STAGING[i];

    if IsBound(proof.factorMappings) then
        # FactorV3 proof
        if VerifyFactorV3Proof(proof, i) then
            totalPass := totalPass + 1;
        else
            totalFail := totalFail + 1;
            Add(failedProofs, i);
        fi;
    elif IsBound(proof.gens) and IsBound(proof.images) then
        # Standard proof
        if VerifyStandardProof(proof, i) then
            totalPass := totalPass + 1;
        else
            totalFail := totalFail + 1;
            Add(failedProofs, i);
        fi;
    else
        Print("FAIL proof ", i, " (dup=", proof.duplicate, "): no gens/images or factorMappings\n");
        totalFail := totalFail + 1;
        Add(failedProofs, i);
    fi;

    if i mod 100 = 0 or i = Length(NEW_PROOFS_STAGING) then
        Print("  Progress: ", i, "/", Length(NEW_PROOFS_STAGING),
              " (", totalPass, " pass, ", totalFail, " fail)\n");
    fi;
od;

Print("\n========================================\n");
Print("VERIFICATION COMPLETE\n");
Print("  Total proofs: ", Length(NEW_PROOFS_STAGING), "\n");
Print("  Passed: ", totalPass, "\n");
Print("  Failed: ", totalFail, "\n");
if totalFail = 0 then
    Print("  STATUS: ALL PROOFS VALID\n");
else
    Print("  STATUS: FAILURES DETECTED\n");
    Print("  Failed proof indices: ", failedProofs, "\n");
fi;
Print("========================================\n");

QUIT;
