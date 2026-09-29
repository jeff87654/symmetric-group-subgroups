# B2: does every IdGroup-map entry equal [Size, IdGroup] of the class's group?  Expects CHUNK, OUT.
BreakOnError := false;;
Read(CHUNK);
_Check := function(e)
  local G;
  G := Group(CLASS[e[1]]);
  if Size(G) <> e[2] then return "order_differs"; fi;
  if not IdGroupsAvailable(e[2]) then return "idgroup_unavailable_for_order"; fi;
  if IdGroup(G) <> [e[2], e[3]] then return "idgroup_differs"; fi;
  return "ok";
end;;
_Main := function()
  local e, r, ok, bad;
  ok := 0;  bad := 0;
  for e in IDS do
    r := CALL_WITH_CATCH(_Check, [e]);
    if r[1] <> true then r := [true, "gap_error"]; fi;
    if r[2] = "ok" then ok := ok + 1;
    else bad := bad + 1; AppendTo(OUT, "FAIL\t", e[1], "\t", e[2], "\t", e[3], "\t", r[2], "\n"); fi;
  od;
  AppendTo(OUT, "SUMMARY\tok=", ok, "\tfail=", bad, "\n");
end;;
_Main();
QUIT;
