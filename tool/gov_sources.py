"""Other administrations that publish our data: federal catalog (data.gov: cities, counties, MPOs, state DOTs, transit agencies, universities),
state DOT / state GIS / state capital sites, and regional planning bodies (MPO / council of governments).
1. data.gov CKAN API, every category keyword -> resources (ArcGIS FeatureServer, GeoJSON, CSV, KML, SHP, XLSX, PDF).
2. state sites crawled for files like city_files.py does.
Output: data/gov_sources/index.json, REPORT.md and downloaded small files (rows extracted)."""
import json, os, re, sys, time, urllib.parse, concurrent.futures as cf
import requests
sys.path.insert(0, os.path.dirname(__file__))
import city_files as cfx

OUT = 'data/gov_sources'
UA = cfx.UA
CATS = {
 'racks': ['bicycle parking', 'bike racks', 'bike corrals', 'bike parking'],
 'secure': ['bike lockers', 'bike cage', 'bike station', 'bicycle shelter', 'bike room'],
 'scooter': ['scooter parking', 'e-scooter corral', 'micromobility parking', 'dockless parking zones'],
 'moto': ['motorcycle parking', 'moped parking'],
 'repair': ['bike repair station', 'bicycle fix-it', 'bike pump'],
 'charging': ['e-bike charging', 'bicycle charging station'],
 'network': ['bikeways', 'bike lanes', 'bicycle facilities', 'bike routes', 'multi-use trails', 'greenways'],
 'routes': ['historic trail', 'scenic byway bicycle', 'heritage trail', 'bicycle route map'],
 'parking': ['parking garages', 'parking lots public', 'parking meters', 'parking rates'],
 'waterfront': ['waterfront trail', 'riverwalk', 'lakefront path', 'harbor walk'],
}
WANTFMT = re.compile(r'geojson|csv|kml|shp|shapefile|xlsx?|zip|featureserver|mapserver|arcgis|wfs|json|pdf|geodatabase', re.I)

def ckan(q, rows=100, start=0):
    try:
        r = requests.get('https://catalog.data.gov/api/3/action/package_search', params={'q': q, 'rows': rows, 'start': start}, headers=UA, timeout=40)
        return r.json()['result']
    except Exception:
        return {'results': [], 'count': 0}

def harvest():
    found = {}
    def one(args):
        cat, q = args
        out = []
        for start in (0, 100, 200):
            res = ckan(q, 100, start)
            for p in res.get('results', []):
                out.append((cat, p))
            if start + 100 >= res.get('count', 0):
                break
        return out
    jobs = [(c, q) for c, qs in CATS.items() for q in qs]
    with cf.ThreadPoolExecutor(6) as ex:
        for lst in ex.map(one, jobs):
            for cat, p in lst:
                pid = p.get('id')
                title = p.get('title', '')
                if not cfx.STRONG.search(title + ' ' + (p.get('notes') or '')[:300]):
                    continue
                e = found.setdefault(pid, {'title': title, 'org': (p.get('organization') or {}).get('title', ''), 'cats': set(), 'res': {}, 'page': f"https://catalog.data.gov/dataset/{p.get('name')}"})
                e['cats'].add(cat)
                for r in p.get('resources', []):
                    u = r.get('url') or ''
                    f = (r.get('format') or '') + ' ' + u
                    if u and WANTFMT.search(f):
                        e['res'][u] = (r.get('format') or '').upper()
    return found

