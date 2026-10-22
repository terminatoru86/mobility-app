#!/usr/bin/env python3
"""Private and customers-only areas from OpenStreetMap (parking lots, residential complexes, offices, malls...).

    osmium tags-filter region.osm.pbf a/access=private,customers,permit,residents -o priv.pbf   (workflow)
    osmium export priv.pbf -f geojsonseq --geometry-types=polygon -o priv.geojsonseq
    python3 tool/private_areas.py priv.geojsonseq private.json

Writes [[south, west, north, east, access, kind, [lat, lon, lat, lon, ...]], ...] (outer ring, at most 80 points).
A rack inside one of these is on private property. No extra packages needed.
"""
import json
import sys

SKIP = {'swimming_pool', 'pitch', 'garden', 'playground', 'track'}  # never hold public racks; keeps the file small


def ring_of(geom):
    if geom['type'] == 'Polygon':
        return [geom['coordinates'][0]]
    if geom['type'] == 'MultiPolygon':
        return [p[0] for p in geom['coordinates']]
    return []


def main(src, dst):
    out = []
    for line in open(src, encoding='utf-8'):
        line = line.strip().lstrip('\x1e')
        if not line:
            continue
        try:
            f = json.loads(line)
        except ValueError:
            continue
        pr = f.get('properties') or {}
        acc = pr.get('access')
        if acc not in ('private', 'customers', 'permit', 'residents'):
            continue
        kind = pr.get('amenity') or pr.get('landuse') or pr.get('leisure') or pr.get('building') and 'building' or pr.get('shop') and 'shop' or pr.get('office') and 'office' or 'area'
        if kind in SKIP:
            continue
        for ring in ring_of(f.get('geometry') or {}):
            if len(ring) < 4:
                continue
            step = max(1, len(ring) // 80)
            pts = ring[::step]
            lats = [p[1] for p in pts]
            lons = [p[0] for p in pts]
            flat = []
            for lon, lat in pts:
                flat += [round(lat, 6), round(lon, 6)]
            out.append([min(lats), min(lons), max(lats), max(lons), acc, kind, flat])
    json.dump(out, open(dst, 'w', encoding='utf-8'), separators=(',', ':'))
    print(f'{len(out)} private areas from {src}')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
