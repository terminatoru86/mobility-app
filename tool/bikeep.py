#!/usr/bin/env python3
"""Bikeep smart bike-parking stations. Their open endpoint needs a "public area" id per region
(services.bikeep.com/location/v1/public-areas/{id}/locations, GeoJSON, no login). This tries the listing
endpoints and the ids we know or can guess, and saves every US station it gets.

    python3 tool/bikeep.py   -> data/bikeep/locations.json + data/bikeep/REPORT.md
"""
import json
import os
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = 'https://services.bikeep.com/location/v1'
LIST = [f'{BASE}/public-areas', f'{BASE}/public-areas/', f'{BASE}/public-areas?limit=1000', f'{BASE}/locations',
        f'{BASE}/public/locations', f'{BASE}/public-locations']
IDS = ['no-baia-mobility', 'us', 'usa', 'united-states', 'bikeep', 'public', 'all', 'global', 'north-america',
       'bart', 'sfmta', 'san-francisco', 'sf', 'new-york', 'nyc', 'chicago', 'boston', 'seattle', 'portland',
       'los-angeles', 'la-metro', 'oakland', 'san-jose', 'vta', 'denver', 'austin', 'washington-dc', 'dc', 'miami',
       'cupertino', 'palo-alto', 'mountain-view', 'stanford', 'apple', 'google', 'meta', 'santa-monica', 'berkeley']


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'MOBIlityBot/1.0', 'Accept': 'application/json'})
    with urllib.request.urlopen(req, timeout=40) as r:
        return r.status, r.read()


def main():
    log, feats = [], {}
    for u in LIST + [f'{BASE}/public-areas/{i}/locations' for i in IDS]:
        try:
            st, body = get(u)
            log.append(f'{st} {u} {body[:200]!r}')
            j = json.loads(body)
            fs = j.get('features') if isinstance(j, dict) else None
            for f in fs or []:
                c = (f.get('geometry') or {}).get('coordinates') or []
                if len(c) == 2 and 17 < c[1] < 72 and -171 < c[0] < -64:
                    feats[str(f.get('id') or c)] = f
            if isinstance(j, (list, dict)) and not fs:
                log.append(f'    keys/items: {list(j)[:20] if isinstance(j, dict) else j[:5]}')
        except urllib.error.HTTPError as e:
            log.append(f'{e.code} {u} {e.read()[:150]!r}')
        except Exception as e:
            log.append(f'ERR {u} {str(e)[:150]}')
    os.makedirs(os.path.join(ROOT, 'data', 'bikeep'), exist_ok=True)
    json.dump(list(feats.values()), open(os.path.join(ROOT, 'data', 'bikeep', 'locations.json'), 'w'))
    open(os.path.join(ROOT, 'data', 'bikeep', 'REPORT.md'), 'w').write(
        f'# Bikeep\n\nUS stations found: {len(feats)}\n\n```\n' + '\n'.join(log) + '\n```\n')
    print('\n'.join(log)); print(f'US stations: {len(feats)}')


if __name__ == '__main__':
    main()
