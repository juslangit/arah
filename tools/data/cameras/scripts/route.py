import sys; sys.path.insert(0,''+__import__('os').path.dirname(__file__)+'')
from lib import *
def build(refpred, hw=('motorway','trunk','primary','motorway_link','trunk_link')):
    adj=collections.defaultdict(list); pos={}
    for w in D['ways']:
        wid,h,ref,name,ow,g=w
        if h not in hw or not refpred(ref,name,h): continue
        for k in range(len(g)-1):
            a,b=g[k],g[k+1]; pos[a[2]]=a[:2]; pos[b[2]]=b[:2]
            d=hav(a[0],a[1],b[0],b[1])
            if h.endswith('_link'): d*=5
            if ow=='-1': adj[b[2]].append((a[2],d))
            else:
                adj[a[2]].append((b[2],d))
                if ow not in ('yes','true','1') and h not in('motorway',): adj[b[2]].append((a[2],d))
    return adj,pos
def nearest_node(pos,la,lo):
    return min(pos,key=lambda n:(pos[n][0]-la)**2+((pos[n][1]-lo)*math.cos(math.radians(la)))**2)
def path(adj,pos,s,t):
    dist={s:0};prev={};pq=[(0,s)]
    while pq:
        d,u=heapq.heappop(pq)
        if u==t: break
        if d>dist[u]: continue
        for v,w in adj[u]:
            nd=d+w
            if nd<dist.get(v,1e18): dist[v]=nd;prev[v]=u;heapq.heappush(pq,(nd,v))
    if t not in dist: return None
    p=[t]
    while p[-1]!=s: p.append(prev[p[-1]])
    p.reverse(); pts=[pos[n] for n in p]
    ch=[0]
    for i in range(1,len(pts)): ch.append(ch[-1]+hav(*pts[i-1],*pts[i]))
    return pts,ch
def project(pts,ch,la,lo):
    best=None
    for i in range(len(pts)-1):
        if abs(pts[i][0]-la)>0.05 and abs(pts[i+1][0]-la)>0.05: continue
        d,t=segdist(la,lo,pts[i],pts[i+1])
        if best is None or d<best[0]: best=(d,ch[i]+t*(ch[i+1]-ch[i]),i)
    return best
def at(pts,ch,c):
    import bisect
    i=max(0,min(len(ch)-2,bisect.bisect_right(ch,c)-1))
    t=(c-ch[i])/(ch[i+1]-ch[i]) if ch[i+1]>ch[i] else 0
    la=pts[i][0]+t*(pts[i+1][0]-pts[i][0]); lo=pts[i][1]+t*(pts[i+1][1]-pts[i][1])
    return la,lo,bearing(*pts[i],*pts[i+1])
