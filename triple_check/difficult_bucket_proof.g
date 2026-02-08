#############################################################################
#
#  Isomorphism proof for the difficult bucket
#  sigKey = [ 2592, 162, 42, 3, [ 2, 2, 2, 2 ] ]
#
#  These 4 groups do NOT decompose as direct products, so factor-level
#  optimization cannot be used.  GAP's IsomorphismGroups() hangs on them
#  (order 2592, derived length 3, 42 conjugacy classes).
#
#  Instead we supply explicit bijective homomorphisms and let GAP verify
#  that each map is indeed a valid bijective group homomorphism.
#
#  Result:  All 4 groups are isomorphic.
#           The bucket collapses to 1 representative.
#
#  Verified: 2026-02-04
#
#############################################################################
#
#  Source records (from s14_large_invariants.g / s14_large_invariants_clean.g):
#
#    Index  3943  (originalIndex 25234)
#    Index  3944  (originalIndex 25235)
#    Index  3945  (originalIndex 25236)
#    Index 10687  (originalIndex 75144)
#
#  Shared invariants:
#    order         = 2592
#    derivedSize   = 162
#    numClasses    = 42
#    derivedLength = 3
#    abelianInvs   = [ 2, 2, 2, 2 ]
#    histogram     = [ [1,1], [2,243], [3,80], [4,972], [6,1296] ]
#    maxOrder      = 6
#    numOrders     = 5
#    isDirectProduct = false
#
#############################################################################

Print("=== Difficult Bucket Isomorphism Proof ===\n");
Print("sigKey = [ 2592, 162, 42, 3, [ 2, 2, 2, 2 ] ]\n\n");

#############################################################################
# 1.  Define the four groups
#############################################################################

G3943 := Group([
  (3,6)(4,8)(5,14)(7,9)(10,12)(11,13),
  (1,2)(3,13)(4,9)(5,10)(6,11)(7,8)(12,14),
  (10,11)(12,13),
  (5,6)(10,11),
  (3,14)(5,6)(10,11)(12,13),
  (3,14,8)(4,5,6),
  (4,5,6),
  (7,13,12)(9,10,11),
  (9,10,11)
]);

G3944 := Group([
  (3,6)(4,8)(5,14)(7,9)(10,12)(11,13),
  (3,13)(4,9)(5,10)(6,11)(7,8)(12,14),
  (10,11)(12,13),
  (1,2)(5,6)(10,11),
  (3,14)(5,6)(10,11)(12,13),
  (3,14,8)(4,5,6),
  (4,5,6),
  (7,13,12)(9,10,11),
  (9,10,11)
]);

G3945 := Group([
  (3,6)(4,8)(5,14)(7,9)(10,12)(11,13),
  (1,2)(3,13)(4,9)(5,10)(6,11)(7,8)(12,14),
  (1,2)(10,11)(12,13),
  (5,6)(10,11),
  (3,14)(5,6)(10,11)(12,13),
  (3,14,8)(4,5,6),
  (4,5,6),
  (7,13,12)(9,10,11),
  (9,10,11)
]);

G10687 := Group([
  (2,5,10),
  (7,8,12),
  (2,5)(7,12),
  (9,14,11),
  (2,5)(11,14),
  (4,13,6),
  (2,5)(6,13),
  (2,12)(4,9)(5,7)(6,11)(8,10)(13,14),
  (2,14)(4,8)(5,11)(6,7)(9,10)(12,13)
]);

# Verify orders
Print("Group orders: ");
Print(Size(G3943), " ", Size(G3944), " ", Size(G3945), " ", Size(G10687), "\n");
Assert(0, Size(G3943) = 2592);
Assert(0, Size(G3944) = 2592);
Assert(0, Size(G3945) = 2592);
Assert(0, Size(G10687) = 2592);

#############################################################################
# 2.  Generators of G3943 (domain of all three maps)
#############################################################################

gens3943 := [
  (3,6)(4,8)(5,14)(7,9)(10,12)(11,13),
  (1,2)(3,13)(4,9)(5,10)(6,11)(7,8)(12,14),
  (10,11)(12,13),
  (5,6)(10,11),
  (3,14)(5,6)(10,11)(12,13),
  (3,14,8)(4,5,6),
  (4,5,6),
  (7,13,12)(9,10,11),
  (9,10,11)
];

errors := 0;
passed := 0;

CheckIso := function(name, phi)
    local ok;
    if phi = fail then
        Print("FAIL ", name, ": GroupHomomorphismByImages returned fail\n");
        errors := errors + 1;
        return;
    fi;
    ok := IsGroupHomomorphism(phi) and IsBijective(phi) and Size(Image(phi)) = 2592;
    if ok then
        Print("PASS ", name, "\n");
        Print("      IsGroupHomomorphism = true\n");
        Print("      IsBijective         = true\n");
        Print("      |Image|             = ", Size(Image(phi)), "\n");
        passed := passed + 1;
    else
        Print("FAIL ", name, ":\n");
        Print("      IsGroupHomomorphism = ", IsGroupHomomorphism(phi), "\n");
        Print("      IsBijective         = ", IsBijective(phi), "\n");
        Print("      |Image|             = ", Size(Image(phi)), "\n");
        errors := errors + 1;
    fi;
