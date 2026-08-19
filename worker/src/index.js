const SEOUL_SUBWAY_API_ORIGIN = "http://swopenapi.seoul.go.kr";
const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

export function createHandler(fetchUpstream = fetch) {
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

    if (url.pathname !== "/v1/arrivals") {
      return jsonResponse({ error: "not_found" }, 404);
    }

    const configurationError = validateEnvironment(env);
    if (configurationError) {
      return jsonResponse({ error: configurationError }, 500);
    }

    if (!isAuthorized(request, env.GOHOME_CLIENT_TOKEN)) {
      return jsonResponse({ error: "unauthorized" }, 401, {
        "www-authenticate": "Bearer",
      });
    }

    const station = normalizeStation(url.searchParams.get("station"));
    if (!station) {
      return jsonResponse({ error: "invalid_station" }, 400);
    }

    const upstreamURL = buildArrivalURL(env.SEOUL_API_KEY, station);

    try {
      const upstreamResponse = await fetchUpstream(upstreamURL, {
        method: "GET",
        headers: { accept: "application/json" },
        signal: AbortSignal.timeout(8_000),
      });

      if (!upstreamResponse.ok) {
        return jsonResponse({ error: "upstream_http_error" }, 502);
      }

      const body = await upstreamResponse.text();
      JSON.parse(body);

      return new Response(body, { status: 200, headers: JSON_HEADERS });
    } catch {
      return jsonResponse({ error: "upstream_unavailable" }, 502);
    }
  };
}

function validateEnvironment(env) {
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

function buildArrivalURL(apiKey, station) {
  const keySegment = encodeURIComponent(apiKey);
  const stationSegment = encodeURIComponent(station);
  return `${SEOUL_SUBWAY_API_ORIGIN}/api/subway/${keySegment}/json/realtimeStationArrival/0/20/${stationSegment}`;
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
