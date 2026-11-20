#!/usr/bin/env python3
"""US public-transit agencies from Transitland (key TRANSITLAND_API_KEY): name, website, the places they serve.
Their websites are then read like the municipal ones (tool/vendor_scan.py): bike lockers, bike rooms, racks and
bike-parking maps at stations. Feeds whose license says no commercial use are left out.

    python3 tool/transitland.py   -> data/foia/agencies.json ([{city, site, places}])
"""
import json
import os
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEY = os.environ.get('TRANSITLAND_API_KEY')


def get(params):
    q = urllib.parse.urlencode(dict(params, apikey=KEY))
    for i in range(5):
        try:
            req = urllib.request.Request(f'https://transit.land/api/v2/rest/agencies?{q}',
                                         headers={'User-Agent': 'MOBIlityBot/1.0'})
            return json.loads(urllib.request.urlopen(req, timeout=90).read())
        except Exception as e:
            print('retry', str(e)[:120], flush=True)
            time.sleep(15 * (i + 1))
    return {}


def main():
    if not KEY:
        raise SystemExit('no TRANSITLAND_API_KEY')
    out, seen, after, n = [], set(), None, 0
    while n < 400:
        p = {'adm0_iso': 'US', 'limit': 100, 'license_commercial_use_allowed': 'exclude_no'}
        if after:
            p['after'] = after
        j = get(p)
        ags = j.get('agencies') or []
        n += 1
        for a in ags:
            url = (a.get('agency_url') or '').strip()
            host = urllib.parse.urlparse(url if '//' in url else '//' + url).netloc.lower().removeprefix('www.')
            if not host or host in seen:
                continue
            seen.add(host)
            pl = [x for x in (a.get('places') or []) if x]
            st = next((x.get('adm1_name') for x in pl if x.get('adm1_name')), '')
            if st == 'Puerto Rico':
                continue
            out.append({'city': f"{a.get('agency_name')} ({st})" if st else a.get('agency_name'), 'site': host,
                        'places': [x.get('city_name') for x in pl if x.get('city_name')][:5]})
        nxt = (j.get('meta') or {}).get('after') or (j.get('meta') or {}).get('next')
        if not ags or not nxt:
            break
        after = urllib.parse.parse_qs(urllib.parse.urlparse(str(nxt)).query).get('after', [nxt])[0] if 'after=' in str(nxt) else nxt
        time.sleep(1)
    os.makedirs(os.path.join(ROOT, 'data', 'foia'), exist_ok=True)
    json.dump(out, open(os.path.join(ROOT, 'data', 'foia', 'agencies.json'), 'w'), indent=0, ensure_ascii=False)
    print(f'{len(out)} US transit agencies with a website ({n} requests)')


if __name__ == '__main__':
    main()
