"""From one Geofabrik extract (cut by the workflow): every NAMED path or track that bikes / e-scooters or motorcycles
may use (greenways, park and forest paths, MTB trails, OHV / dirt-bike tracks), joined into routes, plus the sights
riders see along the way (canyons, waterfalls, peaks, lakes, bridges, lighthouses, monuments, statues, museums,
viewpoints...).

  python3 tool/bike_paths.py --test
  python3 tool/bike_paths.py cut.osm.pbf paths.json sights.json

Walking-only paths are left out: a footway / path / bridleway counts only when bicycle=yes|designated|permissive
(or mtb:scale), a track only when bicycle or motorcycle is allowed; bicycle=no / dismount never counts.
Routes are 1 to 50 km (a route that goes from one town to another, 50 km or more, is not wanted).
"""
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from osm_routes import hav, join, simplify  # noqa: E402

OK = ('yes', 'designated', 'permissive')
NOT_RIDE = re.compile(r'\b(canoe|kayak|paddl\w*|water\s*trail|portage|horse\s*(trail|path|camp|loop)|horse/|/horse|equestrian|bridle|snowmobile|ski\s*trail|nordic|snowshoe|'
                      r'nature\s*walk|walking\s*(trail|path)|foot\s*path|stairs?|steps)\b', re.I)


def kind_of(t):
    """'bicycle', 'mtb' or 'motorcycle' for a way riders may use, or None (walking only, private, cars...)."""
    hw = t.get('highway')
    if t.get('access') in ('private', 'no') or t.get('bicycle') in ('no', 'dismount') and t.get('motorcycle') not in OK:
        return None
    if NOT_RIDE.search(t.get('name') or ''):
        return None
    if hw == 'track' or (hw == 'path' and t.get('motorcycle') in OK):
        if t.get('motorcycle') in OK or t.get('atv') in OK or t.get('motor_vehicle') in OK:
            return 'motorcycle'
        if t.get('bicycle') in OK or t.get('mtb:scale'):
            return 'mtb'
        return None
    if hw == 'cycleway':
        return 'bicycle'
    if hw in ('path', 'footway', 'bridleway', 'pedestrian'):
        if t.get('mtb:scale') or t.get('mtb') in OK:
            return 'mtb'
        if t.get('bicycle') in OK:
            return 'bicycle'
    return None


# ── sights along the way ──
def sight_of(t):
    """(kind, how far it is seen in m) for a landmark, or None."""
    name = t.get('name')
    if not name:
        return None
    big = bool(t.get('wikidata') or t.get('wikipedia'))
    tour, hist, nat, mm = t.get('tourism'), t.get('historic'), t.get('natural'), t.get('man_made')
    if nat in ('valley', 'gorge', 'canyon') or re.search(r'\bcanyon\b|\bgorge\b', name, re.I) and nat:
        return ('canyon', 3000 if big else 1500)
    if nat == 'waterfall' or t.get('waterway') == 'waterfall':
        return ('waterfall', 800)
    if nat in ('peak', 'volcano'):
        return ('peak', 5000) if big else None
    if nat in ('arch', 'cliff', 'rock', 'stone', 'cave_entrance'):
        return ('rock', 600)
    if nat == 'water' and big:
        return ('lake', 800)
    if nat in ('beach', 'bay') and big:
        return ('beach', 600)
    if mm == 'lighthouse' or hist == 'lighthouse':
        return ('lighthouse', 2000)
    if mm in ('tower', 'observation_tower') and (big or t.get('tower:type') == 'observation'):
        return ('tower', 2000)
    if (mm == 'bridge' or t.get('bridge:name')) and big:
        return ('bridge', 1500)
    if hist in ('monument', 'memorial', 'castle', 'fort', 'ruins', 'battlefield', 'ship', 'aircraft', 'locomotive', 'mine', 'building'):
        if hist == 'memorial' and not big:
            return None
        return ('monument', 3000 if big else 300)
    if tour in ('artwork',) and big:
        return ('statue', 2000)
    if tour == 'viewpoint':
        return ('viewpoint', 300)
    if tour in ('museum', 'zoo', 'aquarium', 'theme_park', 'attraction'):
        return ('attraction', 2500 if big else 300)
    return None


