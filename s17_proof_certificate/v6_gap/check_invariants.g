# v6 Phase 3: recompute order, sigKey, histogram (and IdGroup for B-types) of each type representative.
# Expects CHUNK (defining CLASS and TYPES := [[t, i, wantSK, wantH, wantId, order], ...];
# false = field not recorded for that type) and OUT.
BreakOnError := false;;
Read(CHUNK);
_SK := function(G)
  local D, dl, ai;
  D := DerivedSubgroup(G);
  if IsSolvableGroup(G) then dl := DerivedLength(G); else dl := -1; fi;
  ai := ShallowCopy(AbelianInvariants(G));  Sort(ai);
  return [Size(G), Size(D), NrConjugacyClasses(G), dl, ai];
end;;
_H := function(G)
  local pairs, c, o, p;
  pairs := [];
  for c in ConjugacyClasses(G) do
    o := Order(Representative(c));
    p := PositionProperty(pairs, x -> x[1] = o);
    if p = fail then Add(pairs, [o, Size(c)]); else pairs[p][2] := pairs[p][2] + Size(c); fi;
  od;
  Sort(pairs);
  return pairs;
end;;
_Check := function(e)
  local G, why;
  G := Group(CLASS[e[2]]);
  why := [];
  if Size(G) <> e[6] then Add(why, "order"); fi;
  if e[3] <> false and _SK(G) <> e[3] then Add(why, "sigKey"); fi;
  if e[4] <> false and _H(G) <> e[4] then Add(why, "histogram"); fi;
  if e[5] <> false then
    if not IdGroupsAvailable(Size(G)) then Add(why, "idgroup_unavailable");
    elif IdGroup(G) <> e[5] then Add(why, "idgroup"); fi;
  fi;
  return why;
end;;
_Main := function()
  local e, r, ok, bad;
  ok := 0;  bad := 0;
  for e in TYPES do
    r := CALL_WITH_CATCH(_Check, [e]);
    if r[1] <> true then r := [true, ["gap_error"]]; fi;
    if Length(r[2]) = 0 then ok := ok + 1;
    else bad := bad + 1; AppendTo(OUT, "FAIL\t", e[1], "\t", e[2], "\t", r[2], "\n"); fi;
  od;
  AppendTo(OUT, "SUMMARY\tok=", ok, "\tfail=", bad, "\n");
end;;
_Main();
QUIT;
