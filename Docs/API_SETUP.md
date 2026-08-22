# API 키 발급 및 요청 주소

서울시 원본 응답을 로컬에서 점검할 때는 `SEOUL_API_KEY`를 사용한다. 실제 앱은 원본 키를
포함하지 않고 `TRANSIT_PROXY_BASE_URL`과 `TRANSIT_PROXY_CLIENT_TOKEN`으로 Cloudflare
Worker를 호출한다. `PUBLIC_DATA_API_KEY`도 앱에 포함하지 않고 Worker Secret으로만 사용한다.

키는 `Config/Secrets.xcconfig`에만 저장한다. 이 파일은 `.gitignore`에 포함되어 GitHub에 올라가지 않는다. 값에 따옴표를 붙이지 않는다.

```xcconfig
SEOUL_API_KEY = 발급받은_서울시_키
TRANSIT_PROXY_BASE_URL = https:/$()/gohome-transit-proxy.<계정>.workers.dev
TRANSIT_PROXY_CLIENT_TOKEN = 생성한_개인용_토큰
```

`.xcconfig`에서 `//`는 주석으로 처리되므로 Worker URL은 `https:/$()/` 형식으로 적는다.
빌드된 `Info.plist`에는 정상적인 `https://` URL로 치환된다.

Worker 배포 절차는 [WORKER_SETUP.md](WORKER_SETUP.md)를 따른다.

## 1. 서울 열린데이터광장 키

- 인증키 신청: https://data.seoul.go.kr/together/mypage/actkeyMain.do
- 인증키 관리: 서울 열린데이터광장 로그인 → 나의 화면 → 인증키 관리
- 개발 중 요청 URL 입력을 요구하면 아래 실시간 도착정보 데이터셋 URL을 입력한다.
  - https://data.seoul.go.kr/dataList/OA-12764/F/1/datasetView.do

하나의 서울 열린데이터광장 키를 아래 서울시 API들에 사용한다.

### 실시간 역 도착정보

- 데이터셋: https://www.data.go.kr/data/15058052/openapi.do
- 서울시가 공식 문서에서 안내하는 요청 형식:

```text
http://swopenapi.seoul.go.kr/api/subway/{SEOUL_API_KEY}/json/realtimeStationArrival/0/20/{역명}
```

예시에서 `{역명}`에는 `서울`, `시청`, `강남`처럼 `역`을 제외한 이름을 URL 인코딩해 넣는다.

> 주의: 2026-08-19 확인 기준 `swopenapi.seoul.go.kr`은 HTTPS 연결을 제공하지 않고,
> 공식 샘플도 HTTP를 사용한다. 따라서 키와 응답이 전송 구간에서 암호화되지 않는다.
> 실제 앱은 배포된 Cloudflare Worker HTTPS 중계를 통해서만 이 원본 API를 호출한다.
> 아래 로컬 직접 호출 스크립트는 원본 키와 응답 형식을 점검하는 개발 도구로만 사용한다.

Xcode 없이 로컬에서 키와 응답을 1회 점검하려면 아래 명령을 사용한다. 응답은 Git에서
제외된 `tmp/api-samples/`에 저장된다. 이 명령은 HTTP 전송 위험을 이해한 경우에만 실행한다.

```sh
ruby scripts/check_seoul_api.rb --allow-insecure-http 시청
```

2026-08-19 시청역 점검에서 `INFO-000` 정상 응답과 도착정보 14건을 확인했다. 기존 DTO 필드와
급행(`btrainSttus`), 막차(`lstcarAt`), 상태 코드(`arvlCd`), 기준시각(`recptnDt`)의 타입도 확인했다.

### 실시간 열차 위치

- 데이터셋: https://www.data.go.kr/data/15058569/openapi.do
- 원본 요청 형식:

```text
http://swopenapi.seoul.go.kr/api/subway/{SEOUL_API_KEY}/json/realtimePosition/0/100/{호선명}
```

`{호선명}` 예시는 `1호선`, `2호선`, `수인분당선`이다. 이 API는 실제 GPS 좌표가 아니라 현재 역과 진입·도착·출발 상태를 제공한다.

공식 명세의 상태값은 `trainSttus` 0/1/2/3 = 진입/도착/출발/전역 출발이다.
`updnLine` 0/1은 상행·내선/하행·외선, `directAt` 0/1/7은 일반/급행/특급,
`lstcarAt` 0/1은 일반/막차를 뜻한다.

