import json, math, statistics, sys
import os
HERE=os.path.dirname(os.path.abspath(__file__)); RAW=os.path.join(HERE,'..','raw'); ROOT=os.path.join(HERE,'..')

S=RAW+'/'
A=json.load(open(S+'research_A.json')); B=json.load(open(S+'research_B.json')); C=json.load(open(S+'research_C.json'))
PL=json.load(open(S+'plus_closed.json')); LPT=json.load(open(S+'lpt_c1.json'))
OSM=json.load(open('/Users/luqman/Desktop/projects/app/arah/tools/data/out/toll_plazas_osm.json'))
KEEP=('id','name','highway','lat','lon','osm_names','car','moto','both_directions','charged_heading_deg','source','source_date','confidence','note')
def clean(p):
    o={k:p.get(k) for k in KEEP}
    if o['charged_heading_deg'] is None: o.pop('charged_heading_deg')
    for k in ('car_alt','charge_start'):
        if k in p: o[k]=p[k]
    return o
plazas=[]; abolished=[]
dropA={'ekve-sungai-long','ekve-ampang','ekve-bandar-mahkota-cheras','ekve-hulu-langat','lekas-kajang-selatan','lekas-setul','lekas-semenyih','lekas-eco-majestic','lekas-pajam','lekas-mantin','plus-upm','plus-southville-city'}
for p in A:
    if p.get('abolished'):
        abolished.append({"name":p['name']+" ("+p['id']+")","osm_names":p['osm_names'],"lat":p['lat'],"lon":p['lon'],"abolished":p['abolished'],"scope":"one direction only; the other direction still pays (see grandsaga-batu-9 / -11)","source":p['source']}); continue
    if p['id'] in dropA: continue
    plazas.append(clean(p))
dropB={'akleh-datuk-keramat','nnksb-bukit-raja'}
for p in B['plazas']:
    if p['id'] in dropB: continue
    plazas.append(clean(p))
dropC={'penang_bridge','bandar_cassia_link','tanjung_kupang','bsi','kubang_semang','lunas','klk_gombak','klk_bentong'}
for p in C['plazas']:
    if p['id'] in dropC: continue
    o=clean(p); o['id']=o['id'].replace('_','-')
    if o['id']=='penang-2nd-bridge-jk2pp':
        o['id']='penang-second-bridge'
        o['skip_if_closed_exit']=['plus-bcs']
        o['note']+=" APP RULE: do not charge here if the trip's PLUS exit gate is plus-bcs (that PLUS pair already includes this RM5.74)."
    plazas.append(o)
for a in C['abolished']: abolished.append(a)
abolished.append({"name":"Batu Tiga and Sungai Rasau toll plazas (Federal Highway FT2, Shah Alam/Klang)","lat":None,"lon":None,"osm_names":[],"abolished":"2018-01-01","source":"https://paultan.org/2018/01/02/toll-collection-ends-at-batu-tiga-and-sungai-rasau-in-selangor-bukit-kayu-hitam-in-kedah-and-edl-in-johor/","note":"Not in the OSM extract (plazas demolished)."})
# LEKAS open plaza Ampangan kept from A (lekas-ampangan)
# ---------- closed systems ----------
def hav(a,b):
    R=6371; la1,lo1,la2,lo2=map(math.radians,(a[0],a[1],b[0],b[1]))
    h=math.sin((la2-la1)/2)**2+math.cos(la1)*math.cos(la2)*math.sin((lo2-lo1)/2)**2
    return 2*R*math.asin(math.sqrt(h))
CIRC=1.2
def per_km(gates,pairs,mind=0):
    g={x['id']:(x['lat'],x['lon']) for x in gates}
    r=[p['car']/(hav(g[p['from']],g[p['to']])*CIRC) for p in pairs if p['from']!=p['to'] and p['car']>0 and hav(g[p['from']],g[p['to']])>mind]
    return round(statistics.median(r),3) if r else None
