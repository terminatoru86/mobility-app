"""Schools (elementary to universities), malls, markets / bazaars, industrial zones and business parks (where people
ride to work), and parks: what riders need there, from the places' OWN websites (or their district's / manager's).

Same method as tool/waterfront.py: each website (home page + its parking / getting-here / campus-bike / amenities
pages) is read for bike racks, motorcycle / moped / scooter parking, rentals, air pumps, bike repair stands,
e-bike / scooter charging and bike washes; what the map lacks within 300 m is added at the place (ids wtr/...).
A website shared by many places (a school district, a park district, a mall company) is read once.

  python3 tool/venues.py --test
  python3 tool/venues.py --pbf cut.osm.pbf part.json            one Geofabrik extract (cut by the workflow)
  python3 tool/venues.py --group campus part1.json part2.json   one group -> data/venues/<group>.json + REPORT
groups: campus (schools, colleges, universities), shopping (malls, markets), work (industrial zones, business parks),
        parks (city / county parks), transit (train / bus stations, park & ride), civic (libraries, city halls,
        community centers, hospitals), sports (stadiums, sports centers), hotels, government (Social Security, DMV,
        courthouses, post offices, federal / state offices), corporate (campuses of big companies: Google, Apple, Oracle...),
        offices (office buildings and their property managers, coworking: bike rooms, storage, garages for tenants),
        travel (vacation areas like Key West: attractions, visitor centers, resorts, campgrounds, museums),
        safety (police, fire stations, prisons), pets (veterinarians, pet stores / groomers / boarding, dog walkers,
        dog parks); transit also has ferry terminals and airports
"""
import json
import math
import os
import re
import sys
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import waterfront as wf  # noqa: E402

ROOT = wf.ROOT
LABEL = {'school': 'School', 'college': 'College', 'university': 'University', 'mall': 'Mall', 'market': 'Market',
         'industrial': 'Industrial zone', 'business_park': 'Business park', 'park': 'Park',
         'station': 'Station', 'park_ride': 'Park & Ride', 'library': 'Library', 'townhall': 'City hall',
         'community': 'Community center', 'hospital': 'Hospital', 'stadium': 'Stadium', 'sports': 'Sports center',
         'hotel': 'Hotel', 'government': 'Government office', 'ssa': 'Social Security office', 'dmv': 'DMV',
         'courthouse': 'Courthouse', 'post_office': 'Post office', 'corporate': 'Company campus', 'office_building': 'Office building', 'coworking': 'Coworking', 'airport': 'Airport',
         'ferry': 'Ferry terminal', 'attraction': 'Tourist attraction', 'visitor_center': 'Visitor center',
         'resort': 'Resort', 'campground': 'Campground', 'museum': 'Museum', 'police': 'Police station',
         'fire_station': 'Fire station', 'prison': 'Prison', 'vet': 'Veterinarian', 'pet': 'Pet business',
         'dog_park': 'Dog park',
         'cafe': 'Cafe',
         'bar': 'Bar',
         'fast_food': 'Fast food',
         'restaurant': 'Restaurant',
         'canteen': 'Canteen',
         'nightclub': 'Nightclub',
         'supermarket': 'Supermarket',
         'shop': 'Shop',
         'pharmacy': 'Pharmacy',
         'laundromat': 'Laundromat',
         'fuel': 'Gas station',
         'truck_stop': 'Truck stop',
         'car_wash': 'Car wash',
         'car_repair': 'Car repair',
         'car_dealer': 'Car dealer',
         'towing': 'Towing',
         'car_rental': 'Car rental',
         'aquarium': 'Aquarium',
         'botanical_garden': 'Botanical garden',
         'planetarium': 'Planetarium',
         'theatre': 'Theater',
         'cinema': 'Cinema',
         'arts_centre': 'Arts center',
         'exhibition': 'Exhibition center',
         'music_venue': 'Concert venue',
         'events_venue': 'Event / festival grounds',
         'zoo': 'Zoo',
         'worship': 'Church / place of worship',
         'gym': 'Gym',
         'pool': 'Swimming pool',
         'recreation': 'Recreation area',
         'fishing': 'Fishing spot',
         'viewpoint': 'Viewpoint',
         'island': 'Island',
         'plaza': 'Plaza',
         'rest_area': 'Rest area',
         'picnic': 'Picnic area',
         'motel': 'Motel',
         'hostel': 'Hostel',
         'guest_house': 'Guest house',
         'coach': 'Coach / minibus'}
