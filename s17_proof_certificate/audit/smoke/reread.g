CT := [];;
Read("/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s17_proof_certificate/audit/smoke/ct.g");
for k in [62511, 62512, 162511, 9434] do
  r := CT[k];
  Print(k, ": order ", r.order, " classes ", Length(r.reps), " irr ", Length(r.irr),
        "  sum deg^2 = |G|: ", Sum(r.irr, x -> x[1]^2) = r.order,
        "  row orthogonality: ", ForAll(r.irr, x -> Sum([1..Length(r.reps)], c -> r.sizes[c] * x[c] * ComplexConjugate(x[c])) = r.order),
        "  class sizes sum: ", Sum(r.sizes) = r.order, "\n");
od;
QUIT;
