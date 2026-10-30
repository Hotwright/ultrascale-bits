import collections, numpy as np, csv, sys
def fit(data, label):
    b=collections.defaultdict(list)
    for dx,dy,d in data: b[(dx,dy)].append(d)
    pts=[(dx,dy,np.percentile(v,20),np.median(v),len(v)) for (dx,dy),v in b.items() if len(v)>=3 and (dx,dy)!=(0,0)]
    A=np.array([[1,min(dy,6),max(dy-6,0),min(dx,12),max(dx-12,0)] for dx,dy,*_ in pts],float)
    w=np.sqrt([n for *_,n in pts])
    c20,*_=np.linalg.lstsq(A*w[:,None],np.array([p[2] for p in pts])*w,rcond=None)
    cm,*_=np.linalg.lstsq(A*w[:,None],np.array([p[3] for p in pts])*w,rcond=None)
    print(f'{label:22s} arcs {len(data):5d} | p20 fit a,y<6,y>6,x<12,x>12: {np.round(c20).astype(int)} | median fit {np.round(cm).astype(int)}')
    return b
viv=[]
for l in open(sys.argv[1]):
    p=l.rstrip('\n').split('\t'); sx,sy,dx,dy=map(int,p[:4]); viv.append((abs(dx-sx),abs(dy-sy),float(p[6])))
npr=[]
for r in csv.DictReader(open(sys.argv[2])):
    d=float(r['delay'])
    if d<=0: continue
    npr.append((abs(int(r['dx'])-int(r['sx'])),abs(int(r['dy'])-int(r['sy'])),d))
bv=fit(viv,'vivado '+sys.argv[1].split('.')[0]); bn=fit(npr,'nextpnr')
print('\nmedian delay by distance (vivado / nextpnr), n>=3 both')
for key in [(0,1),(0,2),(0,4),(0,8),(0,12),(0,20),(1,0),(2,0),(4,0),(5,0),(8,0),(4,4),(8,8),(12,12)]:
    if len(bv.get(key,[]))>=3 and len(bn.get(key,[]))>=3:
        print(key, int(np.median(bv[key])), '/', int(np.median(bn[key])), '   p20', int(np.percentile(bv[key],20)), '/', int(np.percentile(bn[key],20)))
