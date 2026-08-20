# GoHome

현재 위치에서 가까운 서울 지하철역과 실시간 열차 도착 정보, 막차 정보를 빠르게 확인하는 iOS 앱입니다.

현재 단계의 목표는 비용 없이 개인 iPhone에서 반복적으로 사용하며 제품 방향을 검증하는 것입니다. 정식 배포, Android, 전국 도시철도 지원은 이후 단계로 미룹니다.

## 현재 포함된 것

- SwiftUI 기반 iOS 17+ 앱 골격
- 앱 사용 중 위치 권한 요청
- 서울 실시간 API 지원 범위 563개 역을 이용한 가까운 역 상위 3개 계산
- 위치 거부·대략적 위치·지원 범위 밖 상태 안내와 역명·노선명 수동 검색
- Cloudflare Worker HTTPS 중계를 사용하는 실시간 도착정보 API 클라이언트
- 앱 전면에서만 동작하는 40초 간격 자동 갱신과 수동 요청 중복 방지
- 설정·토큰·호출 한도·Worker·서울시 API 오류별 안내
- 갱신 실패 시 마지막 정상 데이터 유지와 2분 이상 지난 데이터 경고
- 선택 역 각 호선의 실시간 열차 현재 역·진입/도착/출발 상태와 남은 역 수
- 분기·순환·종착역을 고려한 명시적 노선 경로 및 일반/급행/특급·막차 표시
- 열차 위치 오류 시 노선별 마지막 정상 데이터, 기준시각, 오래된 상태 유지
- 노선 스트립을 우선하는 Home 대시보드와 가까운 열차 4대 요약·전체 펼치기
- 노선 고유색, 큰 도착 예정시간, LIVE/지연 상태를 결합한 D 하이브리드 디자인
- 1~9호선의 방향·종착역·급행별 막차 예정 시각과 현재 기준 남은 시간
- 평일·토요일·일요일/공휴일 선택, 오전 4시 영업일 경계, 00·24·25시 시간 처리
- 공휴일 확인 실패 시 요일 기준 폴백과 막차 갱신 실패 시 마지막 정상 시간표 유지
- API 키를 Git에서 제외하는 `xcconfig` 구성
- 역 데이터 생성·검증 스크립트, iOS XCTest 40개, Worker 회귀 테스트 17개

`stations.seed.json`은 파일명이 초기 골격의 흔적을 유지하고 있지만, 현재는 19개 지원 노선의
563개 물리 역과 696개 노선별 역 ID를 포함한 전체 번들입니다. 국가철도공단 좌표와 서울시
실시간 도착 지원 역 목록을 결합해 생성하며, 재생성 방법은
[`DataSources/README.md`](DataSources/README.md)에 정리되어 있습니다.

`line_routes.json`은 역 ID 숫자를 정렬해 순서를 추정하지 않습니다. 같은 서울시 지원역 원본의
행 순서를 기반으로 지선·분기·2호선 순환·6호선 응암루프·GTX-A 미연결 구간을 명시적으로
분리한 19개 노선 28개 경로이며, 생성·누락·인접성 검증을 자동화했습니다.

## 요구사항

- macOS
- 전체 Xcode 설치본
- iOS 17 이상 iPhone 또는 Simulator
- 서울 열린데이터광장 실시간 지하철 API 인증키

전체 Xcode가 설치되어 있으며 Simulator 빌드와 `GoHomeTests`를 검증했습니다. 다른 Mac에서
Command Line Tools가 선택되어 있다면 다음 명령으로 개발자 디렉터리를 전환합니다.

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 시작하기

1. 로컬 비밀 설정 파일을 만듭니다.

   ```sh
   cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
   ```

2. `Config/Secrets.xcconfig`의 값을 채웁니다. 서울시 키는 로컬 API 점검용이고, 앱 번들에는
   배포된 Worker 주소와 개인용 호출 토큰만 들어갑니다. 공공데이터포털 키는 이 파일이 아니라
   Git에서 제외된 `worker/.env.production`에만 둡니다.

   ```xcconfig
   SEOUL_API_KEY = 발급받은_인증키
   TRANSIT_PROXY_BASE_URL = https:/$()/gohome-transit-proxy.<계정>.workers.dev
   TRANSIT_PROXY_CLIENT_TOKEN = 생성한_개인용_토큰
   ```

   `.xcconfig`에서는 `//`가 주석으로 해석되므로 Worker URL의 슬래시는 반드시
   `https:/$()/` 형식으로 작성합니다. 빌드된 앱에는 `https://`로 전달됩니다.

3. `GoHome.xcodeproj`를 Xcode로 엽니다.

4. `GoHome` 타깃의 Signing & Capabilities에서 본인의 Personal Team을 선택합니다. 기본 번들 ID는 `com.prestigekim.GoHome`이며, 등록 충돌이 나면 본인만의 값으로 변경합니다.

5. 연결된 iPhone을 실행 대상으로 선택해 Run합니다.

