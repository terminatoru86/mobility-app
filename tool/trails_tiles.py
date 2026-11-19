"""Cuts the bike routes (data/trails/trails.json.gz) into small 1° pieces the app downloads by area.

  python3 tool/trails_tiles.py            -> data/trails/tiles/t_<lat>_<lon>.json.gz + index.json

Each piece is a list of routes: [id, name, kind, km, operator, from, to, website, lines, sights]
  kind  : bicycle / mtb / motorcycle
  lines : the route's pieces in riding order, each a flat [lat, lon, lat, lon, ...] list (simplified to ~30 m)
  sights: what riders see along the way, [[km from the start, 'L' | 'R' | 'on', name, kind], ...] (canyons, waterfalls,
          peaks, lakes, bridges, lighthouses, monuments, statues, museums, viewpoints), from tool/bike_paths.py
The same route published twice (same name, length and start) is kept once; routes named only with a code
(\"Nfst-2925720\", \"10\") are left out: a rider can't tell what they are.
"""
import gzip
import json
import math
import os
import re
import sys
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EPS = 0.0003  # ~30 m
K = 0.75  # longitude squeeze at US latitudes
# not for riders: canoe / kayak / water trails, horses, snowmobiles, skis, walking-only names
NOT_RIDE = re.compile(r'\b(canoe|kayak|paddl\w*|water\s*trail|portage|equestrian|bridle|horse\s*(trail|path|camp|loop|mapseg)|horse/|/horse|snowmobile|ski\s*trail|nordic|'
                      r'snowshoe|nature\s*walk|walking\s*(trail|path|tour)|hiking\s*only|foot\s*path|interpretive\s*walk)\b', re.I)
CODE = re.compile(r'^(nfst|nfsr|fsr|fs|nf|tr|trail|route|rte)?[\s#._-]*[\d\W]*[a-z]?$', re.I)


def dp(pts, eps=EPS):
    """Douglas-Peucker without recursion depth problems."""
    if len(pts) < 3:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = pts[a][1] * K, pts[a][0]
        bx, by = pts[b][1] * K, pts[b][0]
        dx, dy = bx - ax, by - ay
        ll = dx * dx + dy * dy
        best, bi = -1.0, -1
        for i in range(a + 1, b):
            px, py = pts[i][1] * K, pts[i][0]
            if ll == 0:
                d = math.hypot(px - ax, py - ay)
            else:
                t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / ll))
                d = math.hypot(px - ax - t * dx, py - ay - t * dy)
            if d > best:
                best, bi = d, i
        if best > eps:
            keep[bi] = True
            stack += [(a, bi), (bi, b)]
    return [p for p, k in zip(pts, keep) if k]


def gap(p, q):
    return math.hypot((p[1] - q[1]) * K, p[0] - q[0])


def order(segs):
    """Puts the pieces of a route one after the other (nearest end next), flipping them when needed."""
    if len(segs) < 2:
        return segs
    left = sorted(segs, key=len, reverse=True)
    # start from the piece whose start is farthest from everything else (one end of the route)
    chain = [left.pop(0)]
    while left:
        end, start = chain[-1][-1], chain[0][0]
        best = None
        for i, s in enumerate(left):
            for where, flip, d in (('end', False, gap(end, s[0])), ('end', True, gap(end, s[-1])),
                                   ('start', True, gap(start, s[0])), ('start', False, gap(start, s[-1]))):
                if best is None or d < best[0]:
                    best = (d, i, where, flip)
        _, i, where, flip = best
        s = left.pop(i)
        if flip:
            s = s[::-1]
        if where == 'end':
            chain.append(s)
        else:
            chain.insert(0, s)
    return chain


SG = 0.05  # sight grid cell (deg)


def load_sights():
    """Sights from tool/bike_paths.py ([lat, lon, name, kind, seen_from_m]) in a grid."""
    f = os.path.join(ROOT, 'data', 'trails', 'sights.json.gz')
    if not os.path.exists(f):
        return None
    grid = {}
    for sgt in json.load(gzip.open(f)):
        grid.setdefault((math.floor(sgt[0] / SG), math.floor(sgt[1] / SG)), []).append(sgt)
    print(f'sights: {sum(len(v) for v in grid.values())}')
    return grid


