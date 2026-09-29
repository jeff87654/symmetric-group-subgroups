##  Companion to gpair_invariants.g: the v6 G-pair (54779, 54780) = classes 695154 / 695156, order 8000.
gens1 := [ (1,8,3,6)(2,7)(4,9,10,5), (3,7,9,5)(12,13,15,14), (4,8,10,6)(12,13,15,14),
           (4,10)(6,8)(12,15)(13,14), (11,12,13,14,15), (16,17) ];;
gens2 := [ (1,8,3,6)(2,7)(4,9,10,5), (3,7,9,5)(4,10)(6,8)(12,13,15,14), (4,6,10,8)(12,13,15,14),
           (4,10)(6,8)(12,15)(13,14), (11,12,13,14,15), (16,17) ];;
for gens in [ gens1, gens2 ] do
  g := Group(gens);
  Print(Size(g), "  normal subgroups of order 2000: ",
        Collected(List(Filtered(NormalSubgroups(g), N -> Size(N) = 2000), N -> [ IdGroup(N), IdGroup(g / N) ])), "\n");
od;
QUIT;
