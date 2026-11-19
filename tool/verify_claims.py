"""Automatic check of the requests that business owners send from the app (collection shop_claims).

A request is approved by this script, with no one from the team, only when everything the owner wrote
is confirmed by a source we do not get from the owner:

  1. EIN         nine digits and a prefix the IRS really uses. (There is no public list of EINs, so this
                 is the most that can be checked; the EIN is NOT what proves the business is real.)
  2. Place       the place is in our data, at the coordinates the app sent.
  3. Address     the US Census geocoder finds the written address, within 250 m of that place.
  4. Name        the business name matches the name (or brand) of the place on the map.
  5. Phone       the phone matches the one the place has on the map / its website (when it has one).
  6. Ownership   (the proof that the applicant is the owner, not just someone who knows the shop)
                 either the e-mail of the signed-in account is on the website's own domain
                 (name@shop.com for shop.com), or the code shown in the app is written on the
                 shop's own website.

All of 1-6 pass  -> status approved.   Something clearly wrong -> rejected, with the reason in plain words.
Only the ownership proof missing -> stays pending, with instructions; checked again every run for 7 days,
then rejected. Nothing is ever approved by guessing.

  python3 tool/verify_claims.py            needs FIREBASE_SERVICE_ACCOUNT (the JSON) and FIREBASE_PROJECT_ID
  python3 tool/verify_claims.py --selftest only the rules, on made-up data
"""
import difflib
import gzip
import json
import math
import os
import re
import sys
import time
import urllib.parse
import urllib.request

# Two-digit prefixes the IRS assigns to EINs.
EIN_PREFIXES = set(
    list(range(1, 7)) + list(range(10, 17)) + list(range(20, 28)) + list(range(30, 49)) + list(range(50, 69))
    + list(range(71, 78)) + list(range(80, 89)) + list(range(90, 96)) + [98, 99]
)
FREE_MAIL = {
    'gmail.com', 'googlemail.com', 'yahoo.com', 'outlook.com', 'hotmail.com', 'live.com', 'icloud.com', 'me.com',
    'aol.com', 'msn.com', 'proton.me', 'protonmail.com', 'gmx.com', 'mail.com', 'yandex.com', 'comcast.net',
    'att.net', 'sbcglobal.net', 'verizon.net',
}
MAX_DAYS_PENDING = 7
DOOR_METERS = 250
OK, BAD, WAIT = 'ok', 'bad', 'wait'  # a check passes, fails for good, or cannot be told yet


def ein_check(ein):
    d = re.sub(r'\D', '', ein or '')
    if len(d) != 9:
        return BAD, 'The EIN must have nine digits (12-3456789).'
    if int(d[:2]) not in EIN_PREFIXES:
        return BAD, 'This EIN does not start with a number the IRS uses. Check it on your IRS letter (CP 575 or 147C).'
    if len(set(d)) == 1:
        return BAD, 'This EIN is not valid.'
    return OK, ''


_STOP = {'llc', 'inc', 'co', 'corp', 'corporation', 'company', 'ltd', 'the', 'and', 'of', 'dba', 'shop', 'store', 'bike',
         'bikes', 'cycle', 'cycles', 'cycling', 'bicycle', 'bicycles', 'service', 'services', 'repair', 'rental', 'rentals'}


def _words(s):
    s = re.sub(r"[^a-z0-9 ]", ' ', (s or '').lower().replace('&', ' and '))
    return [w for w in s.split() if w]


def name_score(a, b):
    """0..1: how much two business names look like the same name."""
    wa, wb = _words(a), _words(b)
    if not wa or not wb:
        return 0.0
    ra = [w for w in wa if w not in _STOP] or wa
    rb = [w for w in wb if w not in _STOP] or wb
    common = len(set(ra) & set(rb)) / min(len(set(ra)), len(set(rb)))
    seq = difflib.SequenceMatcher(None, ' '.join(wa), ' '.join(wb)).ratio()
    return max(common, seq)


def name_check(claim_name, tags):
    names = [tags.get(k) for k in ('name', 'brand', 'operator') if tags.get(k)]
    best = max([name_score(claim_name, n) for n in names] or [0])
    if best >= 0.6:
        return OK, ''
    return BAD, 'The business name does not match the name of this place on the map.'


def digits10(s):
    d = re.sub(r'\D', '', s or '')
    return d[-10:] if len(d) >= 10 else ''


def phone_check(claim_phone, place_phones, page_text=''):
    mine = digits10(claim_phone)
    if not mine:
        return BAD, 'The phone number is not valid.'
    known = {digits10(p) for p in place_phones if digits10(p)}
    if known:
        return (OK, '') if mine in known else (BAD, 'The phone number is not the one this business has listed.')
    if page_text and mine in {digits10(m) for m in re.findall(r'\(?\d{3}\)?[\s.\-]?\d{3}[\s.\-]?\d{4}', page_text)}:
        return OK, ''
    return OK, ''  # the place has no public phone: nothing to compare with (not a reason to refuse)


