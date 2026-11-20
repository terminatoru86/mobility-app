#!/usr/bin/env python3
"""Second read of the KMZ / ZIP (shapefile, KML, GeoJSON, CSV inside) files the city crawl downloaded but did not
open. Downloads them again from their URLs (data/city_files/index_*.json) and writes <file>.rows.json next to the
others, for tool/city_rows.py."""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tool'))
os.chdir(ROOT)
import city_files as cf  # noqa: E402

done = kept = rows_n = 0
for f in sorted(glob.glob('data/city_files/index_*.json')):
    for city, v in json.load(open(f)).items():
        for it in v.get('files', []):
            ext = it['url'].split('?')[0].rsplit('.', 1)[-1].lower()
            if ext not in ('kmz', 'zip'):
                continue
            p = cf.download(city, it['url'])
            done += 1
            if not p:
                continue
            rows = cf.extract(p)
            name = os.path.basename(p)
            useful = [r for r in rows if 'error' not in r and (cf.STRONG.search(json.dumps(r, ensure_ascii=False)) or cf.STRONG.search(name))]
            print(f'{city}: {name} rows {len(rows)} useful {len(useful)}', flush=True)
            if useful:
                json.dump(useful[:5000], open(p + '.rows.json', 'w'), ensure_ascii=False)
                kept += 1
                rows_n += len(useful)
            os.remove(p)
print(f'KMZ/ZIP files read again: {done} · with rows: {kept} · rows: {rows_n}')
