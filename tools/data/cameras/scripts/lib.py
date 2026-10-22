import pickle, math, heapq, collections
D=pickle.load(open(__import__('os').path.join(__import__('os').environ.get('CAM_WORK',__import__('os').path.join(__import__('os').path.dirname(__file__),'..','.work')),'osm.pkl'),'rb'))
def hav(a,b,c,d):
    R=6371008.8; p1,p2=math.radians(a),math.radians(c); dp=p2-p1; dl=math.radians(d-b)
    x=math.sin(dp/2)**2+math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2*R*math.asin(math.sqrt(x))
def bearing(a,b,c,d):
    p1,p2=math.radians(a),math.radians(c); dl=math.radians(d-b)
    y=math.sin(dl)*math.cos(p2); x=math.cos(p1)*math.sin(p2)-math.sin(p1)*math.cos(p2)*math.cos(dl)
    return (math.degrees(math.atan2(y,x))+360)%360
# grid index of way segments
G=collections.defaultdict(list)
def cell(la,lo): return (int(la*50),int(lo*50))
for wi,(wid,h,ref,name,ow,g) in enumerate(D['ways']):
    for k in range(len(g)-1):
        G[cell(g[k][0],g[k][1])].append((wi,k))
def segdist(la,lo,a,b):
    # project in local meters
    kx=111320*math.cos(math.radians(la)); ky=110540
    ax,ay=(a[1]-lo)*kx,(a[0]-la)*ky; bx,by=(b[1]-lo)*kx,(b[0]-la)*ky
    dx,dy=bx-ax,by-ay; L=dx*dx+dy*dy
    t=0 if L==0 else max(0,min(1,-(ax*dx+ay*dy)/L))
    px,py=ax+t*dx,ay+t*dy
    return math.hypot(px,py),t
def nearest_ways(la,lo,rad=1,filt=None,n=5):
    c=cell(la,lo); res={}
    for i in range(-rad,rad+1):
        for j in range(-rad,rad+1):
            for wi,k in G.get((c[0]+i,c[1]+j),()):
                w=D['ways'][wi]
                if filt and not filt(w): continue
                d,t=segdist(la,lo,w[5][k],w[5][k+1])
                if wi not in res or d<res[wi][0]: res[wi]=(d,k,t)
    out=sorted(((v[0],wi,v[1],v[2]) for wi,v in res.items()))[:n]
    return [(round(d,1),D['ways'][wi][0],D['ways'][wi][1],D['ways'][wi][2],D['ways'][wi][3],D['ways'][wi][4],
             round(bearing(*D['ways'][wi][5][k][:2],*D['ways'][wi][5][k+1][:2])),wi,k,t) for d,wi,k,t in out]
