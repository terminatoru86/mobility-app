"""Opening hours and phone of shops, workshops and rentals, read from each place's OWN website.

Our own list (data/site_hours.json): one entry per website, kept in the repository, so every
rider gets the hours with the data packs and no phone has to read the sites. Each site is read
again about once a month.

What is read from a page:
  1. the structured data shops publish for search engines (schema.org: openingHoursSpecification,
     openingHours, telephone);
  2. else the hours written as plain text ("Mon-Fri 10am-6pm, Sat 10-5, Sun closed"), only when the
     page states ONE clear set covering at least five days.
A page that lists several stores, or a website shared by several of our places (a chain), is left
alone: its hours would not be about one location.

  python3 tool/site_hours.py            read the sites due for a check, then write hours into the packs
  python3 tool/site_hours.py --apply    only write what the list already holds into the packs
"""
import gzip
import hashlib
import html as htmllib
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
import urllib.robotparser
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.environ.get('PACKS_OUT') or os.path.join(ROOT, 'assets', 'osm', 'tiles')
LIST = os.path.join(ROOT, 'data', 'site_hours.json')
AGENT = 'MOBIlityBot'
UA = {'User-Agent': f'{AGENT}/1.0 (opening hours for a cycling map; github.com/terminatoru86/mobility-app)',
      'Accept': 'text/html'}
RECHECK_DAYS = 30
DAYS = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']
NAMES = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']


def _hhmm(v):
    m = re.match(r'\s*(\d{1,2}):(\d{2})', str(v or ''))
    return f'{int(m.group(1)):02d}:{m.group(2)}' if m else None


def _join(by_day):
    """{0: '10:00-18:00', ..., 6: 'off'} -> 'Mo-Fr 10:00-18:00; Sa 10:00-17:00; Su off'"""
    parts, i = [], 0
    while i < 7:
        h = by_day.get(i)
        if h is None:
            i += 1
            continue
        j = i
        while j + 1 < 7 and by_day.get(j + 1) == h:
            j += 1
        parts.append(f'{DAYS[i] if i == j else DAYS[i] + "-" + DAYS[j]} {h}')
        i = j + 1
    return '; '.join(parts)


_D2 = '(?:Mo|Tu|We|Th|Fr|Sa|Su)'
_R2 = r'\d{1,2}:\d{2}(?::\d{2})?\s*-\s*\d{1,2}:\d{2}(?::\d{2})?'
_PART = re.compile(rf'({_D2}(?:\s*-\s*{_D2})?(?:\s*,\s*{_D2}(?:\s*-\s*{_D2})?)*)\s+(off|closed|{_R2}(?:\s*,\s*{_R2})*)', re.I)


def tidy(text):
    """Hours a site wrote its own way ("Mo 10:00:00-19:00:00, Tu ...") -> our one form, or None when
    they contradict themselves (a day with two different hours) or nothing readable is there."""
    by_day = {}
    for m in _PART.finditer(text or ''):
        val = m.group(2).lower()
        if val in ('off', 'closed'):
            val = 'off'
        else:
            rs = []
            for o, c in re.findall(r'(\d{1,2}:\d{2})(?::\d{2})?\s*-\s*(\d{1,2}:\d{2})(?::\d{2})?', val):
                o, c = _hhmm(o), _hhmm(c)
                if o == c:
                    continue
                rs.append(f'{o}-{c}')
            val = ','.join(rs) or 'off'
        days = []
        for piece in re.split(r'\s*,\s*', m.group(1)):
            ab = [DAYS.index(x.capitalize()) for x in re.split(r'\s*-\s*', piece)]
            days += [ab[0]] if len(ab) == 1 else (list(range(ab[0], ab[1] + 1)) if ab[1] >= ab[0] else list(range(ab[0], 7)) + list(range(0, ab[1] + 1)))
        for d in days:
            if by_day.get(d, val) != val:
                return None
            by_day[d] = val
    if not by_day or all(v == 'off' for v in by_day.values()):
        return None
    return _join(by_day)