closed=[]
# PLUS
pg=[]
for g in PL['gates']:
    g=dict(g); 
    if g['code']=='JPP':
        g['charged_heading_deg']=265
        g['note']=("Penang Bridge (E36) pseudo-gate at the mainland plaza. Charged only island-bound (westbound). "
                   "X->plus-jpp fares include the RM5.74 bridge toll; plus-jpp->plus-jpp (5.74) is the bridge alone for trips that join the bridge without a PLUS ticket. Eastbound (island->mainland) is free: do not treat as a gate eastbound. Motorcycles free since 2019-01-01.")
    if g['code']=='BCS': g['note']=(g.get('note','')+" X->plus-bcs fares include the RM5.74 Second Penang Bridge toll (paid here for NSE through-traffic, westbound); plus-bcs->X does not. The RM0.60 Bandar Cassia link-road component is assumed already included in these PLUS fares.").strip()
    if g['code']=='JPP': g['osm_names']=g['osm_names']+['(unnamed 5.36,100.39)']
    if g['code']=='SKD': g['osm_names']=g['osm_names']+['(unnamed 1.58,103.65)']
    pg.append(g)
plus_pairs=PL['pairs']
selfs={p['from']:p['car'] for p in plus_pairs if p['from']==p['to']}
pk=per_km(pg,[p for p in plus_pairs if 'jpp' not in p['from']+p['to'] and 'bcs' not in p['to']],100)
closed.append({"id":"plus","name":"PLUS closed system (NSE E1/E2, NKVE E1, ELITE E6, Second Link E3, BKE E15, Penang Bridge E36, EDL/BSI, Seremban-Port Dickson E29)",
 "highways":["E1","E2","E3","E6","E15","E29","E36"],
 "car_per_km":pk,"moto_per_km":0,"min_car":min(p['car'] for p in plus_pairs if p['from']!=p['to']),
 "per_km_method":f"Median over all official pairs with gates >100 km apart of fare / (great-circle km x {CIRC} road-circuity factor); great-circle median was {PL['gc_ratio']:.3f} RM/km. Spot check: Jalan Duta-Juru RM35.51 over ~320 road km = 0.111. Use only when a pair is missing.",
 "self_pairs_note":"A pair with from == to is the fixed charge for passing that gate when the trip has no other PLUS gate (open-style barrier): "+", ".join(f"{k} {v:.2f}" for k,v in sorted(selfs.items())),
 "gates":pg,"pairs":plus_pairs,
 "source":"https://plusapp-api-prod1.azurewebsites.net/api/tolls/GetTollFare/{from}/{to}/1 (official API behind the Toll Fare Calculator on https://www.plus.com.my/#toll-fare-calculator), every pair queried 2026-10-22",
 "confidence":"high",
 "note":"Every pair is an official Class 1 fare. Fares are NOT always symmetric (half interchanges, bridge legs), so look up from->to exactly. Pairs the API returned empty or 0.00 for (invalid/direction-impossible combos) are omitted. Motorcycles ride free on all PLUS expressways, and the Penang Bridge / Second Link motorcycle tolls were abolished 2019-01-01. Gate positions are the OSM booth positions (averaged where split)."})
# LPT
lg=[]
for g in next(x for x in C['closed'] if x['id'].startswith('ece'))['gates']:
    lg.append({"id":"lpt-"+g['id'].replace('_','-'),"name":"Plaza Tol "+g['name'],"lat":g['lat'],"lon":g['lon'],"osm_names":sorted(g['osm_names'])})
namemap={"Karak":"karak","Lanchang":"lanchang","Temerloh":"temerloh","Chenor":"chenor","Maran":"maran","Sri Jaya":"sri-jaya","Gambang":"gambang","Kuantan":"kuantan","Jabor":"jabor","Cheneh":"cheneh","Cukai":"cukai","Kijal":"kijal","Kertih":"kerteh","Paka":"paka","Kuala Dungun":"dungun","Bukit Besi":"bukit-besi","Ajil":"ajil","Telemung":"telemung","Kuala Terengganu":"kuala-terengganu"}
assert {"lpt-"+v for v in namemap.values()}=={g['id'] for g in lg}
lp=[]
for k,v in LPT.items():
    a,b=k.split('|'); f=float(v)
    if f==0: f=float(LPT[b+'|'+a])
    lp.append({"from":"lpt-"+namemap[a],"to":"lpt-"+namemap[b],"car":f,"moto":0})
