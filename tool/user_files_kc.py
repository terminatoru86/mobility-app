"""Kansas City MO records reply R026721 + Elko NV + Clemmons NC + Terre Haute IN + West Melbourne FL -> app data."""
import sys, json, hashlib, math, re, csv, collections, openpyxl
sys.path.insert(0, '/home/claude/out'); import shp
U = '/mnt/user-data/uploads'; IO = '/home/claude/mob2/data/inbox_out'; REPO = '/home/claude/mob2'
def hid(*a): return 'usr/' + hashlib.sha1('|'.join(map(str, a)).encode()).hexdigest()[:10]
def km(l): return sum(math.hypot((c-a)*111.32*math.cos(math.radians(b)), (d-b)*110.57) for (a,b),(c,d) in zip(l,l[1:]))
pts = []
SK = 'City data: Kansas City MO (public records reply R026721, Nov 2026)'
# racks from address lists (geocoded)
for r in csv.DictReader(open(IO+'/kansas_city_mo/racks_addresses.geocoded.csv')):
    if r['lat']: pts.append([hid('kc', r['neighborhood'], r['name'], r['address']), round(float(r['lat']),6), round(float(r['lon']),6),
                             {'amenity':'bicycle_parking','name':r['name'],'note':(r['notes'] or '')+(' · ' if r['notes'] else '')+r['neighborhood'],'source':SK}])
for r in csv.DictReader(open(U+'/96b986c9-Final_List_-_Map.csv', encoding='utf-8-sig')):
    if r['Latitude']: pts.append([hid('kcfl', r['Location Name'], r['Latitude']), round(float(r['Latitude']),6), round(float(r['Longitude']),6),
                                  {'amenity':'bicycle_parking','name':r['Location Name'],'note':(r['Notes'] or r['Classification'] or '')[:120],'source':SK}])
ws = openpyxl.load_workbook(U+'/91ea90ff-Station_Locations.xlsx', read_only=True).active
for r in list(ws.iter_rows(values_only=True))[1:]:
    if r and r[1]: pts.append([hid('kcrs', r[0]), round(float(r[1]),6), round(float(r[2]),6), {'amenity':'bicycle_repair_station','name':r[0],'source':SK}])
def kml_points(path):
    k = open(path, encoding='utf-8').read()
    for pm in re.findall(r'<Placemark.*?</Placemark>', k, re.S):
        name = re.search(r'<name>(.*?)</name>', pm, re.S).group(1).strip()
        c = re.search(r'<coordinates>\s*([-\d.]+),([-\d.]+)', pm)
        desc = re.sub(r'<[^>]+>', ' ', re.search(r'<description>(.*?)</description>', pm, re.S).group(1)) if '<description>' in pm else ''
        if c: yield name, float(c.group(2)), float(c.group(1)), desc
for name, lat, lon, desc in kml_points('/home/claude/att/kc/c840de3b-KCMO_Locations/doc.kml'):
    m = re.search(r'Docks:\s*(\d+)', desc)
    p = {'amenity':'bicycle_rental','bicycle_rental':'docking_station','name':name,'network':'RideKC Bike','source':SK}
    if m: p['capacity'] = m.group(1)
    pts.append([hid('kcbs', name), round(lat,6), round(lon,6), p])
for name, lat, lon, desc in kml_points('/home/claude/att/kc/89d2de31-Parking-Only_Hubs_KCMONKC/doc.kml'):
    pts.append([hid('kchub', name), round(lat,6), round(lon,6), {'amenity':'small_electric_vehicle_parking','name':name,'note':'parking-only micromobility hub (bikes / e-scooters)','source':SK}])
for city, src in (('elko_nv','City data: Elko NV (public records reply, Nov 2026)'), ('clemmons_nc','City data: Town of Clemmons NC (public records reply, Nov 2026)')):
    for r in csv.DictReader(open(f'{IO}/{city}/racks_addresses.geocoded.csv')):
        if r['lat']: pts.append([hid(city, r['name']), round(float(r['lat']),6), round(float(r['lon']),6), {'amenity':'bicycle_parking','name':r['name'],'source':src}])