def _from_spec(spec):
    by_day = {}
    for s in spec if isinstance(spec, list) else [spec]:
        if not isinstance(s, dict):
            continue
        o, c = _hhmm(s.get('opens')), _hhmm(s.get('closes'))
        if not o or not c or o == c:
            continue
        d = s.get('dayOfWeek')
        for x in d if isinstance(d, list) else [d]:
            if isinstance(x, dict):
                x = x.get('name') or x.get('@id')
            name = str(x or '').lower().split('/')[-1]
            if name in NAMES:
                i = NAMES.index(name)
                by_day[i] = f'{by_day[i]},{o}-{c}' if i in by_day else f'{o}-{c}'
    return _join(by_day) if by_day else None


def _walk(node, hours, phones):
    if isinstance(node, list):
        for n in node:
            _walk(n, hours, phones)
    elif isinstance(node, dict):
        spec = _from_spec(node.get('openingHoursSpecification'))
        if spec:
            hours.add(spec)
        else:
            oh = node.get('openingHours')
            text = ('; '.join(map(str, oh)) if isinstance(oh, list) else str(oh or '')).strip()
            text = tidy(text) if len(text) < 400 else None
            if text:
                hours.add(text)
        tel = node.get('telephone')
        if isinstance(tel, str) and re.search(r'\d{3}', tel) and len(tel) < 30:
            phones.add(tel.strip())
        for v in node.values():
            if isinstance(v, (dict, list)):
                _walk(v, hours, phones)


def parse_structured(page):
    """(hours, phone) from the schema.org data in the page; each only when the page states exactly one."""
    hours, phones = set(), set()
    for m in re.finditer(r'<script[^>]*application/ld\+json[^>]*>(.*?)</script>', page, re.S | re.I):
        try:
            _walk(json.loads(m.group(1).strip()), hours, phones)
        except Exception:
            pass
    return (next(iter(hours)) if len(hours) == 1 else None), (next(iter(phones)) if len(phones) == 1 else None)


_DAY = r'(mon|tue|wed|thu|fri|sat|sun)[a-z]{0,6}\.?'
_SEP = r'\s*(?:-|–|—|to|thru|through)\s*'
_T = r'(\d{1,2})(?::(\d{2}))?\s*([ap])?\.?m?\.?'
_LINE = re.compile(
    rf'\b{_DAY}(?:{_SEP}{_DAY})?(?:\s*(?:,|&|and)\s*{_DAY})?\s*:?\s*'
    rf'(?:(closed)|{_T}{_SEP}{_T})', re.I)
_ABBR = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']


def _clock(h, m, ap, other_ap, opening):
    h, m = int(h), int(m or 0)
    if h > 23 or m > 59:
        return None
    ap = (ap or '').lower()
    if not ap:
        if h > 12 or h == 0:
            return h * 60 + m  # 24-hour clock
        # "10-6pm": the opening hour takes "am" when it is a morning hour
        ap = 'a' if opening and 5 <= h <= 11 else 'p' if (other_ap or 'p').lower() == 'p' or not opening else 'a'
    if h > 12:
        return None
    return (h % 12 + (12 if ap == 'p' else 0)) * 60 + m


def parse_text(page):
    """Hours written as plain text, or None unless the page states one clear set for 5+ days."""
    body = re.sub(r'<(script|style|noscript)\b.*?</\1>', ' ', page, flags=re.S | re.I)
    text = htmllib.unescape(re.sub(r'<[^>]+>', ' ', body))
    text = re.sub(r'\s+', ' ', text)
    by_day = {}
    for m in _LINE.finditer(text):
        d1, d2, d3, closed, h1, m1, a1, h2, m2, a2 = m.groups()
        if closed:
            val = 'off'
        else:
            o, c = _clock(h1, m1, a1, a2, True), _clock(h2, m2, a2, a1, False)
            if o is None or c is None or not (4 * 60 <= o < c <= 23 * 60 + 59) or c - o < 60:
                continue
            val = f'{o // 60:02d}:{o % 60:02d}-{c // 60:02d}:{c % 60:02d}'
        a = _ABBR.index(d1.lower())
        days = [a]
        if d2:
            b = _ABBR.index(d2.lower())
            days = list(range(a, b + 1)) if b >= a else list(range(a, 7)) + list(range(0, b + 1))
        if d3:
            days.append(_ABBR.index(d3.lower()))
        for d in days:
            if by_day.get(d, val) != val:
                return None  # two different hours for the same day: several stores, or seasons
            by_day[d] = val
    if len(by_day) < 5 or all(v == 'off' for v in by_day.values()):
        return None
    return _join(by_day)


