const SEOUL_SUBWAY_API_ORIGIN = "http://swopenapi.seoul.go.kr";
const SEOUL_TIMETABLE_API_ORIGIN = "http://openapi.seoul.go.kr:8088";
const HOLIDAY_API_ORIGIN = "https://apis.data.go.kr";
const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};
const SUPPORTED_LINES = new Set([
  "1호선", "2호선", "3호선", "4호선", "5호선", "6호선", "7호선", "8호선", "9호선",
  "경의중앙선", "공항철도", "경춘선", "수인분당선", "신분당선", "경강선",
  "우이신설선", "서해선", "신림선", "GTX-A",
]);
const TIMETABLE_LINES = new Set([
  "1호선", "2호선", "3호선", "4호선", "5호선", "6호선", "7호선", "8호선", "9호선",
]);
const TIMETABLE_DIRECTIONS = new Map([
  ["up", "상행"],
  ["down", "하행"],
  ["inner", "내선"],
  ["outer", "외선"],
]);
const TIMETABLE_SERVICE_DAYS = new Map([
  ["weekday", "평일"],
  ["saturday", "주말"],
  ["sunday_holiday", "주말"],
]);
const TRANSIT_PATHS = new Set([
  "/v1/arrivals",
  "/v1/positions",
  "/v1/last-trains",
  "/v1/service-day",
]);

export function createHandler(fetchUpstream = fetch, holidayCache = new Map()) {
  return async function handleRequest(request, env) {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return jsonResponse({ status: "ok" });
    }

    if (request.method !== "GET") {
      return jsonResponse({ error: "method_not_allowed" }, 405, {
        allow: "GET",
      });
    }

    if (!TRANSIT_PATHS.has(url.pathname)) {
      return jsonResponse({ error: "not_found" }, 404);
    }

    const configurationError = validateEnvironment(env, url.pathname);
    if (configurationError) {
      return jsonResponse({ error: configurationError }, 500);
    }

    if (!isAuthorized(request, env.GOHOME_CLIENT_TOKEN)) {
      return jsonResponse({ error: "unauthorized" }, 401, {
        "www-authenticate": "Bearer",
      });
    }

    if (url.pathname === "/v1/service-day") {
      const date = normalizeDate(url.searchParams.get("date"));
      if (!date) {
        return jsonResponse({ error: "invalid_date" }, 400);
      }
      return serviceDayResponse(date, env, fetchUpstream, holidayCache);
    }

    let upstreamURL;
    if (url.pathname === "/v1/arrivals") {
      const station = normalizeStation(url.searchParams.get("station"));
      if (!station) {
        return jsonResponse({ error: "invalid_station" }, 400);
      }
      upstreamURL = buildArrivalURL(env.SEOUL_API_KEY, station);
    } else if (url.pathname === "/v1/positions") {
      const line = normalizeLine(url.searchParams.get("line"));
      if (!line) {
        return jsonResponse({ error: "invalid_line" }, 400);
      }
      upstreamURL = buildPositionURL(env.SEOUL_API_KEY, line);
    } else {
      const station = normalizeStation(url.searchParams.get("station"));
      const line = normalizeTimetableLine(url.searchParams.get("line"));
      const direction = TIMETABLE_DIRECTIONS.get(url.searchParams.get("direction"));
      const serviceDay = TIMETABLE_SERVICE_DAYS.get(url.searchParams.get("serviceDay"));
      const date = normalizeDate(url.searchParams.get("date"));
      if (!station || !line || !direction || !serviceDay || !date) {
        return jsonResponse({ error: "invalid_timetable_query" }, 400);
      }
      upstreamURL = buildTimetableURL(
        env.SEOUL_API_KEY,
        station,
        line,
        direction,
        serviceDay,
        date,
      );
    }

    return proxyJSON(upstreamURL, fetchUpstream);
  };
}

async function proxyJSON(upstreamURL, fetchUpstream) {
  try {
    const upstreamResponse = await fetchUpstream(upstreamURL, {
      method: "GET",
      headers: { accept: "application/json" },
      signal: AbortSignal.timeout(8_000),
    });

    if (upstreamResponse.status === 429) {
      return jsonResponse({ error: "upstream_rate_limited" }, 429);
    }
    if (!upstreamResponse.ok) {
      return jsonResponse({ error: "upstream_http_error" }, 502);
    }

    const body = await upstreamResponse.text();
    try {
      JSON.parse(body);
    } catch {
      return jsonResponse({ error: "invalid_upstream_response" }, 502);
    }
    return new Response(body, { status: 200, headers: JSON_HEADERS });
  } catch {
    return jsonResponse({ error: "upstream_unavailable" }, 502);
  }
}

