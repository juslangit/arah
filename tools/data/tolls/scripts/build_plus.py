import json, math, statistics, sys
import os
HERE=os.path.dirname(os.path.abspath(__file__)); RAW=os.path.join(HERE,'..','raw'); ROOT=os.path.join(HERE,'..')
sys.path.insert(0, HERE)
from plus_gates import G
osm=json.load(open('/Users/luqman/Desktop/projects/app/arah/tools/data/out/toll_plazas_osm.json'))
byname={}
for p in osm: byname.setdefault(p['name'],[]).append(p)
d=json.load(open(os.path.join(RAW,'plus_c1.json')))
gates=[]; gate_ll={}
for code,(name,names) in G.items():
    pts=[]; used=[]
    for n in names:
        if '@' in n:
            n,lat=n.split('@'); cand=[p for p in byname[n] if abs(p['lat']-float(lat))<1e-4]
        else: cand=byname.get(n,[])
        assert cand, (code,n)
        pts+=cand; used.append(n)
    g={"id":"plus-"+code.lower(),"code":code,"name":"Plaza Tol "+name}
    if pts:
        g["lat"]=round(sum(p['lat'] for p in pts)/len(pts),5); g["lon"]=round(sum(p['lon'] for p in pts)/len(pts),5); g["osm_names"]=sorted(set(used))
    if code=="BGC":
        g.update(lat=2.88293,lon=101.6245,osm_names=["(unnamed 2.88,101.62)"],confidence="medium",note="Not named in OSM; matched to the unnamed booth on ELITE at KM26.7 (Gamuda Cove I/C 607A, opened 2019-09-06).")
    gates.append(g); gate_ll[code]=(g['lat'],g['lon'])
notes={
 "JPP":"Penang Bridge. Charged only island-bound (mainland -> island). Pairs X->JPP include the bridge toll; no JPP->X pairs exist.",
 "BKW":"Exit-only in the official calculator.",
 "PDU":"Direction-specific half interchange; PDU and PDS are each valid only for one travel direction.",
 "PDS":"Direction-specific half interchange (see PDU).",
 "BTU":"Half interchange: few valid pairs.","BTS":"Half interchange.","EBN":"Half interchange.","EBS":"Half interchange: entry towards one direction only.",
 "IPU":"Half interchange.","YPS":"Half interchange.",
}
for g in gates:
    if g['code'] in notes: g['note']=(g.get('note','')+' '+notes[g['code']]).strip()
pairs=[]
def hav(a,b):
    R=6371; la1,lo1=map(math.radians,a); la2,lo2=map(math.radians,b)
    h=math.sin((la2-la1)/2)**2+math.cos(la1)*math.cos(la2)*math.sin((lo2-lo1)/2)**2
    return 2*R*math.asin(math.sqrt(h))
ratios=[]
for k,v in d.items():
    if not v: continue
    a,b=k.split('-'); f=float(v)
    if f<=0: continue
    if a not in G or b not in G: continue
    pr={"from":"plus-"+a.lower(),"to":"plus-"+b.lower(),"car":round(f,2),"moto":0}
    pairs.append(pr)
    if a!=b and 'JPP' not in (a,b) and a not in ('BSI','TTK','TLK','TTP','KSG','LUN','JWI') and b not in ('BSI','TTK','TLK','TTP','KSG','LUN','JWI'):
        dist=hav(gate_ll[a],gate_ll[b])
        if dist>100: ratios.append(f/dist)
med=statistics.median(ratios)
print("pairs",len(pairs),"gc ratio median",round(med,4),"p10",round(statistics.quantiles(ratios,n=10)[0],4),"p90",round(statistics.quantiles(ratios,n=10)[-1],4))
mins=sorted(p['car'] for p in pairs if p['from']!=p['to'])[:5]; print("min",mins)
json.dump({"gates":gates,"pairs":pairs,"gc_ratio":med},open(os.path.join(RAW,'plus_closed.json'),'w'))