STATE_SITES = """dot.alabama.gov alaskadot.gov azdot.gov ardot.gov dot.ca.gov codot.gov ct.gov/dot deldot.gov fdot.gov dot.ga.gov hidot.hawaii.gov itd.idaho.gov idot.illinois.gov in.gov/indot iowadot.gov ksdot.gov transportation.ky.gov dotd.la.gov maine.gov/mdot mdot.maryland.gov mass.gov/orgs/massachusetts-department-of-transportation michigan.gov/mdot dot.state.mn.us mdot.ms.gov modot.org mdt.mt.gov dot.nebraska.gov dot.nv.gov dot.nh.gov nj.gov/transportation dot.nm.gov dot.ny.gov ncdot.gov dot.nd.gov transportation.ohio.gov odot.org oregon.gov/odot penndot.pa.gov dot.ri.gov scdot.org dot.sd.gov tn.gov/tdot txdot.gov udot.utah.gov vtrans.vermont.gov virginiadot.org wsdot.wa.gov transportation.wv.gov wisconsindot.gov dot.state.wy.us""".split()
# state capitals and regional planning bodies (MPO / COG) that publish bike inventories
REGION_SITES = """cmap.illinois.gov ctps.org dvrpc.org mwcog.org oregonmetro.gov nctcog.org sandag.org scag.ca.gov mtc.ca.gov psrc.org drcog.org maricopa.gov/maricopa-association-of-governments azmag.gov houstontx.gov/planning h-gac.org capcog.org campotexas.org atlantaregional.com mwcog.org nvtc.gov hrtpo.org crcog.org nymtc.org mapc.org regionalplanning.org miamidade.gov/mpo sfcta.org octa.net metro.net mnmpo.org metrocouncil.org mpo.nashville.gov oki.org macog.com semcog.org nirpc.org""".split()
CAPITALS = """montgomeryal.gov juneau.org phoenix.gov littlerock.gov sacramento.gov denvergov.org hartford.gov dover.de.us talgov.com atlantaga.gov honolulu.gov cityofboise.org springfield-il.gov indy.gov dsm.city topeka.org lexingtonky.gov brgov.com augustamaine.gov annapolis.gov boston.gov lansing.org stpaul.gov jacksonms.gov jeffersoncitymo.gov helenamt.gov lincoln.ne.gov carson.org concordnh.gov trentonnj.org santafenm.gov albanyny.gov raleighnc.gov bismarck.nd.us columbus.gov oklahomacity.gov salemoregon.net harrisburgpa.gov providenceri.gov columbiasc.gov pierre.org nashville.gov austintexas.gov slc.gov montpelier-vt.org richmondgov.com olympiawa.gov charlestonwv.gov madison.com cheyennecity.org""".split()


# state parks / natural resources (trails, scenic routes) and state GIS / open-data portals
PARKS_SITES = """alapark.com dnr.alaska.gov azstateparks.com arkansasstateparks.com parks.ca.gov cpw.state.co.us portal.ct.gov/deep destateparks.com floridastateparks.org gastateparks.org dlnr.hawaii.gov parksandrecreation.idaho.gov dnr.illinois.gov in.gov/dnr iowadnr.gov ksoutdoors.gov parks.ky.gov lastateparks.com maine.gov/dacf/parks dnr.maryland.gov mass.gov/orgs/department-of-conservation-and-recreation michigan.gov/dnr dnr.state.mn.us mdwfp.com mostateparks.com stateparks.mt.gov outdoornebraska.gov parks.nv.gov nhstateparks.org nj.gov/dep/parksandforests emnrd.nm.gov/spd parks.ny.gov ncparks.gov parkrec.nd.gov ohiodnr.gov travelok.com stateparks.oregon.gov dcnr.pa.gov riparks.ri.gov southcarolinaparks.com gfp.sd.gov tnstateparks.com tpwd.texas.gov stateparks.utah.gov vtstateparks.com dcr.virginia.gov parks.wa.gov wvstateparks.com dnr.wisconsin.gov wyoparks.wyo.gov""".split()
GIS_SITES = """gis.data.alaska.gov azgeo-open-data-agic.hub.arcgis.com gis.arkansas.gov gis.data.ca.gov data.colorado.gov geodata.ct.gov firstmap.delaware.gov geodata.floridagio.gov data.georgiaspatial.org geoportal.hawaii.gov gis.idaho.gov clearinghouse.isgs.illinois.edu indianamap.org geodata.iowa.gov kansasgis.org kygeoportal.ky.gov atlas.ga.lsu.edu maine.gov/geolib data.imap.maryland.gov mass.gov/orgs/massgis-bureau-of-geographic-information gis-michigan.opendata.arcgis.com gisdata.mn.gov maris.state.ms.us msdis.missouri.edu geoinfo.msl.mt.gov nebraskamap.gov nevadaseh.org granit.unh.edu njgin.nj.gov rgis.unm.edu gis.ny.gov nconemap.gov gishubdata.nd.gov geohio.oit.ohio.gov data.ok.gov geohub.oregon.gov pasda.psu.edu rigis.org gis.sc.gov opendata2017-09-18t192802468z-sdbit.opendata.arcgis.com tnmap.tn.gov data.tnris.org gis.utah.gov geodata.vermont.gov vgin.vdem.virginia.gov geo.wa.gov wvgis.wvu.edu geodata.wisc.edu wyomingspatialhub.com""".split()

