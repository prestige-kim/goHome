# API 키 발급 및 요청 주소

서울시 원본 응답을 로컬에서 점검할 때는 `SEOUL_API_KEY`를 사용한다. 실제 앱은 원본 키를
포함하지 않고 `TRANSIT_PROXY_BASE_URL`과 `TRANSIT_PROXY_CLIENT_TOKEN`으로 Cloudflare
Worker를 호출한다. `PUBLIC_DATA_API_KEY`는 막차의 공휴일 판정 기능을 구현하는 Phase 4에서 사용한다.

키는 `Config/Secrets.xcconfig`에만 저장한다. 이 파일은 `.gitignore`에 포함되어 GitHub에 올라가지 않는다. 값에 따옴표를 붙이지 않는다.

```xcconfig
SEOUL_API_KEY = 발급받은_서울시_키
TRANSIT_PROXY_BASE_URL = https://gohome-transit-proxy.<계정>.workers.dev
TRANSIT_PROXY_CLIENT_TOKEN = 생성한_개인용_토큰
PUBLIC_DATA_API_KEY = 발급받은_공공데이터포털_Encoding_키
```

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
- 추후 사용할 요청 형식:

```text
http://swopenapi.seoul.go.kr/api/subway/{SEOUL_API_KEY}/json/realtimePosition/0/100/{호선명}
```

`{호선명}` 예시는 `1호선`, `2호선`, `수인분당선`이다. 이 API는 실제 GPS 좌표가 아니라 현재 역과 진입·도착·출발 상태를 제공한다.

### 역명과 역코드 매핑

- 데이터셋: https://www.data.go.kr/data/15058954/openapi.do
- Phase 1에서 전체 역 데이터의 서울시 역 ID·외부코드 연결에 사용한다.

### 막차 시간표

- 역코드 기반 막차: https://www.data.go.kr/data/15056854/openapi.do
- 호선별 첫차·막차: https://www.data.go.kr/data/15056647/openapi.do
- Phase 4에서 방향·종착역별 막차를 구현할 때 사용한다.

서울시 실시간 지하철 OpenAPI는 기본적으로 하루 최대 1,000회 요청 제한이 안내되어 있다. 개인 사용 단계에서는 앱이 전면에 있을 때만 요청하고 30~45초 간격을 유지한다.

## 2. 공공데이터포털 키

- 회원가입·로그인: https://www.data.go.kr
- 한국천문연구원 특일 정보 활용신청: https://www.data.go.kr/data/15012690/openapi.do

공공데이터포털에서 활용신청 후 마이페이지에 표시되는 일반 인증키 중 `Encoding` 키를 `PUBLIC_DATA_API_KEY`에 넣는다. 공휴일 정보는 Phase 4에서 평일·토요일·일요일/공휴일 막차표를 선택할 때 사용한다.

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
5. 역 선택 후 `도착정보 불러오기` 실행

인증키를 GitHub Issue, 커밋, 스크린샷 또는 채팅에 붙여 넣지 않는다.
