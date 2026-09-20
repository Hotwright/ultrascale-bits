#!/usr/bin/env python3
# Check every feature a FASM file emits against prjuray-db, per tile type.
# This is the vendor-free acceptance test for the fasm.cc UltraScale+ port:
# a feature prjuray has never heard of assembles to nothing, silently.
# Usage: python3 tools/check_fasm_vs_uraydb.py <file.fasm>
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

fasm=sys.argv[1]
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
        notile[tt]+=1; continue
    if any(tt+'.'+c in known[tt] for c in cands):
        hit[tt]+=1
    else:
        miss[tt]+=1
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
print("\nunknown feature examples:")
for tt,ex in sorted(examples.items()):
    for e in ex: print("   "+e)
