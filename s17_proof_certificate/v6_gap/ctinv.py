"""Label-free character-table invariant `ctinv` (S17 certificate v6).  See audit/audit_invariant.py
and ../CORRECTION_A174511_17.md for the definition and why it is an isomorphism invariant."""
import hashlib


def _field(line, name):
    """Balanced-bracket value of `name:=` in a GAP record line (or the scalar up to the next comma)."""
    k = line.index(name + ":=") + len(name) + 2
    if line[k] != "[":
        e = k
        while line[e] not in ",)": e += 1
        return line[k:e]
    depth, e = 0, k
    while True:
        ch = line[e]
        if ch == "[": depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0: return line[k:e + 1]
        e += 1


def _split_top(s):
    """'[ a, b, [c,d] ]' -> ['a', 'b', '[c,d]'] (top-level items, stripped)."""
    s = s.strip()[1:-1]
    out, depth, cur = [], 0, []
    for ch in s:
        if ch in "[(": depth += 1
        elif ch in "])": depth -= 1
        if ch == "," and depth == 0:
            out.append("".join(cur).strip()); cur = []
        else:
            cur.append(ch)
    if "".join(cur).strip(): out.append("".join(cur).strip())
    return out


def parse_ct(line):
    r = {"job": int(_field(line, "job")), "t": int(_field(line, "t")),
         "selftest": _field(line, "selftest") == "true", "order": int(_field(line, "order")),
         "idgroup": _field(line, "idgroup").replace(" ", ""),
         "sk": _field(line, "sk").replace(" ", ""), "hist": _field(line, "hist").replace(" ", "")}
    r["sizes"] = [int(x) for x in _split_top(_field(line, "sizes"))]
    r["orders"] = [int(x) for x in _split_top(_field(line, "orders"))]
    r["powermaps"] = [(int(_split_top(pm)[0]), [int(x) for x in _split_top(_split_top(pm)[1])])
                      for pm in _split_top(_field(line, "powermaps"))]
    r["irr"] = [[v.replace(" ", "") for v in _split_top(row)] for row in _split_top(_field(line, "irr"))]
    return r


def _h(obj):
    return hashlib.sha256(repr(obj).encode()).hexdigest()


def fingerprint(r):
    k = len(r["sizes"])
    irr, pms = r["irr"], sorted(r["powermaps"])
    one = r["orders"].index(1)
    C = [_h(("c0", r["orders"][c], r["sizes"][c])) for c in range(k)]
    X = [_h(("x0", irr[x][one])) for x in range(len(irr))]
    nC, nX = len(set(C)), len(set(X))
    for _ in range(k + len(irr) + 2):
        C2 = [_h((C[c], sorted((X[x], irr[x][c]) for x in range(len(irr))),
                  [C[pm[c] - 1] for _, pm in pms])) for c in range(k)]
        X2 = [_h((X[x], sorted((C[c], irr[x][c]) for c in range(k)))) for x in range(len(irr))]
        C, X = C2, X2
        if len(set(C)) == nC and len(set(X)) == nX:
            break                                   # stable: no partition split this round
        nC, nX = len(set(C)), len(set(X))
    return _h((r["order"], [p for p, _ in pms], sorted(C), sorted(X)))
