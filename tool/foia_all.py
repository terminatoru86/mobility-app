"""Where to send a public-records request in EVERY US municipality and county with an official website
(Wikidata: cities, towns, villages, boroughs, townships, counties), except the ones already written to
(data/foia/contacts.json) and Puerto Rico. For each site reads the records / clerk pages (tool/foia_contacts.city)
and keeps request e-mails and portals.

    SHARD=0 NSHARDS=20 python3 tool/foia_all.py find   -> data/foia/all/part_<SHARD>.json
    python3 tool/foia_all.py merge                    -> data/foia/all.json + data/foia/ALL.md
"""
import concurrent.futures as cf
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from foia_contacts import city as find_contacts  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'data', 'foia', 'all')
TYPES = ['Q1093829', 'Q15127012', 'Q3301053', 'Q15284', 'Q47168', 'Q2154459', 'Q751708']
Q = """SELECT ?c ?cLabel ?site ?coord ?type (MAX(?pop) AS ?p) WHERE {
  VALUES ?type { wd:%s }
  ?c wdt:P31 ?type ; wdt:P17 wd:Q30 ; wdt:P856 ?site ; wdt:P625 ?coord .
  OPTIONAL { ?c wdt:P1082 ?pop }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
} GROUP BY ?c ?cLabel ?site ?coord ?type"""
COUNTY = {'http://www.wikidata.org/entity/Q47168'}
TOWN = {'http://www.wikidata.org/entity/Q15127012', 'http://www.wikidata.org/entity/Q751708',
        'http://www.wikidata.org/entity/Q4421'}


def host(u):
    h = urllib.parse.urlparse(u if '//' in u else '//' + u).netloc.lower()
    return re.sub(r'^www\.', '', h)


STATES = None


def state_of(lat, lon):
    global STATES
    if STATES is None:
        g = json.load(open(os.path.join(ROOT, 'data', 'us_states.json')))
        STATES = [(f['properties'].get('name') or f['properties'].get('NAME'), f['geometry']) for f in g['features']]

    def inside(poly, x, y):
        ok = False
        for ring in poly:
            j = len(ring) - 1
            for i in range(len(ring)):
                xi, yi = ring[i][0], ring[i][1]
                xj, yj = ring[j][0], ring[j][1]
                if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
                    ok = not ok
                j = i
        return ok
    for name, geo in STATES:
        polys = geo['coordinates'] if geo['type'] == 'MultiPolygon' else [geo['coordinates']]
        if any(inside(p, lon, lat) for p in polys):
            return name
    return None


def wikidata():
    cache = os.path.join(ROOT, 'data', 'foia', 'wikidata_places.json')
    if os.path.exists(cache) and os.environ.get('USE_CACHE', '1') == '1':
        return json.load(open(cache))
    out = []
    for t in TYPES:
        url = 'https://query.wikidata.org/sparql?' + urllib.parse.urlencode({'query': Q % t, 'format': 'json'})
        for i in range(6):
            try:
                req = urllib.request.Request(url, headers={'User-Agent': 'MOBIlityBot/1.0 (albis_iulian@yahoo.com)'})
                got = json.loads(urllib.request.urlopen(req, timeout=300).read())['results']['bindings']
                print(f'wikidata {t}: {len(got)}', flush=True)
                out += got
                break
            except Exception as e:
                print('wikidata', t, e, flush=True)
                time.sleep(30 * (i + 1))
    if not out:
        raise SystemExit('wikidata failed')
    json.dump(out, open(cache, 'w'))
    return out


