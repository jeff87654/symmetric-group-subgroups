##############################################################################
##  coset_engine.g -- self-contained copy of the coset-action isomorphism engine
##  (s18_dedupe/workers/worker_solvable.g section 8b, 2026-09-27) for the S17 certificate audit.
##  _SOLV_CosetIso(a, Ga, b, Gb, catDeadline, deadline) -> rec(status := iso|noniso|unknown, ...)
##  iso comes with gens/images validated by GroupHomomorphismByImages; a complete search that
##  finds no match proves non-isomorphism (see the THEOREM in the section header below).
##############################################################################

# Coset-action engine (section 8b).  SOLV_COSET_MAX_CHECKS bounds the number of
# conjugacy tests one pair may spend; hitting it (or the pair budget) makes the
# engine answer "unknown" and the cascade falls through to RPF / GQuotients.
if not IsBound(SOLV_COSET) then SOLV_COSET := true; fi;
if not IsBound(SOLV_COSET_MAX_CHECKS) then SOLV_COSET_MAX_CHECKS := 20000; fi;
# Catalogues are per rep and can hold hundreds of subgroups: keep only a few.
if not IsBound(SOLV_COSET_CACHE_LIMIT) then SOLV_COSET_CACHE_LIMIT := 40; fi;
# A catalogue larger than this is abandoned (the biggest real solv rep in the
# bench had ~900 classes; 2-groups with many index-2 subgroups explode).
if not IsBound(SOLV_COSET_MAX_SUBGROUPS) then SOLV_COSET_MAX_SUBGROUPS := 3000; fi;

_SOLV_CosetCache := rec();; _SOLV_CosetN := 0;;

_SOLV_Key := function(idx)
  return Concatenation("i", String(idx));
end;;

# CLAUDE.md #10: Size(Group(images)) = Size(G) is necessary but NOT sufficient.
_SOLV_Validate := function(Gdup, Grep, gens, images)
  local r;
  r := CALL_WITH_CATCH(function()
    local phi;
    phi := GroupHomomorphismByImages(Gdup, Grep, gens, images);
    if phi = fail then return false; fi;
    return Size(Image(phi)) = Size(Gdup);
  end, []);
  return r[1] = true and Length(r) >= 2 and r[2] = true;
end;;

# ---------------------------------------------------------------------------
# 8b. Coset-action engine ("cosetAction", 2026-09-27)
#
#   THEOREM.  Let D, R be finite permutation groups with |D| = |R|, and let
#   O_1..O_k be the orbits of D on its moved points.  Then D ~= R iff there are
#   subgroups H_1..H_k <= R with [R:H_j] = |O_j| such that R acting on the
#   disjoint union of the coset spaces R/H_j (block j laid on the points of
#   O_j) is conjugate to D inside Sym(O_1) x ... x Sym(O_k).
#     (<=)  that action has image of order |D| = |R|, so it is faithful.
#     (=>)  for an isomorphism phi take H_j = phi(Stab_D(p_j)) with p_j in O_j.
#   Replacing H_j by an R-conjugate only relabels block j, so H_j ranges over
#   LowIndexSubgroups(R, max |O_j|) (class representatives).  Block j has to
#   realise D's action on O_j, so only classes whose coset action has the same
#   kernel order and TransitiveIdentification are candidates for O_j.
#
#   The search assigns orbits one at a time and prunes with the necessary
#   condition that R acting on the blocks chosen so far is conjugate, inside
#   the product of the Sym(O_j), to D restricted to those orbits.  A search
#   that runs to completion without a match PROVES D !~= R; one that hits
#   SOLV_COSET_MAX_CHECKS or its time limit answers "unknown".
#
#   Proof: rho(R)^sigma = D gives x -> rho^-1(x^(sigma^-1)), validated with
#   GroupHomomorphismByImages (CLAUDE.md #10) like every other engine.  The
#   catalogue depends only on R, so it is cached per rep index; the coset
#   action of each class is computed lazily, only when some dup needs a class
#   of that index (that per-class work, not LowIndexSubgroups, dominated the
#   catalogue cost in the bench: s18_dedupe/bench/solv_engines/).
# ---------------------------------------------------------------------------

