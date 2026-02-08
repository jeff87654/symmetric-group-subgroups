#############################################################################
#
#  Isomorphism proof for the hard bucket (order 10368)
#  sigKey = [ 10368, 1296, 54, 4, [ 2, 2, 2 ] ]
#
#  These 8 groups do NOT decompose as direct products, so factor-level
#  optimization cannot be used.  GAP's IsomorphismGroups() takes ~5 hours
#  on the raw permutation groups (25-53 minutes per pair).
#
#  Instead we use PcGroup conversion + GQuotients:
#    1. IsomorphismPcGroup converts each solvable perm group to a PcGroup
#    2. Groups 1824-1830 all produce the same CodePcGroup
#    3. Group 8999 has a different PC presentation, but GQuotients finds
#       a surjection (= bijection, same order) to pc_1824
#    4. Explicit generator images supplied below for GAP verification
#
#  Result:  All 8 groups are isomorphic.
#           The bucket collapses to 1 representative.
#
#  Verified: 2026-02-05
#
#############################################################################
#
#  Source records (from s14_large_invariants_clean.g):
#
#    Index  1824  (originalIndex 12545)
#    Index  1825  (originalIndex 12546)
#    Index  1826  (originalIndex 12547)
#    Index  1827  (originalIndex 12548)
#    Index  1828  (originalIndex 12549)
#    Index  1829  (originalIndex 12550)
#    Index  1830  (originalIndex 12551)
#    Index  8999  (originalIndex 56802)
#
#  Shared invariants:
#    order         = 10368 = 2^7 * 3^4
#    derivedSize   = 1296
#    numClasses    = 54
#    derivedLength = 4
#    abelianInvs   = [ 2, 2, 2 ]
#    histogram     = [ [1,1], [2,555], [3,80], [4,2628], [6,2928],
#                      [8,1296], [12,2880] ]
#    maxOrder      = 12
#    numOrders     = 7
#    isDirectProduct = false
#    center        = trivial
#    Fitting subgroup = (Z/3)^4, order 81
#    Sylow 2-subgroup order = 128, derived length 3
#    Sylow 3-subgroup = elementary abelian, order 81
#
#############################################################################

Print("=== Hard Bucket Isomorphism Proof (Order 10368) ===\n");
Print("sigKey = [ 10368, 1296, 54, 4, [ 2, 2, 2 ] ]\n\n");

#############################################################################
# 1.  Define the eight groups
#############################################################################

G1824 := Group([
  (1,2)(3,5)(4,14)(6,8)(7,11)(9,12)(10,13),
  (1,2)(4,9)(5,10)(6,11),
  (3,13)(4,9)(5,10)(6,11)(7,8)(12,14),
  (9,11),
  (7,12)(9,11),
  (4,6)(9,11),
  (4,6)(7,12)(8,14)(9,11),
  (3,14,8)(4,5,6),
  (4,5,6)(7,13,12),
  (7,13,12)(9,10,11),
  (9,10,11)
]);

G1825 := Group([
  (1,2)(3,5)(4,14)(6,8)(7,11)(9,12)(10,13),
  (4,9)(5,10)(6,11),
  (3,13)(4,9)(5,10)(6,11)(7,8)(12,14),
  (1,2)(9,11),
  (7,12)(9,11),
  (4,6)(9,11),
  (4,6)(7,12)(8,14)(9,11),
  (3,14,8)(4,5,6),
  (4,5,6)(7,13,12),
  (7,13,12)(9,10,11),
  (9,10,11)
]);

G1826 := Group([
  (1,2)(3,5)(4,14)(6,8)(7,11)(9,12)(10,13),
  (4,9)(5,10)(6,11),
  (3,13)(4,9)(5,10)(6,11)(7,8)(12,14),
  (9,11),
  (7,12)(9,11),
  (4,6)(9,11),
  (4,6)(7,12)(8,14)(9,11),
  (3,14,8)(4,5,6),
  (4,5,6)(7,13,12),
  (7,13,12)(9,10,11),
  (9,10,11)
]);

