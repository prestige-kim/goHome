# GoHome

현재 위치에서 가까운 서울 지하철역과 실시간 열차 도착 정보, 막차 정보를 빠르게 확인하는 iOS 앱입니다.

현재 단계의 목표는 비용 없이 개인 iPhone에서 반복적으로 사용하며 제품 방향을 검증하는 것입니다. 정식 배포, Android, 전국 도시철도 지원은 이후 단계로 미룹니다.

## 현재 포함된 것

- SwiftUI 기반 iOS 17+ 앱 골격
- 앱 사용 중 위치 권한 요청
- 서울 실시간 API 지원 범위 563개 역을 이용한 가까운 역 상위 3개 계산
- Cloudflare Worker HTTPS 중계를 사용하는 실시간 도착정보 API 클라이언트
- API 키를 Git에서 제외하는 `xcconfig` 구성
- 역 데이터 생성·검증 스크립트와 핵심 거리 계산 단위 테스트

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

API 키가 비어 있어도 위치와 가까운 역 계산 화면까지는 실행됩니다. 실시간 도착정보 요청만 설정 안내 오류를 표시합니다.

## 무료 개인 기기 테스트의 제한

유료 Apple Developer Program 없이 Personal Team으로 본인 기기에 설치할 수 있습니다. 다만 무료 프로비저닝은 7일 후 만료되므로 Xcode에서 다시 빌드·설치해야 하며, 정식 TestFlight나 원격 배포에는 사용할 수 없습니다. 지인 테스트도 각 기기를 Xcode에 연결하는 개발용 설치 절차가 필요합니다.

## 원격 저장소 연결

이 프로젝트의 `origin`은 `https://github.com/prestige-kim/goHome.git`에 연결되어 있습니다.

## 문서

- [개발 계획](PLAN.md)
- [API 키 발급 및 주소](Docs/API_SETUP.md)
- [Cloudflare Worker 설정](Docs/WORKER_SETUP.md)
