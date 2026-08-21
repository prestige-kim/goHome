import assert from "node:assert/strict";
import test from "node:test";

import worker, { createHandler } from "../src/index.js";

const environment = {
  SEOUL_API_KEY: "test-seoul-key",
  PUBLIC_DATA_API_KEY: "test-public-data-key",
  GOHOME_CLIENT_TOKEN: "test-client-token",
};

function authorizedRequest(path) {
  return new Request(`https://proxy.example${path}`, {
    headers: { authorization: `Bearer ${environment.GOHOME_CLIENT_TOKEN}` },
  });
}

test("health check does not require secrets", async () => {
  const response = await worker.fetch(
    new Request("https://proxy.example/health"),
    {},
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "ok" });
});

test("transit endpoints require a bearer token", async () => {
  const handler = createHandler(() => {
    throw new Error("upstream should not be called");
  });
  const response = await handler(
    new Request("https://proxy.example/v1/arrivals?station=시청"),
    environment,
  );

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "unauthorized" });

  const positionResponse = await handler(
    new Request("https://proxy.example/v1/positions?line=2호선"),
    environment,
  );
  assert.equal(positionResponse.status, 401);
  assert.deepEqual(await positionResponse.json(), { error: "unauthorized" });

  const lastTrainResponse = await handler(
    new Request("https://proxy.example/v1/last-trains?station=시청&line=2호선&direction=inner&serviceDay=weekday&date=2026-08-20"),
    environment,
  );
  assert.equal(lastTrainResponse.status, 401);

  const serviceDayResponse = await handler(
    new Request("https://proxy.example/v1/service-day?date=2026-08-20"),
    environment,
  );
  assert.equal(serviceDayResponse.status, 401);
});

test("arrival endpoint validates station input", async () => {
  const handler = createHandler(() => {
    throw new Error("upstream should not be called");
  });
  const response = await handler(
    authorizedRequest("/v1/arrivals?station="),
    environment,
  );

  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid_station" });
});

test("arrival endpoint reports missing worker secrets", async () => {
  const handler = createHandler(() => {
    throw new Error("upstream should not be called");
  });
  const missingClientToken = await handler(
    new Request("https://proxy.example/v1/arrivals?station=시청"),
    { SEOUL_API_KEY: environment.SEOUL_API_KEY },
  );
  assert.equal(missingClientToken.status, 500);
  assert.deepEqual(await missingClientToken.json(), { error: "missing_client_token" });

  const missingSeoulKey = await handler(
    authorizedRequest("/v1/arrivals?station=시청"),
    { GOHOME_CLIENT_TOKEN: environment.GOHOME_CLIENT_TOKEN },
  );
  assert.equal(missingSeoulKey.status, 500);
  assert.deepEqual(await missingSeoulKey.json(), { error: "missing_seoul_api_key" });
});

test("authorization is checked before route-specific secrets", async () => {
  const handler = createHandler(() => {
    throw new Error("upstream should not be called");
  });
  const response = await handler(
    new Request("https://proxy.example/v1/service-day?date=2026-08-20"),
    { GOHOME_CLIENT_TOKEN: environment.GOHOME_CLIENT_TOKEN },
  );

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "unauthorized" });
});

test("worker rejects unsupported methods and routes", async () => {
  const methodResponse = await worker.fetch(
    new Request("https://proxy.example/health", { method: "POST" }),
    {},
  );
  const routeResponse = await worker.fetch(
    new Request("https://proxy.example/v1/anything"),
    {},
  );

  assert.equal(methodResponse.status, 405);
  assert.equal(methodResponse.headers.get("allow"), "GET");
  assert.deepEqual(await methodResponse.json(), { error: "method_not_allowed" });
  assert.equal(routeResponse.status, 404);
  assert.deepEqual(await routeResponse.json(), { error: "not_found" });
});

test("position endpoint accepts only known line names", async () => {
  const handler = createHandler(() => {
    throw new Error("upstream should not be called");
  });

  for (const path of [
    "/v1/positions",
    "/v1/positions?line=",
    "/v1/positions?line=없는노선",
    "/v1/positions?line=https://example.com",
  ]) {
    const response = await handler(authorizedRequest(path), environment);
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { error: "invalid_line" });
  }
});

