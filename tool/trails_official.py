#!/usr/bin/env python3
"""Bike-allowed trails published by national parks, national forests, states, counties and cities.

Searches ArcGIS Online (public layers, no account) for trail line layers, keeps the trails that allow bikes
(a "bike / bicycle / mtb" column saying yes, or a layer that is about bike paths), and joins the pieces of the
same trail into one route. Writes the same records as tool/osm_routes.py plus 'source' and 'url'.

    python3 tool/trails_official.py out.json [report.txt]
    python3 tool/trails_official.py            (self-test)
"""
import hashlib
import json
import re
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from osm_routes import MAX_KM, hav, join, simplify  # noqa: E402

UA = {'User-Agent': 'MOBIlityBot/1.0 (bike routes for a cycling map; github.com/terminatoru86/mobility-app)'}
TERMS = ['"national park" trails', '"national forest" trails', 'NPS trails', 'forest service trails', 'state park trails',
         '"bike trails"', '"bicycle trails"', '"mountain bike trails"', 'greenway', '"shared use path"', '"multi-use trail"',
         '"rail trail"', '"bike paths"', '"park trails"', '"county trails"', 'trails open data',
         '"motorcycle routes"', '"motorcycle trails"', '"scenic byways"', '"off highway motorcycle"', '"OHV trails"',
         # historic routes in cities and around landmarks, published by city / county / park administrations
         '"historic bike route"', '"heritage bike route"', '"history bike tour"', '"historic bike tour"', '"heritage trail"',
         '"history trail"', '"historic trail"', '"heritage corridor"', '"cultural trail"', '"bike tour"', '"cycling tour"',
         '"auto tour route"', '"historic route"', '"national historic trail"', '"historic byway"', '"heritage route"']
LAYER_OK = re.compile(r'trail|greenway|bikeway|bike\s*(path|route|tour|lane|loop|way)|shared[\s-]*use|multi-?use|rail[\s-]*trail|cycle|bicycle|mtb|tour|'
                      r'heritage|historic\s*(route|byway)|byway|'
                      r'motorcycle|motorbike|dirt\s*bike|ohv|off-?highway|scenic\s*byway', re.I)
LAYER_BAD = re.compile(r'propos|planned|plan\b|future|closed|abandon|survey|count|demand|crash|heat|study|draft|\btests?\b|copy|'
                       r'sample|training|demo|trailhead|parking|sign|bridge|access\s*point|restroom|campground|'
                       r'histor\w*\s*(sites?|districts?|buildings?|landmarks?|propert\w*|markers?|structures?|places?)|'
                       r'horse|equestrian|ski|snow|water|paddle|canoe', re.I)
BIKE_LAYER = re.compile(r'(?<!motor)(?<!dirt )(?<!dirt)(?:bike|bicycle|cycl)|mtb|multi-?use|shared[\s-]*use|greenway|rail[\s-]*trail', re.I)
BIKE_FIELD = re.compile(r'(?<!motor)(?<!dirt)(?:bike|bicycle|cycl|biking)|mtb', re.I)
MOTO_LAYER = re.compile(r'motorcycle|motorbike|dirt\s*bike|scenic\s*byway|off-?highway\s*motorcycle|auto\s*tour|'
                        r'historic\s*(route|byway|highway)|heritage\s*(route|byway|highway)|national\s*historic\s*trail', re.I)
