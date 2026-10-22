import sys,json; sys.path.insert(0,''+__import__('os').path.dirname(__file__)+'')
from route import project, at
from lib import D,hav,nearest_ways,bearing
def load(f):
    d=json.load(open(f)); return [tuple(p) for p in d['pts']], d['ch']
def snap(la,lo,ref,want_brg):
    c=[x for x in nearest_ways(la,lo,filt=lambda w:w[1]=='motorway' and ref in w[2].split(';'),n=8)]
    c=[x for x in c if min(abs(x[6]-want_brg),360-abs(x[6]-want_brg))<60]
    x=c[0]; w=D['ways'][x[7]]; k=x[8]; t=x[9]; a,b=w[5][k],w[5][k+1]
    return round(a[0]+t*(b[0]-a[0]),6), round(a[1]+t*(b[1]-a[1]),6), x[6], D['extra'][w[0]], x[0], w[0]
out={}
# E2 KM 265.3 SB
pts,ch=load(__import__('os').path.join(__import__('os').environ.get('CAM_WORK',__import__('os').path.join(__import__('os').path.dirname(__file__),'..','.work')),'e2nb.json'))
la,lo,b=at(pts,ch,265450); r=snap(la,lo,'E2',(b+180)%360); print('E2 265.3 SB',r); out['e2_265.3_sb']=r
# E1 Menora
pts,ch=load(__import__('os').path.join(__import__('os').environ.get('CAM_WORK',__import__('os').path.join(__import__('os').path.dirname(__file__),'..','.work')),'e1nb.json')); L=ch[-1]
for km,off,dirn in [(258.25,1.757,'NB'),(262.5,1.737,'SB')]:
    c=L-(km-off)*1000
    la,lo,b=at(pts,ch,c)   # b is NB bearing (path is NB)
    want=b if dirn=='NB' else (b+180)%360
    r=snap(la,lo,'E1',want); print('E1',km,dirn,r); out[f'e1_{km}_{dirn}']=r
    # nearest tunnel way
    best=None
    for w in D['ways']:
        if D['extra'][w[0]][1] and 'E1' in w[2].split(';') and abs(w[5][0][0]-la)<0.05:
            dd=min(hav(la,lo,p[0],p[1]) for p in w[5])
            if best is None or dd<best[0]: best=(round(dd),w[0],D['extra'][w[0]],w[5][0][:2])
    print('   nearest E1 tunnel/bridge-flagged way',best)
json.dump(out,open(__import__('os').path.join(__import__('os').path.dirname(__file__),'..','kmplaced.json'),'w'))
