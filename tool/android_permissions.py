"""Adds the permissions MOBIlity needs to android/app/src/main/AndroidManifest.xml (safe to run again)."""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'android/app/src/main/AndroidManifest.xml'
PERMS = [
    'android.permission.INTERNET',              # maps, data, help pages, traffic cameras
    'android.permission.ACCESS_FINE_LOCATION',  # GPS
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.CAMERA',                # Fixit QR, SOS photo
]
s = open(path, encoding='utf-8').read()
add = ''.join(f'    <uses-permission android:name="{p}"/>\n' for p in PERMS if p not in s)
if add:
    s = re.sub(r'(<manifest[^>]*>\n)', lambda m: m.group(1) + add, s, count=1)
s = s.replace('android:label="mobility"', 'android:label="MOBIlity"')
open(path, 'w', encoding='utf-8').write(s)
print('permissions ok')