closed.append({"id":"lpt","name":"East Coast Expressway LPT1 (Karak-Jabor) + LPT2 (Jabor-Kuala Terengganu)","highways":["E8"],
 "car_per_km":per_km(lg,lp,30),"moto_per_km":0,"min_car":min(p['car'] for p in lp),
 "per_km_method":f"Median of fare / (great-circle km x {CIRC}) over official pairs >30 km apart. LPT1 is officially ~RM0.12/km (Karak-Jabor RM21.00 over ~169 km = 0.124).",
 "gates":lg,"pairs":lp,
 "source":"https://www.afaprime.com/wp-content/toll_rate/lpt.php (official AFA PRIME, formerly ANIH, 'Kadar Tol LPT1 LPT2' calculator), all 342 pairs queried 2026-10-22",
 "confidence":"high",
 "note":"All pairs official Class 1. The calculator returned 0.00 for Kuala Terengganu->Karak only; the reverse (39.24) was used. Karak plaza is the LPT1 entry right after the open-system KL-Karak section (Gombak/Bentong are in 'plazas'). A sibling calculator (ece.php) disagreed on Lanchang->Karak (RM6.00 vs RM2.80); lpt.php values used. Motorcycles free."})
# EKVE
eg=[{"id":"ekve-sungai-long","name":"Plaza Tol Sungai Long (EKVE)","lat":3.05002,"lon":101.81526,"osm_names":["Plaza Tol Sungai Long"]},
    {"id":"ekve-bandar-mahkota-cheras","name":"Plaza Tol Bandar Mahkota Cheras (EKVE)","lat":3.07102,"lon":101.80591,"osm_names":["(unnamed 3.07,101.81)"],"confidence":"low","note":"OSM booth unnamed; matched by location only."},
    {"id":"ekve-hulu-langat","name":"Plaza Tol Hulu Langat (EKVE)","lat":3.09347,"lon":101.80484,"osm_names":["(unnamed 3.09,101.8)"],"confidence":"low","note":"OSM booth unnamed; matched by location only."},
    {"id":"ekve-ampang","name":"Plaza Tol Ampang (EKVE)","lat":3.15058,"lon":101.78861,"osm_names":["Plaza Tol Ampang"],"confidence":"medium","note":"Matched by location (not the SUKE 'Plaza Tol Ampang (A)/(B)')."}]
em={("sungai-long","bandar-mahkota-cheras"):2.68,("sungai-long","hulu-langat"):3.45,("sungai-long","ampang"):6.08,("bandar-mahkota-cheras","hulu-langat"):2.02,("bandar-mahkota-cheras","ampang"):4.65,("hulu-langat","ampang"):3.67}
ep=[]
for (a,b),f in em.items():
    ep+= [{"from":"ekve-"+a,"to":"ekve-"+b,"car":f,"moto":0},{"from":"ekve-"+b,"to":"ekve-"+a,"car":f,"moto":0}]
closed.append({"id":"ekve","name":"EKVE East Klang Valley Expressway Section 1 (Sungai Long-Ampang)","highways":["E27"],
 "car_per_km":per_km(eg,ep),"moto_per_km":0,"min_car":2.02,"per_km_method":f"Median fare/(great-circle km x {CIRC}) over the 6 official pairs.",
 "gates":eg,"pairs":ep,"source":"https://www.ekve.com.my/","confidence":"high","note":"Tolling began 2025-10-25. Fares symmetric per operator table. Gate positions for the two middle gates are location matches to unnamed OSM booths."})
# LEKAS
lk=[{"id":"lekas-kajang-selatan","name":"Plaza Tol Kajang Selatan","lat":2.95737,"lon":101.82601,"osm_names":["Plaza Tol Kajang Selatan"]},
    {"id":"lekas-semenyih","name":"Plaza Tol Semenyih","lat":2.94072,"lon":101.82785,"osm_names":["Plaza Tol Semenyih"],"confidence":"low"},
    {"id":"lekas-eco-majestic","name":"Plaza Tol Eco Majestic","lat":2.8945,"lon":101.83222,"osm_names":["Plaza Tol Eco Majestic"],"confidence":"low"},
    {"id":"lekas-pajam","name":"Plaza Tol Pajam","lat":2.84054,"lon":101.83372,"osm_names":["Tol Plaza Pajam"],"confidence":"low"},
    {"id":"lekas-mantin","name":"Plaza Tol Mantin","lat":2.81273,"lon":101.90505,"osm_names":["Plaza Tol Mantin"],"confidence":"low"},
    {"id":"lekas-setul","name":"Plaza Tol Setul","lat":2.77071,"lon":101.91576,"osm_names":["Plaza Tol Setul"]}]
