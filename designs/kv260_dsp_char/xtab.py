import pickle, sys, collections
tiles = pickle.load(open("build/tiles.pkl", "rb"))
bit = tuple(map(int, sys.argv[1].split("_"))); site = int(sys.argv[2]); keys = sys.argv[3:]
t = collections.defaultdict(lambda: [0, 0])
for _, _, f, bits in tiles:
    g = {x.split(".", 1)[1] for x in f if x.startswith("DSP_%d." % site)}
    if not g: continue
    k = tuple(next((x for x in g if x.startswith(p + ".")), p + ".?").split(".", 1)[1] for p in keys)
    t[k][bit in bits] += 1
print(sys.argv[1], " ".join(keys))
for k, v in sorted(t.items()):
    print("   %-50s set %3d / %3d %s" % (" ".join(k), v[1], sum(v), "" if v[0] == 0 or v[1] == 0 else "MIXED"))