2026-08-19 배포된 Worker의 `GET /v1/positions?line=2호선`을 통해 HTTPS 종단간 호출을
실행했다. 최종 재검증에서 HTTP 200, 서울시 `INFO-000`, 시청 도착 14건, 2호선 위치 35건,
DTO 필드 13개를 확인했으며 해당 시점에는
상태 코드 0·1·2가 관측됐다. 코드 3은 공식 명세와 단위 테스트로 매핑을 고정했다. 응답 샘플은
Git에서 제외된 `tmp/api-samples/`에만 저장한다.

1호선 실제 응답에서는 같은 열차번호가 서로 다른 `recptnDt`로 중복될 수 있음을 확인했다.
앱은 노선·열차번호별 가장 최신 `recptnDt` 한 건만 DTO 변환 결과로 유지한다.

원본 키를 로컬에서 HTTP로 보내지 않고 다시 확인하려면 다음 명령을 사용한다.

```sh
ruby scripts/check_worker_api.rb 시청 2호선
ruby scripts/check_worker_api.rb 강남 2호선 --display
```

이 스크립트는 비밀값을 출력하지 않고 상태·인증, 도착·위치, 해당 노선의 양방향 막차 시간표,
필수 필드·시간 형식과 공휴일 판정 상태를 확인한다. 2호선은 `inner`/`outer`, 그 밖의 노선은
`up`/`down`을 모두 요청한다. `--display`를 추가하면 앱과 동일하게 방향·종착역·급행별 마지막
출발을 선택하고, 방향·종착역·예정 시각·열차번호처럼 허용된 비민감 필드만 출력한다.

### 역명과 역코드 매핑

- 데이터셋: https://www.data.go.kr/data/15058954/openapi.do
- Phase 1에서 전체 역 데이터의 서울시 역 ID·외부코드 연결에 사용한다.

### 막차 시간표

- 현재 사용 데이터셋: https://data.seoul.go.kr/dataList/OA-22750/A/1/datasetView.do
- 이전 역코드 기반 막차 데이터셋: https://data.seoul.go.kr/dataList/OA-15492/A/1/datasetView.do

2026-08-20 실제 점검에서 이전 `SearchLastTrainTimeByIDService`는 1호선 결과를 반환했지만 2호선은
`INFO-200`이어서, 현재 앱은 서울교통공사의 새 `getTrainSch` 열차운행시각표를 사용한다. 시청역
1호선 역코드는 `0151`, 2호선은 `0201`로 확인했다. 실시간 역 ID의 숫자 접미사와도 다르므로
앱은 역 ID 숫자로 시간표 코드나 순서를 추정하지 않는다.

배포된 Worker의 고정 요청 형식은 다음과 같다. `line`은 1~9호선, `direction`은
`up`/`down`/`inner`/`outer`, `serviceDay`는 `weekday`/`saturday`/`sunday_holiday`만 허용한다.

```text
GET /v1/last-trains?station=시청&line=2호선&direction=inner&serviceDay=weekday&date=2026-08-20
Authorization: Bearer <GOHOME_CLIENT_TOKEN>
```

같은 날 서울시 키 교체 후 기존 Free 플랜 Worker를 재배포하고 종단간 호출을 다시 실행했다.
시청역과 강남역 2호선은 내선 239행·외선 240행, 고속터미널역 3호선은 상·하행 각각 192행을
반환했다. 여섯 응답 모두 HTTP 200, 원본 정상 코드 `00`, 필수 필드 누락 0행, 시간 형식 오류
0행이었다. 원본 응답에는 `00:xx`, `24:xx`가 함께 나타날 수 있어 앱은 둘 다 같은 영업일의
다음 달력 날짜로 변환하고 `25:xx`까지 처리한다. 오전 4시 이전에는 전날을 영업일로 본다.

2026-08-21에는 같은 축약 검증으로 강남역 2호선 7행과 고속터미널역 3호선 7행을 생성했다.
강남역은 내·외선, 고속터미널역은 상·하행의 방향·종착역·예정 시각·열차번호를 앱 표시 형식으로
변환해 원본 시간표와 대조했다.

서울교통공사 원본의 `wkndSe`는 평일/주말만 구분한다. 앱 UI는 평일·토요일·일요일/공휴일을
구분하지만 토요일과 일요일/공휴일 요청은 현재 동일한 원본 `주말` 시간표로 매핑하며 이 한계를
화면에 표시한다.

