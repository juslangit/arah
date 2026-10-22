import sys,json; sys.path.insert(0,''+__import__('os').path.dirname(__file__)+'')
from lib import *
nodes={n['id']:n for n in json.load(open('/Users/luqman/Desktop/projects/app/arah/tools/data/out/speed_cameras_osm.json'))['nodes']}
sig=D['sig']
def nsig(la,lo):
    return min((hav(la,lo,a,b),i) for i,a,b in sig if abs(a-la)<0.02 and abs(b-lo)<0.02) if any(abs(a-la)<0.02 and abs(b-lo)<0.02 for i,a,b in sig) else (None,None)
ids=[int(x) for x in sys.argv[1:]] if len(sys.argv)>1 else [i for i,n in nodes.items() if not (n['lat']<1.48 and 103.55<n['lon']<104.1)]
for i in ids:
    n=nodes[i]
    print(f"\n{i} {n['lat']},{n['lon']} name={n['name']!r} dir={n['direction']} max={n['maxspeed']} ref={n['ref']}  sig={nsig(n['lat'],n['lon'])[0] and round(nsig(n['lat'],n['lon'])[0])}m")
    for x in nearest_ways(n['lat'],n['lon'],filt=lambda w:w[1] in('motorway','trunk','primary','secondary','motorway_link','trunk_link','primary_link'),n=3):
        ex=D['extra'][x[1]]
        print('   ',x[0],'m',x[2],x[3],x[4][:40],'oneway=',x[5],'brg=',x[6],'max=',ex[0],'tun=',ex[1])
