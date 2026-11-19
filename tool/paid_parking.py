"""Paid and private parking businesses for bicycles, mopeds, motorcycles and scooters across the US.

  python3 tool/paid_parking.py --test                         -> only checks the rules
  python3 tool/paid_parking.py --pbf cut.osm.pbf part.json    -> OSM places of one Geofabrik extract
  python3 tool/paid_parking.py part1.json part2.json ...      -> data/paid_parking.json + data/paid_parking/REPORT.md

What we look for:
  1. OpenStreetMap car parks / garages that also take motorcycles, mopeds, bicycles or scooters
     (motorcycle=yes|designated, capacity:motorcycle, capacity:bicycle, capacity:moped, capacity:scooter ...),
     and bike / motorcycle parkings that charge or belong to a business (fee=yes, operator, access=customers).
  2. Overture Maps and Foursquare places in a parking category whose name says bike / motorcycle / scooter
     (bike stations, bike garages, lockers, "Cycle Center", motorcycle parking lots), and the known paid
     bike-parking networks (Oonee, Bikeep, BikeLink, ProPark Bike, Bikestation).
The list goes into the map packs (tool/build_packs.py, source "paid"): fee=yes / access=customers makes the app show
them as "Private parking" with "Paid".
"""
import json
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

TWO = re.compile(r'\b(bikes?|bicycles?|cycles?|cycling|velo|motorcycles?|motorbikes?|moto|mopeds?|scooters?|two[\s-]*wheel\w*'
                 r'|oonee|bikeep|bikelink|bikestation|bike\s*station|propark\s*bike|cycle\s*cent(er|re)|bike\s*hub)\b', re.I)
NOT_PARK = re.compile(r'\b(shop|store|sales|dealer|repair|rental|rentals|tours?|club|school|museum|trail|park\s*&\s*ride'
                      r'|racing|race|speedway|show|insurance|towing|tow|storage\s*units?|self\s*storage)\b', re.I)
NETWORK = re.compile(r'\b(oonee|bikeep|bikelink|bikestation|propark\s*bike)\b', re.I)
# a name that says it is a place to leave the vehicle (not a shop called "... Cycle Center")
LEAVE = re.compile(r'\b(parking|park\s*&\s*lock|garage|lockers?|station|valet|corral|cage|lot|storage\s*room|commuter|hub)\b', re.I)
PAYING = re.compile(r'\b(garage|lockers?|valet|cage|oonee|bikeep|bikelink|bikestation|propark|cent(er|re)|station\b(?!.*rack)|commuter)\b', re.I)
PARK_CAT = re.compile(r'parking|garage', re.I)


def num(v):
    try:
        return int(re.match(r'\s*(\d+)', str(v)).group(1))
    except Exception:
        return 0


def clean(d):
    return {k: v for k, v in d.items() if v not in (None, '', 0)}


def vehicles_of(t):
    """Which two-wheelers a car park takes, from its OSM tags."""
    moto = t.get('motorcycle') in ('yes', 'designated') or num(t.get('capacity:motorcycle')) > 0 \
        or num(t.get('capacity:motorbike')) > 0 or t.get('motorcycle_parking') in ('yes',)
    moped = t.get('moped') in ('yes', 'designated') or num(t.get('capacity:moped')) > 0
    bike = num(t.get('capacity:bicycle')) > 0 or t.get('bicycle_parking') in ('yes', 'building', 'lockers')
    scooter = num(t.get('capacity:scooter')) > 0 or num(t.get('capacity:small_electric_vehicle')) > 0
    return moto, moped, bike, scooter


