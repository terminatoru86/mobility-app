#!/usr/bin/env python3
"""Looks at the candidate pictures from the shops' websites and keeps the ones that show the shop
from the street.

tool/place_photos.py leaves, for places whose website describes no picture as its storefront, a few
candidates ("c") in data/place_photos.json. Here an open image model (CLIP, run on our own build
machine: no picture is sent anywhere) compares each picture with plain descriptions: a shop seen
from outside, or something else (a logo, a product, the inside of a shop, people, a drawing).
The best outside view of each place is added to its photos as ["website", address, date, 0, 0, "seen"].
Pictures are only looked at, never saved.
"""
import io
import json
import os
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIST = os.path.join(ROOT, 'data', 'place_photos.json')
UA = {'User-Agent': 'MOBIlityBot/1.0 (storefront photo for a cycling map; github.com/terminatoru86/mobility-app)',
      'Accept': 'image/*'}

OUTSIDE = [
    'a photo of the outside of a shop, seen from the street',
    'a photo of a storefront with a sign above the entrance',
    'a photo of a store building and its parking lot',
]
OTHER = [
    'a logo', 'a drawing or an illustration', 'a banner with text', 'a map',
    'a product photo of a bicycle', 'a product photo of a motorcycle or a scooter',
    'a photo of the inside of a shop', 'a photo of a workshop with tools', 'a photo of a showroom indoors',
    'a photo of a person riding', 'a portrait of people', 'a photo of a landscape or a trail',
    'a photo of a bicycle outdoors', 'a photo of a motorcycle outdoors', 'a close-up photo of parts',
]
NEED = float(os.environ.get('VISION_NEED', '0.7'))  # how sure the model has to be that it is an outside view


def fetch(url):
    """The picture, opened, or None (gone, too small, a strip, or older than 2024 by the server's date)."""
    from PIL import Image
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=10) as r:
            if not (r.headers.get('Content-Type') or '').startswith('image/'):
                return None
            when = ''
            lm = r.headers.get('Last-Modified')
            if lm:
                try:
                    from email.utils import parsedate_to_datetime
                    when = parsedate_to_datetime(lm).strftime('%Y-%m')
                except Exception:
                    pass
            if when and when < '2024-01':
                return None
            raw = r.read(6_000_000)
        im = Image.open(io.BytesIO(raw))
        w, h = im.size
        if w < 400 or h < 250 or w / h > 3.2 or h / w > 2.2:
            return None
        return im.convert('RGB'), when
    except Exception:
        return None


def main():
    known = json.load(open(LIST, encoding='utf-8'))
    todo = [(k, c) for k, e in known.items() for c in e.get('c') or []]
    places = {k for k, _ in todo}
    print(f'places with candidates: {len(places)} · pictures to look at: {len(todo)}', flush=True)
    if not todo and '--test' not in sys.argv:
        return
    import torch
    import open_clip
    model, _, prep = open_clip.create_model_and_transforms('ViT-B-32', pretrained='laion2b_s34b_b79k')
    model.eval()
    tok = open_clip.get_tokenizer('ViT-B-32')
    with torch.no_grad():
        text = model.encode_text(tok(OUTSIDE + OTHER))
        text = text / text.norm(dim=-1, keepdim=True)

    def score(images):
        with torch.no_grad():
            f = model.encode_image(torch.stack([prep(i) for i in images]))
            f = f / f.norm(dim=-1, keepdim=True)
            pr = (100.0 * f @ text.T).softmax(dim=-1)
        return pr[:, :len(OUTSIDE)].sum(dim=-1).tolist()

    if '--test' in sys.argv:
        from PIL import Image
        print('model ok:', [round(x, 3) for x in score([Image.new('RGB', (640, 480), 'white')])])
        return

    end = time.time() + 60 * float(os.environ.get('VISION_MINUTES', '90'))
    day = datetime.now(timezone.utc).strftime('%Y-%m-%d')
    best, seen, looked, upto = {}, set(), 0, 0
    with ThreadPoolExecutor(max_workers=32) as ex:
        for start in range(0, len(todo), 64):
            if time.time() > end:
                break
            part = todo[start:start + 64]
            got = list(ex.map(lambda kc: fetch(kc[1][1]), part))
            ok = [(kc, g) for kc, g in zip(part, got) if g]
            seen.update(k for k, _ in part)
            upto = start + len(part)
            if ok:
                for ((k, c), (_, when)), sc in zip(ok, score([g[0] for _, g in ok])):
                    looked += 1
                    if sc >= NEED and sc > best.get(k, (0,))[0]:
                        best[k] = (sc, [c[0], c[1], c[2] or when, 0, 0, 'seen'])
            if (start // 64) % 40 == 0:
                print(f'  {start}/{len(todo)} pictures · outside views so far: {len(best)}', flush=True)
    # a place is finished only when all its candidates were tried (they sit next to each other in the list)
    last = todo[upto - 1][0] if 0 < upto < len(todo) and todo[upto][0] == todo[upto - 1][0] else None
    for k in seen:
        if k == last:
            continue
        e = known[k]
        e.pop('c', None)
        e['cv'] = day
        if k in best:
            e['p'] = [r for r in e['p'] if not (len(r) > 5 and r[5] == 'seen')] + [best[k][1]]
    json.dump(known, open(LIST, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'), sort_keys=True)
    left = sum(1 for e in known.values() if e.get('c'))
    print(f'pictures opened and looked at: {looked} · places still waiting: {left}')
    print(f'::notice::website pictures that show the shop from outside: {len(best)} places (of {len(seen)} looked at)')


if __name__ == '__main__':
    main()