def parse_page(page):
    hours, phone = parse_structured(page)
    return hours or parse_text(page), phone


def _get(url, timeout=10):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        if 'html' not in (r.headers.get('Content-Type') or 'html'):
            return ''
        return r.read(2_500_000).decode('utf-8', 'replace')


def read_site(url):
    """{'h': hours or '', 'p': phone or '', 't': day checked} or None when the site did not answer."""
    try:
        parts = urllib.parse.urlsplit(url)
        if parts.scheme not in ('http', 'https') or not parts.netloc:
            return None
        base = f'{parts.scheme}://{parts.netloc}'
        rp = urllib.robotparser.RobotFileParser()
        try:
            req = urllib.request.Request(base + '/robots.txt', headers=UA)
            with urllib.request.urlopen(req, timeout=8) as r:
                rp.parse(r.read(200_000).decode('utf-8', 'replace').splitlines())
        except Exception:
            rp.parse([])  # no robots.txt: nothing is forbidden
        today = datetime.now(timezone.utc).strftime('%Y-%m-%d')
        if not rp.can_fetch(AGENT, url):
            return {'h': '', 'p': '', 't': today, 'no': 1}  # the site asks robots to stay out: we do
        hours, phone = parse_page(_get(url))
        if not hours:
            # many shops keep the hours on their contact page
            for path in ('/contact', '/hours'):
                extra = base + path
                if not rp.can_fetch(AGENT, extra):
                    continue
                try:
                    h2, p2 = parse_page(_get(extra, timeout=8))
                except Exception:
                    continue
                hours, phone = h2, phone or p2
                if hours:
                    break
        return {'h': hours or '', 'p': phone or '', 't': today}
    except Exception:
        return None


def norm_url(u):
    u = (u or '').strip()
    if not u:
        return None
    if not re.match(r'https?://', u, re.I):
        u = 'https://' + u
    return u.split('#')[0]


def wants_hours(tags):
    return bool(tags.get('shop') or tags.get('amenity') in ('bicycle_rental', 'bicycle_repair_station') or tags.get('sport') == 'bmx')


def load_tiles():
    tiles = {}
    for name in sorted(os.listdir(OUT)) if os.path.isdir(OUT) else []:
        m = re.match(r't_(-?\d+)_(-?\d+)\.json\.gz$', name)
        if m:
            tiles[(int(m.group(1)), int(m.group(2)))] = json.loads(gzip.decompress(open(os.path.join(OUT, name), 'rb').read()))
    return tiles


def site_of(tags):
    return norm_url(tags.get('website') or tags.get('contact:website'))


def shared_sites(rows_iter):
    """Websites used by more than one place (a chain's page): never used for hours."""
    seen, shared = {}, set()
    for r in rows_iter:
        if wants_hours(r[3]):
            u = site_of(r[3])
            if u:
                key = (round(r[1], 3), round(r[2], 3))
                if seen.setdefault(u, key) != key:
                    shared.add(u)
    return shared