MOTO_FIELD = re.compile(r'motorcycle|motorbike|dirt\s*bike', re.I)
YES = {'y', 'yes', 'true', '1', 'open', 'allowed', 'managed', 'permitted', 'designated', 'accepted'}
NAME_FIELDS = ('trail_name', 'trailname', 'trlname', 'trail_nm', 'name', 'trail', 'label', 'route_name', 'pathname', 'segment_name', 'full_name')
# layers the search does not find, added by hand (url, where, layer text, source, owner)
FIXED = [
    ('https://services2.arcgis.com/CyVvlIiUfRBmMQuu/arcgis/rest/services/Bikeways_and_Trails/FeatureServer/0', "STATUS='Active'",
     'Bikeways and Trails', 'Bikeways and Trails · City of Virginia Beach', 'City of Virginia Beach'),
    ('https://services2.arcgis.com/CyVvlIiUfRBmMQuu/arcgis/rest/services/Bikeways_and_Trail_Facilities/FeatureServer/0', '1=1',
     'Bikeways and Trail Facilities', 'Bikeways and Trail Facilities · City of Virginia Beach', 'City of Virginia Beach'),
    # Arlington TX: sent by the city in answer to our records request (Hike and Bike off-street + on-street)
    ('https://gis2.arlingtontx.gov/agsext2/rest/services/External/NeighborhoodAmenity/MapServer/6', '1=1',
     'Hike and Bike trails', 'Hike and Bike · City of Arlington TX', 'City of Arlington TX'),
    # Madison WI: sent by the Greater Madison MPO (bike map service; planned facilities are filtered by LAYER_BAD names)
    ('https://maps.cityofmadison.com/arcgis/rest/services/MPO/BicycleMap_Pro/MapServer', '1=1',
     'Madison bike map', 'Bike map · City of Madison WI', 'City of Madison WI'),
    # Phoenix AZ: the city pointed us to its records portal; its existing bikeways are public on the city map server
    ('https://maps.phoenix.gov/pub/rest/services/Public/STR_Bikeways/MapServer/0', '1=1',
     'Bikeways', 'Existing bikeways · City of Phoenix AZ', 'City of Phoenix AZ'),
    # Florida: cities (e.g. Rockledge) answered that FDOT keeps the bike lanes on state roads; FDOT publishes them
    ('https://gis.fdot.gov/arcgis/rest/services/RCI_Layers/FeatureServer/28', '1=1',
     'Bike Lanes', 'Bike lanes on state roads · Florida DOT', 'Florida DOT'),
    ('https://services1.arcgis.com/O1JpcwDW8sjYuddV/ArcGIS/rest/services/USBikeRoutesFlorida/FeatureServer/0', '1=1',
     'US Bike Routes Florida', 'US Bike Routes · Florida DOT', 'Florida DOT'),
    # Topeka KS: the city answered our KORA request with the bikeways plan; the city map server has the bikeways layer
    ('https://maps.topeka.gov/arcgis/rest/services/LandUsePlanning/Bikeways/MapServer', '1=1',
     'Topeka bikeways', 'Bikeways · City of Topeka KS', 'City of Topeka KS'),
    # Kansas DOT statewide bike map (routes, lanes, paths; future layers are dropped by LAYER_BAD)
    ('https://kanplan.ksdot.gov/arcgis_web_adaptor/rest/services/Bike/Kansas_Bikeways/MapServer', '1=1',
     'Kansas bikeways', 'Kansas bikeways · Kansas DOT', 'Kansas DOT'),
    # Iowa DOT pathway asset layer (bike lanes); Ames and other Iowa cities pointed us to plans only
    ('https://gis.iowadot.gov/agshost/rest/services/RAMS/PathwayBikeLanes/MapServer', '1=1',
     'Iowa bike lanes', 'Bike lanes · Iowa DOT', 'Iowa DOT'),
]


def http(url, timeout=90):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
        return r.read()


def _yes(v):
    v = str(v).strip().lower()
    return v in YES or v.startswith('yes')


def kinds_of(props, layer_text):
    """Which vehicles this trail piece is for: 'bicycle' and / or 'motorcycle'. A column saying yes decides; without a
    column, the layer itself has to be about bike paths (or motorcycle routes)."""
    out = set()
    for f in props:
        if BIKE_FIELD.search(f) and _yes(props.get(f)):
            out.add('bicycle')
        if MOTO_FIELD.search(f) and _yes(props.get(f)):
            out.add('motorcycle')
    if not any(BIKE_FIELD.search(f) or MOTO_FIELD.search(f) for f in props):
        if BIKE_LAYER.search(layer_text):
            out.add('bicycle')
        if MOTO_LAYER.search(layer_text):
            out.add('motorcycle')
    return out


def name_of(props):
    low = {k.lower(): v for k, v in props.items()}
    for k in NAME_FIELDS:
        v = low.get(k)
        if v and str(v).strip() and str(v).strip().lower() not in ('null', 'none', 'unnamed', 'n/a'):
            return str(v).strip()
    return None


def routes_from(features, layer_text, source, url, owner=''):
    """features: [(props, [paths])] -> one record per trail name."""
    by = {}
    for props, paths in features:
        n = name_of(props)
        if n:
            for kd in kinds_of(props, layer_text):
                by.setdefault((n.title() if n.isupper() else n, kd), []).extend(paths)
    out = []
    for (n, kd), ways in by.items():
        lines = [simplify(l) for l in join([list(w) for w in ways])]
        km = sum(hav(l[i], l[i + 1]) for l in lines for i in range(len(l) - 1))
        if km < 1 or km >= MAX_KM:
            continue
        out.append({'id': 'a/' + hashlib.md5((url + n + kd).encode()).hexdigest()[:12], 'name': n, 'ref': None, 'kind': kd,
                    'network': None, 'operator': owner or source, 'km': round(km, 1), 'tags': {}, 'source': source, 'url': url,
                    'lines': [[round(c, 5) for p in l for c in p] for l in lines]})
    return out


def layer_features(url, where='1=1'):
    feats, offset = [], 0
    for _ in range(60):
        q = urllib.parse.urlencode({'where': where, 'outFields': '*', 'outSR': '4326', 'returnGeometry': 'true',
                                    'geometryPrecision': 5, 'f': 'json', 'resultOffset': offset})
        j = json.loads(http(f'{url}/query?{q}', timeout=120))
        if j.get('error'):
            break
        fs = j.get('features') or []
        for f in fs:
            paths = [[(y, x) for x, y in p] for p in (f.get('geometry') or {}).get('paths') or [] if len(p) > 1]
            if paths:
                feats.append((f.get('attributes') or {}, paths))
        if not fs or not j.get('exceededTransferLimit'):
            break
        offset += len(fs)
    return feats