# LowIndexSubgroups(G, n), made interruptible: the library method "finite
# groups, using iterated maximals" (lib/grplatt.gi, GAP 4.15.1) step for step,
# with the deadline checked between its steps.  Returns fail once Runtime()
# passes the deadline or more than SOLV_COSET_MAX_SUBGROUPS subgroups turn up.
# SubgroupsOrbitsAndNormalizers runs on chunks of 500: one call on 2,427
# subgroups of a 2-group with 63 index-2 subgroups took 102 s uninterrupted,
# while a typical solv layer fits in one chunk and costs exactly what the
# library method costs.  Reps from DIFFERENT chunks may still be conjugate, so
# they are compared (after a cheap order + orbit-profile key); reps from the
# same chunk are not -- comparing a whole layer pairwise made real solv reps
# 4x slower in testing.  (Replacing SubgroupsOrbitsAndNormalizers entirely by
# pairwise RepresentativeAction was >20x slower in the bench.)
_SOLV_LowIndex := function(G, n, deadline)
  local key, m, all, m2, x, keep, keepChunk, keepKey, reps, repChunk, i, c, j, t, k, ok;
  key := H -> [Size(H), Collected(List(Orbits(H, MovedPoints(G)), Length))];
  m := [G];
  all := [G];
  while Length(m) > 0 do
    m2 := [];
    for x in m do
      if Runtime() > deadline then return fail; fi;
      Append(m2, MaximalSubgroupClassReps(x));
    od;
    m2 := Unique(Filtered(m2, x -> Index(G, x) <= n));
    if Length(all) + Length(m2) > SOLV_COSET_MAX_SUBGROUPS then return fail; fi;
    reps := [];  repChunk := [];
    i := 1;  c := 0;
    while i <= Length(m2) do
      if Runtime() > deadline then return fail; fi;
      c := c + 1;
      for x in SubgroupsOrbitsAndNormalizers(G, m2{[i .. Minimum(i + 499, Length(m2))]}, false) do
        Add(reps, x.representative);
        Add(repChunk, c);
      od;
      i := i + 500;
    od;
    keep := [];  keepChunk := [];  keepKey := [];
    for j in [1 .. Length(reps)] do
      if Runtime() > deadline then return fail; fi;
      x := reps[j];
      ok := ForAll(all, y -> RepresentativeAction(G, x, y) = fail);
      if ok and c > 1 then
        k := key(x);
        for t in [1 .. Length(keep)] do
          if keepChunk[t] <> repChunk[j] and keepKey[t] = k
             and RepresentativeAction(G, x, keep[t]) <> fail then
            ok := false;
            break;
          fi;
        od;
      else
        k := fail;
      fi;
      if ok then
        Add(keep, x);  Add(keepChunk, repChunk[j]);  Add(keepKey, k);
      fi;
    od;
    Append(all, keep);
    m := Filtered(keep, x -> Index(G, x) <= n / 2);
  od;
  return all;
end;;

# Catalogue of R for orbits up to length n, or fail when it cannot be built
# before the deadline.  A failure is remembered, so the rep's other dups go
# straight to the old engines with their whole budget.
_SOLV_CosetCatalogue := function(rep, R, n, deadline)
  local ck, subs, cat;
  ck := _SOLV_Key(rep);
  if IsBound(_SOLV_CosetCache.(ck)) then
    cat := _SOLV_CosetCache.(ck);
    if cat.failed and n >= cat.n then
      return fail;
    fi;
    if not cat.failed and cat.n >= n then
      return cat;
    fi;
  fi;
  subs := _SOLV_LowIndex(R, n, deadline);
  if subs = fail then
    cat := rec(n := n, failed := true);
  else
    cat := rec(n := n, failed := false, R := R, gensR := GeneratorsOfGroup(R),
               entries := List(Filtered(subs, H -> Index(R, H) >= 2),
                               H -> rec(H := H, idx := Index(R, H))));
  fi;
  if _SOLV_CosetN > SOLV_COSET_CACHE_LIMIT then
    _SOLV_CosetCache := rec();
    _SOLV_CosetN := 0;
  fi;
  if not IsBound(_SOLV_CosetCache.(ck)) then
    _SOLV_CosetN := _SOLV_CosetN + 1;
  fi;
  _SOLV_CosetCache.(ck) := cat;
  if cat.failed then
    return fail;
  fi;
  return cat;