def meters(a, b):
    r = 6371000
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp, dl = p2 - p1, math.radians(b[1] - a[1])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def address_check(found, place):
    """found: (lat, lon) from the geocoder, or None when it knows no such address."""
    if found is None:
        return BAD, 'We could not find this address. Write it as on the door: number, street, city, state, ZIP.'
    d = meters(found, place)
    if d > DOOR_METERS:
        return BAD, 'The address is %d m from the place you chose on the map. Choose the place at that address.' % round(d)
    return OK, ''


def domain_of(url):
    h = urllib.parse.urlparse(url if '//' in (url or '') else '//' + (url or '')).hostname or ''
    h = h.lower()
    return h[4:] if h.startswith('www.') else h


def email_matches_site(email, site):
    e = (email or '').lower().rsplit('@', 1)[-1]
    s = domain_of(site)
    if not e or not s or e in FREE_MAIL:
        return False
    return e == s or e.endswith('.' + s) or s.endswith('.' + e)


def ownership_check(email, email_verified, site, code, page_text):
    if not site:
        return WAIT, ('This place has no website on the map, so we cannot confirm it is yours automatically. '
                      'We will keep checking; a team member can also approve it.')
    if email_verified and email_matches_site(email, site):
        return OK, ''
    if code and code.lower() in (page_text or '').lower():
        return OK, ''
    return WAIT, ('To prove the business is yours, write the code %s on your website (the home page or the contact page, '
                  'for example in the footer), or sign in with an e-mail on your own domain (name@%s). '
                  'We check again every few minutes.') % (code or '—', domain_of(site))


def decide(checks, age_days):
    """checks: {name: (OK|BAD|WAIT, text)} -> (status, note)."""
    bad = [t for s, t in checks.values() if s == BAD and t]
    if bad:
        return 'rejected', ' '.join(bad)
    wait = [t for s, t in checks.values() if s == WAIT]
    if wait:
        if age_days > MAX_DAYS_PENDING:
            return 'rejected', 'We could not confirm that you own this business within %d days. %s' % (MAX_DAYS_PENDING, wait[0])
        return 'pending', wait[0]
    return 'approved', ''


# ---------------------------------------------------------------- the world (network)

def http_json(url, data=None, headers=None, method=None, timeout=25):
    req = urllib.request.Request(url, data=json.dumps(data).encode() if data is not None else None,
                                 headers={'Content-Type': 'application/json', **(headers or {})}, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode() or '{}')


def geocode(address):
    """US Census geocoder (free, no key). Returns (lat, lon), None when no such address, raises on a network error."""
    q = urllib.parse.urlencode({'address': address, 'benchmark': 'Public_AR_Current', 'format': 'json'})
    d = http_json('https://geocoding.geo.census.gov/geocoder/locations/onelineaddress?' + q, timeout=40)
    m = (d.get('result') or {}).get('addressMatches') or []
    if not m:
        return None
    c = m[0]['coordinates']
    return c['y'], c['x']


def fetch_text(url, limit=600_000):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'MOBIlity-verify/1.0 (+https://github.com/terminatoru86/mobility-app)'})
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.read(limit).decode('utf-8', 'ignore')
    except Exception:
        return ''


def site_text(site):
    if not site:
        return ''
    base = site if '//' in site else 'https://' + site
    u = urllib.parse.urlparse(base)
    root = f'{u.scheme}://{u.netloc}'
    out = fetch_text(base)
    for path in ('/', '/contact', '/contact-us', '/about'):
        out += ' ' + fetch_text(root + path)
    return out


def find_place(key, lat, lon, tiles_dir='assets/osm/tiles'):
    f = os.path.join(tiles_dir, f't_{math.floor(lat)}_{math.floor(lon)}.json.gz')
    if not os.path.exists(f):
        return None
    for row in json.load(gzip.open(f, 'rt', encoding='utf-8')):
        if row[0].replace('/', '_') == key:
            return row
    return None


def token(sa):
    from google.oauth2 import service_account
    import google.auth.transport.requests as tr
    c = service_account.Credentials.from_service_account_info(sa, scopes=['https://www.googleapis.com/auth/cloud-platform'])
    c.refresh(tr.Request())
    return c.token


def fs_str(f, k):
    return ((f.get(k) or {}).get('stringValue')) or ''


def fs_num(f, k):
    v = f.get(k) or {}
    return float(v.get('doubleValue', v.get('integerValue', 0)) or 0)