def run(pbf, out_paths, out_sights):
    import osmium
    paths, sights = {}, []

    class H(osmium.SimpleHandler):
        def node(self, n):
            if n.tags and n.location.valid():
                s = sight_of(dict(n.tags))
                if s:
                    sights.append([round(n.location.lat, 5), round(n.location.lon, 5), n.tags.get('name'), s[0], s[1]])

        def way(self, w):
            t = dict(w.tags)
            pts = [(nd.lat, nd.lon) for nd in w.nodes if nd.location.valid()]
            if len(pts) < 2:
                return
            if t.get('highway'):
                k = kind_of(t)
                name = t.get('name')
                if k and name:
                    p = paths.setdefault((name, k), {'ids': [], 'ways': [], 'tags': {}})
                    p['ids'].append(w.id)
                    p['ways'].append(pts)
                    for x in ('surface', 'operator', 'website', 'lit', 'mtb:scale', 'smoothness'):
                        if t.get(x) and x not in p['tags']:
                            p['tags'][x] = t[x]
                return
            s = sight_of(t)
            if s:
                sights.append([round(sum(p[0] for p in pts) / len(pts), 5), round(sum(p[1] for p in pts) / len(pts), 5),
                               t.get('name'), s[0], s[1]])

    H().apply_file(pbf, locations=True)
    routes = []
    for (name, kind), p in paths.items():
        lines = [simplify(l) for l in join(p['ways'])]
        groups = []
        for l in lines:  # the same name in two far-apart places is two routes
            for g in groups:
                if min(hav(l[0], x[0]) for x in g) < 15 or min(hav(l[-1], x[-1]) for x in g) < 15:
                    g.append(l)
                    break
            else:
                groups.append([l])
        for gi, g in enumerate(groups):
            km = sum(hav(l[i - 1], l[i]) for l in g for i in range(1, len(l)))
            if km < 1 or km >= 50:
                continue
            routes.append({'id': f'p/{p["ids"][0]}' + (f'-{gi}' if gi else ''), 'name': name, 'ref': None, 'kind': kind,
                           'network': None, 'operator': p['tags'].get('operator'), 'km': round(km, 1),
                           'tags': {k: v for k, v in p['tags'].items() if k != 'operator'},
                           'lines': [[round(v, 5) for pt in l for v in pt] for l in g]})
    json.dump(routes, open(out_paths, 'w'), separators=(',', ':'))
    json.dump(sights, open(out_sights, 'w'), separators=(',', ':'))
    by = {}
    for r in routes:
        by[r['kind']] = by.get(r['kind'], 0) + 1
    print(f'{pbf}: {len(routes)} named paths for riders {by}, {len(sights)} sights', flush=True)


def test():
    assert kind_of({'highway': 'cycleway', 'name': 'Riverwalk'}) == 'bicycle'
    assert kind_of({'highway': 'footway', 'name': 'Park Path'}) is None                       # walking only
    assert kind_of({'highway': 'path', 'bicycle': 'designated', 'name': 'Greenway'}) == 'bicycle'
    assert kind_of({'highway': 'path', 'mtb:scale': '2', 'name': 'Ridge Trail'}) == 'mtb'
    assert kind_of({'highway': 'track', 'motorcycle': 'yes', 'name': 'Forest Road 12'}) == 'motorcycle'
    assert kind_of({'highway': 'track', 'name': 'Farm Track'}) is None
    assert kind_of({'highway': 'path', 'bicycle': 'yes', 'name': 'Honker Divide Canoe Route'}) is None
    assert kind_of({'highway': 'cycleway', 'bicycle': 'dismount', 'name': 'Plaza'}) is None
    assert sight_of({'name': 'Statue of Liberty', 'tourism': 'attraction', 'wikidata': 'Q9202'})[0] == 'attraction'
    assert sight_of({'name': 'Black Canyon', 'natural': 'valley'})[0] == 'canyon'
    assert sight_of({'name': 'Hill 402', 'natural': 'peak'}) is None
    print('rules ok')


if __name__ == '__main__':
    test()
    if len(sys.argv) >= 4:
        run(sys.argv[1], sys.argv[2], sys.argv[3])