test("arrival endpoint proxies only the fixed Seoul API operation", async () => {
  let requestedURL;
  const upstreamPayload = {
    errorMessage: { code: "INFO-000", message: "정상 처리되었습니다." },
    realtimeArrivalList: [{ statnNm: "시청", subwayId: "1001" }],
  };
  const handler = createHandler((url) => {
    requestedURL = url;
    return Promise.resolve(
      new Response(JSON.stringify(upstreamPayload), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
  });

  const response = await handler(
    authorizedRequest("/v1/arrivals?station=시청"),
    environment,
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), upstreamPayload);
  assert.equal(
    requestedURL,
    "http://swopenapi.seoul.go.kr/api/subway/test-seoul-key/json/realtimeStationArrival/0/20/%EC%8B%9C%EC%B2%AD",
  );
});

test("position endpoint proxies only the fixed Seoul API operation", async () => {
  let requestedURL;
  const upstreamPayload = {
    errorMessage: { code: "INFO-000", message: "정상 처리되었습니다." },
    realtimePositionList: [{ statnNm: "을지로입구", subwayId: "1002" }],
  };
  const handler = createHandler((url) => {
    requestedURL = url;
    return Promise.resolve(
      new Response(JSON.stringify(upstreamPayload), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
  });

  const response = await handler(
    authorizedRequest("/v1/positions?line=2호선"),
    environment,
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), upstreamPayload);
  assert.equal(
    requestedURL,
    "http://swopenapi.seoul.go.kr/api/subway/test-seoul-key/json/realtimePosition/0/100/2%ED%98%B8%EC%84%A0",
  );
});

test("last-train endpoint validates every fixed timetable input", async () => {
  const handler = createHandler(() => {
    throw new Error("upstream should not be called");
  });
  const valid = "/v1/last-trains?station=시청&line=2호선&direction=inner&serviceDay=weekday&date=2026-08-20";
  const invalidPaths = [
    valid.replace("station=시청", "station="),
    valid.replace("line=2호선", "line=경의중앙선"),
    valid.replace("line=2호선", "line=https://example.com"),
    valid.replace("direction=inner", "direction=clockwise"),
    valid.replace("serviceDay=weekday", "serviceDay=friday"),
    valid.replace("date=2026-08-20", "date=2026-02-30"),
  ];

  for (const path of invalidPaths) {
    const response = await handler(authorizedRequest(path), environment);
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { error: "invalid_timetable_query" });
  }
});

test("last-train endpoint proxies only the fixed Seoul timetable operation", async () => {
  let requestedURL;
  const upstreamPayload = {
    response: {
      header: { resultCode: "00", resultMsg: "NORMAL_CODE" },
      body: {
        items: {
          item: [{
            lineNm: "2호선",
            upbdnbSe: "내선",
            stnNm: "시청",
            stnCd: "0201",
            arvlStnNm: "을지로입구",
            trainDptreTm: "24:58:30",
          }],
        },
      },
    },
  };
  const handler = createHandler((url) => {
    requestedURL = url;
    return Promise.resolve(new Response(JSON.stringify(upstreamPayload), { status: 200 }));
  });

  const response = await handler(
    authorizedRequest("/v1/last-trains?station=시청&line=2호선&direction=inner&serviceDay=weekday&date=2026-08-20"),
    environment,
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), upstreamPayload);
  assert.equal(
    requestedURL,
    "http://openapi.seoul.go.kr:8088/test-seoul-key/json/getTrainSch/1/1000/%20/N/%EB%82%B4%EC%84%A0/%ED%8F%89%EC%9D%BC/2%ED%98%B8%EC%84%A0//%EC%8B%9C%EC%B2%AD///////2026-08-20%2012%3A00%3A00",
  );
});

test("service-day endpoint classifies and caches a holiday month", async () => {
  let upstreamCalls = 0;
  let requestedURL;
  const holidayPayload = {
    response: {
      header: { resultCode: "00", resultMsg: "NORMAL SERVICE" },
      body: {
        items: {
          item: [
            { locdate: 20260815, isHoliday: "Y", dateName: "광복절" },
          ],
        },
      },
    },
  };
  const handler = createHandler((url) => {
    upstreamCalls += 1;
    requestedURL = url;
    return Promise.resolve(new Response(JSON.stringify(holidayPayload), { status: 200 }));
  });

  const holiday = await handler(
    authorizedRequest("/v1/service-day?date=2026-08-15"),
    environment,
  );
  const weekday = await handler(
    authorizedRequest("/v1/service-day?date=2026-08-20"),
    environment,
  );

  assert.deepEqual(await holiday.json(), {
    date: "2026-08-15",
    type: "sunday_holiday",
    holidayName: "광복절",
  });
  assert.deepEqual(await weekday.json(), {
    date: "2026-08-20",
    type: "weekday",
    holidayName: null,
  });
  assert.equal(upstreamCalls, 1);
  const holidayURL = new URL(requestedURL);
  assert.equal(holidayURL.origin, "https://apis.data.go.kr");
  assert.equal(holidayURL.pathname, "/B090041/openapi/service/SpcdeInfoService/getRestDeInfo");
  assert.equal(holidayURL.searchParams.get("serviceKey"), environment.PUBLIC_DATA_API_KEY);
  assert.equal(holidayURL.searchParams.get("solYear"), "2026");
  assert.equal(holidayURL.searchParams.get("solMonth"), "08");
});

