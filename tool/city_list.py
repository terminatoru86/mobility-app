"""Build data/foia/cities_big.json: the biggest US municipalities with an official website (Wikidata).
Merges data/foia/contacts.json first (our 73 hand-checked cities) and dedupes by site host."""
import json, re, sys, requests, urllib.parse

N = int(sys.argv[1]) if len(sys.argv) > 1 else 1500
Q = """
SELECT ?c ?cLabel ?site (MAX(?pop) AS ?p) WHERE {
  VALUES ?type { wd:Q1093829 wd:Q15127012 wd:Q3301053 wd:Q15284 wd:Q47168 wd:Q2154459 }
  ?c wdt:P31 ?type ; wdt:P856 ?site ; wdt:P1082 ?pop .
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
} GROUP BY ?c ?cLabel ?site ORDER BY DESC(?p) LIMIT %d
""" % (N * 2) % (N * 2)

def host(u):
    h = urllib.parse.urlparse(u if '//' in u else '//' + u).netloc.lower()
    return re.sub(r'^www\.', '', h)

out, seen = [], set()
for c in json.load(open('data/foia/contacts.json')):
    h = host(c['site'])
    if h not in seen:
        seen.add(h); out.append({'city': c['city'], 'site': h})
r = requests.get('https://query.wikidata.org/sparql', params={'query': Q, 'format': 'json'},
                 headers={'User-Agent': 'MOBIlity-app/1.0 (albis_iulian@yahoo.com)'}, timeout=180)
r.raise_for_status()
for b in r.json()['results']['bindings']:
    site, name = b['site']['value'], b['cLabel']['value']
    h = host(site)
    if not h or h in seen or name.startswith('Q'):
        continue
    seen.add(h); out.append({'city': name, 'site': h})
    if len(out) >= N:
        break
json.dump(out, open('data/foia/cities_big.json', 'w'), ensure_ascii=False, indent=0)
print(len(out), 'cities')