GROUP = {'school': 'campus', 'college': 'campus', 'university': 'campus', 'mall': 'shopping', 'market': 'shopping',
         'industrial': 'work', 'business_park': 'work', 'park': 'parks',
         'station': 'transit', 'park_ride': 'transit', 'library': 'civic', 'townhall': 'civic', 'community': 'civic',
         'hospital': 'civic', 'stadium': 'sports', 'sports': 'sports', 'hotel': 'hotels',
         'government': 'government', 'ssa': 'government', 'dmv': 'government', 'courthouse': 'government',
         'post_office': 'government', 'corporate': 'corporate', 'office_building': 'offices', 'coworking': 'offices', 'airport': 'transit',
         'ferry': 'transit', 'attraction': 'travel', 'visitor_center': 'travel', 'resort': 'travel', 'campground': 'travel',
         'museum': 'travel', 'police': 'safety', 'fire_station': 'safety', 'prison': 'safety',
         'vet': 'pets', 'pet': 'pets', 'dog_park': 'pets',
         'cafe': 'food',
         'bar': 'food',
         'fast_food': 'food',
         'restaurant': 'food',
         'canteen': 'food',
         'nightclub': 'food',
         'supermarket': 'retail',
         'shop': 'retail',
         'pharmacy': 'retail',
         'laundromat': 'retail',
         'fuel': 'auto',
         'truck_stop': 'auto',
         'car_wash': 'auto',
         'car_repair': 'auto',
         'car_dealer': 'auto',
         'towing': 'auto',
         'car_rental': 'auto',
         'aquarium': 'culture',
         'botanical_garden': 'culture',
         'planetarium': 'culture',
         'theatre': 'culture',
         'cinema': 'culture',
         'arts_centre': 'culture',
         'exhibition': 'culture',
         'music_venue': 'culture',
         'events_venue': 'culture',
         'zoo': 'culture',
         'worship': 'culture',
         'gym': 'leisure',
         'pool': 'leisure',
         'recreation': 'leisure',
         'fishing': 'leisure',
         'viewpoint': 'leisure',
         'island': 'leisure',
         'plaza': 'leisure',
         'rest_area': 'leisure',
         'picnic': 'leisure',
         'motel': 'lodging',
         'hostel': 'lodging',
         'guest_house': 'lodging',
         'coach': 'transit'}
MAX_SITES = 100000
MORE_KINDS = ('cafe', 'bar', 'fast_food', 'restaurant', 'canteen', 'nightclub', 'supermarket', 'shop', 'pharmacy', 'laundromat',
              'fuel', 'truck_stop', 'car_wash', 'car_repair', 'car_dealer', 'towing', 'car_rental', 'aquarium', 'botanical_garden',
              'planetarium', 'theatre', 'cinema', 'arts_centre', 'exhibition', 'music_venue', 'events_venue', 'zoo', 'worship', 'gym',
              'pool', 'recreation', 'fishing', 'viewpoint', 'island', 'plaza', 'rest_area', 'picnic', 'motel', 'hostel', 'guest_house',
              'coach')
SSA = re.compile(r'social\s+security|\bssa\b', re.I)
DMV = re.compile(r'\b(dmv|bmv|mvd|rmv|mva|motor\s+vehicles?|driver\s+(services|license|licensing)|secretary\s+of\s+state\s+(facility|driver)|license\s+(branch|office)|tag\s+office)\b', re.I)
BIG = re.compile(r'\b(google|alphabet|apple|oracle|microsoft|amazon|meta\s+platforms|facebook|intel|cisco|ibm|salesforce|adobe|nvidia|netflix|'
                 r'tesla|boeing|lockheed|northrop|raytheon|general\s+motors|ford\s+motor|general\s+electric|ge\s+(aerospace|healthcare|vernova)|'
                 r'jpmorgan|bank\s+of\s+america|wells\s+fargo|citi(group|bank)?|goldman|morgan\s+stanley|state\s+farm|allstate|'
                 r'walmart|target\s+corp|nike|starbucks|mcdonald|boeing|caterpillar|deere|abbott|abbvie|pfizer|merck|johnson\s*&\s*johnson|'
                 r'medtronic|qualcomm|amd|hp\s+inc|hewlett|dell|vmware|broadcom|paypal|ebay|uber|lyft|airbnb|linkedin|yahoo|'
                 r'servicenow|workday|intuit|autodesk|zoom|dropbox|twitter|snap|pinterest|expedia|t-mobile|verizon|at&t|comcast|'
                 r'disney|warner|paramount|sony|samsung|toyota|honda|nissan|hyundai|bmw|mercedes|volkswagen|siemens|bosch|'
                 r'united\s+airlines|american\s+airlines|delta\s+air|fedex|ups|kraft|mondelez|pepsico|coca-?cola|procter|3m|'
                 r'motorola|zebra|grainger|discover|exelon|accenture|deloitte|kpmg|pwc|ernst|mckinsey|capital\s+one|visa|mastercard|'
                 r'american\s+express|humana|cigna|unitedhealth|cvs|walgreens|kaiser|genentech|amgen|gilead|biogen|moderna)\b', re.I)  # per group, so one run stays within the time limit