def discover(minutes=60):
    out, seen, log = [], set(), []
    end = time.time() + 60 * minutes
    expanded = []
    for lurl, where, text, source, owner in FIXED:
        if lurl.rstrip('/').endswith(('MapServer', 'FeatureServer')):  # a whole service: its line layers about bikes
            try:
                info = json.loads(http(f'{lurl}?f=json', timeout=40))
                for ly in info.get('layers') or []:
                    nm = ly.get('name') or ''
                    if LAYER_OK.search(nm) and not LAYER_BAD.search(nm):
                        expanded.append((f"{lurl.rstrip('/')}/{ly['id']}", where, f'{nm} {text}', source, owner))
            except Exception as err:
                log.append(f'FAILED {lurl}: {str(err)[:80]}')
        else:
            expanded.append((lurl, where, text, source, owner))
    for lurl, where, text, source, owner in expanded:
        seen.add(lurl.rsplit('/', 1)[0])
        try:
            recs = routes_from(layer_features(lurl, where), text, source, lurl, owner)
            log.append(f'{len(recs):5d} routes  {lurl}  [{source}] (fixed)')
            out += recs
        except Exception as err:
            log.append(f'FAILED {lurl}: {str(err)[:80]}')
    for t in TERMS:
        for start in range(1, 601, 100):
            if time.time() > end:
                break
            q = urllib.parse.urlencode({'q': f'{t} AND (type:"Feature Service" OR type:"Map Service")', 'num': 100, 'start': start,
                                        'bbox': '-170,17,-65,72', 'f': 'json', 'sortField': 'numviews', 'sortOrder': 'desc'})
            try:
                j = json.loads(http(f'https://www.arcgis.com/sharing/rest/search?{q}', timeout=60))
            except Exception as err:
                print(f'  search {t} failed: {str(err)[:100]}', flush=True)
                break
            for it in j.get('results', []):
                url = (it.get('url') or '').rstrip('/')
                title = it.get('title') or ''
                if not url or url in seen or LAYER_BAD.search(title) or time.time() > end:
                    continue
                seen.add(url)
                try:
                    info = json.loads(http(f'{url}?f=json', timeout=40))
                except Exception:
                    continue
                for ly in info.get('layers') or []:
                    name = ly.get('name') or ''
                    if ly.get('geometryType') != 'esriGeometryPolyline' or LAYER_BAD.search(name):
                        continue
                    if not (LAYER_OK.search(name) or (LAYER_OK.search(title) and len(info['layers']) == 1)):
                        continue
                    lurl = f"{url}/{ly['id']}"
                    try:
                        recs = routes_from(layer_features(lurl), f'{name} {title}', f'{title} · {it.get("owner", "")}'[:90], lurl,
                                           it.get('owner', ''))
                    except Exception as err:
                        log.append(f'FAILED {lurl}: {str(err)[:80]}')
                        continue
                    log.append(f'{len(recs):5d} routes  {lurl}  [{title[:50]}]')
                    out += recs
            if len(j.get('results', [])) < 100:
                break
            time.sleep(1)
    return out, log


def selftest():
    A = [(41.0 + i * 0.002, -87.0) for i in range(8)]
    feats = [({'TRAIL_NAME': 'LAKE LOOP', 'BIKE': 'Yes'}, [A[:4], A[3:]]), ({'TRAIL_NAME': 'Hiker Only', 'BIKE': 'No'}, [A]),
             ({'NAME': 'No column', 'x': 1}, [A])]
    r = routes_from(feats, 'Park trails', 'Test', 'http://x/0')
    assert [(x['name'], x['kind']) for x in r] == [('Lake Loop', 'bicycle')], r          # bike column decides; layer without one is not bike-only
    assert r[0]['km'] > 1.4 and len(r[0]['lines']) == 1
    r2 = routes_from([({'NAME': 'Greenway A'}, [A])], 'Greenway', 'Test', 'http://x/1')
    assert len(r2) == 1                                          # no column, but the layer is a greenway layer
    far = [(41.0 + i * 0.01, -87.0) for i in range(8)]  # 7.7 km
    m = routes_from([({'NAME': 'Dirt Loop', 'MOTORCYCLE': 'Yes', 'BIKE': 'No'}, [far])], 'Forest trails', 'T', 'http://x/2')
    assert [(x['name'], x['kind']) for x in m] == [('Dirt Loop', 'motorcycle')], m
    long_ = [(41.0 + i * 0.1, -87.0) for i in range(8)]  # 78 km: city to city, left out
    assert not routes_from([({'NAME': 'Long', 'BIKE': 'Yes'}, [long_])], 'Trails', 'T', 'http://x/3')
    assert not LAYER_OK.search('Parking lots') and LAYER_BAD.search('Proposed trails') and LAYER_BAD.search('Trailheads')
    print('self-test ok')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        selftest()
    else:
        recs, log = discover()
        json.dump(recs, open(sys.argv[1], 'w', encoding='utf-8'), separators=(',', ':'), ensure_ascii=False)
        if len(sys.argv) > 2:
            open(sys.argv[2], 'w', encoding='utf-8').write('\n'.join(log))
        print(f'{len(recs)} trails from {len(log)} layers')
