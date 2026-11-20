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

KEEP_AMENITY = {'bicycle_parking', 'bicycle_repair_station', 'compressed_air', 'bicycle_wash', 'bicycle_rental',
                'motorcycle_parking', 'small_electric_vehicle_parking', 'kick-scooter_parking', 'mobility_hub'}
KEEP = {
    'amenity', 'bicycle_parking', 'capacity', 'covered', 'fee', 'access', 'lit', 'surveillance', 'name', 'brand',
    'network', 'operator', 'shop', 'bicycle', 'bicycle_rental', 'opening_hours', 'phone', 'contact:phone', 'website',
    'contact:website', 'addr:housenumber', 'addr:street', 'motorcycle', 'scooter', 'small_electric_vehicle',
    'service:vehicle:repair', 'motorcycle:repair',
    # photos, freshness and details
    'image', 'image:0', 'image:1', 'wikimedia_commons', 'mapillary', 'panoramax', 'check_date', 'survey:date', 'cargo_bike', 'capacity:cargo_bike', 'supervised', 'maxstay', 'charge', 'valves', 'manometer', 'level', 'location', 'description',
    'surveillance:type', 'self_service', 'automated', 'rental', 'sport', 'surface', 'email', 'contact:email',
    'manufacturer',
}


def wanted(tags):
    a = tags.get('amenity')
    if a == 'fuel' and tags.get('compressed_air') == 'yes':
        return True  # free / paid air at a gas station -> an air pump on the map
    if a == 'car_wash' and (tags.get('motorcycle') in ('yes', 'designated') or 'motorcycle' in (tags.get('name') or '').lower()):
        return True  # a car wash that also washes motorcycles
    if a in KEEP_AMENITY or tags.get('shop') in ('bicycle', 'motorcycle', 'scooter', 'motorcycle_repair'):
        return True
    if tags.get('sport') == 'bmx':
        return True
    return a == 'charging_station' and 'yes' in (tags.get('bicycle'), tags.get('scooter'), tags.get('motorcycle'))


def slim(tags):
    out = {k: v for k, v in tags.items() if k in KEEP or k.startswith(('service:', 'socket:', 'motorcycle:'))}
    if tags.get('amenity') == 'fuel':
        out.update({'amenity': 'compressed_air', 'mobility:at': 'gas station',
                    'name': f"Air at {tags.get('brand') or tags.get('name') or 'the gas station'}"})
        if tags.get('compressed_air:fee'):
            out['fee'] = tags['compressed_air:fee']
    if tags.get('amenity') == 'car_wash':
        out.update({'amenity': 'bicycle_wash', 'motorcycle': 'yes', 'mobility:at': 'car wash'})
    return out


def dated(tags, obj):
    """last edit of the element in OpenStreetMap, for the newest-source rule of the duplicates"""
    try:
        tags['source:date'] = obj.timestamp.strftime('%Y-%m-%d')
    except Exception:
        pass
    return tags


class H(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.out = []

    def node(self, n):
        t = dict(n.tags)
        if t and wanted(t) and n.location.valid():
            self.out.append([f'node/{n.id}', round(n.location.lat, 6), round(n.location.lon, 6), dated(slim(t), n)])

    def way(self, w):
        t = dict(w.tags)
        if not t or not wanted(t):
            return
        pts = [(nd.lat, nd.lon) for nd in w.nodes if nd.location.valid()]
        if pts:  # the middle of the outline
            self.out.append([f'way/{w.id}', round(sum(p[0] for p in pts) / len(pts), 6),
                             round(sum(p[1] for p in pts) / len(pts), 6), dated(slim(t), w)])


if __name__ == '__main__':
    h = H()
    h.apply_file(sys.argv[1], locations=True)
    json.dump(h.out, open(sys.argv[2], 'w', encoding='utf-8'), separators=(',', ':'), ensure_ascii=False)
    print(f'{len(h.out)} places from {sys.argv[1]}')