def kind_of_osm(t):
    a = t.get('amenity')
    if a in ('school', 'college', 'university'):
        return a
    if t.get('shop') == 'mall':
        return 'mall'
    if a == 'marketplace':
        return 'market'
    lu = t.get('landuse')
    if lu == 'industrial':
        return 'industrial'
    if lu in ('commercial', 'retail') and re.search(r'business|office|corporate|tech(nology)?|research|industrial|commerce\s*park|center', t.get('name') or '', re.I):
        return 'business_park'
    if t.get('leisure') == 'park':
        return 'park'
    if t.get('public_transport') == 'station' or t.get('railway') in ('station', 'halt') or a == 'bus_station' \
            or t.get('station') in ('subway', 'light_rail', 'train'):
        return 'station'
    if a == 'ferry_terminal' or (t.get('public_transport') == 'station' and t.get('ferry') == 'yes'):
        return 'ferry'
    if t.get('aeroway') in ('aerodrome', 'terminal') and (t.get('iata') or t.get('website') or t.get('aeroway') == 'terminal'):
        return 'airport'
    if t.get('park_ride') in ('yes', 'bus', 'train') or (a == 'parking' and re.search(r'park\s*(&|and|n)\s*ride', t.get('name') or '', re.I)):
        return 'park_ride'
    if a == 'library':
        return 'library'
    if a == 'townhall':
        return 'townhall'
    if a == 'community_centre':
        return 'community'
    if a == 'hospital':
        return 'hospital'
    if t.get('leisure') == 'stadium':
        return 'stadium'
    if t.get('leisure') == 'sports_centre':
        return 'sports'
    if t.get('tourism') == 'hotel':
        return 'hotel'
    name = t.get('name') or ''
    if a == 'veterinary':
        return 'vet'
    if t.get('shop') in ('pet', 'pet_grooming') or a in ('animal_boarding', 'animal_shelter', 'animal_training') \
            or t.get('craft') == 'pet_grooming':
        return 'pet'
    if t.get('leisure') == 'dog_park':
        return 'dog_park'
    if a == 'police':
        return 'police'
    if a == 'fire_station':
        return 'fire_station'
    if a == 'prison':
        return 'prison'
    tour = t.get('tourism')
    if tour == 'attraction' or tour == 'theme_park' and False:
        return 'attraction'
    if tour == 'information' and t.get('information') in ('office', 'visitor_centre'):
        return 'visitor_center'
    if tour in ('resort',) or t.get('leisure') == 'resort':
        return 'resort'
    if tour in ('camp_site', 'caravan_site'):
        return 'campground'
    if tour == 'museum':
        return 'museum'
    if a == 'courthouse':
        return 'courthouse'
    if a == 'post_office':
        return 'post_office'
    if t.get('office') == 'government' or t.get('government'):
        return 'ssa' if SSA.search(name) else 'dmv' if DMV.search(name) else 'government'
    if DMV.search(name) and (t.get('office') or a == 'public_building'):
        return 'dmv'
    if t.get('office') in ('company', 'corporate') or t.get('landuse') == 'commercial' or t.get('building') in ('office', 'commercial'):
        if BIG.search(name) or BIG.search(t.get('operator') or '') or re.search(r'\b(campus|headquarters|hq|corporate\s+(center|campus|park))\b', name, re.I):
            return 'corporate'
    if t.get('office') == 'coworking' or t.get('amenity') == 'coworking_space':
        return 'coworking'
    if t.get('building') in ('office', 'commercial') or t.get('office') in ('property_management', 'estate_agent') and False:
        return 'office_building'  # the building's own site: tenants' amenities (bike room, storage, garage)
    return more_osm(t)


def more_osm(t):
    """Food, shops, auto, culture, leisure, lodging, coaches (the places riders go to every day)."""
    a, sh, tour, lei = t.get('amenity'), t.get('shop'), t.get('tourism'), t.get('leisure')
    name = t.get('name') or ''
    if a == 'cafe' or a == 'ice_cream':
        return 'cafe'
    if a in ('bar', 'pub', 'biergarten'):
        return 'bar'
    if a == 'fast_food':
        return 'fast_food'
    if a == 'restaurant':
        return 'restaurant'
    if a in ('canteen', 'food_court'):
        return 'canteen'
    if a == 'nightclub':
        return 'nightclub'
    if sh == 'supermarket':
        return 'supermarket'
    if a == 'pharmacy' or sh == 'chemist':
        return 'pharmacy'
    if sh in ('laundry', 'dry_cleaning'):
        return 'laundromat'
    if a == 'fuel':
        return 'truck_stop' if (t.get('hgv') == 'yes' and re.search(r'truck|travel\s*(center|plaza)|pilot|flying\s*j|love\'?s|ta\b|petro', name, re.I)) else 'fuel'
    if a == 'car_wash':
        return 'car_wash'
    if sh in ('car_repair', 'tyres', 'car_parts') or a == 'vehicle_inspection':
        return 'towing' if re.search(r'tow(ing)?\b|wrecker|recovery', name, re.I) else 'car_repair'
    if sh == 'car':
        return 'car_dealer'
    if a == 'car_rental':
        return 'car_rental'
    if tour == 'aquarium':
        return 'aquarium'
    if lei == 'garden' and t.get('garden:type') == 'botanical' or re.search(r'botanic', name, re.I) and lei in ('garden', 'park'):
        return 'botanical_garden'
    if a == 'planetarium':
        return 'planetarium'
    if a == 'theatre':
        return 'theatre'
    if a == 'cinema':
        return 'cinema'
    if a == 'arts_centre':
        return 'arts_centre'
    if a == 'exhibition_centre':
        return 'exhibition'
    if a == 'music_venue':
        return 'music_venue'
    if a in ('events_venue', 'conference_centre') or t.get('landuse') == 'fairground':
        return 'events_venue'
    if tour == 'zoo':
        return 'zoo'
    if a == 'place_of_worship':
        return 'worship'
    if lei == 'fitness_centre':
        return 'gym'
    if lei in ('swimming_pool', 'water_park') and False or lei == 'swimming_pool' or (lei == 'sports_centre' and 'swimming' in (t.get('sport') or '')):
        return 'pool'
    if lei == 'recreation_ground':
        return 'recreation'
    if lei == 'fishing':
        return 'fishing'
    if tour == 'viewpoint':
        return 'viewpoint'
    if t.get('place') in ('island', 'islet'):
        return 'island'
    if t.get('place') == 'square' or (t.get('highway') == 'pedestrian' and t.get('area') == 'yes'):
        return 'plaza'
    if t.get('highway') in ('rest_area', 'services'):
        return 'rest_area'
    if tour == 'picnic_site':
        return 'picnic'
    if tour == 'motel':
        return 'motel'
    if tour == 'hostel':
        return 'hostel'
    if tour == 'guest_house':
        return 'guest_house'
    if sh:
        return 'shop'  # toys, department stores, every other shop with a website: small businesses too
    return None