closed.append({"id":"lekas","name":"LEKAS Kajang-Seremban Highway (closed section Kajang Selatan-Setul)","highways":["E21"],
 "car_per_km":0.1666,"moto_per_km":0,"min_car":None,"max_car":5.50,
 "per_km_method":"Official tariff basis: RM0.1666 per km (Class 1) since 2023-01-01, capped at RM5.50 for Kajang Selatan<->Setul. Use road km between entry and exit gate; the only published pair is the end-to-end one.",
 "gates":lk,"pairs":[{"from":"lekas-kajang-selatan","to":"lekas-setul","car":5.50,"moto":0},{"from":"lekas-setul","to":"lekas-kajang-selatan","car":5.50,"moto":0}],
 "source":"https://en.wikipedia.org/wiki/Kajang%E2%80%93Seremban_Highway (2023-01-01 restructuring; IJM does not publish a per-pair table)","confidence":"medium",
 "note":"The open Ampangan plaza (RM2.30) is in 'plazas' (lekas-ampangan) and is paid in addition. Ramp gates (Semenyih, Eco Majestic, Pajam, Mantin) are identified by location; their per-pair fares are NOT verified - use car_per_km."})
# SDE
sd=next(x for x in C['closed'] if x['id']=='sde_e22')
sg=[{"id":"sde-"+g['id'].replace('_','-'),"name":"Plaza Tol "+g['name']+" (SDE)","lat":g['lat'],"lon":g['lon'],"osm_names":g['osm_names']} for g in sd['gates']]
sp=[]
for p in sd['pairs']:
    a="sde-"+p['from'].replace('_','-'); b="sde-"+p['to'].replace('_','-')
    sp+=[{"from":a,"to":b,"car":p['car'],"moto":0},{"from":b,"to":a,"car":p['car'],"moto":0}]
closed.append({"id":"sde","name":"Senai-Desaru Expressway","highways":["E22"],"car_per_km":per_km(sg,sp),"moto_per_km":0,"min_car":min(p['car'] for p in sp),
 "per_km_method":f"Median fare/(great-circle km x {CIRC}) over the 6 official pairs.","gates":sg,"pairs":sp,"source":sd['source'],"confidence":"high","note":sd['note']})
# WCE / SKVE from B
for c in B['closed']:
    if c['id']=='lpt1': continue
    pre={'skve-wce-south':'skve','wce-klang':'wce','wce-teluk-intan':'wce','wce-perak-north':'wce'}[c['id']]
    gs=[{"id":f"{pre}-{g['id']}","name":"Plaza Tol "+g['name'],"lat":g['lat'],"lon":g['lon'],"osm_names":g['osm_names']} for g in c['gates']]
    ps=[]
    for p in c['pairs']:
        a=f"{pre}-{p['from']}"; b=f"{pre}-{p['to']}"
        for x,y in ((a,b),(b,a)):
            e={"from":x,"to":y,"car":p['car'],"moto":0}
            if p.get('confidence'): e['confidence']=p['confidence']
            ps.append(e)
    closed.append({"id":c['id'],"name":c['name'],"highways":["E26","E32"] if pre=='skve' else ["E32"],
      "car_per_km":per_km(gs,ps),"moto_per_km":0,"min_car":min(p['car'] for p in ps),
      "per_km_method":f"Median fare/(great-circle km x {CIRC}) over the official pairs in this table.",
      "gates":gs,"pairs":ps,"source":c['source'],"confidence":c['confidence'],"note":c['note']})
# ---------- OSM coverage ----------
used=set()
for p in plazas: used|=set(p['osm_names'])
for c in closed:
    for g in c['gates']: used|=set(g.get('osm_names',[]))
