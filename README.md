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
- API 키를 Git에서 제외하는 `xcconfig` 구성
- 역 데이터 생성·검증 스크립트, 도착정보 단위 테스트, Worker 회귀 테스트

`stations.seed.json`은 파일명이 초기 골격의 흔적을 유지하고 있지만, 현재는 19개 지원 노선의
563개 물리 역과 696개 노선별 역 ID를 포함한 전체 번들입니다. 국가철도공단 좌표와 서울시
실시간 도착 지원 역 목록을 결합해 생성하며, 재생성 방법은
[`DataSources/README.md`](DataSources/README.md)에 정리되어 있습니다.

## 요구사항

- macOS
- 전체 Xcode 설치본
- iOS 17 이상 iPhone 또는 Simulator
- 서울 열린데이터광장 실시간 지하철 API 인증키

현재 이 작업 환경은 Command Line Tools만 선택되어 있어 `xcodebuild` 검증이 불가능합니다. Xcode 설치 후 필요하면 다음 명령으로 개발자 디렉터리를 선택합니다.

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 시작하기

1. 로컬 비밀 설정 파일을 만듭니다.

   ```sh
   cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
   ```

2. `Config/Secrets.xcconfig`의 값을 채웁니다. 서울시 키는 로컬 API 점검용이고, 앱에서는
   배포된 Worker 주소와 개인용 호출 토큰을 사용합니다.

   ```xcconfig
   SEOUL_API_KEY = 발급받은_인증키
   TRANSIT_PROXY_BASE_URL = https://gohome-transit-proxy.<계정>.workers.dev
   TRANSIT_PROXY_CLIENT_TOKEN = 생성한_개인용_토큰
   PUBLIC_DATA_API_KEY = 발급받은_인증키
   ```

3. `GoHome.xcodeproj`를 Xcode로 엽니다.

4. `GoHome` 타깃의 Signing & Capabilities에서 본인의 Personal Team을 선택합니다. 기본 번들 ID는 `com.prestigekim.GoHome`이며, 등록 충돌이 나면 본인만의 값으로 변경합니다.

5. 연결된 iPhone을 실행 대상으로 선택해 Run합니다.

API 설정이 비어 있어도 위치와 가까운 역 계산 화면까지는 실행됩니다. 실시간 도착정보 요청만
설정 안내 오류를 표시합니다. 역을 선택하면 앱이 활성 상태인 동안 즉시 조회한 뒤 40초 간격으로
자동 갱신하고, 백그라운드로 전환하면 해당 작업을 취소합니다. 목록을 아래로 당기거나 도착정보
버튼을 눌러 수동 갱신할 수도 있으며 진행 중인 요청과 중복 호출하지 않습니다.

새 요청이 실패해도 같은 역의 마지막 정상 목록은 지우지 않습니다. 이때 오류 원인과 마지막 정상
데이터를 표시 중이라는 안내가 함께 나오며, 서울시 수신시각이 2분 이상 지난 항목은 오래된
데이터로 표시합니다.

## 테스트

Worker 테스트는 전체 Xcode 없이 실행할 수 있습니다.

```sh
cd worker
npm test
```

iOS 단위 테스트는 `GoHomeTests` 타깃에 거리·번들 검증과 도착정보 오류 분류, 중복 요청 방지,
자동 갱신 취소, 마지막 정상 데이터 유지, 역 검색·지원 범위 판정 검증을 포함합니다. 전체 Xcode를
사용할 수 있는 환경에서 해당 타깃을 실행합니다. Phase 0–2의 Simulator·실기기·전광판 최종
검증 절차는 [`Docs/PHASE_0_2_ACCEPTANCE.md`](Docs/PHASE_0_2_ACCEPTANCE.md)를 따릅니다.

## 무료 개인 기기 테스트의 제한

유료 Apple Developer Program 없이 Personal Team으로 본인 기기에 설치할 수 있습니다. 다만 무료 프로비저닝은 7일 후 만료되므로 Xcode에서 다시 빌드·설치해야 하며, 정식 TestFlight나 원격 배포에는 사용할 수 없습니다. 지인 테스트도 각 기기를 Xcode에 연결하는 개발용 설치 절차가 필요합니다.

## 원격 저장소 연결

이 프로젝트의 `origin`은 `https://github.com/prestige-kim/goHome.git`에 연결되어 있습니다.

## 문서

- [개발 계획](PLAN.md)
- [API 키 발급 및 주소](Docs/API_SETUP.md)
- [Cloudflare Worker 설정](Docs/WORKER_SETUP.md)
- [Phase 0–2 최종 승인 검증표](Docs/PHASE_0_2_ACCEPTANCE.md)
