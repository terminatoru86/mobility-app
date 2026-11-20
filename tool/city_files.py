"""Crawl the city websites (data/foia/contacts.json) for published bike-parking / bikeway data in any format.
Finds PDF, Excel, CSV, GeoJSON, KML, zip/shapefile and SQL files and open-data portals (ArcGIS Hub, Socrata, CKAN),
downloads the small ones to data/city_files/<city>/ and writes data/city_files/REPORT.md and index.json.
Run in GitHub Actions (the shell has no general internet)."""
import json, os, re, sys, time, hashlib, urllib.parse, concurrent.futures as cf
import requests
from bs4 import BeautifulSoup

OUT = 'data/city_files'
UA = {'User-Agent': 'MOBIlity-data-bot/1.0 (public bike-parking data; contact albis_iulian@yahoo.com)'}
KEY = re.compile(r'bike|bicycl|cycl|rack|corral|locker|scooter|moped|motorcycle|trail|greenway|bikeway|gis|open.?data|'
                 r'transportation|mobility|parking|garage|public.?works|map|route|historic|waterfront|charging|repair|'
                 r'micromobility|parks|recreation|data|download|dataset', re.I)
STRONG = re.compile(r'bike|bicycl|cycl|rack|corral|locker|cage|scooter|e-?scoot|micromobil|moped|motorcycle|motorbike|'
                    r'bikeway|greenway|trail|path|route|loop|historic|heritage|scenic|waterfront|riverwalk|lakefront|harbor|'
                    r'repair|fix-?it|pump|charg|outlet|ev-?station|parking|garage|lot|meter|kiosk|bikeshare|bike-?share|divvy|'
                    r'wayfinding|sharrow|boulevard|park-?and-?ride|transit|map', re.I)
FILE = re.compile(r'\.(pdf|xlsx?|csv|geojson|json|kml|kmz|zip|shp|gpx|sql|gdb)(\?|$)', re.I)
PORTAL = re.compile(r'arcgis\.com|hub\.arcgis|opendata|open-data|data\.[a-z\-]+\.(gov|org|us)|socrata|ckan|gis\.', re.I)
MAXMB = 40
PAGES = int(os.environ.get('PAGES', 110))
SECS = int(os.environ.get('SECS', 150))
SHARD = int(os.environ.get('SHARD', 0))
NSHARDS = int(os.environ.get('NSHARDS', 1))
CITIES_FILE = os.environ.get('CITIES_FILE', 'data/foia/contacts.json')
SUF = os.environ.get('SUFFIX', '')

def get(url, **kw):
    try:
        r = requests.get(url, headers=UA, timeout=25, **kw)
        return r if r.status_code == 200 else None
    except Exception:
        return None

def links(url, html):
    soup = BeautifulSoup(html, 'html.parser')
    for a in soup.find_all('a', href=True):
        u = urllib.parse.urljoin(url, a['href']).split('#')[0]
        yield u, (a.get_text(' ', strip=True) or '')[:120]

def crawl_city(c):
    site = c['site'].strip().replace('https://', '').replace('http://', '').strip('/')
    base = 'https://' + site
    seen, queue, files, portals = set(), [(base, 0)], {}, {}
    t0 = time.time()
    # search the site itself too
    for q in ('bike rack', 'bicycle parking', 'bike locker', 'scooter parking', 'motorcycle parking', 'bike repair station', 'e-bike charging', 'bike map', 'trail map', 'historic route', 'waterfront', 'parking garage rates', 'bikeway gis data', 'open data'):
        queue.append((f'{base}/search?q={urllib.parse.quote(q)}', 1))
        queue.append((f'{base}/Search?searchPhrase={urllib.parse.quote(q)}', 1))
    while queue and len(seen) < PAGES and time.time() - t0 < SECS:
        url, d = queue.pop(0)
        if url in seen:
            continue
        seen.add(url)
        host = urllib.parse.urlparse(url).netloc
        if FILE.search(url):
            if STRONG.search(url):
                files[url] = ''
            continue
        r = get(url)
        if not r or 'html' not in r.headers.get('content-type', ''):
            continue
        for u, txt in links(url, r.text):
            lt = u + ' ' + txt
            if FILE.search(u):
                if STRONG.search(lt) or d == 0:
                    if STRONG.search(lt):
                        files[u] = txt
            elif PORTAL.search(u) and KEY.search(lt) and len(portals) < 12:
                portals[u] = txt
            elif d < 2 and urllib.parse.urlparse(u).netloc.endswith(site.split('.', 1)[-1] if site.count('.') > 1 else site) and KEY.search(lt):
                queue.append((u, d + 1))
    return files, portals