def osm_record(oid, lat, lon, t):
    a = t.get('amenity')
    name = t.get('name')
    common = {
        'name': name, 'operator': t.get('operator'), 'brand': t.get('brand'),
        'phone': t.get('phone') or t.get('contact:phone'), 'website': t.get('website') or t.get('contact:website'),
        'opening_hours': t.get('opening_hours'), 'charge': t.get('charge'), 'fee': t.get('fee'),
        'access': t.get('access'), 'covered': t.get('covered'), 'surveillance': t.get('surveillance'),
        'supervised': t.get('supervised'), 'lit': t.get('lit'), 'maxstay': t.get('maxstay'),
        'addr:street': ' '.join(x for x in (t.get('addr:housenumber'), t.get('addr:street')) if x) or None,
        'source': 'OpenStreetMap · paid / private parking'}
    if a == 'parking':
        if t.get('access') in ('no', 'private') and not (t.get('operator') or t.get('fee') == 'yes'):
            return None  # someone's own lot
        moto, moped, bike, scooter = vehicles_of(t)
        if not (moto or moped or bike or scooter):
            return None
        garage = t.get('parking') in ('multi-storey', 'underground', 'garage', 'garages')
        if moto or moped:
            tags = {'amenity': 'motorcycle_parking', 'capacity': num(t.get('capacity:motorcycle')) or num(t.get('capacity:moped')) or None}
            if bike:
                tags['bicycle'] = 'yes'
        elif bike:
            tags = {'amenity': 'bicycle_parking', 'bicycle_parking': 'building' if garage else 'stands',
                    'capacity': num(t.get('capacity:bicycle')) or None}
        else:
            tags = {'amenity': 'small_electric_vehicle_parking', 'capacity': num(t.get('capacity:scooter')) or None}
        if garage:
            tags['covered'] = 'yes'
        tags['parking'] = t.get('parking')
        tags['mobility:in_car_park'] = 'yes'
        tags.update(clean(common))
        return [f'pay/{oid}', round(lat, 6), round(lon, 6), clean(tags)]
    if a in ('bicycle_parking', 'motorcycle_parking', 'small_electric_vehicle_parking'):
        # only the ones run as a business: charging, customers only, or with an operator and a building / lockers
        business = t.get('fee') == 'yes' or t.get('access') in ('customers', 'permit') or (
            t.get('operator') and t.get('bicycle_parking') in ('building', 'lockers', 'shed')) or bool(NETWORK.search(
                f'{name or ""} {t.get("operator") or ""} {t.get("brand") or ""}'))
        if not business:
            return None
        tags = {'amenity': a, 'bicycle_parking': t.get('bicycle_parking'), 'capacity': num(t.get('capacity')) or None}
        tags.update(clean(common))
        return [f'pay/{oid}', round(lat, 6), round(lon, 6), clean(tags)]
    return None


def osm_from_pbf(pbf, out_json):
    import osmium
    found = []

    class H(osmium.SimpleHandler):
        def node(self, n):
            if n.tags and n.location.valid():
                r = osm_record(f'node/{n.id}', n.location.lat, n.location.lon, dict(n.tags))
                if r:
                    found.append(r)

        def way(self, w):
            if not w.tags:
                return
            pts = [(nd.lat, nd.lon) for nd in w.nodes if nd.location.valid()]
            if pts:
                r = osm_record(f'way/{w.id}', sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts), dict(w.tags))
                if r:
                    found.append(r)

    H().apply_file(pbf, locations=True)
    json.dump(found, open(out_json, 'w'))
    print(f'{pbf}: {len(found)} paid / private two-wheeler parkings', flush=True)


def business_record(oid, lat, lon, name, cat, phone, web, street, src):
    """An Overture / Foursquare place: a parking business for two-wheelers, or None."""
    n = name or ''
    if not n or NOT_PARK.search(n):
        return None
    if not (NETWORK.search(n) or (PARK_CAT.search(cat or '') and LEAVE.search(n)) or re.search(r'\bparking\b', n, re.I)):
        return None  # "Performance Cycle Center" (a shop) is not a parking
    if not TWO.search(n) and not re.search(r'bicycle|motorcycle', cat or '', re.I):
        return None
    if re.search(r'motorcycle|motorbike|moto\b|moped', n + ' ' + (cat or ''), re.I):
        a = {'amenity': 'motorcycle_parking'}
    elif re.search(r'scooter', n, re.I) and not re.search(r'bike|bicycle|cycle', n, re.I):
        a = {'amenity': 'small_electric_vehicle_parking'}
    else:
        a = {'amenity': 'bicycle_parking', 'bicycle_parking': 'building' if re.search(r'station|garage|cent(er|re)|hub|room|cage|vault', n, re.I)
             else ('lockers' if re.search(r'locker|bikelink|oonee|bikeep|pod', n, re.I) else None)}
    paid = bool(PAYING.search(n)) and not re.search(r'\bracks?\b|\bfree\b', n, re.I)
    tags = {**a, 'name': n, 'fee': 'yes' if paid else None, 'access': None if paid else 'yes', 'phone': phone, 'website': web, 'addr:street': street, 'source': src}
    return [f'pay/{oid}', round(lat, 6), round(lon, 6), clean(tags)]


