##############################################################################
##  audit_search.g -- step 4 of the S17 certificate audit (2026-09-27)
##  For each pair of types [a, b, ia, ib] (a < b) that no invariant separated: complete coset-action
##  search, mapping b's representative onto a's.  iso -> validated gens/images (b merges into a);
##  noniso -> the complete search is the proof of distinctness; unknown -> search capped.
##  Expects PAIRS, OUTFILE, LOGFILE, BUDGET_MS; AUDIT_GENS from types.g.
##############################################################################
BreakOnError := false;;
SOLV_COSET_MAX_SUBGROUPS := 20000;;  SOLV_COSET_MAX_CHECKS := 10^6;;

_Line := function(file, args...)
  local out;
  out := OutputTextFile(file, true);
  SetPrintFormattingStatus(out, false);
  CallFuncList(PrintTo, Concatenation([out], args));
  PrintTo(out, "\n");
  CloseStream(out);
end;;

_OnePair := function(p)
  local a, b, Ga, Gb, t0, r, ok, phi;
  a := p[1];  b := p[2];
  _Line(LOGFILE, "BEGIN ", a, " ", b);
  Ga := Group(AUDIT_GENS[p[3]]);  Gb := Group(AUDIT_GENS[p[4]]);
  t0 := Runtime();
  r := _SOLV_CosetIso(p[4], Gb, p[3], Ga, t0 + BUDGET_MS, t0 + BUDGET_MS);
  if r.status = "iso" then
    phi := GroupHomomorphismByImages(Gb, Ga, r.gens, r.images);
    ok := phi <> fail and IsBijective(phi);
    _Line(OUTFILE, "PAIR[", a, ",", b, "] := rec(a:=", a, ",b:=", b, ",status:=\"iso\",valid:=", ok,
          ",ms:=", Runtime() - t0, ",detail:=\"", r.detail, "\",gens:=", r.gens, ",images:=", r.images, ");");
  else
    _Line(OUTFILE, "PAIR[", a, ",", b, "] := rec(a:=", a, ",b:=", b, ",status:=\"", r.status,
          "\",ms:=", Runtime() - t0, ",detail:=\"", r.detail, "\");");
  fi;
  _Line(LOGFILE, "DONE ", a, " ", b, " ", r.status);
end;;

_Main := function()
  local p;
  for p in PAIRS do
    if CALL_WITH_CATCH(_OnePair, [p])[1] <> true then
      _Line(LOGFILE, "ERROR ", p[1], " ", p[2]);
    fi;
  od;
  _Line(LOGFILE, "ALLDONE");
end;;
_Main();
QUIT;
