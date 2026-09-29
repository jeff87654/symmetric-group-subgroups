##############################################################################
##  gpair_ns.g -- explicit invariant for the certificate's G-pairs (2026-09-28)
##  For each G-type representative, the sorted list of [IdGroup(N), IdGroup(G/N)] over all normal
##  subgroups N of order NSORD.  An isomorphism maps the normal subgroups of a given order onto each
##  other, so a difference proves non-isomorphism.  NSORD = 2000 is where the pair's profiles differ
##  (gpair_invariants_out.txt: the index-2 subgroups of the order-4000 groups); for the order-8000
##  pair (the same groups x C2) the order-2000 normal subgroups show the same difference.
##  Writes gpair_ns.txt:  class index <TAB> NSORD <TAB> list.
##############################################################################
Read("/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s17_proof_certificate/audit/types.g");
NSORD := 2000;;
GTYPES := [ 77238, 77239, 695154, 695156 ];;
OUTF := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s17_proof_certificate/audit/gpair_ns.txt";;

NsProfile := function(G, ord)
  return SortedList(List(Filtered(NormalSubgroups(G), N -> Size(N) = ord),
                         N -> [ IdGroup(N), IdGroup(G / N) ]));
end;;

OUTS := OutputTextFile(OUTF, false);;
SetPrintFormattingStatus(OUTS, false);
for i in GTYPES do
  PrintTo(OUTS, i, "\t", NSORD, "\t", NsProfile(Group(AUDIT_GENS[i]), NSORD), "\n");
od;
CloseStream(OUTS);
Print("done\n");
QUIT;