def kind_of_cat(cat):
    c = (cat or '').lower()
    if re.search(r'college|universit', c):
        return 'university' if 'univers' in c else 'college'
    if re.search(r'(elementary|middle|high|primary|secondary|public|private|charter)[\s_]*school|^school$|>\s*school\b', c):
        return 'school'
    if re.search(r'shopping[\s_]*(mall|center|centre)|\bmall\b', c):
        return 'mall'
    if re.search(r'farmers?[\s_]*market|flea[\s_]*market|public[\s_]*market|bazaar|marketplace', c):
        return 'market'
    if re.search(r'industrial[\s_]*(estate|park|area)|business[\s_]*park|office[\s_]*park|technology[\s_]*park|research[\s_]*park', c):
        return 'business_park'
    k = more_cat(c)
    if k:
        return k
    if re.search(r'veterinar|animal[\s_]*hospital', c):
        return 'vet'
    if re.search(r'dog[\s_]*park', c):
        return 'dog_park'
    if re.search(r'\bpet|dog[\s_]*(walk|sitter|train|groom|day)|animal[\s_]*(shelter|boarding|training)|kennel|groomer', c):
        return 'pet'
    if re.search(r'ferry', c) and not re.search(r'rental|charter', c):
        return 'ferry'
    if re.search(r'police', c):
        return 'police'
    if re.search(r'fire[\s_]*(station|department)', c):
        return 'fire_station'
    if re.search(r'prison|jail|correctional|detention', c):
        return 'prison'
    if re.search(r'visitor[\s_]*(center|centre|information)|tourist[\s_]*information', c):
        return 'visitor_center'
    if re.search(r'tourist[\s_]*attraction|landmark|historic[\s_]*site|monument|lighthouse|scenic[\s_]*(point|lookout)', c):
        return 'attraction'
    if re.search(r'campground|camp[\s_]*site|rv[\s_]*park', c):
        return 'campground'
    if re.search(r'\bmuseum', c):
        return 'museum'
    if re.search(r'\bairport|airport[\s_]*terminal', c) and not re.search(r'shuttle|parking|rental|lounge|hotel', c):
        return 'airport'
    if re.search(r'train[\s_]*station|bus[\s_]*station|transit[\s_]*station|metro[\s_]*station|subway|light[\s_]*rail|railway[\s_]*station|bus[\s_]*terminal', c):
        return 'station'
    if re.search(r'park[\s_]*(and|&|n)[\s_]*ride', c):
        return 'park_ride'
    if re.search(r'\blibrar', c):
        return 'library'
    if re.search(r'city[\s_]*hall|town[\s_]*hall', c):
        return 'townhall'
    if re.search(r'community[\s_]*(center|centre)|recreation[\s_]*center', c):
        return 'community'
    if re.search(r'\bhospital', c):
        return 'hospital'
    if re.search(r'stadium|arena', c):
        return 'stadium'
    if re.search(r'sports[\s_]*(center|centre|complex|club)|athletic', c):
        return 'sports'
    if re.search(r'\bhotel\b|\bresort\b', c):
        return 'hotel'
    if re.search(r'social[\s_]*security', c):
        return 'ssa'
    if re.search(r'motor[\s_]*vehicle|dmv|driver[\s_]*licens', c):
        return 'dmv'
    if re.search(r'courthouse|court[\s_]*house', c):
        return 'courthouse'
    if re.search(r'post[\s_]*office', c):
        return 'post_office'
    if re.search(r'government|federal|public[\s_]*service', c):
        return 'government'
    if re.search(r'corporate[\s_]*(office|campus)|headquarters', c):
        return 'corporate'
    if re.search(r'coworking|shared[\s_]*office|business[\s_]*center', c):
        return 'coworking'
    if re.search(r'office[\s_]*building|commercial[\s_]*real[\s_]*estate|property[\s_]*management|office[\s_]*space', c):
        return 'office_building'
    if re.search(r'(^|[>|_\s])park($|[\s_|])|city[\s_]*park|national[\s_]*park|state[\s_]*park|county[\s_]*park', c) \
            and not re.search(r'parking|amusement|water[\s_]*park|theme|rv[\s_]*park|dog[\s_]*park|skate|trailer|mobile[\s_]*home', c):
        return 'park'
    return None


