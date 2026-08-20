# Cloudflare Worker 중계 서버 설정

## 목적

서울시 실시간 지하철 API는 HTTP만 제공한다. GoHome Worker는 앱과 Cloudflare 사이를 HTTPS로
연결하고, 서울시 API 키를 앱 번들 대신 Cloudflare의 암호화 Secret에 보관한다.

```text
iPhone -- HTTPS + 개인용 토큰 --> Cloudflare Worker -- HTTP + 서울시 키 --> 서울시 API
```

서울시 구간은 원본 서비스 제약 때문에 HTTP가 남지만, 사용자의 Wi-Fi·이동통신 구간에 서울시
키가 노출되지 않고 앱을 분석해도 원본 키를 얻을 수 없다. Worker는 고정된 도착정보·열차 위치·시간표·공휴일 API만
호출할 수 있으므로 임의 프록시로 악용할 수 없다.

## 현재 제공 경로

- `GET /health`: 배포 상태 확인, 인증 불필요
- `GET /v1/arrivals?station=시청`: 역별 실시간 도착정보, Bearer 토큰 필요
- `GET /v1/positions?line=2호선`: 노선별 실시간 열차 위치, Bearer 토큰 필요
- `GET /v1/last-trains?station=시청&line=2호선&direction=inner&serviceDay=weekday&date=2026-08-20`: 예정 운행시각표, Bearer 토큰 필요
- `GET /v1/service-day?date=2026-08-20`: 평일·토요일·일요일/공휴일 판정, Bearer 토큰 필요

위치 경로의 `line`은 앱이 지원하는 19개 노선 allowlist의 정확한 이름만 허용한다. URL이나 임의
호스트를 받을 수 없으며 원본 서비스도 `realtimePosition`으로 고정되어 있다.

막차 경로는 1~9호선과 정해진 방향·영업일·ISO 날짜만 허용하고 원본 서비스는 `getTrainSch`로
고정한다. 공휴일 경로도 ISO 날짜만 받아 한국천문연구원 `getRestDeInfo`를 월 단위로 조회·캐시한다.
모든 보호 경로는 원본별 Secret 존재 여부보다 Bearer 인증을 먼저 검사한다. 오류 응답에는 원본
URL, 서울시 키, 공공데이터포털 키를 포함하지 않는다.

도착정보 경로는 원본의 HTTP 429를 `upstream_rate_limited`/429로 전달하고, 원본 HTTP 오류·연결
실패·JSON 형식 오류를 키나 원본 URL이 포함되지 않은 오류 코드로 정규화한다. 앱은 이 코드와
HTTP 상태를 사용해 토큰 오류, 호출 한도, Worker 장애, 서울시 API 장애를 구분한다.

## 비용

Cloudflare Workers Free 플랜은 기본 제공되며 현재 개인 개발 단계의 요청량에는 충분하다.
유료 플랜으로 직접 전환하지 않는 한 이 구성은 비용 0원으로 운영한다.

## 최초 배포

1. 무료 Cloudflare 계정을 만든다.
2. 터미널에서 Worker 폴더로 이동해 도구를 설치한다.

   ```sh
   cd worker
   npm install
   npx wrangler login
   ```

3. 배포용 Secret 파일을 만들고 세 값을 채운다.

   ```sh
   cp .dev.vars.example .env.production
   openssl rand -hex 32
   ```

   - `SEOUL_API_KEY`: 기존 서울 열린데이터광장 키
   - `PUBLIC_DATA_API_KEY`: 공공데이터포털 한국천문연구원 특일 정보 Encoding 키
   - `GOHOME_CLIENT_TOKEN`: 위 `openssl` 명령의 결과

   `PUBLIC_DATA_API_KEY`가 아직 없으면 막차 시간표 경로는 사용할 수 있지만 자동 공휴일 판정은
   비활성화되어 앱이 달력 요일 기준으로 폴백한다.

4. 코드와 암호화 Secret을 함께 배포한다.

   ```sh
   npx wrangler deploy --secrets-file .env.production
   ```

5. 출력된 `https://...workers.dev` 주소를 확인한다.

## 앱 설정

`Config/Secrets.xcconfig`에 배포 주소와 같은 개인용 토큰을 추가한다.

```xcconfig
TRANSIT_PROXY_BASE_URL = https:/$()/gohome-transit-proxy.<계정>.workers.dev
TRANSIT_PROXY_CLIENT_TOKEN = 위에서_생성한_GOHOME_CLIENT_TOKEN
```

`.xcconfig`에서는 `//`가 주석이므로 `https:/$()/` 형식을 유지한다. 앱 번들에는
정상적인 `https://` URL로 들어간다.

`SEOUL_API_KEY`와 `PUBLIC_DATA_API_KEY`는 iOS 앱의 `Info.plist`에 포함되지 않는다.
`TRANSIT_PROXY_CLIENT_TOKEN`은 개인 테스트의 무단 호출 방지용이며,
정식 공개 앱의 완전한 사용자 인증 수단은 아니다.

## 확인

배포 주소의 상태를 확인한다.

```sh
curl https://gohome-transit-proxy.<계정>.workers.dev/health
```

정상 응답은 다음과 같다.

```json
{"status":"ok"}
```

2026-08-19 최초 배포에서 `/health`, Bearer 토큰 인증, 시청역 실시간 도착정보 13건을
종단간으로 확인했다. 로컬에서 다시 점검할 때는 다음 스크립트를 사용한다.

같은 날 원본 429·비정상 JSON 오류 정규화와 회귀 테스트를 보강한 버전을 재배포했으며,
재배포 후에도 `/health`, Bearer 인증, 서울시 `INFO-000`, 시청역 도착정보 12건을 종단간으로
확인했다.

```sh
ruby scripts/check_worker_api.rb 시청
```

2026-08-19 위치 경로 배포 후 `/health`, 무인증 요청의 401 차단, Bearer 인증, 시청역 도착 14건,
2호선 위치 35건,
서울시 `INFO-000`과 위치 DTO 13개 필드를 종단간으로 확인했다.

2026-08-20 막차 경로 배포 후 `/health` 200, 무인증 요청 401, Bearer 인증, 서울시 정상 코드
`00`, 시청역 2호선 내선 시간표 239건을 종단간으로 확인했다. 공휴일 경로는 키 미설정 상태에서
원본 정보를 노출하지 않는 `missing_public_data_api_key`로 닫히며 앱 폴백으로 연결되는 것을 확인했다.

모든 `/v1/*` 요청은 `Authorization: Bearer <GOHOME_CLIENT_TOKEN>` 헤더가 있어야 한다. 토큰이나
서울시 키를 명령 기록, GitHub Issue, 커밋, 스크린샷에 남기지 않는다.

## 로컬 테스트

Worker 코드의 자동 테스트는 실제 키나 네트워크를 사용하지 않는다. 상태 확인, 인증, 입력 검증,
허용 메서드·경로, 위치·시간표 allowlist, 네 고정 원본 연산, 인증 우선순위, Secret 누락,
공휴일 월 캐시, 원본 연결 실패, HTTP 429, 잘못된 JSON 응답을 17개 테스트로 회귀 검증한다.

```sh
cd worker
npm test
```
