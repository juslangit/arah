import os, sys, urllib.request, urllib.parse, re, json, concurrent.futures as cf
P=["Karak","Lanchang","Temerloh","Chenor","Maran","Sri Jaya","Gambang","Kuantan","Jabor","Cheneh","Cukai","Kijal","Kertih","Paka","Kuala Dungun","Bukit Besi","Ajil","Telemung","Kuala Terengganu"]
U="https://www.afaprime.com/wp-content/toll_rate/lpt.php?action=submit"
def get(p):
    a,b=p
    data=urllib.parse.urlencode({"action":"submit","from":a,"to":b,"class":"1"}).encode()
    for i in range(3):
        try:
            t=urllib.request.urlopen(urllib.request.Request(U,data=data,headers={"User-Agent":"Mozilla/5.0"}),timeout=30).read().decode('latin1')
            m=re.search(r'TOLL RATE\s*:\s*RM\s*([0-9.]+)',re.sub(r'<[^>]+>',' ',t))
            return p,(m.group(1) if m else None)
        except Exception: pass
    return p,"ERR"
out={}
with cf.ThreadPoolExecutor(4) as ex:
    for (a,b),r in ex.map(get,[(a,b) for a in P for b in P if a!=b]): out[f"{a}|{b}"]=r
OUT=sys.argv[1] if len(sys.argv)>1 else os.path.join(os.path.dirname(os.path.abspath(__file__)),"..","raw","lpt_c1.json")
json.dump(out,open(OUT,"w"),indent=0)
print(sum(1 for v in out.values() if v not in (None,"ERR")), [k for k,v in out.items() if v in (None,"ERR")][:10])