function validateEnvironment(env, pathname) {
  if (pathname === "/v1/service-day") {
    if (!env?.PUBLIC_DATA_API_KEY) return "missing_public_data_api_key";
    if (!env?.GOHOME_CLIENT_TOKEN) return "missing_client_token";
    return null;
  }
  if (!env?.SEOUL_API_KEY) return "missing_seoul_api_key";
  if (!env?.GOHOME_CLIENT_TOKEN) return "missing_client_token";
  return null;
}

function isAuthorized(request, expectedToken) {
  const authorization = request.headers.get("authorization") ?? "";
  return authorization === `Bearer ${expectedToken}`;
}

function normalizeStation(value) {
  const station = value?.trim();
  if (!station || station.length > 40) return null;
  if (/[\u0000-\u001F\u007F]/u.test(station)) return null;
  return station;
}

function normalizeLine(value) {
  const line = value?.trim();
  return line && SUPPORTED_LINES.has(line) ? line : null;
}

function normalizeTimetableLine(value) {
  const line = value?.trim();
  return line && TIMETABLE_LINES.has(line) ? line : null;
}

function normalizeDate(value) {
  const date = value?.trim();
  if (!date || !/^\d{4}-\d{2}-\d{2}$/u.test(date)) return null;
  const [year, month, day] = date.split("-").map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  return parsed.getUTCFullYear() === year &&
    parsed.getUTCMonth() === month - 1 &&
    parsed.getUTCDate() === day
    ? date
    : null;
}

function buildArrivalURL(apiKey, station) {
  const keySegment = encodeURIComponent(apiKey);
  const stationSegment = encodeURIComponent(station);
  return `${SEOUL_SUBWAY_API_ORIGIN}/api/subway/${keySegment}/json/realtimeStationArrival/0/20/${stationSegment}`;
}

function buildPositionURL(apiKey, line) {
  const keySegment = encodeURIComponent(apiKey);
  const lineSegment = encodeURIComponent(line);
  return `${SEOUL_SUBWAY_API_ORIGIN}/api/subway/${keySegment}/json/realtimePosition/0/100/${lineSegment}`;
}

function buildTimetableURL(apiKey, station, line, direction, serviceDay, date) {
  const segments = [
    apiKey,
    "json",
    "getTrainSch",
    "1",
    "1000",
    " ",
    "N",
    direction,
    serviceDay,
    line,
    "",
    station,
    "",
    "",
    "",
    "",
    "",
    "",
    `${date} 12:00:00`,
  ];
  return `${SEOUL_TIMETABLE_API_ORIGIN}/${segments.map(encodeURIComponent).join("/")}`;
}

async function serviceDayResponse(date, env, fetchUpstream, holidayCache) {
  const month = date.slice(0, 7);
  let holidays = holidayCache.get(month);

  try {
    if (!holidays) {
      holidays = await fetchHolidayMonth(month, env.PUBLIC_DATA_API_KEY, fetchUpstream);
      holidayCache.set(month, holidays);
    }
  } catch {
    return jsonResponse({ error: "holiday_api_unavailable" }, 502);
  }

  const holidayName = holidays.get(date) ?? null;
  const dayOfWeek = new Date(`${date}T00:00:00Z`).getUTCDay();
  const type = holidayName || dayOfWeek === 0
    ? "sunday_holiday"
    : dayOfWeek === 6
      ? "saturday"
      : "weekday";
  return jsonResponse({ date, type, holidayName });
}

async function fetchHolidayMonth(month, apiKey, fetchUpstream) {
  const [year, monthNumber] = month.split("-");
  const url = new URL(
    "/B090041/openapi/service/SpcdeInfoService/getRestDeInfo",
    HOLIDAY_API_ORIGIN,
  );
  url.searchParams.set("serviceKey", apiKey);
  url.searchParams.set("solYear", year);
  url.searchParams.set("solMonth", monthNumber);
  url.searchParams.set("numOfRows", "100");
  url.searchParams.set("_type", "json");

  const response = await fetchUpstream(url.toString(), {
    method: "GET",
    headers: { accept: "application/json" },
    signal: AbortSignal.timeout(8_000),
  });
  if (!response.ok) throw new Error("holiday upstream failure");

  const payload = await response.json();
  const header = payload?.response?.header;
  if (String(header?.resultCode).padStart(2, "0") !== "00") {
    throw new Error("holiday API error");
  }

  const rawItems = payload?.response?.body?.items?.item;
  const items = Array.isArray(rawItems) ? rawItems : rawItems ? [rawItems] : [];
  return new Map(items
    .filter((item) => item?.isHoliday === "Y" && /^\d{8}$/u.test(String(item?.locdate)))
    .map((item) => {
      const compact = String(item.locdate);
      const itemDate = `${compact.slice(0, 4)}-${compact.slice(4, 6)}-${compact.slice(6, 8)}`;
      return [itemDate, item.dateName ?? "공휴일"];
    }));
}

function jsonResponse(payload, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...JSON_HEADERS, ...extraHeaders },
  });
}

const handler = createHandler();

export default {
  fetch(request, env) {
    return handler(request, env);
  },
};