G1827 := Group([
  (3,5)(4,14)(6,8)(7,11)(9,12)(10,13),
  (1,2)(4,9)(5,10)(6,11),
  (3,13)(4,9)(5,10)(6,11)(7,8)(12,14),
  (1,2)(9,11),
  (7,12)(9,11),
  (4,6)(9,11),
  (4,6)(7,12)(8,14)(9,11),
  (3,14,8)(4,5,6),
  (4,5,6)(7,13,12),
  (7,13,12)(9,10,11),
  (9,10,11)
]);

G1828 := Group([
  (1,2)(3,5)(4,14)(6,8)(7,11)(9,12)(10,13),
  (1,2)(4,9)(5,10)(6,11),
  (3,13)(4,9)(5,10)(6,11)(7,8)(12,14),
  (1,2)(9,11),
  (7,12)(9,11),
  (4,6)(9,11),
  (4,6)(7,12)(8,14)(9,11),
  (3,14,8)(4,5,6),
  (4,5,6)(7,13,12),
  (7,13,12)(9,10,11),
  (9,10,11)
]);

G1829 := Group([
  (3,5)(4,14)(6,8)(7,11)(9,12)(10,13),
  (4,9)(5,10)(6,11),
  (3,13)(4,9)(5,10)(6,11)(7,8)(12,14),
  (1,2)(9,11),
  (7,12)(9,11),
  (4,6)(9,11),
  (4,6)(7,12)(8,14)(9,11),
  (3,14,8)(4,5,6),
  (4,5,6)(7,13,12),
  (7,13,12)(9,10,11),
  (9,10,11)
]);

G1830 := Group([
  (3,5)(4,14)(6,8)(7,11)(9,12)(10,13),
  (1,2)(4,9)(5,10)(6,11),
  (3,13)(4,9)(5,10)(6,11)(7,8)(12,14),
  (9,11),
  (7,12)(9,11),
  (4,6)(9,11),
  (4,6)(7,12)(8,14)(9,11),
  (3,14,8)(4,5,6),
  (4,5,6)(7,13,12),
  (7,13,12)(9,10,11),
  (9,10,11)
]);

G8999 := Group([
  (7,8,12),
  (2,5,10),
  (2,10)(7,8),
  (2,8,10,7)(5,12),
  (9,14,11),
  (7,8)(9,11),
  (4,6,13),
  (6,13)(7,8),
  (4,14)(6,11)(7,8)(9,13),
  (2,13)(4,5)(6,10)(7,11)(8,9)(12,14),
  (7,8)
]);

# Verify orders
Print("Group orders: ");
Print(Size(G1824), " ", Size(G1825), " ", Size(G1826), " ", Size(G1827), " ");
Print(Size(G1828), " ", Size(G1829), " ", Size(G1830), " ", Size(G8999), "\n");
Assert(0, Size(G1824) = 10368);
Assert(0, Size(G1825) = 10368);
Assert(0, Size(G1826) = 10368);
Assert(0, Size(G1827) = 10368);
Assert(0, Size(G1828) = 10368);
Assert(0, Size(G1829) = 10368);
Assert(0, Size(G1830) = 10368);
Assert(0, Size(G8999) = 10368);

#############################################################################
# 2.  Generator lists (domains of the maps)
#############################################################################

gens1825 := GeneratorsOfGroup(G1825);
gens1826 := GeneratorsOfGroup(G1826);
gens1827 := GeneratorsOfGroup(G1827);
gens1828 := GeneratorsOfGroup(G1828);
gens1829 := GeneratorsOfGroup(G1829);
gens1830 := GeneratorsOfGroup(G1830);
gens8999 := GeneratorsOfGroup(G8999);

errors := 0;
passed := 0;

CheckIso := function(name, phi)
    local ok;
    if phi = fail then
        Print("FAIL ", name, ": GroupHomomorphismByImages returned fail\n");
        errors := errors + 1;
        return;
    fi;
    ok := IsGroupHomomorphism(phi) and IsBijective(phi) and Size(Image(phi)) = 10368;
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
# 3a.  Isomorphism  G1825 --> G1824
#
#  Method: IsomorphismPcGroup + GQuotients (PcGroup route)
#  Groups 1824-1830 share the same CodePcGroup.
#############################################################################