for a in abolished: used|=set(a.get('osm_names') or [])
ignore=[]
for n in C['notes']['not_road_tolls']: ignore.append({"osm_name":n['osm_name'],"lat":n['lat'],"lon":n['lon'],"reason":n['verdict']})
ignore+=[{"osm_name":"(unnamed 3.01,101.49)","lat":3.00937,"lon":101.48722,"reason":"Booths on a highway=construction way: future WCE Section 3 plaza (opening expected 2027). No fare yet."},
 {"osm_name":"(unnamed 3.07,101.42)","lat":3.07467,"lon":101.42143,"reason":"60 m from NNKSB 'Plaza Tol Kapar' mainline plaza; probably an extra booth node of it. Not priced separately to avoid double charging."},
 {"osm_name":"Plaza Tol Jelapang","lat":4.66638,"lon":101.07268,"reason":"PLUS plaza next to Ipoh Utara; not in the official PLUS calculator. Unpriced - verify (may be an old/merged Ipoh Utara booth)."}]
for n,la,lo in [("(unnamed 2.21,102.24)",2.20522,102.24061),("(unnamed 2.21,102.25)",2.21407,102.24669),("(unnamed 2.22,102.24)",2.21635,102.24427),("(unnamed 3.2,101.79)",3.20155,101.78908),("(unnamed 4.06,103.31)",4.06376,103.31396),("(unnamed 4.3,101.25)",4.29802,101.2522)]:
    ignore.append({"osm_name":n,"lat":la,"lon":lo,"reason":"Unidentified unnamed booth; no toll found for this location. Not priced - verify."})
used|={i['osm_name'] for i in ignore}
for p in OSM:
    if p['name'] in used: continue
    if p['name']=='ERP' or p['lat']<1.47 and p['lon']<103.95 and p['lat']<1.45:
        ignore.append({"osm_name":p['name'],"lat":p['lat'],"lon":p['lon'],"reason":"Singapore (ERP gantry / Sentosa) - outside Malaysia."}); used.add(p['name']) if p['name']!='ERP' else None; continue
unmatched=[p for p in OSM if p['name'] not in used and p['name']!='ERP' and not (p['lat']<1.45)]
out={"updated":"2026-10-22","currency":"MYR",
 "notes":("Class 1 (private car) and motorcycle tolls for Malaysia. 'plazas' are open-system fixed charges: charge 'car' each time the route passes the plaza "
  "(only in charged_heading_deg +/- ~60 deg when both_directions is false). 'closed' systems: the first gate the route passes is the entry, the next gate of the same system is the exit; "
  "look up pairs[from=entry,to=exit] exactly (not always symmetric). If the route passes a single gate of a system and a from==to pair exists, that is its fixed charge. "
  "If a pair is missing, use car_per_km x road km between the gates (approximate; flag the price as estimated) and never below min_car. "
  "Motorcycles: 0 everywhere in this file - every motorcycle toll in Malaysia (Penang Bridge, Second Penang Bridge, Second Link) was abolished 2019-01-01; motorcycles are banned from SMART tunnel. "
  "No road tolls are collected in Sabah or Sarawak. Penang Bridge is modelled as PLUS gate plus-jpp (westbound only). See NOTES.md for sources and confidence."),
 "plazas":plazas,"closed":closed,"abolished":abolished,"ignore_osm":ignore}
OUTF=sys.argv[1] if len(sys.argv)>1 else os.path.join(ROOT,'tolls.json')
json.dump(out,open(OUTF,'w'),ensure_ascii=False,indent=1)
print("plazas",len(plazas),"closed",[(c['id'],len(c['gates']),len(c['pairs']),c['car_per_km']) for c in closed],"abolished",len(abolished),"ignore",len(ignore))
print("UNMATCHED", [(p['name'],p['lat'],p['lon'],p['roads']) for p in unmatched])
from collections import Counter
print(Counter(p['confidence'] for p in plazas))
ids=[p['id'] for p in plazas]+[g['id'] for c in closed for g in c['gates']]; print('dup ids',[k for k,v in Counter(ids).items() if v>1])
osmdup=Counter(n for p in plazas for n in p['osm_names'])+Counter(n for c in closed for g in c['gates'] for n in g.get('osm_names',[])); print('osm dup',[k for k,v in osmdup.items() if v>1])