def apply(rows_iter, known, shared):
    """Writes the hours and phone we hold into the places that lack them. Returns how many got hours."""
    n = 0
    for r in rows_iter:
        t = r[3]
        if not wants_hours(t):
            continue
        u = site_of(t)
        e = known.get(u) if u and u not in shared else None
        ours = t.get('hours:source') == 'website'
        if ours and not (e and e.get('h')):
            # we wrote these hours earlier and the site no longer states them
            t.pop('opening_hours', None)
            t.pop('hours:source', None)
        if not e:
            continue
        if e.get('h') and (ours or not t.get('opening_hours')):
            t['opening_hours'] = e['h']
            t['hours:source'] = 'website'
            n += 1
        if e.get('p') and not (t.get('phone') or t.get('contact:phone')):
            t['phone'] = e['p']
    return n


def load_list():
    try:
        return json.load(open(LIST, encoding='utf-8'))
    except Exception:
        return {}


def main():
    tiles = load_tiles()
    before = {k: hashlib.md5(json.dumps(v, sort_keys=True).encode()).hexdigest() for k, v in tiles.items()}
    every = [r for rows in tiles.values() for r in rows]
    known = load_list()
    shared = shared_sites(every)
    for e in known.values():
        if e.get('h'):
            e['h'] = tidy(e['h']) or ''  # everything in one form; what cannot be read is dropped
    if '--apply' not in sys.argv:
        today = datetime.now(timezone.utc)
        due = []
        for r in every:
            t = r[3]
            if not wants_hours(t) or (t.get('opening_hours') and t.get('hours:source') != 'website'):
                continue
            u = site_of(t)
            if not u or u in shared:
                continue
            e = known.get(u)
            age = (today - datetime.strptime(e['t'], '%Y-%m-%d').replace(tzinfo=timezone.utc)).days if e else 10 ** 6
            if age >= RECHECK_DAYS:
                due.append((age, u))
        due = [u for _, u in sorted(set(due), reverse=True)]  # never read first, then the oldest
        budget = float(os.environ.get('HOURS_MINUTES', '45')) * 60
        print(f'places: {len(every)} · websites due for a check: {len(due)} · used by several places (skipped): {len(shared)}', flush=True)
        end = time.time() + budget
        done = failed = 0

        def one(u):
            return (u, read_site(u)) if time.time() < end else (u, 'late')

        with ThreadPoolExecutor(max_workers=40) as pool:
            for u, e in pool.map(one, due):
                if e == 'late':
                    continue
                done += 1
                if e is None:
                    failed += 1  # no answer: asked again next time
                else:
                    known[u] = e
        with_h = sum(1 for e in known.values() if e.get('h'))
        print(f'read now: {done} (no answer: {failed}) · in our list: {len(known)} websites, {with_h} with hours', flush=True)
        os.makedirs(os.path.dirname(LIST), exist_ok=True)
        with open(LIST, 'w', encoding='utf-8') as f:
            json.dump(dict(sorted(known.items())), f, indent=0, ensure_ascii=False, sort_keys=True)
    with open(LIST, 'w', encoding='utf-8') as f:
        json.dump(dict(sorted(known.items())), f, indent=0, ensure_ascii=False, sort_keys=True)
    n = apply(every, known, shared)
    index_path = os.path.join(OUT, 'index.json')
    index = json.load(open(index_path))
    changed = 0
    for (a, b), rows in tiles.items():
        if hashlib.md5(json.dumps(rows, sort_keys=True).encode()).hexdigest() == before[(a, b)]:
            continue
        rows = sorted(rows, key=lambda x: x[0])
        text = json.dumps(rows, separators=(',', ':'), ensure_ascii=False)
        with open(os.path.join(OUT, f't_{a}_{b}.json.gz'), 'wb') as f:
            f.write(gzip.compress(text.encode('utf-8'), compresslevel=9, mtime=0))
        index['tiles'][f'{a}_{b}'] = [len(rows), hashlib.md5(text.encode('utf-8')).hexdigest()[:12]]
        changed += 1
    if changed:
        with open(index_path, 'w') as f:
            json.dump(index, f, separators=(',', ':'))
    line = f'hours from websites now on {n} places · map pieces changed: {changed}'
    print(f'::notice title=Hours::{line}' if os.environ.get('GITHUB_ACTIONS') else line, flush=True)


if __name__ == '__main__':
    main()
