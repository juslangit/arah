import sys; sys.path.insert(0,''+__import__('os').path.dirname(__file__)+'')
from route import *
import json
def graph(refs):
    adj=collections.defaultdict(list); pos={}
    for wid,h,ref,name,ow,g in D['ways']:
        rs=[x.strip() for x in ref.replace(',',';').split(';')]
        if h not in ('motorway','trunk','primary','motorway_link','trunk_link','primary_link'): continue
        on = any(r in refs for r in rs)
        pen = 1 if on else (30 if h in('motorway','motorway_link','trunk','trunk_link') else 8)
        for k in range(len(g)-1):
            a,b=g[k],g[k+1]; pos[a[2]]=a[:2]; pos[b[2]]=b[:2]
            d=hav(a[0],a[1],b[0],b[1])
            if ow=='-1': adj[b[2]].append((a[2],d,pen))
            else:
                adj[a[2]].append((b[2],d,pen))
                if ow not in ('yes','true','1'): adj[b[2]].append((a[2],d,pen))
    return adj,pos
def route(adj,pos,A,B):
    cands=sorted((n for n in pos if abs(pos[n][0]-A[0])<0.02 and abs(pos[n][1]-A[1])<0.02 and adj[n]),key=lambda n:hav(*pos[n],*A))
    s=cands[0]
    dist={s:0};prev={};pq=[(0,s)]
    while pq:
        d,u=heapq.heappop(pq)
        if d>dist[u]: continue
        for v,w,p in adj[u]:
            nd=d+w*p
            if nd<dist.get(v,1e18): dist[v]=nd;prev[v]=u;heapq.heappush(pq,(nd,v))
    t=min(dist,key=lambda n:hav(*pos[n],*B)); print('snap end m',round(hav(*pos[t],*B)),'start m',round(hav(*pos[s],*A)))
    p=[t]
    while p[-1]!=s: p.append(prev[p[-1]])
    p.reverse(); pts=[pos[n] for n in p]; ch=[0]
    for i in range(1,len(pts)): ch.append(ch[-1]+hav(*pts[i-1],*pts[i]))
    return pts,ch
if __name__=='__main__':
    refs=set(sys.argv[1].split(',')); A=tuple(map(float,sys.argv[2].split(','))); B=tuple(map(float,sys.argv[3].split(',')))
    adj,pos=graph(refs); pts,ch=route(adj,pos,A,B)
    json.dump({'pts':pts,'ch':ch},open(sys.argv[4],'w')); print('len km',round(ch[-1]/1000,2))
