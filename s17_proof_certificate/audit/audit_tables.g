##############################################################################
##  audit_tables.g -- step 2 of the S17 certificate audit (2026-09-27)
##
##  For each job: build the representative's group, and record
##    * order, IdGroup (only when the SmallGroups library identifies that order),
##    * the FULL character table: class representatives (as permutations), class
##      sizes, element orders, p-power maps for every prime p dividing |G|, and
##      all irreducible character values (GAP cyclotomic literals),
##    * sigKey and element-order histogram recomputed from scratch, so the audit
##      can cross-check the certificate's stored values.
##  Columns of Irr / power maps / sizes / orders all follow the order of `reps`.
##  |Aut| is deliberately NOT computed (not used as evidence in this audit).
##
##  Expects: AUDIT_GENS (types.g), JOBS := [ [job, t, i, selftest], ... ],
##           OUTFILE, LOGFILE, and optionally SELFTEST_SEED.
##  One record per line, written with print formatting off (no line wrapping);
##  the file is closed after every record, so a killed worker loses nothing.
##############################################################################

BreakOnError := false;;

_Line := function(file, args...)
  local out;
  out := OutputTextFile(file, true);
  SetPrintFormattingStatus(out, false);
  CallFuncList(PrintTo, Concatenation([out], args));
  PrintTo(out, "\n");
  CloseStream(out);
end;;

_Hist := function(cls)
  local c, pairs, o, p;
  pairs := [];
  for c in cls do
    o := Order(Representative(c));
    p := PositionProperty(pairs, x -> x[1] = o);
    if p = fail then Add(pairs, [o, Size(c)]); else pairs[p][2] := pairs[p][2] + Size(c); fi;
  od;
  Sort(pairs);
  return pairs;
end;;

_OneJob := function(job)
  local jobId, t, i, selftest, gens, G, sigma, t0, o, id, cls, ct, irr, primes, pm, reps,
        ords, sizes, dsub, dlen, ai, sk;
  jobId := job[1];  t := job[2];  i := job[3];  selftest := job[4];
  gens := AUDIT_GENS[i];
  if selftest then
    # Same group, relabelled: conjugate by a pseudo-random permutation of 17 points,
    # reverse the generators and append a redundant product.
    sigma := Random(SymmetricGroup(17));
    gens := List(Reversed(gens), x -> x ^ sigma);
    if Length(gens) >= 2 then Add(gens, gens[1] * gens[2]); fi;
  fi;
  _Line(LOGFILE, "BEGIN ", jobId);
  t0 := Runtime();
  G := Group(gens);
  o := Size(G);
  id := fail;
  if IdGroupsAvailable(o) then id := IdGroup(G); fi;
  ct := CharacterTable(G);
  cls := ConjugacyClasses(ct);
  irr := Irr(ct);
  primes := PrimeDivisors(o);
  pm := List(primes, p -> [p, PowerMap(ct, p)]);
  reps := List(cls, Representative);
  ords := OrdersClassRepresentatives(ct);
  sizes := SizesConjugacyClasses(ct);
  dsub := Size(DerivedSubgroup(G));
  if IsSolvableGroup(G) then dlen := DerivedLength(G); else dlen := -1; fi;
  ai := ShallowCopy(AbelianInvariants(G));  Sort(ai);
  sk := [o, dsub, Length(cls), dlen, ai];
  _Line(OUTFILE, "CT[", jobId, "] := rec(job:=", jobId, ",t:=", t, ",i:=", i,
        ",selftest:=", selftest, ",order:=", o, ",idgroup:=", id, ",sk:=", sk,
        ",hist:=", _Hist(cls), ",reps:=", reps, ",sizes:=", sizes, ",orders:=", ords,
        ",powermaps:=", pm, ",irr:=", List(irr, ValuesOfClassFunction),
        ",ms:=", Runtime() - t0, ");");
  _Line(LOGFILE, "DONE ", jobId, " ", Runtime() - t0);
end;;

_Main := function()
  local job;
  if IsBound(SELFTEST_SEED) then
    Reset(GlobalMersenneTwister, SELFTEST_SEED);
    Reset(GlobalRandomSource, SELFTEST_SEED);
  fi;
  for job in JOBS do
    if CALL_WITH_CATCH(_OneJob, [job])[1] <> true then
      _Line(LOGFILE, "ERROR ", job[1]);
    fi;
  od;
  _Line(LOGFILE, "ALLDONE");
end;;

_Main();
QUIT;