API 설정이 비어 있어도 위치와 가까운 역 계산 화면까지는 실행됩니다. 실시간 정보 요청만 설정
안내 오류를 표시합니다. 역을 선택하면 앱이 활성 상태인 동안 도착정보와 선택 역의 각 호선 열차
위치를 함께 조회한 뒤 40초 간격으로 자동 갱신하고, 백그라운드로 전환하면 해당 작업을
취소합니다. 목록을 아래로 당기거나 실시간 정보 버튼을 눌러 수동 갱신할 수도 있으며 진행 중인
요청과 중복 호출하지 않습니다.

새 요청이 실패해도 같은 역의 마지막 정상 목록은 지우지 않습니다. 이때 오류 원인과 마지막 정상
데이터를 표시 중이라는 안내가 함께 나오며, 서울시 수신시각이 2분 이상 지난 항목은 오래된
데이터로 표시합니다.

열차 위치 영역은 서울시의 현재 역 ID와 진입·도착·출발 상태를 이용해 선택 역까지 남은 역 수를
계산합니다. 실제 선로 위 GPS 좌표가 아니며, 이 제한을 화면 하단에 항상 표시합니다. 분기나
종착역 때문에 선택 역을 지나지 않는 열차는 접근 열차 목록에서 제외합니다. 서울시가 같은
열차의 여러 수신시각을 반환하면 최신 위치만 유지합니다. 노선·방향별 가까운 열차를 최대 3대씩
선별한 뒤 Home 첫 화면에는 전체 접근 열차 중 가까운 4대를 요약하고, 나머지는 펼치기 버튼으로
확인할 수 있습니다.

Home 디자인은 노선 스트립 중심의 정보 계층, 큰 도착 예정시간, LIVE/지연 상태를 결합한
D 하이브리드안입니다. 선택 역은 상단 버튼과 별도 역 선택 시트에서 바꾸며, 별도 탭이나 지도
없이 한 화면에서 열차 위치와 도착정보를 이어서 읽도록 구성했습니다.

막차 영역은 서울교통공사의 예정 운행시각표입니다. 실시간 열차 위치의 `막차` 표식과 구분해
표시하며 1~9호선에서 방향·종착역·급행별 가장 늦은 출발을 보여줍니다. `오늘`은 한국천문연구원
공휴일 정보로 평일·토요일·일요일/공휴일을 판정하고, 공휴일 API 설정이나 연결에 실패하면 화면에
경고한 뒤 달력 요일 기준으로 동작합니다. 현재 서울교통공사 원본은 토요일과 일요일/공휴일에 같은
`주말` 시간표를 제공한다는 한계도 화면에 안내합니다.

## 테스트

Worker 테스트는 전체 Xcode 없이 실행할 수 있습니다.

```sh
cd worker
npm test
```

iOS 단위 테스트는 `GoHomeTests` 타깃에 거리·번들 검증과 도착정보 오류 분류, 중복 요청 방지,
자동 갱신 취소, 위치 DTO·상태 코드, 분기·순환선 남은 역 계산, 위치 마지막 정상 데이터 유지,
동일 열차 최신 스냅샷 선택, 위치 표시 제한, 일시적 Core Location 오류 처리, 역 검색·지원 범위
판정, 영업일 시계, 00·24시 파싱, 막차 DTO와 마지막 정상 시간표 유지 검증을 포함합니다.
Xcode 26.6의 iPhone 17 Pro Simulator에서 전체 40개가 통과했습니다.
Phase 0–2의 Simulator·실기기·전광판 최종
검증 절차는 [`Docs/PHASE_0_2_ACCEPTANCE.md`](Docs/PHASE_0_2_ACCEPTANCE.md)를 따릅니다.
Phase 3의 미실행 iOS 검증은 [`Docs/PHASE_3_ACCEPTANCE.md`](Docs/PHASE_3_ACCEPTANCE.md)에
분리되어 있고 Phase 4 막차 검증은 [`Docs/PHASE_4_ACCEPTANCE.md`](Docs/PHASE_4_ACCEPTANCE.md)에
정리되어 있습니다. Xcode 26.6의 iPhone 17 Pro Simulator에서는 전면 약 40초 자동 갱신,
백그라운드 중지, 전면 복귀 직후 재개까지 확인했습니다.

## 무료 개인 기기 테스트의 제한

유료 Apple Developer Program 없이 Personal Team으로 본인 기기에 설치할 수 있습니다. 다만 무료 프로비저닝은 7일 후 만료되므로 Xcode에서 다시 빌드·설치해야 하며, 정식 TestFlight나 원격 배포에는 사용할 수 없습니다. 지인 테스트도 각 기기를 Xcode에 연결하는 개발용 설치 절차가 필요합니다.

## 원격 저장소 연결

이 프로젝트의 `origin`은 `https://github.com/prestige-kim/goHome.git`에 연결되어 있습니다.

## 문서

- [개발 계획](PLAN.md)
- [API 키 발급 및 주소](Docs/API_SETUP.md)
- [Cloudflare Worker 설정](Docs/WORKER_SETUP.md)
- [Phase 0–2 최종 승인 검증표](Docs/PHASE_0_2_ACCEPTANCE.md)
- [Phase 3 최종 승인 검증표](Docs/PHASE_3_ACCEPTANCE.md)
- [Phase 4 최종 승인 검증표](Docs/PHASE_4_ACCEPTANCE.md)