서울시 실시간 지하철 OpenAPI는 기본적으로 하루 최대 1,000회 요청 제한이 안내되어 있다. 개인
사용 단계에서는 선택 역을 앱 전면에서만 40초 간격으로 요청한다. 백그라운드 전환 시 자동 갱신을
취소하며, 수동 요청이 진행 중이거나 같은 역의 최근 요청 후 40초가 지나지 않았으면 자동 요청을
중복 실행하지 않는다. 연속 실패 시 최대 5분까지 지수 백오프하고 전면 자동 갱신은 30분 뒤
일시정지한다. 막차 시간표는 앱에서 6시간 재사용하며 2호선은 내선·외선만 요청한다. 사용자가
명시적으로 새로고침하면 캐시와 자동 갱신 세션을 새로 시작할 수 있으므로, 하루 한도는 여전히
사용 패턴에 따라 관리해야 한다.

## 2. 공공데이터포털 키

- 회원가입·로그인: https://www.data.go.kr
- 한국천문연구원 특일 정보 활용신청: https://www.data.go.kr/data/15012690/openapi.do

공공데이터포털에서 활용신청 후 마이페이지에 표시되는 일반 인증키 중 `Encoding` 키를
`worker/.env.production`의 `PUBLIC_DATA_API_KEY`에 넣는다. 이 파일은 Git에서 제외되며 앱의
`Config/Secrets.xcconfig`나 `Info.plist`에는 넣지 않는다. Worker는 `getRestDeInfo` 결과를
`YYYY-MM` 단위로 메모리 캐시해 `weekday`/`saturday`/`sunday_holiday`를 반환한다. 포털의
`Encoding` 키는 Worker에서 한 번만 URL 인코딩되도록 정규화한다.

2026-08-21 기존 Free 플랜 Worker에 키를 반영한 뒤 `scripts/check_service_day_api.rb`로 HTTPS,
무인증 401, 평일과 법정공휴일을 검증했다. 2026-08-21은 `weekday`, 2026-08-15는
`sunday_holiday / 광복절`로 확인됐다. 점검기는 비밀값과 원본 응답 전문을 출력하지 않는다.
키가 없거나 원본 호출이 실패하면 `/v1/service-day`는 원본 URL이나 키를 노출하지 않는 오류를
반환하고 앱은 달력 요일 기준으로 폴백하면서 경고를 표시한다.

## 3. 역 좌표 원본

역 좌표 데이터는 정적 파일이므로 앱 실행 중 API 키가 필요하지 않다.

- 전국도시철도역사정보표준데이터: https://www.data.go.kr/data/15013205/standard.do
- 국가철도공단 도시광역철도 역사정보: https://www.data.go.kr/data/15093755/fileData.do

원본 XLSX와 서울시 실시간 지원 역 목록은 `DataSources/raw/`에 버전 고정해 두었다.
`scripts/build_station_bundle.py`가 지원 구간만 선별하고 역명·환승역·역 ID를 정규화해
`GoHome/Resources/stations.seed.json`을 생성한다. 현재 번들은 563개 물리 역과 696개
노선별 역 ID를 포함한다. `scripts/validate_station_bundle.py`로 결과를 독립 검증할 수 있다.

## 4. 키 확인 순서

1. `Config/Secrets.xcconfig`에 키 입력
2. Xcode를 완전히 종료했다가 프로젝트 다시 열기
3. GoHome 타깃의 Debug 빌드 실행
4. 앱에서 위치 권한 허용
5. 역 선택 후 첫 자동 조회 또는 `도착정보 불러오기` 실행

## 5. 앱의 오류 안내

앱은 다음 상태를 서로 다른 메시지로 표시한다.

- `TRANSIT_PROXY_BASE_URL` 또는 `TRANSIT_PROXY_CLIENT_TOKEN` 누락: 앱 인증 설정 안내
- Worker의 HTTP 401/403: 호출 토큰 불일치 안내
- HTTP 429 또는 서울시 응답의 한도 초과 메시지: 호출 한도 안내
- Worker 5xx·연결 실패·시간 초과: Worker 연결 장애 안내
- Worker가 분류한 원본 연결 실패: 서울시 실시간 API 연결 장애 안내
- 서울시 `errorMessage`/`RESULT`의 비정상 코드: 코드와 원본 메시지를 포함한 서울시 API 오류
- 공휴일 API 설정·연결 실패: 요일 기준 막차표로 폴백하고 공휴일 미검증 상태 안내
- 막차표 갱신 실패: 같은 역의 마지막 정상 예정 시간표 유지

오류가 발생해도 같은 역의 마지막 정상 도착 목록과 노선별 마지막 정상 위치는 유지한다. 서울시
`recptnDt`가 현재보다 2분 이상 오래됐거나 수신시각이 없으면 오래된 데이터 경고를 표시한다.

인증키를 GitHub Issue, 커밋, 스크린샷 또는 채팅에 붙여 넣지 않는다.
