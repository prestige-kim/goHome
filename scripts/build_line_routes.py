#!/usr/bin/env python3

"""Build explicit transit routes without inferring order from numeric station IDs."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable

from build_station_bundle import DEFAULT_SEOUL_PATH, LINE_ORDER, identifier, read_sheet


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT_PATH = PROJECT_ROOT / "GoHome/Resources/line_routes.json"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seoul", type=Path, default=DEFAULT_SEOUL_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    return parser.parse_args()


class RouteSource:
    def __init__(self, records: list[dict[str, Any]]) -> None:
        self.by_line: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for record in records:
            self.by_line[str(record["호선이름"])].append(record)

    def records(self, line: str) -> list[dict[str, Any]]:
        return self.by_line[line]

    def record(self, line: str, name: str) -> dict[str, Any]:
        matches = [row for row in self.records(line) if str(row["STATN_NM"]) == name]
        if len(matches) != 1:
            raise ValueError(f"Expected one {line} station named {name}, found {len(matches)}")
        return matches[0]

    def span(self, line: str, start: str, end: str) -> list[dict[str, Any]]:
        rows = self.records(line)
        start_index = rows.index(self.record(line, start))
        end_index = rows.index(self.record(line, end))
        if start_index > end_index:
            raise ValueError(f"Invalid source span: {line} {start} -> {end}")
        return rows[start_index : end_index + 1]

    def named(self, line: str, names: Iterable[str]) -> list[dict[str, Any]]:
        return [self.record(line, name) for name in names]


def route(route_id: str, rows: list[dict[str, Any]], *, circular: bool = False) -> dict[str, Any]:
    return {
        "id": route_id,
        "isCircular": circular,
        "stationIDs": [identifier(row["STATN_ID"]) for row in rows],
    }


def build_routes(source: RouteSource) -> list[dict[str, Any]]:
    routes_by_line: dict[str, list[dict[str, Any]]] = {}

    north = source.named("1호선", ["연천", "전곡", "청산"]) + source.span("1호선", "소요산", "구로")
    south = source.span("1호선", "가산디지털단지", "신창")
    routes_by_line["1호선"] = [
        route("incheon", north + source.span("1호선", "구일", "인천")),
        route("sinchang", north + south),
        route("gwangmyeong", north + source.span("1호선", "가산디지털단지", "금천구청") + source.named("1호선", ["광명"])),
        route("seodongtan", north + source.span("1호선", "가산디지털단지", "병점") + source.named("1호선", ["서동탄"])),
    ]

    routes_by_line["2호선"] = [
        route("circle", source.span("2호선", "시청", "충정로"), circular=True),
        route("seongsu-branch", source.named("2호선", ["성수"]) + source.span("2호선", "용답", "신설동")),
        route("sinjeong-branch", source.named("2호선", ["신도림"]) + source.span("2호선", "도림천", "까치산")),
    ]

    routes_by_line["5호선"] = [
        route("hanam", source.span("5호선", "방화", "강동") + source.span("5호선", "길동", "하남검단산")),
        route("macheon", source.span("5호선", "방화", "강동") + source.span("5호선", "둔촌동", "마천")),
    ]

    eungam = source.record("6호선", "응암순환(상선)")
    routes_by_line["6호선"] = [
        route(
            "eungam-loop",
            [eungam] + source.span("6호선", "역촌", "구산") + [eungam] + source.span("6호선", "새절(신사)", "신내"),
        )
    ]

    routes_by_line["GTX-A"] = [
        route("north", source.span("GTX-A", "운정중앙", "서울")),
        route("south", source.span("GTX-A", "수서", "동탄")),
    ]

    east = source.span("경의중앙선", "용산", "지평")
    west = list(reversed(source.span("경의중앙선", "공덕", "임진강")))
    west_to_gajwa = list(reversed(source.span("경의중앙선", "가좌", "임진강")))
    routes_by_line["경의중앙선"] = [
        route("main", west + source.named("경의중앙선", ["효창공원앞"]) + east),
        route("seoul-branch", west_to_gajwa + source.named("경의중앙선", ["신촌(경의중앙선)", "서울"])),
    ]

    routes_by_line["공항철도"] = [
        route(
            "main",
            source.named(
                "공항철도",
                [
                    "서울", "공덕", "홍대입구", "디지털미디어시티", "마곡나루", "김포공항",
                    "계양", "검암", "청라국제도시", "영종", "운서", "공항화물청사",
                    "인천공항1터미널", "인천공항2터미널",
                ],
            ),
        )
    ]

    gyeongchun_tail = source.span("경춘선", "상봉", "춘천")
    routes_by_line["경춘선"] = [
        route("cheongnyangni", source.span("경춘선", "청량리", "중랑") + gyeongchun_tail),
        route("gwangun", source.named("경춘선", ["광운대"]) + gyeongchun_tail),
    ]

    special_lines = set(routes_by_line)
    for line in LINE_ORDER:
        if line not in special_lines:
            routes_by_line[line] = [route("main", source.records(line))]

    return [
        {"lineName": line, "routes": routes_by_line[line]}
        for line in LINE_ORDER
    ]


def main() -> None:
    arguments = parse_arguments()
    source_rows = read_sheet(arguments.seoul, "SUBWAY_ID")
    payload = {
        "source": arguments.seoul.name,
        "ordering": "official source row order with explicit audited branch and loop routes",
        "lines": build_routes(RouteSource(source_rows)),
    }
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print("Line route build completed")
    print(f"- Lines: {len(payload['lines'])}")
    print(f"- Routes: {sum(len(line['routes']) for line in payload['lines'])}")
    print(f"- Output: {arguments.output.relative_to(PROJECT_ROOT)}")


if __name__ == "__main__":
    main()
