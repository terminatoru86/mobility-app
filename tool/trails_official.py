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
from osm_routes import hav, join, simplify  # noqa: E402

UA = {'User-Agent': 'MOBIlityBot/1.0 (bike routes for a cycling map; github.com/terminatoru86/mobility-app)'}
TERMS = ['"national park" trails', '"national forest" trails', 'NPS trails', 'forest service trails', 'state park trails',
         '"bike trails"', '"bicycle trails"', '"mountain bike trails"', 'greenway', '"shared use path"', '"multi-use trail"',
         '"rail trail"', '"bike paths"', '"park trails"', '"county trails"', 'trails open data']
LAYER_OK = re.compile(r'trail|greenway|bikeway|bike\s*path|shared[\s-]*use|multi-?use|rail[\s-]*trail|cycle|bicycle|mtb', re.I)
LAYER_BAD = re.compile(r'propos|planned|plan\b|future|closed|abandon|survey|count|demand|crash|heat|study|draft|\btests?\b|copy|'
                       r'sample|training|demo|trailhead|parking|sign|bridge|access\s*point|restroom|campground|history|historic|'
                       r'horse|equestrian|ski|snow|water|paddle|canoe', re.I)
BIKE_LAYER = re.compile(r'bike|bicycle|cycl|mtb|multi-?use|shared[\s-]*use|greenway|rail[\s-]*trail', re.I)
BIKE_FIELD = re.compile(r'bike|bicycle|cycl|mtb|biking', re.I)
YES = {'y', 'yes', 'true', '1', 'open', 'allowed', 'managed', 'permitted', 'designated', 'accepted'}
NAME_FIELDS = ('trail_name', 'trailname', 'trlname', 'trail_nm', 'name', 'trail', 'label', 'route_name', 'pathname')


def http(url, timeout=90):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
        return r.read()


def keeps(fields, props, layer_text):
    """Does this trail piece allow bikes? A bike column decides; without one, the layer itself has to be about bike paths."""
    cols = [f for f in props if BIKE_FIELD.search(f)]
    if cols:
        return any(str(props.get(c)).strip().lower() in YES or str(props.get(c)).strip().lower().startswith('yes') for c in cols)
    return bool(BIKE_LAYER.search(layer_text))


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
        if n and keeps(None, props, layer_text):
            by.setdefault(n.title() if n.isupper() else n, []).extend(paths)
    out = []
    for n, ways in by.items():
        lines = [simplify(l) for l in join([list(w) for w in ways])]
        km = sum(hav(l[i], l[i + 1]) for l in lines for i in range(len(l) - 1))
        if km < 1:
            continue
        out.append({'id': 'a/' + hashlib.md5((url + n).encode()).hexdigest()[:12], 'name': n, 'ref': None, 'kind': 'bicycle',
                    'network': None, 'operator': owner or source, 'km': round(km, 1), 'tags': {}, 'source': source, 'url': url,
                    'lines': [[round(c, 5) for p in l for c in p] for l in lines]})
    return out


def layer_features(url):
    feats, offset = [], 0
    for _ in range(60):
        q = urllib.parse.urlencode({'where': '1=1', 'outFields': '*', 'outSR': '4326', 'returnGeometry': 'true',
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
    assert [x['name'] for x in r] == ['Lake Loop'], r          # bike column decides; layer without one is not bike-only
    assert r[0]['km'] > 1.4 and len(r[0]['lines']) == 1
    r2 = routes_from([({'NAME': 'Greenway A'}, [A])], 'Greenway', 'Test', 'http://x/1')
    assert len(r2) == 1                                          # no column, but the layer is a greenway layer
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