test("service-day endpoint encodes a portal Encoding key exactly once", async () => {
  let requestedURL;
  const handler = createHandler((url) => {
    requestedURL = url;
    return Promise.resolve(new Response(JSON.stringify({
      response: {
        header: { resultCode: "00", resultMsg: "NORMAL SERVICE" },
        body: { items: "" },
      },
    }), { status: 200 }));
  });
  const encodedKey = "test%2Bpublic%2Fdata%3D";

  const response = await handler(
    authorizedRequest("/v1/service-day?date=2026-08-21"),
    { ...environment, PUBLIC_DATA_API_KEY: encodedKey },
  );

  assert.equal(response.status, 200);
  assert.equal(new URL(requestedURL).searchParams.get("serviceKey"), "test+public/data=");
  assert.equal(requestedURL.includes("%252B"), false);
  assert.equal(requestedURL.includes("%253D"), false);
});

test("service-day endpoint requires the public-data key and sanitizes failures", async () => {
  const missingKeyResponse = await createHandler(() => {
    throw new Error("upstream should not be called");
  })(
    new Request("https://proxy.example/v1/service-day?date=2026-08-20", {
      headers: { authorization: `Bearer ${environment.GOHOME_CLIENT_TOKEN}` },
    }),
    {
      SEOUL_API_KEY: environment.SEOUL_API_KEY,
      GOHOME_CLIENT_TOKEN: environment.GOHOME_CLIENT_TOKEN,
    },
  );
  assert.equal(missingKeyResponse.status, 500);
  assert.deepEqual(await missingKeyResponse.json(), { error: "missing_public_data_api_key" });

  const failedResponse = await createHandler(() => Promise.reject(
    new Error(`request exposed ${environment.PUBLIC_DATA_API_KEY}`),
  ))(
    authorizedRequest("/v1/service-day?date=2026-08-20"),
    environment,
  );
  const body = await failedResponse.text();
  assert.equal(failedResponse.status, 502);
  assert.equal(body.includes(environment.PUBLIC_DATA_API_KEY), false);
  assert.deepEqual(JSON.parse(body), { error: "holiday_api_unavailable" });
});

test("upstream failures do not expose the upstream URL or key", async () => {
  const handler = createHandler(() => Promise.reject(new Error("network error")));
  const response = await handler(
    authorizedRequest("/v1/arrivals?station=시청"),
    environment,
  );
  const body = await response.text();

  assert.equal(response.status, 502);
  assert.equal(body.includes(environment.SEOUL_API_KEY), false);
  assert.deepEqual(JSON.parse(body), { error: "upstream_unavailable" });
});

test("position failures do not expose the upstream URL, key, or line", async () => {
  const handler = createHandler(() => Promise.reject(new Error("network error")));
  const response = await handler(
    authorizedRequest("/v1/positions?line=2호선"),
    environment,
  );
  const body = await response.text();

  assert.equal(response.status, 502);
  assert.equal(body.includes(environment.SEOUL_API_KEY), false);
  assert.equal(body.includes("swopenapi"), false);
  assert.deepEqual(JSON.parse(body), { error: "upstream_unavailable" });
});

test("upstream rate limits are preserved without exposing details", async () => {
  const handler = createHandler(() => Promise.resolve(
    new Response("rate limited", { status: 429 }),
  ));
  const response = await handler(
    authorizedRequest("/v1/arrivals?station=시청"),
    environment,
  );

  assert.equal(response.status, 429);
  assert.deepEqual(await response.json(), { error: "upstream_rate_limited" });
});

test("invalid upstream JSON is returned as a sanitized Seoul API failure", async () => {
  const handler = createHandler(() => Promise.resolve(
    new Response("<html>temporary error</html>", { status: 200 }),
  ));
  const response = await handler(
    authorizedRequest("/v1/arrivals?station=시청"),
    environment,
  );

  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { error: "invalid_upstream_response" });
});
