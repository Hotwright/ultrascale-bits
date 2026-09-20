#!/usr/bin/env python3
# Check every feature a FASM file emits against prjuray-db, per tile type, and
# optionally write a copy with the unknown ones removed.
#
# This is the vendor-free acceptance test for the fasm.cc UltraScale+ port. It
# matters because prjuray's assembler does NOT ignore a feature it has never
# heard of: utils/fasm_assembler.py collects every one and then raises
#
#   FasmLookupError: Segment DB <tile type>, key <feature> not found ...
#
# so a single stray name makes fasm2bit.py refuse the whole file. There is no
# flag to relax that.
#
# --filter OUT writes OUT with the unknown features dropped and names every one
# it dropped. Use it only where the dropped feature is known to carry no bits --
# see SCOPE-K26.md for which tile types those are and why.
#
# NOTE what this proves: emitted features are a SUBSET of what prjuray knows. It
# cannot see a feature we FAIL to write.
#
# Usage: python3 tools/check_fasm_vs_uraydb.py <file.fasm> [--filter out.fasm]
import re, sys, os, json, collections
DB=os.environ.get('URAY_DB', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'prjuray-db', 'zynqusp'))
# Build: tile_type -> set of known feature names (with [i] normalised)
known=collections.defaultdict(set)
for fn in os.listdir(DB):
    if not fn.startswith('segbits_') or fn.endswith('origin_info.db'): continue
    for line in open(os.path.join(DB,fn)):
        f=line.split()[0]
        tt=f.split('.')[0]
        known[tt].add(re.sub(r'\[\d+\]','[i]',f))
print("segbits tile types: %d, features: %d" % (len(known), sum(len(v) for v in known.values())))

args=[a for a in sys.argv[1:] if not a.startswith('--')]
fasm=args[0]
filter_out=None
if '--filter' in sys.argv:
    filter_out=sys.argv[sys.argv.index('--filter')+1]
kept_lines=[]; dropped_lines=[]
miss=collections.Counter(); hit=collections.Counter(); notile=collections.Counter()
examples=collections.defaultdict(list)
for line in open(fasm):
    line=line.strip()
    if not line or line.startswith('#'): continue
    feat=line.split(' =')[0]
    inst=feat.split('.')[0]
    tt=re.sub(r'_X\d+Y\d+$','',inst)
    rest=feat[len(inst)+1:]
    # INIT[63:0] = ... expands to INIT[0..63]
    cands=[]
    if re.search(r'\[\d+:\d+\]$',rest):
        cands=[re.sub(r'\[\d+:\d+\]$','[i]',rest)]
    else:
        cands=[re.sub(r'\[\d+\]','[i]',rest)]
    if tt not in known:
        notile[tt]+=1; dropped_lines.append(line); continue
    if any(tt+'.'+c in known[tt] for c in cands):
        hit[tt]+=1; kept_lines.append(line)
    else:
        miss[tt]+=1; dropped_lines.append(line)
        if len(examples[tt])<6: examples[tt].append(feat)

tot_h, tot_m = sum(hit.values()), sum(miss.values())
print("\n%-22s %8s %8s %8s" % ("tile type","known","unknown","%known"))
for tt in sorted(set(hit)|set(miss)):
    h,m=hit[tt],miss[tt]
    print("%-22s %8d %8d %7.1f%%" % (tt,h,m,100*h/(h+m)))
print("%-22s %8d %8d %7.1f%%" % ("TOTAL",tot_h,tot_m,100*tot_h/max(1,tot_h+tot_m)))
if notile:
    print("\nno segbits file for these tile types (feature count):")
    for tt,n in notile.most_common(): print("   %-28s %d" % (tt,n))
if filter_out:
    with open(filter_out,'w') as f:
        f.write("# Filtered by tools/check_fasm_vs_uraydb.py --filter.\n")
        f.write("# %d features dropped because prjuray-db has no entry for them;\n" % len(dropped_lines))
        f.write("# prjuray's assembler raises FasmLookupError rather than ignoring them.\n")
        for l in kept_lines: f.write(l+"\n")
    print("\nwrote %s: %d features kept, %d dropped:" % (filter_out, len(kept_lines), len(dropped_lines)))
    for l in dropped_lines: print("   DROPPED %s" % l)

print("\nunknown feature examples:")
for tt,ex in sorted(examples.items()):
    for e in ex: print("   "+e)
