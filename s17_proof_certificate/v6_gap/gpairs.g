# v6 Phase 4: every G-pair is separated twice, independently.
#  (a) NS: each G-type's stored `ns` is recomputed from its class group: the sorted list of
#      [IdGroup(N), IdGroup(G/N)] over the normal subgroups N of order `nsord`.  An isomorphism maps
#      the normal subgroups of a given order onto each other, so this is an isomorphism invariant,
#      and the two stored lists of a pair differ (checked by the Python side).
#  (b) PAIR: the complete coset-action search must prove non-isomorphism.
# Expects GPAIRS := [[t1, t2, i1, i2], ...], GNS := [[t, i, nsord, ns], ...],
# CLASS (generators by class index), OUT.
BreakOnError := false;;
SOLV_COSET_MAX_SUBGROUPS := 20000;;  SOLV_COSET_MAX_CHECKS := 10^6;;
_NsProfile := function(G, ord)
  return SortedList(List(Filtered(NormalSubgroups(G), N -> Size(N) = ord),
                         N -> [ IdGroup(N), IdGroup(G / N) ]));
end;;
_Main := function()
  local x, p, r, G1, G2;
  for x in GNS do
    r := CALL_WITH_CATCH(_NsProfile, [Group(CLASS[x[2]]), x[3]]);
    if r[1] <> true then AppendTo(OUT, "NS\t", x[1], "\terror\n");
    else AppendTo(OUT, "NS\t", x[1], "\t", r[2] = x[4], "\n"); fi;
  od;
  for p in GPAIRS do
    G1 := Group(CLASS[p[3]]);  G2 := Group(CLASS[p[4]]);
    r := CALL_WITH_CATCH(_SOLV_CosetIso, [p[4], G2, p[3], G1, infinity, infinity]);
    if r[1] <> true then AppendTo(OUT, "PAIR\t", p[1], "\t", p[2], "\terror\n");
    else AppendTo(OUT, "PAIR\t", p[1], "\t", p[2], "\t", r[2].status, "\t", r[2].detail, "\n"); fi;
  od;
  AppendTo(OUT, "ALLDONE\n");
end;;
_Main();
QUIT;