ABBR = {'AL': 'Alabama', 'AK': 'Alaska', 'AZ': 'Arizona', 'AR': 'Arkansas', 'CA': 'California', 'CO': 'Colorado',
        'CT': 'Connecticut', 'DE': 'Delaware', 'DC': 'District of Columbia', 'FL': 'Florida', 'GA': 'Georgia',
        'HI': 'Hawaii', 'ID': 'Idaho', 'IL': 'Illinois', 'IN': 'Indiana', 'IA': 'Iowa', 'KS': 'Kansas',
        'KY': 'Kentucky', 'LA': 'Louisiana', 'ME': 'Maine', 'MD': 'Maryland', 'MA': 'Massachusetts', 'MI': 'Michigan',
        'MN': 'Minnesota', 'MS': 'Mississippi', 'MO': 'Missouri', 'MT': 'Montana', 'NE': 'Nebraska', 'NV': 'Nevada',
        'NH': 'New Hampshire', 'NJ': 'New Jersey', 'NM': 'New Mexico', 'NY': 'New York', 'NC': 'North Carolina',
        'ND': 'North Dakota', 'OH': 'Ohio', 'OK': 'Oklahoma', 'OR': 'Oregon', 'PA': 'Pennsylvania',
        'RI': 'Rhode Island', 'SC': 'South Carolina', 'SD': 'South Dakota', 'TN': 'Tennessee', 'TX': 'Texas',
        'UT': 'Utah', 'VT': 'Vermont', 'VA': 'Virginia', 'WA': 'Washington', 'WV': 'West Virginia',
        'WI': 'Wisconsin', 'WY': 'Wyoming'}


def dotgov():
    """Every city / county .gov domain (CISA dotgov-data, public domain): name, state, domain."""
    import csv
    import io
    cache = os.path.join(ROOT, 'data', 'foia', 'dotgov_local.json')
    if os.path.exists(cache) and os.environ.get('USE_CACHE', '1') == '1':
        return json.load(open(cache))
    raw = urllib.request.urlopen(urllib.request.Request(
        'https://raw.githubusercontent.com/cisagov/dotgov-data/main/current-full.csv',
        headers={'User-Agent': 'MOBIlityBot/1.0'}), timeout=120).read().decode('utf-8', 'replace')
    out = []
    for r in csv.DictReader(io.StringIO(raw)):
        typ = (r.get('Domain type') or r.get('Domain Type') or '').strip()
        if typ not in ('City', 'County'):
            continue
        st = ABBR.get((r.get('State') or '').strip().upper())
        if not st:
            continue
        org = (r.get('Organization name') or r.get('Organization') or '').strip()
        out.append({'domain': (r.get('Domain name') or r.get('Domain Name') or '').strip().lower(), 'type': typ,
                    'org': org, 'state': st})
    json.dump(out, open(cache, 'w'))
    print('dotgov', len(out), flush=True)
    return out


def org_name(org, typ):
    o = re.sub(r'\s+', ' ', org).strip()
    m = re.match(r'^(city|town|village|borough|township|county|municipality|parish)\s+of\s+(the\s+)?(.+)$', o, re.I)
    if m:
        kind = m.group(1).title()
        return m.group(3), ('Town' if kind in ('Town', 'Village', 'Borough', 'Township') else kind if kind in ('County', 'Parish') else 'City')
    m = re.match(r'^(.+?)\s+(county|parish)$', o, re.I)
    if m:
        return o, 'Org'
    return o, 'Org' if typ == 'County' else 'City'


def targets():
    done_host, done_name = set(), set()
    for c in json.load(open(os.path.join(ROOT, 'data', 'foia', 'contacts.json'))):
        if c.get('site'):
            done_host.add(host(c['site']))
        done_name.add(c['city'].lower())
        for e in c.get('email') or []:
            done_host.add(e.split('@')[-1].lower())
    rows, seen = [], set()
    for b in wikidata():
        h = host(b['site']['value'])
        name = b['cLabel']['value']
        if not h or h in seen or name.startswith('Q') or h in done_host:
            continue
        lon, lat = map(float, b['coord']['value'].replace('Point(', '').rstrip(')').split()[:2])
        if 17.4 <= lat < 18.9 and -68.2 <= lon < -65.0:        # Puerto Rico: banned
            continue
        seen.add(h)
        t = b['type']['value']
        kind = 'County' if t in COUNTY else 'Town' if t in TOWN else 'City'
        rows.append({'name': name, 'site': h, 'lat': lat, 'lon': lon, 'kind': kind,
                     'pop': int(float(b['p']['value'])) if b.get('p') else 0})
    if os.environ.get('SOURCE', 'wikidata') == 'dotgov':
        wd = rows
        rows = []
        wd_hosts = {r['site'] for r in wd}
        for d in dotgov():
            h = d['domain']
            if not h or h in seen and h not in wd_hosts or h in done_host:
                continue
            if h in wd_hosts:           # already read by the Wikidata run
                continue
            seen.add(h)
            name, kind = org_name(d['org'], d['type'])
            rows.append({'name': name, 'site': h, 'lat': None, 'lon': None, 'kind': kind, 'pop': 0, 'state': d['state']})
    rows.sort(key=lambda r: (-r['pop'], r['site']))
    return rows, done_name


