#!/usr/bin/env python3

"""Validate the generated GoHome station JSON without third-party packages."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BUNDLE = PROJECT_ROOT / "GoHome/Resources/stations.seed.json"
EXPECTED_STATION_LINE_COUNT = 696


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", nargs="?", type=Path, default=DEFAULT_BUNDLE)
    return parser.parse_args()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def station_named(stations: list[dict[str, Any]], name: str) -> list[dict[str, Any]]:
    return [station for station in stations if station["name"] == name]


def main() -> None:
    path = parse_arguments().bundle
    stations: list[dict[str, Any]] = json.loads(path.read_text(encoding="utf-8"))

    require(len(stations) >= 550, f"Too few physical stations: {len(stations)}")
    require(len({station["id"] for station in stations}) == len(stations), "Duplicate station IDs")
    require(
        sum(len(station["lineNames"]) for station in stations) == EXPECTED_STATION_LINE_COUNT,
        "Station-line mappings are incomplete",
    )

    for station in stations:
        require(33 <= station["latitude"] <= 39, f"Invalid latitude: {station['id']}")
        require(124 <= station["longitude"] <= 132, f"Invalid longitude: {station['id']}")
        require(bool(station["apiName"]), f"Missing API name: {station['id']}")
        require(
            set(station["lineNames"])
            == set(station["seoulStationIDs"])
            == set(station["subwayIDs"]),
            f"Line metadata mismatch: {station['id']}",
        )

    line_counts = Counter(line for station in stations for line in station["lineNames"])
    require(len(line_counts) == 19, f"Expected 19 supported lines, found {len(line_counts)}")

    seoul = station_named(stations, "서울")
    require(len(seoul) == 1 and "GTX-A" in seoul[0]["lineNames"], "서울역 transfer merge failed")
    ichon = station_named(stations, "이촌")
    require(len(ichon) == 1 and set(ichon[0]["lineNames"]) == {"4호선", "경의중앙선"}, "이촌 transfer merge failed")
    require(len(station_named(stations, "양평")) == 2, "Two distinct 양평 stations were merged")

    sinchon = [station for station in stations if station["apiName"].startswith("신촌")]
    require(len(sinchon) == 2, "Two distinct 신촌 stations were merged")
    require({tuple(station["lineNames"]) for station in sinchon} == {("2호선",), ("경의중앙선",)}, "신촌 line split failed")

    renamed = {
        "평택지제": "지제",
        "능길": "신길온천",
        "자양": "뚝섬유원지",
        "세종대왕릉": "세종왕릉",
    }
    for display_name, api_name in renamed.items():
        matches = station_named(stations, display_name)
        require(len(matches) == 1 and matches[0]["apiName"] == api_name, f"Rename mapping failed: {display_name}")

    yangwon = station_named(stations, "양원")
    require(len(yangwon) == 1, "Yangwon station match failed")
    require(37.5 < yangwon[0]["latitude"] < 37.7, "Yangwon latitude regression")
    require(127.0 < yangwon[0]["longitude"] < 127.2, "Yangwon longitude regression")

    print("Station bundle validation passed")
    print(f"- Physical stations: {len(stations)}")
    print(f"- Station-line mappings: {EXPECTED_STATION_LINE_COUNT}")
    print(f"- Supported lines: {len(line_counts)}")


if __name__ == "__main__":
    main()
