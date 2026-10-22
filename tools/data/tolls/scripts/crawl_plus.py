import os, json, urllib.request, concurrent.futures as cf, time, sys
codes="BTR BSR BGC BBR LKT TTP TLK TTK BSI KPS SNU SKD KLI SDK SPR MAC AHT YPS YPU BGR PGH JSN TGK AKH SAT MBU PLI SWG PDS PDU SBN KLA PTJ BSP PHT USJ SEA EBS EBN PSV SHA BDA BBN PPM BGS KJG UPM SBI BKR STA SBG DMR JLD KDR SBY HSB RWS SGB RAW BKB LBB BKW TGM BRG PSR SKI BDR TPH GPG SPP IPS JPP IPU KKS CKJ TPU BKM ALP JWI LUN KSG BCS BTS BTU JRU SGD BRT SPS SPU GRN PDG ASS ASU HKG JTR".split()
B="https://plusapp-api-prod1.azurewebsites.net/api/tolls/GetTollFare/"
cls=int(sys.argv[1]) if len(sys.argv)>1 else 1
OUT=sys.argv[2] if len(sys.argv)>2 else os.path.join(os.path.dirname(os.path.abspath(__file__)),"..","raw","plus_c1.json")
def get(p):
    a,b=p
    for i in range(4):
        try:
            r=urllib.request.urlopen(urllib.request.Request(B+f"{a}/{b}/{cls}",headers={"User-Agent":"Mozilla/5.0"}),timeout=30).read().decode().strip()
            return p,r
        except Exception as e:
            time.sleep(2*(i+1))
    return p,"ERR"
pairs=[(a,b) for a in codes for b in codes]
out={}
with cf.ThreadPoolExecutor(8) as ex:
    for (a,b),r in ex.map(get,pairs):
        out[f"{a}-{b}"]=r
json.dump(out,open(OUT,"w"))
print(len(out), sum(1 for v in out.values() if v=="ERR"), sum(1 for v in out.values() if v not in("","ERR")))