def fetch_overture():
    import duckdb
    import urllib.request
    cat = json.loads(urllib.request.urlopen('https://stac.overturemaps.org/catalog.json', timeout=60).read())
    release = cat.get('latest') or sorted(l['href'].split('/')[1] for l in cat['links'] if l.get('rel') == 'child')[-1]
    release = release.strip('./').split('/')[0]
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2';")
    q = f"""
      SELECT id, names.primary, CAT_EXPR, (bbox.ymin + bbox.ymax) / 2, (bbox.xmin + bbox.xmax) / 2,
             phones[1], websites[1], addresses[1].freeform
      FROM read_parquet('s3://overturemaps-us-west-2/release/{release}/theme=places/type=place/*', hive_partitioning=1)
      WHERE bbox.xmin BETWEEN -180 AND -65 AND bbox.ymin BETWEEN 17 AND 72 AND addresses[1].country = 'US'
        AND confidence >= 0.5
        AND (regexp_matches(lower(CAT_EXPR), 'parking|garage')
             OR regexp_matches(lower(names.primary), 'oonee|bikeep|bikelink|bikestation|bike station|cycle cent|bike parking|motorcycle parking'))
    """
    rows, last = None, None
    for expr in ('coalesce(taxonomy.primary, basic_category)', 'basic_category', 'categories.primary'):
        try:
            rows = con.execute(q.replace('CAT_EXPR', expr)).fetchall()
            break
        except Exception as err:
            last = err
    if rows is None:
        raise last
    out = [r for r in (business_record(f'ovt/{i}', la, lo, n, c, ph, w, s, 'Overture Maps') for i, n, c, la, lo, ph, w, s in rows) if r]
    print(f'Overture {release}: {len(rows)} parking places looked at, {len(out)} for two-wheelers', flush=True)
    return out


def fetch_foursquare():
    token = os.environ.get('HF_TOKEN')
    if not token:
        print('Foursquare skipped: no HF_TOKEN', flush=True)
        return []
    import duckdb
    import urllib.request
    req = urllib.request.Request('https://huggingface.co/api/datasets/foursquare/fsq-os-places/tree/main/release',
                                 headers={'Authorization': f'Bearer {token}'})
    tree = json.loads(urllib.request.urlopen(req, timeout=60).read())
    rel = sorted(t['path'] for t in tree if t.get('type') == 'directory' and 'dt=' in t.get('path', ''))[-1]
    con = duckdb.connect()
    con.execute('INSTALL httpfs; LOAD httpfs;')
    con.execute(f"CREATE SECRET hf (TYPE huggingface, TOKEN '{token}');")
    q = f"""
      SELECT fsq_place_id, name, latitude, longitude, array_to_string(fsq_category_labels, ' | '), tel, website, address, date_refreshed
      FROM read_parquet('hf://datasets/foursquare/fsq-os-places/{rel}/places/parquet/*.parquet')
      WHERE country = 'US' AND date_closed IS NULL AND latitude IS NOT NULL
        AND (regexp_matches(lower(array_to_string(fsq_category_labels, ' | ')), 'parking')
             OR regexp_matches(lower(name), 'oonee|bikeep|bikelink|bikestation|bike station|cycle cent|bike parking|motorcycle parking'))
    """
    rows = con.execute(q).fetchall()
    out = [r for r in (business_record(f'fsq/{i}', la, lo, n, c, ph, w, s, 'Foursquare OS Places')
                       for i, n, la, lo, c, ph, w, s, d in rows if (d or '')[:10] >= '2022-01-01') if r]
    print(f'Foursquare {rel}: {len(rows)} parking places looked at, {len(out)} for two-wheelers', flush=True)
    return out


def merge(lists):
    """Same place from two sources (same kind within 150 m, or same name within 400 m): kept once."""
    G = 0.005
    grid, out = {}, []
    def key(n):
        return re.sub(r'[^a-z0-9]', '', (n or '').lower())
    for lst in lists:
        for p in lst:
            cell = (math.floor(p[1] / G), math.floor(p[2] / G))
            hit = None
            for i in range(cell[0] - 1, cell[0] + 2):
                for j in range(cell[1] - 1, cell[1] + 2):
                    for q in grid.get((i, j), []):
                        d = math.hypot((q[1] - p[1]) * 111000, (q[2] - p[2]) * 111000 * math.cos(math.radians(p[1])))
                        same_name = key(q[3].get('name')) and key(q[3].get('name')) == key(p[3].get('name'))
                        if (same_name and d < 400) or (d < 150 and q[3]['amenity'] == p[3]['amenity']):
                            hit = q
            if hit:
                for k, v in p[3].items():
                    if k == 'source':
                        if v not in hit[3]['source']:
                            hit[3]['source'] += f' · {v}'
                    elif k not in hit[3]:
                        hit[3][k] = v
                continue
            out.append(p)
            grid.setdefault(cell, []).append(p)
    return out


