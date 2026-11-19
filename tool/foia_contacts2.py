"""Second pass for cities with no portal / e-mail: read sitemap.xml (and robots.txt sitemaps), follow pages whose
URL talks about public records / FOIA, keep portals and records e-mails. Updates data/foia/contacts.json."""
import json, re, sys, gzip, urllib.request, concurrent.futures as cf
sys.path.insert(0, 'tool')
from foia_contacts import get, PORTAL, MAIL, GOOD_MAIL, WORDS, UA

BAD = re.compile(r'granicus\.com/(product|solution)|favicon|\.ico$|/assets/', re.I)


def raw(url):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': UA})
        with urllib.request.urlopen(req, timeout=25) as r:
            b = r.read(20_000_000)
            if url.endswith('.gz') or b[:2] == b'\x1f\x8b':
                b = gzip.decompress(b)
            return b.decode('utf-8', 'replace')
    except Exception:
        return ''


def sitemap_urls(host):
    maps = re.findall(r'(?im)^sitemap:\s*(\S+)', raw(f'https://{host}/robots.txt')) or [f'https://{host}/sitemap.xml']
    urls, seen = [], set()
    while maps and len(seen) < 60:
        m = maps.pop(0)
        if m in seen:
            continue
        seen.add(m)
        x = raw(m)
        locs = re.findall(r'<loc>\s*([^<\s]+)\s*</loc>', x)
        if '<sitemapindex' in x:
            maps += locs
        else:
            urls += locs
    return urls


def fix(r):
    host = r['site'] if r['site'].startswith('my.') else 'www.' + r['site']
    pages = [u for u in sitemap_urls(host) if WORDS.search(u.replace('-', ' ').replace('_', ' '))][:15]
    portals, mails = {}, {}
    for u in pages:
        html, final = get(u)
        if not html:
            continue
        for m in PORTAL.finditer(html):
            p = m.group(0).rstrip('.,);')
            if not BAD.search(p):
                portals[p] = portals.get(p, 0) + 1
        for m in MAIL.finditer(html):
            e = m.group(0).lower().rstrip('.')
            if GOOD_MAIL.search(e.split('@')[0]):
                mails[e] = mails.get(e, 0) + 1
    r['portal'] = r['portal'] or sorted(portals, key=lambda k: -portals[k])[:3]
    r['email'] = r['email'] or sorted(mails, key=lambda k: -mails[k])[:3]
    r['pages'] = r['pages'] or pages[:3]
    return r


rows = json.load(open('data/foia/contacts.json'))
for r in rows:
    r['portal'] = [p for p in r['portal'] if not BAD.search(p)]
todo = [r for r in rows if not r['portal'] or not r['email']]
with cf.ThreadPoolExecutor(12) as ex:
    list(ex.map(fix, todo))
json.dump(rows, open('data/foia/contacts.json', 'w'), indent=1)
print(sum(1 for r in rows if r['portal'] or r['email']), '/', len(rows))