end;;

# TransitiveIdentification of a transitive group of degree len, or fail when
# the TransGrp library cannot identify that degree (32 needs an extra download,
# 48 has no identification).  S18 orbits never exceed 18; the guard is for the
# static test groups and for any future n.
_SOLV_Tid := function(img, len)
  if len > 30 then
    return fail;
  fi;
  return TransitiveIdentification(img);
end;;

# Does catalogue entry e realise the orbit type o = rec(len, kerSize, tid)?
# The coset action is built on first use; TransitiveIdentification only after
# the cheap kernel-order test has passed.  tid = fail matches any class of the
# right index and kernel order (the search then checks that orbit explicitly).
_SOLV_CosetMatches := function(cat, e, o)
  local ent, hom;
  ent := cat.entries[e];
  if ent.idx <> o.len then
    return false;
  fi;
  if not IsBound(ent.imgs) then
    hom := FactorCosetAction(cat.R, ent.H);
    ent.img := Image(hom);
    ent.kerSize := Size(cat.R) / Size(ent.img);
    ent.imgs := List(cat.gensR, g -> Image(hom, g));
  fi;
  if ent.kerSize <> o.kerSize then
    return false;
  fi;
  if o.tid = fail then
    return true;
  fi;
  if not IsBound(ent.tid) then
    ent.tid := _SOLV_Tid(ent.img, ent.idx);
  fi;
  return ent.tid = o.tid;
end;;

# Orbits of D with the type of D's action on each ([1..len] <-> O[1..len]).
_SOLV_CosetOrbits := function(D)
  local out, O, img;
  out := [];
  for O in Orbits(D, MovedPoints(D)) do
    O := Set(O);
    img := Image(ActionHomomorphism(D, O, OnPoints, "surjective"));
    Add(out, rec(O := O, len := Length(O), kerSize := Size(D) / Size(img),
                 tid := _SOLV_Tid(img, Length(O))));
  od;
  return out;
end;;

# Depth-first search over one catalogue class per orbit (orbits in the order
# given).  Returns rec(found, capped, checks); found = rec(rho, rhoGens, sigma).
_SOLV_CosetSearch := function(D, cat, orbs, cands, deadline)
  local k, gensD, N, lists, prefixD, prefixSize, prefixW, U, s, checks,
        capped, found, Descend;

  k := Length(orbs);
  gensD := GeneratorsOfGroup(D);
  N := LargestMovedPoint(D);
  lists := List(cat.gensR, g -> [1 .. N]);     # point images, one list per generator of R

  # D restricted to the first s orbits, and the product of their Sym(O_j).
  prefixD := [];  prefixSize := [];  prefixW := [];  U := [];
  for s in [1 .. k] do
    U := Union(U, orbs[s].O);
    prefixD[s] := Group(List(gensD, g -> RestrictedPerm(g, U)), ());
    prefixW[s] := Group(Concatenation(List(orbs{[1 .. s]},
                         o -> GeneratorsOfGroup(SymmetricGroup(o.O)))), ());
  od;

  checks := 0;  capped := false;  found := fail;

  Descend := function(s)
    local e, ent, gi, i, t, rhoGens, rho, sigma, O;
    O := orbs[s].O;
    for e in cands[s] do
      if Runtime() > deadline then
        capped := true;
        return;
      fi;
      ent := cat.entries[e];
      for gi in [1 .. Length(lists)] do
        for i in [1 .. orbs[s].len] do
          lists[gi][O[i]] := O[i ^ ent.imgs[gi]];
        od;
        for t in [s + 1 .. k] do             # forget blocks left over from a deeper branch
          for i in orbs[t].O do lists[gi][i] := i; od;
        od;
      od;
      if s = 1 and k > 1 and orbs[1].tid <> fail then
        # Equal TransitiveIdentification already makes block 1 conjugate to D on O_1.
        Descend(2);
      else
        rhoGens := List(lists, PermList);
        rho := Group(rhoGens, ());
        if not IsBound(prefixSize[s]) then prefixSize[s] := Size(prefixD[s]); fi;
        if Size(rho) = prefixSize[s] then
          checks := checks + 1;
          if checks > SOLV_COSET_MAX_CHECKS then
            capped := true;
            return;
          fi;
          sigma := RepresentativeAction(prefixW[s], rho, prefixD[s]);
          if sigma <> fail then
            if s = k then
              found := rec(rho := rho, rhoGens := rhoGens, sigma := sigma);
              return;
            fi;
            Descend(s + 1);
          fi;
        fi;
      fi;
      if found <> fail or capped then
        return;
      fi;
    od;
  end;

  Descend(1);
  return rec(found := found, capped := capped, checks := checks);
