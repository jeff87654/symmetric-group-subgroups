##############################################################################
##  gpair_invariants.g -- look for a concrete invariant separating the v6 G-pair
##  (43999, 44000) = classes 77238 / 77239, order 4000.  The other G-pair (54779, 54780)
##  = classes 695154 / 695156 is the same two groups x C2 (extra generator (16,17)).
##  Prints each invariant for both groups and whether they agree.
##############################################################################
gens1 := [ (1,8,3,6)(2,7)(4,9,10,5), (3,7,9,5)(12,13,15,14), (4,8,10,6)(12,13,15,14),
           (4,10)(6,8)(12,15)(13,14), (11,12,13,14,15) ];;
gens2 := [ (1,8,3,6)(2,7)(4,9,10,5), (3,7,9,5)(4,10)(6,8)(12,13,15,14), (4,6,10,8)(12,13,15,14),
           (4,10)(6,8)(12,15)(13,14), (11,12,13,14,15) ];;
GG := [ Group(gens1), Group(gens2) ];;

Id := function(H)
  if IdGroupsAvailable(Size(H)) then return IdGroup(H); fi;
  return [ Size(H), fail ];
end;;

Report := function(name, f)
  local t, v, c1, c2;
  t := Runtime();
  v := List(GG, f);
  Print("\n== ", name, ": ", v[1] = v[2], "  (", Runtime() - t, " ms)\n");
  if IsList(v[1]) and Length(v[1]) > 12 and IsList(v[2]) then
    c1 := Filtered(v[1], x -> not x in v[2]);
    c2 := Filtered(v[2], x -> not x in v[1]);
    Print("   G1 only: ", c1, "\n   G2 only: ", c2, "\n");
  else
    Print("   G1: ", v[1], "\n   G2: ", v[2], "\n");
  fi;
end;;

Report("sizes", Size);
Report("orbits [len, TransitiveIdentification, image size]",
       g -> List(Orbits(g, MovedPoints(g)), o -> [ Length(o), TransitiveIdentification(Action(g, o)), Size(Action(g, o)) ]));
Report("center / derived / Frattini / Fitting",
       g -> [ Id(Center(g)), Id(DerivedSubgroup(g)), Id(FrattiniSubgroup(g)), Id(FittingSubgroup(g)) ]);
Report("derived series", g -> List(DerivedSeriesOfGroup(g), Id));
Report("Sylow 2, Sylow 5, their normalizers",
       g -> [ Id(SylowSubgroup(g, 2)), Id(SylowSubgroup(g, 5)),
              Id(Normalizer(g, SylowSubgroup(g, 2))), Id(Normalizer(g, SylowSubgroup(g, 5))) ]);
Report("maximal subgroup classes [IdGroup, class length]",
       g -> Collected(List(MaximalSubgroupClassReps(g), M -> [ Id(M), Index(g, Normalizer(g, M)) ])));
Report("normal subgroups [IdGroup(N), IdGroup(G/N)]",
       g -> Collected(List(NormalSubgroups(g), N -> [ Id(N), Id(g / N) ])));
Report("character tables permutation-equivalent (incl. power maps)",
       g -> TransformingPermutationsCharacterTables(CharacterTable(GG[1]), CharacterTable(g)) <> fail);

CCS := [];;
Report("number of conjugacy classes of subgroups", function(g)
  local c;
  c := ConjugacyClassesSubgroups(g);
  Add(CCS, c);
  return Length(c);
end);
Report("subgroup classes [IdGroup, class length]",
       g -> Collected(List(CCS[Position(GG, g)], c -> [ Id(Representative(c)), Size(c) ])));
Report("subgroup classes [index, core order, TransitiveIdentification of coset action]",
       g -> Collected(List(CCS[Position(GG, g)], function(c)
              local H, hom;
              H := Representative(c);
              if Index(g, H) = 1 or Index(g, H) > 30 then return [ Index(g, H), Size(Core(g, H)), fail ]; fi;
              hom := FactorCosetAction(g, H);
              return [ Index(g, H), Size(Core(g, H)), TransitiveIdentification(Image(hom)) ];
            end)));
Print("\nALLDONE\n");
QUIT;