def run():
    raw, pid = os.environ.get('FIREBASE_SERVICE_ACCOUNT', ''), os.environ.get('FIREBASE_PROJECT_ID', '')
    if not raw or not pid:
        print('Firebase secrets not set yet: nothing checked.')
        return 0
    sa = json.loads(raw)
    h = {'Authorization': 'Bearer ' + token(sa)}
    base = f'https://firestore.googleapis.com/v1/projects/{pid}/databases/(default)/documents'
    rows = http_json(base + ':runQuery', {'structuredQuery': {
        'from': [{'collectionId': 'shop_claims'}],
        'where': {'fieldFilter': {'field': {'fieldPath': 'status'}, 'op': 'EQUAL', 'value': {'stringValue': 'pending'}}}}}, h)
    docs = [r['document'] for r in rows if 'document' in r]
    print(len(docs), 'pending request(s)')
    for doc in docs:
        f = doc['fields']
        name = doc['name']
        key, uid = fs_str(f, 'placeKey'), fs_str(f, 'uid')
        age = (time.time() * 1000 - fs_num(f, 'at')) / 86_400_000
        checks = {}
        try:
            checks['ein'] = ein_check(fs_str(f, 'ein'))
            lat, lon = fs_num(f, 'lat'), fs_num(f, 'lon')
            row = find_place(key, lat, lon) if lat or lon else None
            if row is None:
                checks['place'] = (BAD, 'We could not find this place in our data. Choose it again from the list.')
            else:
                tags = row[3]
                place = (row[1], row[2])
                checks['name'] = name_check(fs_str(f, 'businessName'), tags)
                checks['address'] = address_check(geocode(fs_str(f, 'address')), place)
                site = tags.get('website') or tags.get('contact:website') or ''
                text = site_text(site)
                checks['phone'] = phone_check(fs_str(f, 'phone'), [tags.get('phone', ''), tags.get('contact:phone', '')], text)
                u = http_json(f'https://identitytoolkit.googleapis.com/v1/projects/{pid}/accounts:lookup', {'localId': [uid]}, h)
                us = (u.get('users') or [{}])[0]
                checks['owner'] = ownership_check(us.get('email', ''), bool(us.get('emailVerified')), site, fs_str(f, 'code'), text)
        except Exception as e:  # network trouble: try again in the next run, decide nothing
            print('  ', key, 'cannot be checked now:', e)
            continue
        status, note = decide(checks, age)
        print('  ', key, status, {k: v[0] for k, v in checks.items()}, note[:90])
        patch = {'status': {'stringValue': status}, 'note': {'stringValue': note},
                 'checks': {'stringValue': json.dumps({k: v[0] for k, v in checks.items()})}}
        if status == 'pending' and note == fs_str(f, 'note') and fs_str(f, 'checks'):
            continue
        q = '&'.join('updateMask.fieldPaths=' + k for k in patch)
        http_json(f'https://firestore.googleapis.com/v1/{name}?{q}', {'fields': patch}, h, method='PATCH')
    return 0


def selftest():
    assert ein_check('12-3456789')[0] == OK and ein_check('07-1234567')[0] == BAD and ein_check('12345')[0] == BAD
    assert ein_check('11-1111111')[0] == BAD
    assert name_check('Johnson Bikes LLC', {'name': "Johnson's Bike Shop"})[0] == OK
    assert name_check('Acme Plumbing', {'name': 'Wheel Works'})[0] == BAD
    assert phone_check('(312) 738-4269', ['+1 312-738-4269'])[0] == OK
    assert phone_check('312 555 0000', ['+1 312-738-4269'])[0] == BAD
    assert phone_check('312 555 0000', [])[0] == OK
    assert address_check(None, (41.8, -87.6))[0] == BAD
    assert address_check((41.8001, -87.6001), (41.8, -87.6))[0] == OK
    assert address_check((41.9, -87.6), (41.8, -87.6))[0] == BAD
    assert email_matches_site('ana@motoworkschicago.com', 'https://www.motoworkschicago.com/bmw') is True
    assert email_matches_site('ana@gmail.com', 'https://gmail.com') is False
    assert email_matches_site('ana@other.com', 'https://shop.com') is False
    assert ownership_check('ana@shop.com', True, 'https://shop.com', 'ABC123', '')[0] == OK
    assert ownership_check('ana@shop.com', False, 'https://shop.com', 'ABC123', '')[0] == WAIT
    assert ownership_check('x@gmail.com', True, 'https://shop.com', 'ABC123', 'footer abc123 ok')[0] == OK
    assert ownership_check('x@gmail.com', True, '', 'ABC123', '')[0] == WAIT
    allok = {k: (OK, '') for k in 'abc'}
    assert decide(allok, 0) == ('approved', '')
    assert decide({**allok, 'o': (WAIT, 'w')}, 1) == ('pending', 'w')
    assert decide({**allok, 'o': (WAIT, 'w')}, 9)[0] == 'rejected'
    assert decide({**allok, 'x': (BAD, 'no')}, 0) == ('rejected', 'no')
    print('selftest ok')


if __name__ == '__main__':
    if '--selftest' in sys.argv:
        selftest()
    else:
        sys.exit(run())
