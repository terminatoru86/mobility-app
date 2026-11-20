#!/usr/bin/env bash
# Downloads one Geofabrik extract and checks that it is whole (Geofabrik sometimes cuts a transfer, or is
# unreachable for minutes). Usage: tool/get_extract.sh us-midwest region.osm.pbf
set -u
region="$1"; out="$2"
url="https://download.geofabrik.de/north-america/${region}-latest.osm.pbf"
for try in 1 2 3 4 5 6 7 8; do
  rm -f "$out"
  if curl -fsSL --speed-limit 20000 --speed-time 120 --max-time 3600 --retry 20 --retry-delay 60 --retry-all-errors "$url" -o "$out" && osmium fileinfo -e "$out" > /dev/null 2>&1; then
    echo "got $region ($(du -h "$out" | cut -f1)) on try $try"
    exit 0
  fi
  echo "try $try: download failed or file not whole, again in 2 minutes"
  sleep 120
done
exit 1