def test():
    g = osm_record('way/1', 41.88, -87.63, {'amenity': 'parking', 'parking': 'multi-storey', 'motorcycle': 'yes',
                                             'fee': 'yes', 'operator': 'SP+', 'capacity:bicycle': '20'})
    assert g and g[3]['amenity'] == 'motorcycle_parking' and g[3]['bicycle'] == 'yes' and g[3]['covered'] == 'yes', g
    assert osm_record('way/2', 41.88, -87.63, {'amenity': 'parking', 'fee': 'yes'}) is None  # cars only
    assert osm_record('node/3', 41.88, -87.63, {'amenity': 'bicycle_parking', 'bicycle_parking': 'stands'}) is None  # a free rack
    assert osm_record('node/4', 41.88, -87.63, {'amenity': 'bicycle_parking', 'fee': 'yes', 'name': 'Bike garage'})
    b = business_record('ovt/1', 41.88, -87.62, '2 N Riverside Bike Garage', 'parking', None, None, None, 'Overture Maps')
    assert b and b[3]['amenity'] == 'bicycle_parking' and b[3]['bicycle_parking'] == 'building' and b[3]['fee'] == 'yes', b
    r = business_record('fsq/3', 41.88, -87.62, 'Bike Racks At The Train Station Outbound Side', 'Parking', None, None, None, 'F')
    assert r and 'fee' not in r[3], r
    m = business_record('fsq/2', 40.7, -74.0, 'Downtown Motorcycle Parking', 'Parking Lot', None, None, None, 'Foursquare')
    assert m and m[3]['amenity'] == 'motorcycle_parking', m
    for n in ('Harley-Davidson of Chicago', 'Joe\'s Bike Shop', 'Main St Parking Garage', 'Lake Bike Trail Parking',
              'Performance Cycle Center', 'Markham Cycle Center', 'Village Cycle Center'):
        assert business_record('x', 1, 1, n, 'parking', None, None, None, 's') is None, n
    print('rules ok')


def main():
    test()
    if '--test' in sys.argv:
        return
    if '--pbf' in sys.argv:
        i = sys.argv.index('--pbf')
        osm_from_pbf(sys.argv[i + 1], sys.argv[i + 2])
        return
    osm = [r for f in sys.argv[1:] if f.endswith('.json') for r in json.load(open(f))]
    parts = [osm]
    for name, fn in (('overture', fetch_overture), ('foursquare', fetch_foursquare)):
        try:
            parts.append(fn())
        except Exception as err:
            print(f'{name} failed: {err}', flush=True)
            parts.append([])
    allp = merge(parts)
    allp.sort(key=lambda p: (p[1], p[2]))
    json.dump(allp, open(os.path.join(ROOT, 'data', 'paid_parking.json'), 'w'), separators=(',', ':'), ensure_ascii=False)
    kinds, srcs = {}, {}
    for p in allp:
        k = p[3]['amenity'] + (' (in a car park)' if p[3].get('mobility:in_car_park') else '')
        kinds[k] = kinds.get(k, 0) + 1
        for s in p[3]['source'].split(' · '):
            srcs[s] = srcs.get(s, 0) + 1
    paid = sum(1 for p in allp if p[3].get('fee') == 'yes')
    os.makedirs(os.path.join(ROOT, 'data', 'paid_parking'), exist_ok=True)
    with open(os.path.join(ROOT, 'data', 'paid_parking', 'REPORT.md'), 'w', encoding='utf-8') as f:
        f.write(f'# Paid / private parking for two-wheelers: {len(allp)}\n\nBy kind: {kinds}\n\nBy source: {srcs}\n\n'
                f'Paid (fee=yes): {paid} · with a phone: {sum(1 for p in allp if p[3].get("phone"))} · '
                f'with hours: {sum(1 for p in allp if p[3].get("opening_hours"))}\n\n## Around Chicago\n')
        for p in allp:
            if abs(p[1] - 41.88) < 0.4 and abs(p[2] + 87.7) < 0.5:
                t = p[3]
                f.write(f'- {t.get("name") or t.get("operator") or "(no name)"} · {t["amenity"]} · fee={t.get("fee", "?")} · {t["source"]}\n')
    print(f'{len(allp)} places · {kinds} · {srcs} · paid {paid}', flush=True)


if __name__ == '__main__':
    main()