Print("\n--- phi1 : G1825 -> G1824 ---\n");

phi1 := GroupHomomorphismByImages(G1825, G1824, gens1825, [
  (1,2)(3,5)(4,8)(6,14)(7,9)(10,12)(11,13),
  (1,2)(4,11)(5,9)(6,10),
  (3,7)(4,11)(5,9)(6,10)(8,13)(12,14),
  (4,6),
  (4,6)(8,14),
  (4,6)(10,11),
  (4,6)(8,14)(10,11)(12,13),
  (7,12,13)(9,11,10),
  (3,14,8)(9,11,10),
  (3,14,8)(4,6,5),
  (4,6,5)
]);

CheckIso("phi1 : G1825 -> G1824", phi1);

#############################################################################
# 3b.  Isomorphism  G1826 --> G1824
#############################################################################

Print("\n--- phi2 : G1826 -> G1824 ---\n");

phi2 := GroupHomomorphismByImages(G1826, G1824, gens1826, [
  (1,2)(3,9)(4,7)(5,13)(6,12)(8,11)(10,14),
  (1,2)(4,11)(5,10)(6,9),
  (3,12)(4,11)(5,10)(6,9)(7,8)(13,14),
  (10,11),
  (8,14)(10,11),
  (4,5)(10,11),
  (4,5)(7,13)(8,14)(10,11),
  (4,5,6)(7,12,13),
  (3,14,8)(4,5,6),
  (3,14,8)(9,11,10),
  (9,11,10)
]);

CheckIso("phi2 : G1826 -> G1824", phi2);

#############################################################################
# 3c.  Isomorphism  G1827 --> G1824
#############################################################################

Print("\n--- phi3 : G1827 -> G1824 ---\n");

phi3 := GroupHomomorphismByImages(G1827, G1824, gens1827, [
  (1,2)(3,5)(4,8)(6,14)(7,11)(9,12)(10,13),
  (1,2)(3,12)(7,14)(8,13),
  (3,12)(4,10)(5,9)(6,11)(7,14)(8,13),
  (8,14),
  (4,6)(8,14),
  (7,13)(8,14),
  (4,6)(7,13)(8,14)(10,11),
  (7,12,13)(9,11,10),
  (4,5,6)(7,12,13),
  (3,8,14)(4,5,6),
  (3,8,14)
]);

CheckIso("phi3 : G1827 -> G1824", phi3);

#############################################################################
# 3d.  Isomorphism  G1828 --> G1824
#############################################################################

Print("\n--- phi4 : G1828 -> G1824 ---\n");

phi4 := GroupHomomorphismByImages(G1828, G1824, gens1828, [
  (1,2)(3,4)(5,14)(6,8)(7,9)(10,13)(11,12),
  (3,14),
  (3,14)(4,5),
  (1,2)(3,12)(7,14)(8,13),
  (3,12)(4,11)(5,9)(6,10)(7,14)(8,13),
  (3,14)(7,12),
  (3,14)(4,5)(7,12)(9,11),
  (3,14,8)(4,6,5)(7,13,12)(9,11,10),
  (3,14,8)(4,5,6)(7,13,12)(9,11,10),
  (3,8,14)(4,5,6)(7,13,12)(9,11,10),
  (3,8,14)(7,13,12)
]);

CheckIso("phi4 : G1828 -> G1824", phi4);

#############################################################################
# 3e.  Isomorphism  G1829 --> G1824
#############################################################################

Print("\n--- phi5 : G1829 -> G1824 ---\n");