th = json.load(open(IO+'/terre_haute_in/BicycleRepairStations.shp__BicycleRepairStations.geojson'))
for i, f in enumerate(th['features']):
    lon, lat = f['geometry']['coordinates'][:2]; pr = f['properties']
    nm = next((str(v) for k, v in pr.items() if re.search('name|loc', k, re.I) and v), 'Bike repair station')
    pts.append([hid('th', i, lat), round(lat,6), round(lon,6), {'amenity':'bicycle_repair_station','name':nm,'source':'City data: Terre Haute IN (public records reply, Nov 2026)'}])
# West Melbourne: 1 rack, NAD83(2011) Florida East ftUS
wm = shp.TM('PROJCS["x",GEOGCS["g"],PROJECTION["Transverse_Mercator"],PARAMETER["False_Easting",656166.667],PARAMETER["False_Northing",0.0],PARAMETER["Central_Meridian",-81.0],PARAMETER["Scale_Factor",0.999941177],PARAMETER["Latitude_Of_Origin",24.33333333333333],UNIT["Foot_US",0.3048006096012192]]')
lon, lat = wm.inv(764527.556906, 1351471.649457)
pts.append([hid('wm', 1), round(lat,6), round(lon,6), {'amenity':'bicycle_parking','name':'City park bike rack','source':'City data: West Melbourne FL (public records reply, Nov 2026)'}])
# KC trails
TYP = {'Marked Bike Route':('Signed bike route','bicycle'),'Shared Use Path':('Shared use path','bicycle'),'Bike Lanes':('Bike lane','bicycle'),
       'Separated Bike Lanes':('Separated bike lane','bicycle'),'Mountain Bike Trail':('Mountain bike trail','mtb'),'Walking Trail':('Walking trail','hiking')}
g = collections.defaultdict(list)
for f in json.load(open(IO+'/kansas_city_mo/Existing_Bikeways_Trails_2026.kmz_doc.kml__KCMO_TrailsAndBikeway_MARC.geojson'))['features']:
    cells = dict(re.findall(r'<td>([A-Za-z_]+)</td>\s*<td>(.*?)</td>', f['properties'].get('description',''), re.S))
    if cells.get('Status','Existing') != 'Existing': continue
    ft = cells.get('FacilityTy','')
    if ft not in TYP: continue
    name = (cells.get('RouteName') or f['properties'].get('Name') or 'Unnamed').strip()
    geom = f['geometry']; lines = geom['coordinates'] if geom['type']=='MultiLineString' else [geom['coordinates']]
    g[(name, ft, cells.get('SurfaceTyp',''))] += [[(c[0],c[1]) for c in ln] for ln in lines if len(ln)>1]
trails = []
for (name, ft, surf), lines in sorted(g.items()):
    label, kind = TYP[ft]
    trails.append({'id':'a/'+hashlib.sha1(f'kc|{name}|{ft}|{surf}'.encode()).hexdigest()[:12], 'name': name if re.search('trail|path|greenway|grnwy|trl', name, re.I) else f'{name} {label.lower()}',
                   'ref':None,'kind':kind,'network':None,'operator':'City of Kansas City MO','km':round(sum(km(l) for l in lines),1),
                   'tags':{'bike_facility':label, **({'surface':surf} if surf else {})},'source':'City of Kansas City MO / MARC (records reply R026721, Nov 2026)','url':None,
                   'lines':[[v for lon,lat in ln for v in (round(lat,5),round(lon,5))] for ln in lines]})
SRC = {p[3]['source'] for p in pts}
uo = json.load(open(REPO+'/data/user_official.json'))
uo = [r for r in uo if r[3].get('source') not in SRC] + pts
json.dump(uo, open(REPO+'/data/user_official.json','w'), separators=(',',':'))
json.dump(trails, open(REPO+'/data/trails_user/kansas_city_mo.json','w'), separators=(',',':'))
print(collections.Counter((p[3]['source'].split(':')[1].split('(')[0].strip(), p[3]['amenity']) for p in pts))
print('KC trails', len(trails), round(sum(t['km'] for t in trails)), 'km', collections.Counter(t['tags']['bike_facility'] for t in trails), 'WM', lat, lon)
