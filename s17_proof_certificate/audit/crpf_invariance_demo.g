# Is the S17 certificate's crpf string an isomorphism invariant?  Same function as
# s17_proof_certificate/work/compute_crpf_gpair.g (_CrpfString), applied to relabelled copies.
Read("/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s17_proof_certificate/audit/s17_gpairs_groups.g");
_CrpfString := function(G)
  local ct, n, irrs, fps, i, j, fp;
  ct := CharacterTable(G);;  n := NrConjugacyClasses(G);;  irrs := Irr(ct);;
  fps := [];;
  for i in [1..n] do
    fp := [List([1..n], j -> PowerMap(ct, j)[i])];;
    for j in [1..Length(irrs)] do Add(fp, irrs[j][i]); od;
    Add(fps, fp);;
  od;
  Sort(fps);;
  return String(fps);
end;;
# Order-independent control: per character, sorted values on each prime power map; then sort.
_Canon := function(G)
  local ct, irrs, primes, pm, fps, chi, fp, k, v;
  ct := CharacterTable(G);; irrs := Irr(ct);; primes := PrimeDivisors(Size(G));;
  pm := List(primes, p -> PowerMap(ct, p));;
  fps := [];;
  for chi in irrs do
    fp := [SortedList(List(chi))];
    for k in [1..Length(primes)] do Add(fp, SortedList(List(pm[k], j -> chi[j]))); od;
    Add(fps, fp);
  od;
  Sort(fps);; return String(fps);
end;;
Reset(GlobalMersenneTwister, 17);;
G := Group(GENS[1375569]);;
sigma := Random(SymmetricGroup(17));;
Gc := Group(List(Reversed(GeneratorsOfGroup(G)), x -> x^sigma));;   # relabelled copy of the SAME group
H := Group(GENS[1375578]);;                                          # proven isomorphic to G
sG := _CrpfString(G);; sGc := _CrpfString(Gc);; sH := _CrpfString(H);;
Print("crpf(G) = crpf(G^sigma, generators reversed): ", sG = sGc, "\n");
Print("crpf(G) = crpf(H)  [H proven isomorphic to G]: ", sG = sH, "\n");
Print("control (order-independent): G vs G^sigma ", _Canon(G) = _Canon(Gc), ",  G vs H ", _Canon(G) = _Canon(H), "\n");
QUIT;