def download(city, url):
    d = os.path.join(OUT, re.sub(r'[^A-Za-z0-9]+', '_', city).strip('_'))
    os.makedirs(d, exist_ok=True)
    name = re.sub(r'[^A-Za-z0-9._-]+', '_', os.path.basename(urllib.parse.urlparse(url).path))[:70] or 'file'
    path = os.path.join(d, hashlib.md5(url.encode()).hexdigest()[:6] + '_' + name)
    try:
        r = requests.get(url, headers=UA, timeout=60, stream=True)
        if r.status_code != 200:
            return None
        n = 0
        with open(path, 'wb') as f:
            for ch in r.iter_content(1 << 16):
                n += len(ch)
                if n > MAXMB << 20:
                    f.close(); os.remove(path); return None
                f.write(ch)
        return path
    except Exception:
        return None

ADDR = re.compile(r'\b\d{2,5}\s+[A-Z0-9][A-Za-z0-9 .]+\s(?:St|Street|Ave|Avenue|Blvd|Rd|Road|Dr|Drive|Way|Pl|Place|Ln|Lane|Ct|Court|Pkwy|Hwy)\b\.?')

def extract(path):
    """Rows found in a file: table rows or address lines that mention bikes. Returns list of dicts."""
    ext = path.rsplit('.', 1)[-1].lower()
    rows = []
    try:
        if ext == 'pdf':
            import pdfplumber
            with pdfplumber.open(path) as pdf:
                for pg in pdf.pages[:80]:
                    for tb in pg.extract_tables() or []:
                        for r in tb:
                            rows.append({'row': [str(x or '').strip() for x in r]})
                    for ln in (pg.extract_text() or '').splitlines():
                        if ADDR.search(ln):
                            rows.append({'line': ln.strip()})
        elif ext in ('xlsx', 'xls'):
            import openpyxl
            wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
            for ws in wb.worksheets[:6]:
                for i, r in enumerate(ws.iter_rows(values_only=True)):
                    if i > 5000: break
                    rows.append({'sheet': ws.title, 'row': ['' if x is None else str(x) for x in r]})
        elif ext == 'csv':
            import csv
            with open(path, newline='', encoding='utf-8', errors='replace') as f:
                for i, r in enumerate(csv.reader(f)):
                    if i > 5000: break
                    rows.append({'row': r})
        elif ext in ('geojson', 'json'):
            d = json.load(open(path, encoding='utf-8', errors='replace'))
            for ft in (d.get('features') or [])[:5000] if isinstance(d, dict) else []:
                rows.append({'geometry': ft.get('geometry'), 'props': ft.get('properties')})
        elif ext in ('kml',):
            soup = BeautifulSoup(open(path, encoding='utf-8', errors='replace').read(), 'xml')
            for pm in soup.find_all('Placemark')[:5000]:
                rows.append({'name': pm.find('name').text if pm.find('name') else '', 'coords': pm.find('coordinates').text.strip() if pm.find('coordinates') else ''})
        elif ext == 'sql':
            for ln in open(path, encoding='utf-8', errors='replace'):
                if ln.upper().startswith('INSERT'):
                    rows.append({'sql': ln[:400]})
                    if len(rows) > 5000: break
    except Exception as e:
        rows.append({'error': str(e)[:100]})
    return rows

def process(c):
    """crawl one city, then download + extract its files; returns (city, entry)."""
    try:
        files, portals = crawl_city(c)
    except Exception as e:
        return c['city'], {'files': [], 'portals': {}, 'error': str(e)[:100]}
    city = c['city']
    got = []
    for u, txt in list(files.items())[:25]:
        try:
            p = download(city, u)
            if not p:
                continue
            rows = extract(p)
            useful = [r for r in rows if STRONG.search(json.dumps(r, ensure_ascii=False))]
            got.append({'url': u, 'text': txt, 'file': p, 'rows': len(rows), 'bike_rows': len(useful)})
            if useful:
                json.dump(useful[:3000], open(p + '.rows.json', 'w'), ensure_ascii=False)
        except Exception:
            continue
    return city, {'files': got, 'portals': portals}

def main():
    cities = json.load(open(CITIES_FILE))
    cities = [c for i, c in enumerate(cities) if i % NSHARDS == SHARD]
    os.makedirs(OUT, exist_ok=True)
    index = {}
    rep = ['# City files found (shard %d/%d)\n' % (SHARD, NSHARDS), '| City | Files | Portals |', '|---|---|---|']
    def flush():
        json.dump(index, open(f'{OUT}/index{SUF}.json', 'w'), indent=1, ensure_ascii=False)
        open(f'{OUT}/REPORT{SUF}.md', 'w').write('\n'.join(rep) + '\n')
    with cf.ThreadPoolExecutor(8) as ex:
        for n, (city, e) in enumerate(ex.map(process, cities), 1):
            index[city] = e
            rep.append(f"| {city} | {len(e['files'])} ({sum(g['bike_rows'] for g in e['files'])} bike rows) | {len(e['portals'])} |")
            if n % 10 == 0:
                flush()
    flush()
    print('\n'.join(rep))

if __name__ == '__main__':
    main()
