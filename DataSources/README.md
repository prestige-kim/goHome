# Station data sources

The app station bundle is generated from versioned source files in `raw/`.

| File | Purpose | Source |
|---|---|---|
| `kric_metro_stations_20260630.xlsx` | Coordinates, line names, operators | https://data.kric.go.kr/rips/M_01_01/detail.do?id=32 |
| `seoul_realtime_arrival_stations_20260804.xlsx` | Seoul real-time API supported station and line IDs | https://data.seoul.go.kr/dataList/OA-12764/A/1/datasetView.do |
| `kric_gtx_a_stations_20240715.xlsx` | Official GTX-A southern section coordinates | https://data.kric.go.kr/rips/M_01_01/detail.do?id=1279 |

The official GTX-A workbook predates the northern section and has no rows for `운정중앙` and `킨텍스`.
Those two coordinates are explicit audited overrides in `scripts/build_station_bundle.py`, sourced from:

- https://rail.blue/railroad/logis/stationinfo.aspx?id=4821890
- https://rail.blue/railroad/logis/stationinfo.aspx?id=4821891

The KRIC `4호선 이촌` coordinate is an outlier roughly 900 m from its connected platform. The
converter merges it with the same-name `경원선` record and uses that official KORAIL coordinate.
Conversely, same-name non-transfer stations (`신촌`, `양평`) are kept separate by line.

Rebuild from the repository root:

```sh
python3 -m pip install -r scripts/requirements.txt
python3 scripts/build_station_bundle.py
python3 scripts/validate_station_bundle.py
python3 scripts/build_line_routes.py
python3 scripts/validate_line_routes.py
```

`station_build_report.json` records counts, duplicate physical names, and coordinate overrides. The
generated JSON deliberately preserves both the current display name and the legacy name required by
the Seoul real-time API when those names differ.

## Line route bundle

`scripts/build_line_routes.py` creates `GoHome/Resources/line_routes.json` from the versioned Seoul
support workbook. It never sorts numeric station IDs. The official workbook row order is used only for
linear spans; audited route definitions explicitly reconnect the branches of lines 1, 2, 5, 6,
Gyeongui-Jungang, Airport Railroad, and Gyeongchun, keep the Line 2 loop circular, and keep the two
currently disconnected GTX-A sections separate.

The generated bundle contains 19 lines and 28 service routes. `scripts/validate_line_routes.py` verifies
all 696 station-line mappings are covered, every ID belongs to its line, route IDs are unique, branch and
loop invariants remain present, and consecutive stations are geographically plausible.

The 2026-06-30 KRIC workbook has a known erroneous coordinate for Gyeongui-Jungang Yangwon station.
KRIC acknowledged the source issue at https://data.kric.go.kr/rips/M_04_04/detail.do?id=79&page=2.
The bundle records an audited correction from https://rail.blue/railroad/logis/stationinfo.aspx?id=609,
and both Python and Swift regression checks keep the station in Seoul.
