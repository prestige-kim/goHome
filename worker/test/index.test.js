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

test("arrival endpoint requires a bearer token", async () => {
  const handler = createHandler(() => {
    throw new Error("upstream should not be called");
  });
  const response = await handler(
    new Request("https://proxy.example/v1/arrivals?station=시청"),
    environment,
  );

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "unauthorized" });
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
