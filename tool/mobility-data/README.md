# mobility-data

Public data for the MOBIlity app.

- **Offline street map**: releases `map-<lat>` hold the 1° × 1° pieces `m_<lat>_<lon>.pmtiles`
  (Protomaps basemap, © OpenStreetMap contributors, ODbL). `map-index/map_index.json` lists them.
  Rebuilt every Sunday by `.github/workflows/basemap.yml`.
