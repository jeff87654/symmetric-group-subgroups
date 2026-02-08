# Spot-check A174511(14) IdGroup type counts at specific orders
# Loads 75,154 S14 conjugacy class reps and checks IdGroup at selected orders

Print("=== Spot Check: IdGroup type counts at specific orders ===\n\n");

# Define S14_TC in case the cache file needs it
S14_TC := "S14_TC";;

Print("Loading S14 subgroup representatives...\n");

# The file uses 'return [...]' format, so we need to ReadAsFunction
loadFunc := ReadAsFunction("/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/triple_check/conjugacy_cache/s14_subgroups.g");;
genLists := loadFunc();;
Print("Loaded ", Length(genLists), " generator lists.\n");

# Convert generator lists to permutation groups
Print("Converting to groups...\n");
S14_SUBGROUP_REPS := [];;
for i in [1..Length(genLists)] do
    gens := List(genLists[i], PermList);
    if Length(gens) = 0 then
        Add(S14_SUBGROUP_REPS, Group(()));
    else
        Add(S14_SUBGROUP_REPS, Group(gens));
    fi;
    if i mod 10000 = 0 then
        Print("  Converted ", i, " / ", Length(genLists), "\n");
    fi;
od;
Print("Converted ", Length(S14_SUBGROUP_REPS), " groups.\n\n");

# Free memory
Unbind(genLists);
Unbind(loadFunc);

# Orders to spot-check
orders_to_check := [6, 10, 12, 16, 20, 24, 36, 48, 60, 72, 96, 100, 120];;

# First pass: bin groups by order (only the orders we care about)
Print("Binning groups by order...\n");
order_bins := rec();;
for o in orders_to_check do
    order_bins.(String(o)) := [];
od;

for i in [1..Length(S14_SUBGROUP_REPS)] do
    g := S14_SUBGROUP_REPS[i];
    sz := Size(g);
    key := String(sz);
    if IsBound(order_bins.(key)) then
        Add(order_bins.(key), g);
    fi;
    if i mod 10000 = 0 then
        Print("  Binned ", i, " / ", Length(S14_SUBGROUP_REPS), " groups...\n");
    fi;
od;
Print("Binning complete.\n\n");

# Header
Print("Order | #ConjClasses | #DistinctTypes | NrSmallGroups | Types<=Library?\n");
Print("------+--------------+----------------+---------------+----------------\n");

# Process each order
for o in orders_to_check do
    key := String(o);
    grps := order_bins.(key);
    num_cc := Length(grps);

    # Compute IdGroup for each and collect unique types
    id_set := [];;
    for g in grps do
        id := IdGroup(g);
        id_str := String(id);
        if not id_str in id_set then
            Add(id_set, id_str);
        fi;
    od;
    num_types := Length(id_set);

    # Get library count
    nr_lib := NrSmallGroups(o);

    # Check validity
    if num_types <= nr_lib then
        valid := "YES";
    else
        valid := "FAIL !!!";
    fi;

    Print(String(o, 5), " | ",
          String(num_cc, 12), " | ",
          String(num_types, 14), " | ",
          String(nr_lib, 13), " | ",
          valid, "\n");
od;

Print("\n=== Spot check complete ===\n");
QUIT;