MORE_CAT = [
    ('truck_stop', r'truck[\s_]*stop|travel[\s_]*(center|plaza)'), ('fuel', r'gas[\s_]*station|fuel'),
    ('car_wash', r'car[\s_]*wash|auto[\s_]*detail'), ('towing', r'towing'), ('car_rental', r'car[\s_]*rental|rent[\s_]*a[\s_]*car'),
    ('car_dealer', r'car[\s_]*dealer|auto[\s_]*dealer|used[\s_]*car'), ('car_repair', r'auto[\s_]*repair|car[\s_]*repair|tire|mechanic|body[\s_]*shop'),
    ('cafe', r'\bcafe|coffee|tea[\s_]*room|bakery[\s_]*cafe|ice[\s_]*cream'), ('nightclub', r'night[\s_]*club|dance[\s_]*club|disco'),
    ('bar', r'\bbar\b|_bar$|^bar_|\bpub\b|brewery|tavern|lounge|wine_bar|beer'), ('fast_food', r'fast[\s_]*food|burger|pizza|taco|sandwich'),
    ('canteen', r'cafeteria|canteen|food[\s_]*court'), ('restaurant', r'restaurant|diner|eatery|grill|bistro'),
    ('supermarket', r'supermarket|grocery'), ('pharmacy', r'pharmacy|drugstore'), ('laundromat', r'laundromat|laundry|dry[\s_]*clean'),
    ('aquarium', r'aquarium'), ('botanical_garden', r'botanical'), ('planetarium', r'planetarium|observatory'),
    ('theatre', r'theat(er|re)|performing[\s_]*arts|opera'), ('cinema', r'cinema|movie[\s_]*theat'),
    ('arts_centre', r'arts?[\s_]*cent(er|re)|gallery'), ('exhibition', r'exhibition|convention[\s_]*cent'),
    ('music_venue', r'music[\s_]*venue|concert|amphitheat'), ('events_venue', r'event[\s_]*venue|fairground|festival|venue_and_event'),
    ('zoo', r'\bzoo\b|wildlife[\s_]*park'), ('worship', r'church|cathedral|mosque|synagogue|temple|place[\s_]*of[\s_]*worship'),
    ('pool', r'swimming[\s_]*pool|aquatic'), ('gym', r'\bgym\b|fitness|yoga|crossfit'),
    ('fishing', r'fishing'), ('viewpoint', r'scenic[\s_]*(lookout|viewpoint)|observation[\s_]*deck|viewpoint'),
    ('rest_area', r'rest[\s_]*(area|stop)'), ('recreation', r'recreation[\s_]*area'), ('plaza', r'\bplaza\b|public[\s_]*square'),
    ('motel', r'\bmotel'), ('hostel', r'hostel'), ('guest_house', r'bed[\s_]*and[\s_]*breakfast|guest[\s_]*house|inn\b'),
    ('coach', r'bus[\s_]*(service|charter|tour|line)|coach|charter[\s_]*bus|shuttle'),
    ('shop', r'toy|department[\s_]*store|discount[\s_]*store|clothing|shoe|book[\s_]*store|hardware|electronics|furniture|'
             r'gift|jewel|sporting[\s_]*goods|retail|boutique|convenience|outlet'),
]


def more_cat(c):
    for k, rx in MORE_CAT:
        if re.search(rx, c):
            return k
    return None


def from_pbf(pbf, out_json):
    import osmium
    dest = []

    def rec(oid, lat, lon, t):
        k = kind_of_osm(t)
        name = t.get('name')
        if not k or not name:
            return
        if k in ('industrial', 'business_park', 'park', 'government', 'corporate', 'office_building', 'coworking',
                 'attraction', 'museum', 'campground', 'resort') + tuple(MORE_KINDS) and not (t.get('website') or t.get('contact:website') or t.get('operator')):
            return  # thousands of unnamed-on-the-web lots: only the ones with a website or a manager
        dest.append([oid, round(lat, 6), round(lon, 6), {x: v for x, v in {
            'kind': k, 'name': name, 'website': t.get('website') or t.get('contact:website') or t.get('url'),
            'operator': t.get('operator'), 'phone': t.get('phone') or t.get('contact:phone'), 'source': 'OpenStreetMap'}.items() if v}])

    class H(osmium.SimpleHandler):
        def node(self, n):
            if n.tags and n.location.valid():
                rec(f'node/{n.id}', n.location.lat, n.location.lon, dict(n.tags))

        def way(self, w):
            pts = [(nd.lat, nd.lon) for nd in w.nodes if nd.location.valid()]
            if pts:
                rec(f'way/{w.id}', sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts), dict(w.tags))

    H().apply_file(pbf, locations=True)
    json.dump({'dest': dest}, open(out_json, 'w'))
    by = {}
    for d in dest:
        by[d[3]['kind']] = by.get(d[3]['kind'], 0) + 1
    print(f'{pbf}: {len(dest)} places {by} ({sum(1 for d in dest if d[3].get("website"))} with a website)', flush=True)


