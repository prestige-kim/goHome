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
```

`station_build_report.json` records counts, duplicate physical names, and coordinate overrides. The
generated JSON deliberately preserves both the current display name and the legacy name required by
the Seoul real-time API when those names differ.
