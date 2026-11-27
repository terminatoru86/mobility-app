"""Where to send a public-records request in each city that publishes no bike-parking data.
Reads the official city website: home page, then pages whose link says public records / open records / FOIA /
right to know / public information, plus a few usual paths. Keeps request portals (GovQA, NextRequest, JustFOIA,
Granicus...) and e-mail addresses that look like the records office. Output: data/foia/contacts.json + CONTACTS.md"""
import json, re, sys, urllib.request, urllib.parse, concurrent.futures as cf

CITIES = {
 'Houston TX': 'houstontx.gov', 'Phoenix AZ': 'phoenix.gov', 'Philadelphia PA': 'phila.gov',
 'San Antonio TX': 'sa.gov', 'Jacksonville FL': 'jacksonville.gov', 'Fort Worth TX': 'fortworthtexas.gov',
 'Columbus OH': 'columbus.gov', 'Charlotte NC': 'charlottenc.gov', 'Indianapolis IN': 'indy.gov',
 'Oklahoma City OK': 'okc.gov', 'El Paso TX': 'elpasotexas.gov', 'Las Vegas NV': 'lasvegasnevada.gov',
 'Louisville KY': 'louisvilleky.gov', 'Albuquerque NM': 'cabq.gov', 'Tucson AZ': 'tucsonaz.gov',
 'Fresno CA': 'fresno.gov', 'Kansas City MO': 'kcmo.gov', 'Colorado Springs CO': 'coloradosprings.gov',
 'Virginia Beach VA': 'vbgov.com', 'Bakersfield CA': 'bakersfieldcity.us', 'Wichita KS': 'wichita.gov',
 'Arlington TX': 'arlingtontx.gov', 'Tampa FL': 'tampa.gov', 'Anaheim CA': 'anaheim.net',
 'Lexington KY': 'lexingtonky.gov', 'Stockton CA': 'stocktonca.gov', 'Corpus Christi TX': 'corpuschristitx.gov',
 'Henderson NV': 'cityofhenderson.com', 'Orlando FL': 'orlando.gov', 'Anchorage AK': 'muni.org',
 'Plano TX': 'plano.gov', 'Durham NC': 'durhamnc.gov', 'Chandler AZ': 'chandleraz.gov', 'Toledo OH': 'toledo.oh.gov',
 'Madison WI': 'cityofmadison.com', 'Gilbert AZ': 'gilbertaz.gov', 'Reno NV': 'reno.gov',
 'Fort Wayne IN': 'cityoffortwayne.org', 'North Las Vegas NV': 'cityofnorthlasvegas.com',
 'St. Petersburg FL': 'stpete.org', 'Lubbock TX': 'ci.lubbock.tx.us', 'Irving TX': 'cityofirving.org',
 'Laredo TX': 'cityoflaredo.com', 'Winston-Salem NC': 'cityofws.org', 'Chesapeake VA': 'cityofchesapeake.net',
 'Glendale AZ': 'glendaleaz.com', 'Garland TX': 'garlandtx.gov', 'Boise ID': 'cityofboise.org',
 'Fremont CA': 'fremont.gov', 'Spokane WA': 'my.spokanecity.org', 'Santa Clarita CA': 'santaclarita.gov',
 'Baton Rouge LA': 'brla.gov', 'Tacoma WA': 'cityoftacoma.org', 'San Bernardino CA': 'sbcity.org',
 'Modesto CA': 'modestogov.com', 'Fontana CA': 'fontanaca.gov', 'Des Moines IA': 'dsm.city',
 'Birmingham AL': 'birminghamal.gov', 'Salt Lake City UT': 'slc.gov', 'Hartford CT': 'hartfordct.gov',
 'Little Rock AR': 'littlerock.gov', 'Savannah GA': 'savannahga.gov', 'Ann Arbor MI': 'a2gov.org',
 'Portland ME': 'portlandmaine.gov', 'Jackson MS': 'jacksonms.gov', 'Columbia SC': 'columbiasc.gov',
 'Sioux Falls SD': 'siouxfalls.gov', 'Fargo ND': 'fargond.gov', 'Billings MT': 'billingsmt.gov',
 'Cheyenne WY': 'cheyennecity.org', 'Manchester NH': 'manchesternh.gov', 'Wilmington DE': 'wilmingtonde.gov',
 'Charleston WV': 'charlestonwv.gov',
}
UA = 'Mozilla/5.0 (compatible; MOBIlityBot/1.0; +https://github.com/terminatoru86/mobility-app)'
WORDS = re.compile(r'public[\s-]*records?|open[\s-]*records?|records?\s*requests?|foia|freedom of information|'
                   r'right[\s-]*to[\s-]*know|public[\s-]*information|open[\s-]*government|sunshine', re.I)
PORTAL = re.compile(r'https?://[^\s"\'<>]*(govqa\.us|mycusthelp\.(com|net)|nextrequest\.com|justfoia\.com|'
                    r'granicus|foia\.?[^\s"\'<>/]*|publicrecords?[^\s"\'<>/]*|records?center)[^\s"\'<>]*', re.I)
