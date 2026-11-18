#!/usr/bin/env python3
"""Bicycle and mountain-bike route relations (with their lines) from a Geofabrik OpenStreetMap extract.

    osmium tags-filter region.osm.pbf r/route=bicycle,mtb -o routes.osm.pbf     (done by the workflow)
    python3 tool/osm_routes.py routes.osm.pbf out.json

Writes [{id, name, ref, kind, network, operator, km, tags:{...}, lines:[[lat,lon,lat,lon,...], ...]}, ...]
Lines are joined end to end and simplified (about 20 m), coordinates with 5 decimals.
Needs: pip install osmium (only to read the file; the geometry part below needs nothing).
"""
import json
import math
import sys

KEEP = ('name', 'ref', 'network', 'operator', 'distance', 'description', 'website', 'surface', 'from', 'to',
        'wikipedia', 'wikidata', 'colour', 'symbol', 'ascent', 'cycle_network', 'complete', 'state', 'ele')


def hav(a, b):
    r = 6371.0088
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp, dl = p2 - p1, math.radians(b[1] - a[1])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def join(ways):
    """Ways (lists of (lat, lon)) joined end to end into as few lines as possible."""
    ways = [w for w in ways if len(w) > 1]
    lines = []
    while ways:
        line = list(ways.pop(0))
        grown = True
        while grown:
            grown = False
            for i, w in enumerate(ways):
                if w[0] == line[-1]:
                    line += w[1:]
                elif w[-1] == line[-1]:
                    line += w[-2::-1]
                elif w[-1] == line[0]:
                    line = w[:-1] + line
                elif w[0] == line[0]:
                    line = w[:0:-1] + line
                else:
                    continue
                ways.pop(i)
                grown = True
                break
        lines.append(line)
    return lines


def simplify(pts, tol_km=0.02):
    """Douglas-Peucker, iterative (long routes would overflow the recursion limit)."""
    if len(pts) < 3:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    k = math.cos(math.radians(pts[0][0]))
    while stack:
        a, b = stack.pop()
        ax, ay, bx, by = pts[a][1] * k, pts[a][0], pts[b][1] * k, pts[b][0]
        dx, dy = bx - ax, by - ay
        ln = dx * dx + dy * dy
        far, idx = 0.0, None
        for i in range(a + 1, b):
            px, py = pts[i][1] * k, pts[i][0]
            if ln == 0:
                d = math.hypot(px - ax, py - ay)
            else:
                t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / ln))
                d = math.hypot(px - ax - t * dx, py - ay - t * dy)
            if d > far:
                far, idx = d, i
        if idx is not None and far * 111.2 > tol_km:
            keep[idx] = True
            stack += [(a, idx), (idx, b)]
    return [p for p, f in zip(pts, keep) if f]


def build(tags, ways):
    """One route: its tags and the geometry of its ways -> the record, or None when it is too small."""
    lines = [simplify(l) for l in join([list(w) for w in ways])]
    km = sum(hav(l[i], l[i + 1]) for l in lines for i in range(len(l) - 1))
    if km < 1 or not (tags.get('name') or tags.get('ref')):
        return None
    t = {k: v for k, v in tags.items() if k in KEEP}
    return {'name': tags.get('name') or tags.get('ref'), 'ref': tags.get('ref'), 'kind': tags.get('route'),
            'network': tags.get('network'), 'operator': tags.get('operator'), 'km': round(km, 1), 'tags': t,
            'lines': [[round(c, 5) for p in l for c in p] for l in lines]}


def main(src, dst):
    import osmium

    class Rels(osmium.SimpleHandler):
        def __init__(self):
            super().__init__()
            self.rels = {}

        def relation(self, r):
            t = dict(r.tags)
            if t.get('route') in ('bicycle', 'mtb') and t.get('type') == 'route':
                self.rels[r.id] = (t, [m.ref for m in r.members if m.type == 'w'])

    class Ways(osmium.SimpleHandler):
        def __init__(self, need):
            super().__init__()
            self.need, self.geom = need, {}

        def way(self, w):
            if w.id in self.need:
                self.geom[w.id] = [(n.lat, n.lon) for n in w.nodes if n.location.valid()]

    a = Rels()
    a.apply_file(src)
    need = {w for _, ws in a.rels.values() for w in ws}
    b = Ways(need)
    b.apply_file(src, locations=True)
    out = []
    for rid, (t, ws) in a.rels.items():
        rec = build(t, [b.geom[w] for w in ws if w in b.geom])
        if rec:
            rec['id'] = f'r/{rid}'
            out.append(rec)
    json.dump(out, open(dst, 'w', encoding='utf-8'), separators=(',', ':'), ensure_ascii=False)
    print(f'{len(out)} routes from {len(a.rels)} relations')


def selftest():
    # two ways that meet, one that has to be turned round, and a far spur
    w1 = [(41.0, -87.0), (41.01, -87.0), (41.02, -87.0)]
    w2 = [(41.04, -87.0), (41.03, -87.0), (41.02, -87.0)]
    assert len(join([w1, w2])) == 1
    r = build({'route': 'bicycle', 'name': 'Test', 'network': 'rcn'}, [w1, w2])
    assert r and 4.3 < r['km'] < 4.6, r
    assert build({'route': 'bicycle', 'name': 'Tiny'}, [[(41.0, -87.0), (41.0001, -87.0)]]) is None
    assert build({'route': 'bicycle'}, [w1, w2]) is None  # no name or ref
    zig = [(41.0 + i * 0.0001, -87.0 + (0.000001 if i % 2 else 0)) for i in range(2000)]
    assert len(simplify(zig)) < 5
    print('self-test ok')


if __name__ == '__main__':
    selftest() if len(sys.argv) < 3 else main(sys.argv[1], sys.argv[2])
