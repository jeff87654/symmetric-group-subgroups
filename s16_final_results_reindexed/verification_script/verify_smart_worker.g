# verify_smart_worker.g
# Smart conjugacy verification: uses CC histogram (with fixed points)
# to sub-bucket within (type, orbit-type) buckets.
#
# Parameters (set before Read):
#   WORKER_ID   - worker number (1..NUM_WORKERS)
#   NUM_WORKERS - total workers
#   SUB_THRESHOLD - min bucket size to use CC histogram sub-bucketing
#
# Buckets are interleaved: worker k gets buckets k, k+NUM_WORKERS, k+2*NUM_WORKERS, ...
# Since buckets are sorted by size ascending, this naturally balances load.

if not IsBound(basedir) then
    basedir := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/s16_final_results_reindexed/";
fi;;

Print("W", WORKER_ID, ": Loading subgroups...\n");
subs := ReadAsFunction(Concatenation(basedir, "s16_subgroups.g"))();;
Print("W", WORKER_ID, ": Loaded ", Length(subs), " subgroups\n");

Print("W", WORKER_ID, ": Loading buckets...\n");
Read(Concatenation(basedir, "conj_buckets.g"));;
numBuckets := Length(CONJ_BUCKETS);;
Print("W", WORKER_ID, ": Loaded ", numBuckets, " buckets\n");

S16 := SymmetricGroup(16);;

totalChecked := 0;;
totalSkipped := 0;;
conjugateFound := 0;;
bucketsDone := 0;;
t0 := Runtime();;

MakeGroup := function(entry)
  if Length(entry) = 0 then
    return Group(());
  else
    return Group(List(entry, PermList));
  fi;
end;;

# CC histogram: for each conjugacy class, [Order(rep), FixedPoints(rep), ClassSize]
# This is a CONJUGACY invariant (not just isomorphism invariant) because
# fixed points depend on the specific embedding in S16.
CCHistogram := function(G)
  local cc, hist, c, rep;
  cc := ConjugacyClasses(G);
  hist := [];
  for c in cc do
    rep := Representative(c);
    Add(hist, [Order(rep), 16 - NrMovedPoints(rep), Size(c)]);
  od;
  Sort(hist);
  return hist;
end;;

# Build my bucket list (interleaved assignment)
myBuckets := [];;
idx := WORKER_ID;;
while idx <= numBuckets do
  Add(myBuckets, idx);
  idx := idx + NUM_WORKERS;
od;;

myTotalPairs := 0;;
for idx in myBuckets do
  n := Length(CONJ_BUCKETS[idx]);
  myTotalPairs := myTotalPairs + n * (n - 1) / 2;
od;;

Print("W", WORKER_ID, ": Assigned ", Length(myBuckets), " buckets (",
      myTotalPairs, " original pairs)\n");
Print("W", WORKER_ID, ": Sub-bucket threshold: ", SUB_THRESHOLD, "\n\n");

for taskIdx in [1..Length(myBuckets)] do
  bucketIdx := myBuckets[taskIdx];;
  indices := CONJ_BUCKETS[bucketIdx];;
  n := Length(indices);;
  originalPairs := n * (n - 1) / 2;;
  bucketChecked := 0;;
  bucketConjugate := 0;;

  groups := List(indices, i -> MakeGroup(subs[i]));;

  if n > SUB_THRESHOLD then
    # Compute CC histogram for sub-bucketing
    histStrs := List(groups, g -> String(CCHistogram(g)));;

    # Group by histogram string
    combined := List([1..n], k -> [histStrs[k], k]);;
    Sort(combined, function(a, b) return a[1] < b[1]; end);;

    # Pairwise test within each sub-bucket
    subStart := 1;;
    while subStart <= n do
      subEnd := subStart;;
      while subEnd < n and combined[subEnd + 1][1] = combined[subStart][1] do
        subEnd := subEnd + 1;
      od;
      for ii in [subStart..subEnd] do
        for jj in [ii + 1..subEnd] do
          gi := combined[ii][2];
          gj := combined[jj][2];
          if IsConjugate(S16, groups[gi], groups[gj]) then
            Print("CONJUGATE FOUND: indices ", indices[gi], " ~ ", indices[gj],
                  " (bucket ", bucketIdx, ")\n");
            bucketConjugate := bucketConjugate + 1;
          fi;
          bucketChecked := bucketChecked + 1;
        od;
      od;
      subStart := subEnd + 1;
    od;
  else
    # Direct pairwise, no sub-bucketing
    for i in [1..n] do
      for j in [i + 1..n] do
        if IsConjugate(S16, groups[i], groups[j]) then
          Print("CONJUGATE FOUND: indices ", indices[i], " ~ ", indices[j],
                " (bucket ", bucketIdx, ")\n");
          bucketConjugate := bucketConjugate + 1;
        fi;
        bucketChecked := bucketChecked + 1;
      od;
    od;
  fi;

  skipped := originalPairs - bucketChecked;;
  totalChecked := totalChecked + bucketChecked;;
  totalSkipped := totalSkipped + skipped;;
  conjugateFound := conjugateFound + bucketConjugate;;
  bucketsDone := bucketsDone + 1;;

  # Report progress
  doReport := false;;
  if n >= 20 then
    doReport := true;
  elif bucketsDone mod 500 = 0 then
    doReport := true;
  fi;
  if doReport then
    elapsed := Int((Runtime() - t0) / 1000);;
    Print("W", WORKER_ID, " [", bucketsDone, "/", Length(myBuckets),
          "] bkt#", bucketIdx,
          " sz=", n, " chk=", bucketChecked, "/", originalPairs);
    Print(" | tot: ", totalChecked, " chk, ",
          totalSkipped, " skip, ",
          conjugateFound, " conj, ",
          elapsed, "s\n");
  fi;
od;

elapsed := Int((Runtime() - t0) / 1000);;
Print("\n========================================\n");
Print("W", WORKER_ID, " COMPLETE (", elapsed, "s)\n");
Print("  Buckets processed: ", bucketsDone, "\n");
Print("  Pairs checked: ", totalChecked, "\n");
Print("  Pairs skipped (CC histogram): ", totalSkipped, "\n");
Print("  Conjugate pairs found: ", conjugateFound, "\n");
if conjugateFound = 0 then
  Print("  RESULT: ALL NON-CONJUGATE (PASSED)\n");
else
  Print("  RESULT: CONJUGATE PAIRS DETECTED (FAILED)\n");
fi;
Print("========================================\n");

QUIT;
