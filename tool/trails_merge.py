#!/usr/bin/env python3
"""Joins the route lists (OpenStreetMap regions + official sources) into data/trails/trails.json.gz and a short report.

    python3 tool/trails_merge.py out_dir file1.json file2.json ...
"""
import collections
import gzip
import json
import os
import sys


def main(out, files):
    recs, seen = [], set()
    for f in files:
        for r in json.load(open(f, encoding='utf-8')):
            if r['id'] in seen:
                continue
            seen.add(r['id'])
            r.setdefault('source', 'OpenStreetMap')
            recs.append(r)
    recs.sort(key=lambda r: r['id'])
    os.makedirs(out, exist_ok=True)
    text = json.dumps(recs, separators=(',', ':'), ensure_ascii=False)
    with open(os.path.join(out, 'trails.json.gz'), 'wb') as f:
        f.write(gzip.compress(text.encode('utf-8'), compresslevel=9, mtime=0))
    size = os.path.getsize(os.path.join(out, 'trails.json.gz')) / 1e6
    by_src = collections.Counter('OpenStreetMap' if r['source'] == 'OpenStreetMap' else 'Official layers' for r in recs)
    by_net = collections.Counter(r.get('network') or '-' for r in recs)
    by_kind = collections.Counter(r.get('kind') for r in recs)
    ops = collections.Counter(r.get('operator') or '-' for r in recs)
    km = sum(r['km'] for r in recs)
    lines = [f'# Bike routes found ({len(recs)} routes, {km:,.0f} km, file {size:.1f} MB)', '',
             f'By source: {dict(by_src)}', f'By kind: {dict(by_kind)}',
             f'OpenStreetMap network (ncn national, rcn regional, lcn local): {dict(by_net.most_common(8))}',
             f'Longer than 10 km: {sum(1 for r in recs if r["km"] >= 10)} · longer than 50 km: {sum(1 for r in recs if r["km"] >= 50)}', '',
             '## Operators with the most routes', *[f'- {k}: {v}' for k, v in ops.most_common(25)], '',
             '## Longest routes', *[f'- {r["name"]} · {r["km"]} km · {r.get("operator") or r.get("source")} · {r["id"]}'
                                    for r in sorted(recs, key=lambda r: -r['km'])[:25]]]
    open(os.path.join(out, 'REPORT.md'), 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
    print('\n'.join(lines[:8]))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2:])
