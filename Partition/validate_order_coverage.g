# Validation Test: Ensure all orders from batch files are covered by deduplication
#
# IMPORTANT: Run this BEFORE and AFTER any deduplication process to verify coverage.
# This test catches the bug where some orders were never assigned to any process.

BASE_PATH := "/cygdrive/c/Users/jeffr/Downloads/Symmetric Groups/Partition/";

Print("=== Order Coverage Validation Test ===\n\n");

# Load all large groups from batch files
allLargeOrders := [];

Read(Concatenation(BASE_PATH, "batch_1_large.g"));
Append(allLargeOrders, BATCH_1_LARGE_ORDERS);

Read(Concatenation(BASE_PATH, "batch_2_large.g"));
Append(allLargeOrders, BATCH_2_LARGE_ORDERS);

Read(Concatenation(BASE_PATH, "batch_3_large.g"));
Append(allLargeOrders, BATCH_3_LARGE_ORDERS);

Read(Concatenation(BASE_PATH, "batch_4_large.g"));
Append(allLargeOrders, BATCH_4_LARGE_ORDERS);

batchOrders := Set(allLargeOrders);
Print("Batch files contain ", Length(allLargeOrders), " groups\n");
Print("Unique orders in batch files: ", Length(batchOrders), "\n\n");

# Collect all orders from deduplication result files
dedupeOrders := [];

# Try loading each dedupe result file
LoadDedupeFile := function(filename, varPrefix)
    local orders;
    if IsExistingFile(Concatenation(BASE_PATH, filename)) then
        Read(Concatenation(BASE_PATH, filename));
        # The file should define *_ORDERS variable
        return true;
    fi;
    return false;
end;

# Load dedupe_result_1-8
for i in [1..8] do
    filename := Concatenation("dedupe_result_", String(i), ".g");
    if IsExistingFile(Concatenation(BASE_PATH, filename)) then
        Read(Concatenation(BASE_PATH, filename));
        ordersVar := VALUE_GLOBAL(Concatenation("DEDUPE_", String(i), "_ORDERS"));
        if ordersVar <> fail then
            Append(dedupeOrders, ordersVar);
        fi;
    fi;
od;

# Load dedupe_order_* files
individualOrders := [95040, 5040, 302400, 129600, 32256, 20160, 28800, 907200];
for ord in individualOrders do
    filename := Concatenation("dedupe_order_", String(ord), ".g");
    if IsExistingFile(Concatenation(BASE_PATH, filename)) then
        Add(dedupeOrders, ord);
    fi;
od;

# Load invariant_dedupe_p* files (orders 2592, 6912, 10368)
for i in [0..7] do
    filename := Concatenation("invariant_dedupe_p", String(i), ".g");
    if IsExistingFile(Concatenation(BASE_PATH, filename)) then
        # These cover orders 2592, 6912, 10368
        Append(dedupeOrders, [2592, 6912, 10368]);
    fi;
od;

# Load missing_dedupe_p* files if they exist
for i in [0..7] do
    filename := Concatenation("missing_dedupe_p", String(i), ".g");
    if IsExistingFile(Concatenation(BASE_PATH, filename)) then
        Read(Concatenation(BASE_PATH, filename));
        ordersVar := VALUE_GLOBAL(Concatenation("MISSING_DEDUPE_P", String(i), "_ORDERS"));
        if ordersVar <> fail then
            Append(dedupeOrders, ordersVar);
        fi;
    fi;
od;

coveredOrders := Set(dedupeOrders);
Print("Orders covered by deduplication: ", Length(coveredOrders), "\n\n");

# Find missing orders
missingOrders := Filtered(batchOrders, o -> not o in coveredOrders);

if Length(missingOrders) = 0 then
    Print("*** VALIDATION PASSED ***\n");
    Print("All ", Length(batchOrders), " orders are covered by deduplication.\n");
else
    Print("*** VALIDATION FAILED ***\n");
    Print("Missing orders: ", Length(missingOrders), "\n");
    Print(missingOrders, "\n\n");

    # Count groups in missing orders
    missingGroupCount := 0;
    for o in missingOrders do
        cnt := Length(Filtered(allLargeOrders, x -> x = o));
        missingGroupCount := missingGroupCount + cnt;
        Print("  Order ", o, ": ", cnt, " groups\n");
    od;
    Print("\nTotal groups NOT covered: ", missingGroupCount, "\n");
fi;

QUIT;