MAIL = re.compile(r'[\w.+-]+@[\w-]+(\.[\w-]+)+')
GOOD_MAIL = re.compile(r'record|foia|pia|clerk|openrec|publicinfo|righttoknow|rtk|cpra|pra\b|sunshine|transparen', re.I)
import os as _os
WIDE = _os.environ.get('WIDE') == '1'
OFFICE_MAIL = re.compile(r'^(info|admin|office|cityhall|townhall|townoffice|villagehall|villageoffice|boroughhall|'
                         r'village|town|city|borough|township|twp|contact|contactus|general|manager|citymanager|'
                         r'townmanager|administrator|secretary|treasurer|clerktreas|clerk-treas)[\w.-]*$', re.I)
PATHS = ['/contact', '/contact-us', '/contactus', '/government', '/town-office', '/administration'] if WIDE else []
PATHS += ['/public-records', '/publicrecords', '/open-records', '/foia', '/records', '/public-records-request',
         '/departments/city-clerk', '/clerk', '/government/public-records', '/cityclerk']


def get(url):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept': 'text/html'})
        with urllib.request.urlopen(req, timeout=25) as r:
            if 'html' not in (r.headers.get('Content-Type') or ''):
                return None, url
            return r.read(1_500_000).decode('utf-8', 'replace'), r.geturl()
    except Exception:
        return None, url


def links(html, base):
    for m in re.finditer(r'<a\b[^>]*href=["\']([^"\'#]+)["\'][^>]*>(.*?)</a>', html, re.S | re.I):
        text = re.sub(r'<[^>]+>', ' ', m.group(2))
        yield urllib.parse.urljoin(base, m.group(1).strip()), ' '.join(text.split())[:120]


def city(name, domain):
    seen, pages, portals, mails = set(), [], {}, {}
    queue = [f'https://www.{domain}/' if not domain.startswith('my.') else f'https://{domain}/']
    queue += [f'https://www.{domain}{p}' for p in PATHS]
    depth = {u: 0 for u in queue}
    while queue and len(seen) < 40:
        url = queue.pop(0)
        if url in seen:
            continue
        seen.add(url)
        html, final = get(url)
        if not html:
            continue
        if depth[url] > 0 or WORDS.search(final):
            title = re.search(r'<title>(.*?)</title>', html, re.S | re.I)
            if WORDS.search(final) or (title and WORDS.search(title.group(1))):
                pages.append(final)
        for m in PORTAL.finditer(html):
            u = m.group(0).rstrip('.,);')
            if re.search(r'\.(css|js|png|jpg|svg|pdf)(\?|$)', u, re.I):
                continue
            portals[u] = portals.get(u, 0) + 1
        for m in MAIL.finditer(html):
            e = m.group(0).lower().rstrip('.')
            if re.search(r'\.(png|jpg|gif)$', e):
                continue
            if GOOD_MAIL.search(e.split('@')[0]):
                mails[e] = mails.get(e, 0) + (2 if depth[url] else 1) + (10 if WIDE else 0)
            elif WIDE and OFFICE_MAIL.match(e.split('@')[0]) and domain.split('.')[-2] in e.split('@')[1]:
                mails[e] = mails.get(e, 0) + 1
        if depth[url] >= 2:
            continue
        for u, text in links(html, final):
            host = urllib.parse.urlparse(u).netloc
            if WORDS.search(text) or WORDS.search(u):
                if PORTAL.match(u):
                    portals[u] = portals.get(u, 0) + 3
                if domain.split('.')[-2] in host and u not in depth:
                    depth[u] = depth[url] + 1
                    queue.insert(0, u)
    best_portal = sorted(portals, key=lambda u: -portals[u])[:3]
    best_mail = sorted(mails, key=lambda e: -mails[e])[:3]
    return {'city': name, 'site': domain, 'portal': best_portal, 'email': best_mail, 'pages': pages[:3]}


def main(out_dir):
    import os; os.makedirs(out_dir, exist_ok=True)
    with cf.ThreadPoolExecutor(16) as ex:
        rows = list(ex.map(lambda kv: city(*kv), CITIES.items()))
    json.dump(rows, open(f'{out_dir}/contacts.json', 'w'), indent=1)
    md = ['# Unde se trimite cererea (FOIA) – orașe fără date oficiale', '',
          '| Oraș | Portal | Email | Pagina |', '|---|---|---|---|']
    for r in rows:
        md.append(f"| {r['city']} | {' <br>'.join(r['portal'][:2]) or '–'} | {' <br>'.join(r['email'][:2]) or '–'} | "
                  f"{r['pages'][0] if r['pages'] else '–'} |")
    open(f'{out_dir}/CONTACTS.md', 'w').write('\n'.join(md) + '\n')
    found = sum(1 for r in rows if r['portal'] or r['email'])
    print(f'{found}/{len(rows)} cities with a portal or e-mail')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'data/foia')