def find():
    shard, n = int(os.environ.get('SHARD', 0)), int(os.environ.get('NSHARDS', 1))
    rows, done_name = targets()
    if os.environ.get('WIDE') == '1':
        import glob
        had = set()
        for f in glob.glob(os.path.join(OUT, '*_*.json')):
            if os.path.basename(f).startswith(os.environ.get('PART', 'part') + '_'):
                continue
            for x in json.load(open(f)):
                if x.get('email'):
                    had.add(host(x['site']))
        rows = [r for r in rows if host(r['site']) not in had]
    mine = rows[shard::n]
    print(f'{len(rows)} sites not written to yet; shard {shard}: {len(mine)}', flush=True)
    os.makedirs(OUT, exist_ok=True)
    stop = time.time() + float(os.environ.get('STOP_AFTER_MIN', 300)) * 60
    res = []

    def one(r):
        if time.time() > stop:
            return None
        st = r.get('state') or state_of(r['lat'], r['lon'])
        if not st or f"{r['name']} {st}".lower() in done_name:
            return None
        try:
            c = find_contacts(r['name'], r['site'])
        except Exception:
            return None
        return dict(r, state=st, email=c.get('email') or [], portal=c.get('portal') or [], pages=c.get('pages') or [])
    with cf.ThreadPoolExecutor(int(os.environ.get('THREADS', 48))) as ex:
        for i, x in enumerate(ex.map(one, mine)):
            if x:
                res.append(x)
            if i % 200 == 0:
                print(f'{i}/{len(mine)} · with e-mail {sum(1 for y in res if y["email"])}', flush=True)
                json.dump(res, open(os.path.join(OUT, f"{os.environ.get('PART', 'part')}_{shard}.json"), 'w'), separators=(',', ':'))
    json.dump(res, open(os.path.join(OUT, f"{os.environ.get('PART', 'part')}_{shard}.json"), 'w'), separators=(',', ':'))
    print(f'shard {shard}: {len(res)} read · e-mail {sum(1 for y in res if y["email"])} · portal only '
          f'{sum(1 for y in res if y["portal"] and not y["email"])}', flush=True)
    os._exit(0)


def merge():
    import glob
    rows = []
    for f in sorted(glob.glob(os.path.join(OUT, '*_*.json'))):
        rows += json.load(open(f))
    rows.sort(key=lambda r: (-r['pop'], r['site']))
    json.dump(rows, open(os.path.join(ROOT, 'data', 'foia', 'all.json'), 'w'), indent=0, ensure_ascii=False)
    em = [r for r in rows if r['email']]
    po = [r for r in rows if r['portal'] and not r['email']]
    no = [r for r in rows if not r['portal'] and not r['email']]
    lines = [f'# All municipalities and counties not yet written to: {len(rows)}', '',
             f'With e-mail: {len(em)} · portal only: {len(po)} · nothing found: {len(no)}', '',
             '## Portal only', '| Place | State | Pop. | Portal |', '|---|---|---|---|']
    lines += [f"| {r['kind']} of {r['name']} | {r['state']} | {r['pop']:,} | {r['portal'][0]} |" for r in po]
    open(os.path.join(ROOT, 'data', 'foia', 'ALL.md'), 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines[:3]))


if __name__ == '__main__':
    {'find': find, 'merge': merge, 'list': lambda: print(len(targets()[0]), 'targets')}[sys.argv[1]]()