def sights_along(segs, grid, most=12):
    """What riders see along the route, in riding order (line order): [[km, side, name, kind], ...],
    side L (left) / R (right) / on (the route passes it), from the nearest piece of the route."""
    pts = [p for s in segs for p in s]
    if len(pts) < 2:
        return []
    k = math.cos(math.radians(pts[0][0]))
    xy = [(p[1] * k * 111320, p[0] * 110540) for p in pts]
    cum = [0.0]
    for i in range(1, len(xy)):
        cum.append(cum[-1] + math.hypot(xy[i][0] - xy[i - 1][0], xy[i][1] - xy[i - 1][1]))
    la = [p[0] for p in pts]
    lo = [p[1] for p in pts]
    cand, seen = [], set()
    for i in range(math.floor((min(la) - 0.05) / SG), math.floor((max(la) + 0.05) / SG) + 1):
        for j in range(math.floor((min(lo) - 0.06) / SG), math.floor((max(lo) + 0.06) / SG) + 1):
            cand += grid.get((i, j), [])
    out = []
    for lat, lon, name, kind, far in cand:
        if name in seen:
            continue
        px, py = lon * k * 111320, lat * 110540
        best = None
        for i in range(1, len(xy)):
            ax, ay = xy[i - 1]
            bx, by = xy[i]
            dx, dy = bx - ax, by - ay
            ll = dx * dx + dy * dy
            t = 0.0 if ll == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / ll))
            d = math.hypot(px - ax - t * dx, py - ay - t * dy)
            if best is None or d < best[0]:
                best = (d, i, t, dx * (py - ay) - dy * (px - ax))
        if best is None or best[0] > far:
            continue
        d, i, t, cross = best
        side = 'on' if d < 40 else ('L' if cross > 0 else 'R')
        km = (cum[i - 1] + t * (cum[i] - cum[i - 1])) / 1000
        seen.add(name)
        out.append((far >= 1500, -d, round(km, 1), side, name, kind))
    out.sort(key=lambda x: (not x[0], -x[1]))  # far-seen landmarks first, then the nearest
    keep = sorted(out[:most], key=lambda x: x[2])
    return [[x[2], x[3], x[4], x[5]] for x in keep]


def main():
    src = os.path.join(ROOT, 'data', 'trails', 'trails.json.gz')
    out_dir = os.path.join(ROOT, 'data', 'trails', 'tiles')
    routes = json.load(gzip.open(src))
    # + the named bike paths along the water (tool/waterfront.py), unless the same route is already there
    for extra_f in (os.path.join(ROOT, 'data', 'waterfront_paths.json'), os.path.join(ROOT, 'data', 'trails', 'paths.json')):
        if not os.path.exists(extra_f):
            continue
        have = {}
        for r in routes:
            if r.get('lines') and r.get('name'):
                have.setdefault(re.sub(r'[^a-z0-9]', '', r['name'].lower()), []).append(r['lines'][0][:2])
        n_extra = 0
        for r in json.load(open(extra_f)):
            starts = have.get(re.sub(r'[^a-z0-9]', '', r['name'].lower()), [])
            p0 = r['lines'][0][:2]
            if any(abs(a - p0[0]) < 0.05 and abs(b - p0[1]) < 0.07 for a, b in starts):
                continue
            routes.append(r)
            n_extra += 1
        print(f'{os.path.basename(extra_f)}: {n_extra} routes added')
    sight_grid = load_sights()
    seen, tiles, left = set(), {}, {'code name': 0, 'twice': 0, 'no line': 0}
    for r in routes:
        name = (r.get('name') or '').strip()
        if not name or CODE.match(name):
            left['code name'] += 1
            continue
        if NOT_RIDE.search(name):
            left['not for riders'] = left.get('not for riders', 0) + 1
            continue
        lines = [l for l in r.get('lines') or [] if len(l) >= 4]
        if not lines:
            left['no line'] += 1
            continue
        key = (name.lower(), round(r.get('km') or 0), round(lines[0][0], 2), round(lines[0][1], 2))
        if key in seen:
            left['twice'] += 1
            continue
        seen.add(key)
        segs = order([dp([(l[i], l[i + 1]) for i in range(0, len(l), 2)]) for l in lines])
        flat = [[round(v, 5) for p in s for v in p] for s in segs]
        t = r.get('tags') or {}
        first = segs[0][0]
        tile = f'{math.floor(first[0])}_{math.floor(first[1])}'
        along = sights_along(segs, sight_grid) if sight_grid else []
        if along:
            left['with sights'] = left.get('with sights', 0) + 1
        tiles.setdefault(tile, []).append([
            r['id'], name, r.get('kind') or 'bicycle', r.get('km'), r.get('operator') or None,
            t.get('from') or None, t.get('to') or None, t.get('website') or t.get('contact:website') or None, flat, along])
    os.makedirs(out_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        if f.startswith('t_'):
            os.remove(os.path.join(out_dir, f))
    size = 0
    for tile, lst in tiles.items():
        b = gzip.compress(json.dumps(lst, separators=(',', ':'), ensure_ascii=False).encode(), 9, mtime=0)
        size += len(b)
        open(os.path.join(out_dir, f't_{tile}.json.gz'), 'wb').write(b)
    kinds = {}
    for lst in tiles.values():
        for r in lst:
            kinds[r[2]] = kinds.get(r[2], 0) + 1
    total = sum(len(v) for v in tiles.values())
    json.dump({'at': datetime.now(timezone.utc).strftime('%Y-%m-%d'), 'total': total, 'kinds': kinds,
               'tiles': {k: len(v) for k, v in sorted(tiles.items())}},
              open(os.path.join(out_dir, 'index.json'), 'w'), separators=(',', ':'))
    print(f'{total} routes in {len(tiles)} pieces, {size / 1e6:.1f} MB · kinds {kinds} · left out {left}')


if __name__ == '__main__':
    sys.exit(main())
