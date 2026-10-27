import sys, collections, pickle, os, glob
sys.argv = [sys.argv[0]] + sys.argv[1:]
import importlib.util as _u
_sp = _u.spec_from_file_location("dsolve", os.path.join(os.path.dirname(os.path.abspath(__file__)), "solve.py"))
S = _u.module_from_spec(_sp)
_sp.loader.exec_module(S)
cache = "build/tiles.pkl"
if os.path.exists(cache) and os.path.getmtime(cache) > max(os.path.getmtime(p) for p in __import__('glob').glob('build/*/design.bit')):
    tiles = pickle.load(open(cache, "rb"))
else:
    tiles = S.load("build"); pickle.dump(tiles, open(cache, "wb"))
for name in sys.argv[1:]:
    fr, off = map(int, name.split("_"))
    b = (fr, off)
    with_b = [f for _, _, f, bits in tiles if b in bits]
    without = [f for _, _, f, bits in tiles if b not in bits]
    allf = set().union(*(f for _, _, f, _ in tiles))
    rows = []
    for f in allf:
        a = sum(f in x for x in with_b); c = sum(f in x for x in without)
        rows.append((a / len(with_b) - c / max(1, len(without)), f, a, len(with_b), c, len(without)))
    rows.sort(reverse=True)
    print("bit", name, "set in", len(with_b), "of", len(tiles))
    for r in rows[:8]:
        print("   %+.2f %-36s with-bit %d/%d  without-bit %d/%d" % r)