end;;

# Returns rec(status := iso|noniso|unknown, method, detail, gens, images, va, vb).
_SOLV_CosetIso := function(dup, Gdup, rep, Grep, catDeadline, deadline)
  local orbs, cat, cands, j, e, keys, order, res, tau, gens, images, o;

  orbs := _SOLV_CosetOrbits(Gdup);
  cat := _SOLV_CosetCatalogue(rep, Grep, Maximum(List(orbs, o -> o.len)), catDeadline);
  if cat = fail then
    return rec(status := "unknown", method := "cosetAction",
               detail := "catalogue not built within the time limit");
  fi;

  cands := [];
  for j in [1 .. Length(orbs)] do
    o := orbs[j];
    cands[j] := [];
    for e in [1 .. Length(cat.entries)] do
      if Runtime() > deadline then
        return rec(status := "unknown", method := "cosetAction",
                   detail := "time limit while matching orbit types");
      fi;
      if _SOLV_CosetMatches(cat, e, o) then
        Add(cands[j], e);
      fi;
    od;
    if Length(cands[j]) = 0 then
      return rec(status := "noniso", method := "cosetAction",
                 detail := Concatenation("no class realises orbit type ",
                                         String([o.len, o.tid, o.kerSize])),
                 va := "", vb := "");
    fi;
  od;

  # Most constrained orbits first (fewest candidate classes, then longest).
  keys := List([1 .. Length(orbs)], j -> [Length(cands[j]), -orbs[j].len, j]);
  Sort(keys);
  order := List(keys, x -> x[3]);

  res := _SOLV_CosetSearch(Gdup, cat, orbs{order}, cands{order}, deadline);
  if res.found = fail then
    if res.capped then
      return rec(status := "unknown", method := "cosetAction",
                 detail := Concatenation("search capped after ", String(res.checks),
                                         " checks"));
    fi;
    return rec(status := "noniso", method := "cosetAction",
               detail := Concatenation("complete search, ", String(res.checks), " checks"),
               va := "", vb := "");
  fi;

  tau := GroupHomomorphismByImagesNC(cat.R, res.found.rho, cat.gensR, res.found.rhoGens);
  gens := GeneratorsOfGroup(Gdup);
  images := List(gens, x -> PreImagesRepresentative(tau, x ^ (res.found.sigma ^ -1)));
  if not _SOLV_Validate(Gdup, Grep, gens, images) then
    return rec(status := "error", method := "cosetAction",
               detail := "coset map is not a homomorphism");
  fi;
  return rec(status := "iso", method := "cosetAction",
             detail := Concatenation(String(res.checks), " checks"),
             gens := gens, images := images);
end;;

