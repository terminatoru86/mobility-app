#!/usr/bin/env python3
"""Rider places from a Geofabrik OpenStreetMap extract (fast, no server limits).

    osmium tags-filter region.osm.pbf ... -o filtered.osm.pbf     (done by the workflow)
    python3 tool/osm_extract.py filtered.osm.pbf out.json

Writes [[id, lat, lon, tags], ...] like the Overpass path of build_packs.py.
Needs: pip install osmium
"""
import json
import sys

import osmium

KEEP_AMENITY = {'bicycle_parking', 'bicycle_repair_station', 'compressed_air', 'bicycle_wash', 'bicycle_rental'}
KEEP = {
    'amenity', 'bicycle_parking', 'capacity', 'covered', 'fee', 'access', 'lit', 'surveillance', 'name', 'brand',
    'network', 'operator', 'shop', 'bicycle', 'bicycle_rental', 'opening_hours', 'phone', 'contact:phone', 'website',
    'contact:website', 'addr:housenumber', 'addr:street',
}


def wanted(tags):
    a = tags.get('amenity')
    if a in KEEP_AMENITY or tags.get('shop') == 'bicycle':
        return True
    return a == 'charging_station' and tags.get('bicycle') == 'yes'


def slim(tags):
    return {k: v for k, v in tags.items() if k in KEEP or k.startswith('service:bicycle:')}


class H(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.out = []

    def node(self, n):
        t = dict(n.tags)
        if t and wanted(t) and n.location.valid():
            self.out.append([f'node/{n.id}', round(n.location.lat, 6), round(n.location.lon, 6), slim(t)])

    def way(self, w):
        t = dict(w.tags)
        if not t or not wanted(t):
            return
        pts = [(nd.lat, nd.lon) for nd in w.nodes if nd.location.valid()]
        if pts:  # the middle of the outline
            self.out.append([f'way/{w.id}', round(sum(p[0] for p in pts) / len(pts), 6),
                             round(sum(p[1] for p in pts) / len(pts), 6), slim(t)])


if __name__ == '__main__':
    h = H()
    h.apply_file(sys.argv[1], locations=True)
    json.dump(h.out, open(sys.argv[2], 'w', encoding='utf-8'), separators=(',', ':'), ensure_ascii=False)
    print(f'{len(h.out)} places from {sys.argv[1]}')