def overture(group):
    import duckdb
    cat = json.loads(urllib.request.urlopen('https://stac.overturemaps.org/catalog.json', timeout=60).read())
    release = cat.get('latest') or sorted(l['href'].split('/')[1] for l in cat['links'] if l.get('rel') == 'child')[-1]
    release = release.strip('./').split('/')[0]
    rx = {'campus': 'school|college|universit', 'shopping': 'mall|shopping_center|market|bazaar',
          'work': 'industrial|business_park|office_park|technology_park|research_park', 'parks': 'park',
          'transit': 'station|park_and_ride|park_ride|transit|subway|light_rail|bus_terminal|airport|ferry|bus_service|charter|coach|shuttle',
          'travel': 'tourist|attraction|landmark|historic|monument|lighthouse|scenic|visitor|resort|campground|camp_site|rv_park|museum',
          'safety': 'police|fire_station|fire_department|prison|jail|correctional|detention',
          'pets': 'veterinar|animal|pet|dog|kennel|groom',
          'food': 'cafe|coffee|bar|pub|brewery|tavern|lounge|fast_food|burger|pizza|taco|restaurant|diner|eatery|grill|cafeteria|food_court|night_club|ice_cream',
          'retail': 'supermarket|grocery|pharmacy|drugstore|laundr|dry_clean|toy|department_store|discount|clothing|shoe|book|hardware|electronics|furniture|gift|jewel|sporting_goods|retail|boutique|convenience|outlet|shop|store',
          'auto': 'gas_station|fuel|truck_stop|travel_center|car_wash|auto_detail|towing|car_rental|car_dealer|auto_dealer|used_car|auto_repair|car_repair|tire|mechanic|body_shop',
          'culture': 'aquarium|botanical|planetarium|observatory|theat|performing_arts|opera|cinema|movie|arts|gallery|exhibition|convention|music_venue|concert|amphitheat|event|fairground|festival|zoo|church|cathedral|mosque|synagogue|temple|worship',
          'leisure': 'gym|fitness|yoga|swimming|aquatic|fishing|lookout|viewpoint|observation|rest_area|rest_stop|recreation|plaza|square',
          'lodging': 'motel|hostel|bed_and_breakfast|guest_house|inn', 'civic': 'librar|city_hall|town_hall|community_center|recreation_center|hospital',
          'sports': 'stadium|arena|sports|athletic', 'hotels': 'hotel|resort',
          'government': 'government|social_security|motor_vehicle|dmv|courthouse|post_office|federal|public_service',
          'corporate': 'corporate|headquarters|office|technology|software|company',
          'offices': 'coworking|shared_office|business_center|office_building|commercial_real_estate|property_management|office_space'}[group]
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2';")
    q = f"""
      SELECT id, names.primary, CAT_EXPR, (bbox.ymin + bbox.ymax) / 2, (bbox.xmin + bbox.xmax) / 2, websites[1], phones[1]
      FROM read_parquet('s3://overturemaps-us-west-2/release/{release}/theme=places/type=place/*', hive_partitioning=1)
      WHERE bbox.xmin BETWEEN -180 AND -65 AND bbox.ymin BETWEEN 17 AND 72 AND addresses[1].country = 'US'
        AND confidence >= 0.6 AND websites[1] IS NOT NULL AND regexp_matches(lower(CAT_EXPR), '{rx}')
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
    out = []
    for i, n, c, la, lo, w, ph in rows:
        k = kind_of_cat(c)
        if group == 'government' and n:
            k = 'ssa' if SSA.search(n) else 'dmv' if DMV.search(n) else k
        if group == 'corporate':
            k = 'corporate' if n and (BIG.search(n) or re.search(r'\b(campus|headquarters|hq)\b', n, re.I)) else None
        if k and n and GROUP[k] == group:
            out.append([f'ovt/{i}', round(la, 6), round(lo, 6), {x: v for x, v in {
                'kind': k, 'name': n, 'website': w, 'phone': ph, 'source': 'Overture Maps'}.items() if v}])
    print(f'Overture {group}: {len(out)} places with a website', flush=True)
    return out


def host_path(u):
    u = u if '://' in u else 'https://' + u
    p = urllib.parse.urlsplit(u)
    return p.netloc.lower().removeprefix('www.') + p.path.rstrip('/')


def main_group(group, parts):
    osm = [d for f in parts for d in json.load(open(f))['dest'] if GROUP.get(d[3]['kind']) == group]
    lists = [osm]
    try:
        lists.append(overture(group))
    except Exception as err:
        print(f'overture failed: {err}', flush=True)
    dest = wf.merge_dest(lists)
    sites = {}
    for d in dest:
        w = (d[3].get('website') or '').strip()
        if w and not re.search(r'facebook\.com|instagram\.com|yelp\.com|google\.|wikipedia\.org|tripadvisor', w, re.I):
            sites.setdefault(host_path(w), {'url': w if '://' in w else 'https://' + w, 'dest': []})['dest'].append(d)
    keys = sorted(sites, key=lambda k: (len(sites[k]['dest']) > 20, -min(len(sites[k]['dest']), 20)))[:MAX_SITES]
    print(f'{group}: {len(dest)} places, {len(sites)} websites, reading {len(keys)}', flush=True)
    with ThreadPoolExecutor(max_workers=128) as pool:
        got = dict(zip(keys, pool.map(lambda k: wf.read_site(sites[k]['url']), keys)))
    grid = wf.packs_parking()
    added, said, done = [], {k: 0 for k in wf.SAYS}, set()
    vlabel = {'bike': 'bike parking', 'moto': 'motorcycle parking', 'scooter': 'scooter parking', 'rent': 'bike rental',
              'pump': 'air pump', 'repair': 'bike repair station', 'charge': 'e-bike charging', 'wash': 'bike wash', 'mwash': 'motorcycle wash'}
    amen = {'bike': 'bicycle_parking', 'moto': 'motorcycle_parking', 'scooter': 'small_electric_vehicle_parking',
            'rent': 'bicycle_rental', 'pump': 'compressed_air', 'repair': 'bicycle_repair_station',
            'charge': 'charging_station', 'wash': 'bicycle_wash', 'mwash': 'bicycle_wash'}
    for k_site in keys:
        r = got.get(k_site) or {}
        ds = sites[k_site]['dest']
        shared = len(ds) > 1
        for k, v in (r.get('says') or {}).items():
            said[k] += 1
            for d in ds:
                # a district / park-district site that lists one thing does not mean every school / park has it:
                # a site shared by several places counts only for the place its page names (in the text or the address)
                key = wf.norm(d[3]['name'])[:12]
                if shared and key not in wf.norm(v['snip']) and key not in wf.norm(v['page']):
                    continue
                twin = (wf.norm(d[3]['name']), k, round(d[1], 2), round(d[2], 2))
                if twin in done:
                    continue  # the same college / mall twice (two map objects with one name)
                done.add(twin)
                if wf.has_near(grid, k, d[1], d[2]):
                    continue
                t = {'amenity': amen[k], 'name': f'{d[3]["name"]} · {vlabel[k]}', 'fee': v.get('fee'), 'charge': v.get('charge'),
                     'website': v['page'], 'operator': d[3].get('operator'), 'phone': d[3].get('phone'),
                     'mobility:near': d[3]['name'], 'mobility:near_kind': LABEL[d[3]['kind']],
                     'mobility:approx': 'yes', 'description': v['snip'], 'source': f'Website of {d[3]["name"]}'}
                if k == 'bike':
                    t['bicycle_parking'] = 'stands'
                if k == 'charge':
                    t.update({'bicycle': 'yes', 'scooter': 'yes'})
                if k == 'mwash':
                    t['motorcycle'] = 'yes'
                added.append([f'wtr/{d[0]}/{k}', d[1], d[2], {x: y for x, y in t.items() if y}])
                grid.setdefault((round(d[1] / 0.01), round(d[2] / 0.01)), []).append((k, d[1], d[2]))
    os.makedirs(os.path.join(ROOT, 'data', 'venues'), exist_ok=True)
    json.dump(added, open(os.path.join(ROOT, 'data', 'venues', f'{group}.json'), 'w'), separators=(',', ':'), ensure_ascii=False)
    kinds, by_added = {}, {}
    for d in dest:
        kinds[d[3]['kind']] = kinds.get(d[3]['kind'], 0) + 1
    for a in added:
        by_added[a[3]['amenity']] = by_added.get(a[3]['amenity'], 0) + 1
    read = sum(1 for v in got.values() if v and v.get('pages'))
    with open(os.path.join(ROOT, 'data', 'venues', f'REPORT_{group}.md'), 'w', encoding='utf-8') as f:
        f.write(f'# {group}: {len(dest)} places\n\nBy kind: {kinds}\n\nWebsites: {len(sites)} · read: {read}/{len(keys)}\n\n'
                f'Websites that mention: {said}\n\nAdded (not on the map within 300 m): {len(added)} · {by_added}\n\n## Added around Chicago\n')
        for a in added:
            if abs(a[1] - 41.88) < 0.6 and abs(a[2] + 87.7) < 0.8:
                f.write(f'- {a[3]["name"]} · {a[3]["website"]}\n  > {a[3]["description"][:200]}\n')
    print(f'{group}: places {kinds} · read {read}/{len(keys)} · mention {said} · added {len(added)} {by_added}', flush=True)


def test():
    assert kind_of_osm({'amenity': 'university'}) == 'university' and kind_of_osm({'shop': 'mall'}) == 'mall'
    assert kind_of_osm({'landuse': 'commercial', 'name': 'Oak Brook Business Park'}) == 'business_park'
    assert kind_of_cat('shopping_mall') == 'mall' and kind_of_cat('farmers_market') == 'market'
    assert kind_of_cat('park') == 'park' and kind_of_cat('parking') is None and kind_of_cat('dog_park') == 'dog_park'
    assert kind_of_osm({'railway': 'station'}) == 'station' and kind_of_osm({'amenity': 'library'}) == 'library'
    assert kind_of_cat('train_station') == 'station' and kind_of_cat('hotel') == 'hotel' and kind_of_cat('stadium_arena') == 'stadium'
    assert kind_of_osm({'office': 'government', 'name': 'Social Security Administration'}) == 'ssa'
    assert kind_of_osm({'office': 'government', 'name': 'Illinois Secretary of State Driver Services Facility'}) == 'dmv'
    assert kind_of_osm({'office': 'company', 'name': 'Google Chicago'}) == 'corporate'
    assert kind_of_osm({'office': 'company', 'name': 'Joe Plumbing LLC'}) is None
    assert kind_of_osm({'building': 'office', 'name': '150 North Riverside'}) == 'office_building'
    assert kind_of_osm({'office': 'coworking', 'name': 'WeWork'}) == 'coworking'
    assert kind_of_cat('coworking_space') == 'coworking' and kind_of_cat('commercial_real_estate') == 'office_building'
    s2 = wf.what_page_says('Amenities: fitness center, secure bike room with repair stand, EV and e-bike charging in the garage.')
    assert 'bike' in s2 and 'repair' in s2 and 'charge' in s2, s2
    assert kind_of_osm({'aeroway': 'aerodrome', 'iata': 'ORD'}) == 'airport' and kind_of_cat('airport') == 'airport'
    assert kind_of_osm({'railway': 'station', 'station': 'subway'}) == 'station'
    assert kind_of_cat('airport_shuttle') == 'coach'
    assert kind_of_osm({'amenity': 'ferry_terminal'}) == 'ferry' and kind_of_osm({'amenity': 'police'}) == 'police'
    assert kind_of_osm({'tourism': 'information', 'information': 'office'}) == 'visitor_center'
    assert kind_of_cat('ferry_service') == 'ferry' and kind_of_cat('tourist_attraction') == 'attraction'
    assert kind_of_cat('fire_department') == 'fire_station' and kind_of_cat('jail_and_prison') == 'prison'
    assert kind_of_osm({'amenity': 'veterinary'}) == 'vet' and kind_of_osm({'shop': 'pet'}) == 'pet'
    assert kind_of_cat('dog_walkers') == 'pet' and kind_of_cat('veterinarian') == 'vet' and kind_of_cat('dog_park') == 'dog_park'
    assert kind_of_osm({'amenity': 'fuel', 'name': 'Shell'}) == 'fuel' and kind_of_osm({'shop': 'toys'}) == 'shop'
    assert kind_of_osm({'place': 'island', 'name': 'Northerly Island'}) == 'island' and kind_of_osm({'highway': 'rest_area'}) == 'rest_area'
    assert kind_of_osm({'shop': 'car_repair', 'name': 'Joe\'s Towing'}) == 'towing' and kind_of_osm({'tourism': 'motel'}) == 'motel'
    assert kind_of_cat('coffee_shop') == 'cafe' and kind_of_cat('laundromat') == 'laundromat' and kind_of_cat('truck_stop') == 'truck_stop'
    assert kind_of_cat('planetarium') == 'planetarium' and kind_of_cat('motel') == 'motel' and kind_of_cat('toy_store') == 'shop'
    s3 = wf.what_page_says('We now wash motorcycles too: our motorcycle wash bay is open daily. Free air for your tires at every pump island.')
    assert 'mwash' in s3 and 'pump' in s3, s3
    assert kind_of_cat('college_university') == 'university' and kind_of_cat('elementary_school') == 'school'
    s = wf.what_page_says('Campus bike repair stations are located outside the library and the student union. '
                          'E-bike charging is available in Garage B.')
    assert 'repair' in s and 'charge' in s, s
    print('rules ok')


if __name__ == '__main__':
    test()
    if '--test' in sys.argv:
        sys.exit()
    if '--pbf' in sys.argv:
        i = sys.argv.index('--pbf')
        from_pbf(sys.argv[i + 1], sys.argv[i + 2])
    elif '--group' in sys.argv:
        i = sys.argv.index('--group')
        main_group(sys.argv[i + 1], [a for a in sys.argv[i + 2:] if a.endswith('.json')])