end;

#############################################################################
# 3a.  Isomorphism  G3943 --> G3944
#
#      Generator images found by explicit construction.
#############################################################################

Print("\n--- phi1 : G3943 -> G3944 ---\n");

phi1 := GroupHomomorphismByImages(G3943, G3944, gens3943, [
  (1,2)(3,8)(7,12),
  (1,2)(3,12)(4,10)(5,11)(6,9)(7,8)(13,14),
  (3,8)(4,6),
  (3,6)(4,8)(5,14)(7,10)(9,12)(11,13),
  (3,8)(4,6)(7,12)(9,10),
  (7,13,12),
  (7,12,13)(9,10,11),
  (3,8,14),
  (3,14,8)(4,5,6)
]);

CheckIso("phi1 : G3943 -> G3944", phi1);

#############################################################################
# 3b.  Isomorphism  G3943 --> G3945
#############################################################################

Print("\n--- phi2 : G3943 -> G3945 ---\n");

phi2 := GroupHomomorphismByImages(G3943, G3945, gens3943, [
  (1,2)(3,7)(4,9)(5,10)(6,11)(8,13)(12,14),
  (3,8)(7,13),
  (3,10)(4,12)(5,7)(6,13)(8,11)(9,14),
  (1,2)(5,6)(7,13),
  (3,8)(5,6)(7,13)(10,11),
  (3,14,8)(4,5,6)(7,13,12)(9,11,10),
  (4,5,6)(7,13,12),
  (3,8,14)(4,5,6)(7,12,13)(9,11,10),
  (4,5,6)(7,12,13)
]);

CheckIso("phi2 : G3943 -> G3945", phi2);

#############################################################################
# 3c.  Isomorphism  G3943 --> G10687
#############################################################################

Print("\n--- phi3 : G3943 -> G10687 ---\n");

phi3 := GroupHomomorphismByImages(G3943, G10687, gens3943, [
  (2,6)(4,10)(5,13)(7,11)(8,9)(12,14),
  (7,12)(11,14),
  (2,8)(4,14)(5,7)(6,9)(10,12)(11,13),
  (5,10)(7,12),
  (4,13)(5,10)(7,12)(11,14),
  (2,5,10)(4,13,6)(7,12,8)(9,14,11),
  (2,5,10)(7,12,8),
  (2,5,10)(4,13,6)(7,8,12)(9,11,14),
  (2,5,10)(7,8,12)
]);

CheckIso("phi3 : G3943 -> G10687", phi3);

#############################################################################
# 3d.  Derived isomorphisms by composition
#
#      phi1^{-1} ; phi3  :  G3944 -> G10687
#      phi2^{-1} ; phi3  :  G3945 -> G10687
#############################################################################

Print("\n--- Compositions ---\n");

phi_3944_10687 := CompositionMapping(phi3, InverseGeneralMapping(phi1));
CheckIso("phi1^-1 ; phi3 : G3944 -> G10687", phi_3944_10687);

phi_3945_10687 := CompositionMapping(phi3, InverseGeneralMapping(phi2));
CheckIso("phi2^-1 ; phi3 : G3945 -> G10687", phi_3945_10687);

#############################################################################
# 4.  Summary
#############################################################################

Print("\n========================================\n");
Print("Passed: ", passed, " / 5\n");
Print("Errors: ", errors, "\n\n");

if errors = 0 then
    Print("CONCLUSION: All 4 groups are pairwise isomorphic.\n");
    Print("The difficult bucket [ 2592, 162, 42, 3, [ 2, 2, 2, 2 ] ]\n");
    Print("collapses to 1 isomorphism class representative.\n");
    Print("\nRESULT: PASS\n");
else
    Print("RESULT: FAIL\n");
fi;
Print("========================================\n");

#############################################################################
#
#  NOTE: GAP's IsomorphismGroups() cannot handle these groups — it exhausts
#  memory on order-2592 solvable groups with identical invariants.  The proof
#  above instead supplies explicit generator images and asks GAP to verify
#  that each map is a bijective homomorphism, which GAP can do quickly.
#
#  The 3 explicit maps  phi1, phi2, phi3  together with transitivity of
#  isomorphism establish all 6 pairwise isomorphisms:
#
#      G3943 ~ G3944    (phi1)
#      G3943 ~ G3945    (phi2)
#      G3943 ~ G10687   (phi3)
#      G3944 ~ G3945    (phi1^-1 ; phi2)
#      G3944 ~ G10687   (phi1^-1 ; phi3)   — verified above
#      G3945 ~ G10687   (phi2^-1 ; phi3)   — verified above
#
#############################################################################

QuitGap(errors);
