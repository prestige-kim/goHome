import assert from "node:assert/strict";
import test from "node:test";

import worker, { createHandler } from "../src/index.js";

const environment = {
  SEOUL_API_KEY: "test-seoul-key",
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
  const response = await handler(
    new Request("https://proxy.example/v1/arrivals?station=시청"),
    {},
  );

  assert.equal(response.status, 500);
  assert.deepEqual(await response.json(), { error: "missing_seoul_api_key" });
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
