#!/usr/bin/env python3
"""For bits solve.py leaves unexplained: find an exact formula over at most
two features (f, f AND g, f OR g; each possibly negated) that matches the
bit in every tile instance. Uses probe.py's cached tile list.

    explain.py [bit ...]     (default: every bit set in 10+ tiles and not
                              explained by a single feature)
"""
import os, pickle, sys, itertools, collections
import numpy as np

tiles = pickle.load(open("build/tiles.pkl", "rb"))
always = set.intersection(*(b for _, _, _, b in tiles))
feats = sorted(set().union(*(f for _, _, f, _ in tiles)))
fi = {f: i for i, f in enumerate(feats)}
F = np.zeros((len(tiles), len(feats)), bool)
for r, (_, _, f, _) in enumerate(tiles):
    F[r, [fi[x] for x in f]] = True
allbits = sorted(set().union(*(b for _, _, _, b in tiles)) - always)
B = {b: np.array([b in bits for _, _, _, bits in tiles]) for b in allbits}


def explain(v):
    # single literal
    eq = (F == v[:, None]).all(0)
    if eq.any():
        return [feats[i] for i in np.flatnonzero(eq)][:3]
    neq = (F == ~v[:, None]).all(0)
    if neq.any():
        return ["!" + feats[i] for i in np.flatnonzero(neq)][:3]
    # OR: every literal must imply v; AND: v must imply every literal
    imp_pos = np.flatnonzero(~(F & ~v[:, None]).any(0))          # f -> v
    imp_neg = np.flatnonzero(~(~F & ~v[:, None]).any(0))         # !f -> v
    lits = [(i, True) for i in imp_pos] + [(i, False) for i in imp_neg]
    col = lambda l: F[:, l[0]] if l[1] else ~F[:, l[0]]
    name = lambda l: feats[l[0]] if l[1] else "!" + feats[l[0]]
    for a, b in itertools.combinations(lits, 2):
        if ((col(a) | col(b)) == v).all():
            return ["%s | %s" % (name(a), name(b))]
    by_pos = np.flatnonzero(~(~F & v[:, None]).any(0))           # v -> f
    by_neg = np.flatnonzero(~(F & v[:, None]).any(0))            # v -> !f
    lits = [(i, True) for i in by_pos] + [(i, False) for i in by_neg]
    for a, b in itertools.combinations(lits, 2):
        if ((col(a) & col(b)) == v).all():
            return ["%s & %s" % (name(a), name(b))]
    return None


want = [tuple(map(int, x.split("_"))) for x in sys.argv[1:]] or [b for b in allbits if B[b].sum() >= 10]
out = collections.Counter()
for b in want:
    e = explain(B[b])
    out["explained" if e else "unexplained"] += 1
    print("%02d_%03d  n=%3d  %s" % (b[0], b[1], B[b].sum(), " ; ".join(e) if e else "-"))
print(dict(out), file=sys.stderr)
