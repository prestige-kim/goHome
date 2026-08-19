#!/usr/bin/env python3

"""Validate the generated line routes against the bundled station metadata."""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parent.parent
STATIONS_PATH = PROJECT_ROOT / "GoHome/Resources/stations.seed.json"
ROUTES_PATH = PROJECT_ROOT / "GoHome/Resources/line_routes.json"
EXPECTED_LINES = 19
EXPECTED_STATION_LINE_COUNT = 696
MAX_ADJACENT_DISTANCE_METERS = 30_000


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def haversine_meters(first: dict[str, Any], second: dict[str, Any]) -> float:
    latitude1, longitude1 = map(math.radians, (first["latitude"], first["longitude"]))
    latitude2, longitude2 = map(math.radians, (second["latitude"], second["longitude"]))
    latitude_delta = latitude2 - latitude1
    longitude_delta = longitude2 - longitude1
    value = (
        math.sin(latitude_delta / 2) ** 2
        + math.cos(latitude1) * math.cos(latitude2) * math.sin(longitude_delta / 2) ** 2
    )
    return 6_371_000 * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value))


def main() -> None:
    stations: list[dict[str, Any]] = json.loads(STATIONS_PATH.read_text(encoding="utf-8"))
    bundle: dict[str, Any] = json.loads(ROUTES_PATH.read_text(encoding="utf-8"))
    lines = bundle["lines"]
    require(len(lines) == EXPECTED_LINES, f"Expected {EXPECTED_LINES} lines")
    require(len({line['lineName'] for line in lines}) == len(lines), "Duplicate line routes")

    station_by_line_id: dict[tuple[str, str], dict[str, Any]] = {}
    expected_by_line: dict[str, set[str]] = {}
    for station in stations:
        for line, station_id in station["seoulStationIDs"].items():
            station_by_line_id[(line, station_id)] = station
            expected_by_line.setdefault(line, set()).add(station_id)

    require(
        sum(len(ids) for ids in expected_by_line.values()) == EXPECTED_STATION_LINE_COUNT,
        "Station bundle line count changed",
    )

    route_count = 0
    for line in lines:
        line_name = line["lineName"]
        require(line_name in expected_by_line, f"Unknown line: {line_name}")
        route_ids = [route["id"] for route in line["routes"]]
        require(len(route_ids) == len(set(route_ids)), f"Duplicate route ID: {line_name}")
        covered: set[str] = set()
        for route in line["routes"]:
            route_count += 1
            station_ids = route["stationIDs"]
            require(len(station_ids) >= 2, f"Route too short: {line_name} {route['id']}")
            for station_id in station_ids:
                require(
                    (line_name, station_id) in station_by_line_id,
                    f"Unknown station ID: {line_name} {station_id}",
                )
                covered.add(station_id)
            for first_id, second_id in zip(station_ids, station_ids[1:]):
                first = station_by_line_id[(line_name, first_id)]
                second = station_by_line_id[(line_name, second_id)]
                distance = haversine_meters(first, second)
                require(
                    distance <= MAX_ADJACENT_DISTANCE_METERS,
                    f"Implausible edge: {line_name} {first['name']} -> {second['name']} ({distance:.0f}m)",
                )
        require(
            covered == expected_by_line[line_name],
            f"Route coverage mismatch: {line_name} missing={sorted(expected_by_line[line_name] - covered)}",
        )

    two = next(line for line in lines if line["lineName"] == "2호선")
    require(any(route["isCircular"] for route in two["routes"]), "2호선 circular route missing")
    gtx = next(line for line in lines if line["lineName"] == "GTX-A")
    require(len(gtx["routes"]) == 2, "GTX-A disconnected sections must remain separate")

    print("Line route validation passed")
    print(f"- Lines: {len(lines)}")
    print(f"- Routes: {route_count}")
    print(f"- Covered station-line mappings: {EXPECTED_STATION_LINE_COUNT}")


if __name__ == "__main__":
    main()
