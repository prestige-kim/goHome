# Cloudflare Worker 중계 서버 설정

## 목적

서울시 실시간 지하철 API는 HTTP만 제공한다. GoHome Worker는 앱과 Cloudflare 사이를 HTTPS로
연결하고, 서울시 API 키를 앱 번들 대신 Cloudflare의 암호화 Secret에 보관한다.

```text
iPhone -- HTTPS + 개인용 토큰 --> Cloudflare Worker -- HTTP + 서울시 키 --> 서울시 API
```

서울시 구간은 원본 서비스 제약 때문에 HTTP가 남지만, 사용자의 Wi-Fi·이동통신 구간에 서울시
키가 노출되지 않고 앱을 분석해도 원본 키를 얻을 수 없다. Worker는 고정된 도착정보 API만
호출할 수 있으므로 임의 프록시로 악용할 수 없다.

## 현재 제공 경로

- `GET /health`: 배포 상태 확인, 인증 불필요
- `GET /v1/arrivals?station=시청`: 역별 실시간 도착정보, Bearer 토큰 필요

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

3. 배포용 Secret 파일을 만들고 두 값을 채운다.

   ```sh
   cp .env.production.example .env.production
   openssl rand -hex 32
   ```

   - `SEOUL_API_KEY`: 기존 서울 열린데이터광장 키
   - `GOHOME_CLIENT_TOKEN`: 위 `openssl` 명령의 결과

4. 코드와 암호화 Secret을 함께 배포한다.

   ```sh
   npx wrangler deploy --secrets-file .env.production
   ```

5. 출력된 `https://...workers.dev` 주소를 확인한다.

## 앱 설정

`Config/Secrets.xcconfig`에 배포 주소와 같은 개인용 토큰을 추가한다.

```xcconfig
TRANSIT_PROXY_BASE_URL = https://gohome-transit-proxy.<계정>.workers.dev
TRANSIT_PROXY_CLIENT_TOKEN = 위에서_생성한_GOHOME_CLIENT_TOKEN
```

`SEOUL_API_KEY`는 로컬 API 점검 스크립트를 위해 남겨도 되지만 iOS 앱의 `Info.plist`에는 더
이상 포함되지 않는다. `TRANSIT_PROXY_CLIENT_TOKEN`은 개인 테스트의 무단 호출 방지용이며,
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

도착정보 요청은 `Authorization: Bearer <GOHOME_CLIENT_TOKEN>` 헤더가 있어야 한다. 토큰이나
서울시 키를 명령 기록, GitHub Issue, 커밋, 스크린샷에 남기지 않는다.

## 로컬 테스트

Worker 코드의 자동 테스트는 실제 키나 네트워크를 사용하지 않는다. 상태 확인, 인증, 입력 검증,
허용 메서드·경로, 고정 원본 URL, Secret 누락, 원본 연결 실패, HTTP 429, 잘못된 JSON 응답을
회귀 테스트한다.

```sh
cd worker
npm test
```