phi5 := GroupHomomorphismByImages(G1829, G1824, gens1829, [
  (1,2)(3,6)(4,14)(5,8)(7,11)(9,12)(10,13),
  (1,2)(3,12)(7,8)(13,14),
  (3,12)(4,10)(5,11)(6,9)(7,8)(13,14),
  (7,13),
  (7,13)(10,11),
  (7,13)(8,14),
  (4,5)(7,13)(8,14)(10,11),
  (3,14,8)(4,6,5),
  (3,14,8)(9,11,10),
  (7,12,13)(9,11,10),
  (7,12,13)
]);

CheckIso("phi5 : G1829 -> G1824", phi5);

#############################################################################
# 3f.  Isomorphism  G1830 --> G1824
#############################################################################

Print("\n--- phi6 : G1830 -> G1824 ---\n");

phi6 := GroupHomomorphismByImages(G1830, G1824, gens1830, [
  (1,2)(3,5)(4,8)(6,14)(7,10)(9,12)(11,13),
  (1,2)(3,13)(7,8)(12,14),
  (3,13)(4,10)(5,11)(6,9)(7,8)(12,14),
  (3,8),
  (3,8)(4,5),
  (3,8)(7,13),
  (3,8)(4,5)(7,13)(10,11),
  (7,12,13)(9,10,11),
  (4,5,6)(7,12,13),
  (3,8,14)(4,5,6),
  (3,8,14)
]);

CheckIso("phi6 : G1830 -> G1824", phi6);

#############################################################################
# 3g.  Isomorphism  G8999 --> G1824
#
#  Group 8999 has a completely different embedding (different points/cycles).
#  PcGroup conversion gives a different presentation, but GQuotients finds
#  a surjection pc_8999 -> pc_1824 (= bijection since |G| = |H|).
#############################################################################

Print("\n--- phi7 : G8999 -> G1824 ---\n");

phi7 := GroupHomomorphismByImages(G8999, G1824, gens8999, [
  (4,5,6)(9,11,10),
  (4,6,5)(9,11,10),
  (4,6)(10,11),
  (1,2)(4,11,6,10)(5,9),
  (3,8,14)(7,13,12),
  (3,13)(4,11)(5,9)(6,10)(7,8)(12,14),
  (3,14,8)(7,13,12),
  (3,13)(4,11)(5,9)(6,10)(7,14)(8,12),
  (1,2)(4,11)(5,9)(6,10)(8,14),
  (1,2)(3,5)(4,14)(6,8)(7,10)(9,13)(11,12),
  (1,2)(4,11)(5,9)(6,10)
]);

CheckIso("phi7 : G8999 -> G1824", phi7);

#############################################################################
# 4.  Summary
#############################################################################

Print("\n========================================\n");
Print("Passed: ", passed, " / 7\n");
Print("Errors: ", errors, "\n\n");

if errors = 0 then
    Print("CONCLUSION: All 8 groups are pairwise isomorphic.\n");
    Print("The hard bucket [ 10368, 1296, 54, 4, [ 2, 2, 2 ] ]\n");
    Print("collapses to 1 isomorphism class representative.\n");
    Print("\nRESULT: PASS\n");
else
    Print("RESULT: FAIL\n");
fi;
Print("========================================\n");

#############################################################################
#
#  NOTE: GAP's IsomorphismGroups() takes 25-53 minutes per pair on these
#  order-10368 permutation groups.  The PcGroup route (IsomorphismPcGroup +
#  GQuotients) resolves them almost instantly because these are solvable
#  groups (derived length 4) with polycyclic presentations.
#
#  The 7 explicit maps phi1..phi7 together with transitivity of isomorphism
#  establish all 28 pairwise isomorphisms among the 8 groups.
#
#  Method used to find the isomorphisms:
#    1. phi_to_pc := IsomorphismPcGroup(g_source)
#    2. pc_source := Range(phi_to_pc)
#    3. pc_target := Range(IsomorphismPcGroup(g_target))
#    4. surjections := GQuotients(pc_source, pc_target)
#    5. Compose: g_source -> pc_source -> pc_target -> g_target
#    For groups 1824-1830, step 4 is trivial (same CodePcGroup).
#    For group 8999, GQuotients finds the surjection.
#
#############################################################################

QuitGap(errors);