def write_sites(path='data/foia/gov_sites.json'):
    out = []
    for label, sites in (('state', STATE_SITES), ('region', REGION_SITES), ('capital', CAPITALS), ('parks', PARKS_SITES), ('gis', GIS_SITES)):
        for x in sites:
            out.append({'city': f'{label}:{x}', 'site': x.split('/')[0]})
    seen, uniq = set(), []
    for c in out:
        if c['site'] not in seen:
            seen.add(c['site']); uniq.append(c)
    json.dump(uniq, open(path, 'w'), indent=0)
    print(len(uniq), 'sites')

def harvest_only():
    os.makedirs(OUT, exist_ok=True)
    found = harvest()
    rep = ['# data.gov datasets with our categories\n', f'Datasets: {len(found)}\n', '| Publisher | Datasets | Categories |', '|---|---|---|']
    byorg = {}
    for e in found.values():
        byorg.setdefault(e['org'] or '?', []).append(e)
    for org, lst in sorted(byorg.items(), key=lambda x: -len(x[1]))[:300]:
        rep.append(f"| {org} | {len(lst)} | {', '.join(sorted(set(c for e in lst for c in e['cats'])))} |")
    json.dump({'datasets': [{**e, 'cats': sorted(e['cats'])} for e in found.values()]}, open(f'{OUT}/datagov.json', 'w'), indent=1, ensure_ascii=False)
    open(f'{OUT}/REPORT_datagov.md', 'w').write('\n'.join(rep) + '\n')
    print('\n'.join(rep[:40]))

def crawl_sites(sites, label):
    cities = [{'city': f'{label}:{s}', 'site': s.split('/')[0]} for s in sites]
    out = []
    with cf.ThreadPoolExecutor(8) as ex:
        res = list(ex.map(lambda c: (c, cfx.crawl_city(c)), cities))
    return res

def main():
    os.makedirs(OUT, exist_ok=True)
    cfx.OUT = OUT + '/files'
    found = harvest()
    rep = ['# Other administrations\n', f'data.gov datasets with our categories: {len(found)}\n']
    byorg = {}
    for e in found.values():
        byorg.setdefault(e['org'] or '?', []).append(e)
    rep += ['| Publisher | Datasets | Categories |', '|---|---|---|']
    for org, lst in sorted(byorg.items(), key=lambda x: -len(x[1]))[:150]:
        rep.append(f"| {org} | {len(lst)} | {', '.join(sorted(set(c for e in lst for c in e['cats'])))} |")
    idx = {'datasets': [{**e, 'cats': sorted(e['cats'])} for e in found.values()]}
    files = {}
    for label, sites in (('state', STATE_SITES), ('region', REGION_SITES), ('capital', CAPITALS)):
        for c, (fl, pt) in crawl_sites(sites, label):
            files[c['city']] = {'files': list(fl.items())[:25], 'portals': pt}
    for key, v in files.items():
        got = []
        for u, txt in v['files']:
            p = cfx.download(key, u)
            if not p: continue
            rows = cfx.extract(p)
            useful = [r for r in rows if cfx.STRONG.search(json.dumps(r, ensure_ascii=False))]
            got.append({'url': u, 'text': txt, 'file': p, 'rows': len(rows), 'bike_rows': len(useful)})
            if useful:
                json.dump(useful[:3000], open(p + '.rows.json', 'w'), ensure_ascii=False)
        v['got'] = got
        del v['files']
    idx['sites'] = files
    json.dump(idx, open(f'{OUT}/index.json', 'w'), indent=1, ensure_ascii=False)
    rep += ['\n## State / regional / capital sites\n', '| Site | Files | Portals |', '|---|---|---|']
    for k, v in files.items():
        rep.append(f"| {k} | {len(v['got'])} ({sum(g['bike_rows'] for g in v['got'])} rows) | {len(v['portals'])} |")
    open(f'{OUT}/REPORT.md', 'w').write('\n'.join(rep) + '\n')
    print('\n'.join(rep[:60]))

if __name__ == '__main__':
    if 'sites' in sys.argv:
        write_sites()
    elif 'harvest' in sys.argv:
        harvest_only()
    else:
        main()
