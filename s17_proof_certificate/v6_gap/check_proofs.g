# B1: does every proof link the RIGHT groups?  Expects CHUNK, OUT.  Writes FAIL lines + one SUMMARY line.
BreakOnError := false;;
Read(CHUNK);
_grp := rec();;
_G := function(i)
  local k;
  k := Concatenation("c", String(i));
  if not IsBound(_grp.(k)) then _grp.(k) := Group(CLASS[i]); fi;
  return _grp.(k);
end;;
_Check := function(p)
  local Gd, Gr, gens, imgs, phi;
  Gd := _G(p[1]);  Gr := _G(p[2]);
  gens := List(p[3], EvalString);  imgs := List(p[4], EvalString);
  if Size(Gd) <> Size(Gr) then return "orders_differ"; fi;
  if not ForAll(gens, g -> g in Gd) then return "gens_not_in_duplicate_group"; fi;
  if Size(Subgroup(Gd, gens)) <> Size(Gd) then return "gens_do_not_generate_duplicate_group"; fi;
  if not ForAll(imgs, x -> x in Gr) then return "images_not_in_representative_group"; fi;
  phi := GroupHomomorphismByImages(Gd, Gr, gens, imgs);
  if phi = fail then return "not_a_homomorphism"; fi;
  if Size(Image(phi)) <> Size(Gr) then return "not_surjective"; fi;
  return "ok";
end;;
_Main := function()
  local p, r, ok, bad, out;
  ok := 0;  bad := 0;
  for p in PROOFS do
    r := CALL_WITH_CATCH(_Check, [p]);
    if r[1] <> true then r := [true, "gap_error"]; fi;
    if r[2] = "ok" then ok := ok + 1;
    else
      bad := bad + 1;
      AppendTo(OUT, "FAIL\t", p[1], "\t", p[2], "\t", p[5], "\t", r[2], "\n");
    fi;
  od;
  AppendTo(OUT, "SUMMARY\tok=", ok, "\tfail=", bad, "\n");
end;;
_Main();
QUIT;
