import osmium, pickle, sys
class H(osmium.SimpleHandler):
    def __init__(s):
        super().__init__(); s.ms=[]; s.sig=[]; s.ways=[]; s.extra={}
    def node(s,n):
        t=n.tags
        if t.get('highway')=='milestone' or ('distance' in t and t.get('highway') in (None,'milestone')) :
            s.ms.append((n.id,n.location.lat,n.location.lon,dict(t)))
        elif t.get('highway')=='traffic_signals':
            s.sig.append((n.id,n.location.lat,n.location.lon))
    def way(s,w):
        h=w.tags.get('highway')
        if h in ('motorway','trunk','primary','secondary','motorway_link','trunk_link','primary_link'):
            try: g=[(nd.lat,nd.lon,nd.ref) for nd in w.nodes]
            except Exception: return
            s.ways.append((w.id,h,w.tags.get('ref',''),w.tags.get('name',''),w.tags.get('oneway',''),g)); s.extra[w.id]=(w.tags.get('maxspeed',''),w.tags.get('tunnel',''),w.tags.get('bridge',''))
h=H(); h.apply_file(sys.argv[1],locations=True)
pickle.dump({'ms':h.ms,'sig':h.sig,'ways':h.ways,'extra':h.extra},open(sys.argv[2],'wb'))
print(len(h.ms),len(h.sig),len(h.ways))
