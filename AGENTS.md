# GoHome 작업 규칙

이 파일은 GoHome 저장소에서 작업하는 모든 에이전트와 자동화가 따라야 하는 하네스 규칙이다.
보안 규칙은 구현 속도나 편의보다 우선하며, 불확실하면 비밀값을 읽지 않는 쪽으로 행동한다.

## 1. 비밀값 보안 — 최우선 규칙

### 보호 대상

- `Config/Secrets.xcconfig`
- `worker/.env.production`
- `worker/.dev.vars`
- 모든 `.env`, 인증키, Bearer 토큰, 세션·쿠키, 서명 인증서와 프로비저닝 자료
- 로컬 API 응답, 요청 헤더, 원본 키가 포함될 수 있는 URL과 로그

### 절대 금지

- 보호 대상 파일을 `cat`, `sed`, `head`, `tail`, `grep`, `rg`, `awk`, `perl`, `ruby`,
  `python`, `strings` 등으로 화면이나 도구 결과에 출력하지 않는다.
- 저장소 전체를 대상으로 `grep -R`, `rg --hidden`, `find ... -exec grep`처럼 ignored 파일의
  내용까지 읽을 수 있는 재귀 검색을 실행하지 않는다.
- `env`, `printenv`, `set`, `export -p`, `xcodebuild -showBuildSettings`, `curl -v`,
  `curl --trace*`, Wrangler debug 출력처럼 환경변수·헤더·빌드 설정을 덤프할 수 있는 명령을
  실행하지 않는다.
- 키나 토큰을 명령 인자, URL query, 코드, 테스트 fixture, 문서, 커밋 메시지, Issue, 채팅,
  스크린샷에 직접 넣지 않는다.
- 비밀값의 일부, 길이, 접두·접미사, 해시나 fingerprint도 불필요하게 출력하지 않는다.
- 사용자가 키를 채팅에 붙여 넣도록 요청하지 않는다. 사용자가 ignored 로컬 파일에 직접
  입력하도록 안내한다.

### 안전한 검색과 확인

- 코드 검색은 기본적으로 `git grep`을 사용해 Git 추적 파일만 검색한다.
- 파일 목록은 `git ls-files`를 우선 사용한다. untracked 파일이 필요하면
  `git ls-files --others --exclude-standard`를 사용해 ignored 파일을 제외한다.
- 비밀 설정은 값이 아니라 `설정됨`/`누락`만 확인한다. 가능하면 전용 스크립트가 종료 코드와
  안전한 상태 문구만 반환하도록 한다.
- 보호 파일을 입력으로 사용하는 배포 명령은 해당 도구가 값을 출력하지 않는 검증된 방식만
  허용한다. 현재 허용된 예는 `wrangler deploy --secrets-file worker/.env.production`이다.
- 명령 실행 전에 stdout·stderr에 비밀값이나 Authorization 헤더가 나타날 가능성을 먼저
  검토한다. 가능성이 있으면 명령을 바꾸거나 실행하지 않는다.
- 코드·문서·커밋 전 `ruby scripts/check_secret_hygiene.rb`를 실행한다.

### 노출 사고 대응

- 비밀값이 출력되면 즉시 작업을 멈추고 사용자에게 원인, 노출된 종류, 확인 가능한 범위를
  값 없이 알린다.
- Git 미포함 여부만으로 안전하다고 판단하지 않는다. 도구 출력·채팅·로그에 나타난 키도
  노출된 것으로 취급하고 폐기·재발급을 권고한다.
- 사고 후에는 같은 종류의 명령을 다시 실행하지 않고 하네스 규칙이나 검증 스크립트를
  보강한 뒤 작업을 재개한다.
- 노출된 값을 삭제·회수했다고 보장할 수 없으면 그렇게 말하지 않는다.

## 2. 앱과 Worker 보안 경계

- iOS 앱 번들에는 `TRANSIT_PROXY_BASE_URL`과 개인용 `TRANSIT_PROXY_CLIENT_TOKEN`만 포함한다.
- `SEOUL_API_KEY`와 `PUBLIC_DATA_API_KEY`는 앱의 `Info.plist`, Swift 코드, 빌드 리소스에 절대
  포함하지 않고 Worker Secret에만 둔다.
- Worker는 인증이 필요한 고정 경로와 allowlist만 제공한다. 사용자가 전달한 URL이나 host를
  호출하는 범용 프록시를 만들지 않는다.
- Worker 오류는 원본 URL, 요청 경로, API 키, Bearer 토큰, 원본 응답 전문을 노출하지 않는다.
- 모든 `/v1/*` 보호 경로는 원본별 설정 검사보다 Bearer 인증을 먼저 수행한다.
- 실제 호출 검증은 상태 코드, 원본 정상 코드, 건수와 허용된 비민감 필드만 출력한다.

## 3. 데이터와 제품 불변 조건

- 비용은 0원으로 유지한다. 사용자 승인 없이 유료 서비스·데이터베이스·도메인을 추가하지 않는다.
- 열차 위치는 GPS 좌표가 아니라 서울시가 제공하는 현재 역 기반 상태임을 UI에서 명확히 한다.
- 역 ID 숫자만으로 노선 순서를 추정하지 않는다. 순환선·지선·분기·종착역은 명시적 정적 경로와
  자동 검증으로 처리한다.
- API 원본 DTO 필드명을 SwiftUI View까지 전달하지 않는다. DTO → Domain Model → ViewModel →
  View 경계를 유지한다.
- 앱 전면에서만 실시간 데이터를 갱신하고 백그라운드에서는 중지한다.
- 도착·위치 요청은 기존 중복 방지와 자동 갱신 주기를 공유하고 불필요한 중복 호출을 만들지 않는다.
- 오류 시 마지막 정상 데이터를 유지하고 기준시각·오래된 상태·폴백 여부를 사용자에게 표시한다.
- 예정 시간표와 실시간 열차 상태를 혼동시키지 않는다.
- 위치 권한은 `When In Use`만 사용하며 거부·대략적 위치·지원 범위 밖에서도 수동 역 선택이
  가능해야 한다.

## 4. 코드 변경과 검증

- 이미 완료된 Phase 기능을 다시 만들지 말고 기존 모델·갱신·오류·stale 구조를 재사용한다.
- 변경 전 `git status --short`, 현재 브랜치, `HEAD`와 `origin/main` 상태를 확인한다. 기존 변경은
  사용자 작업일 수 있으므로 출처와 범위를 판단하고 보존한다.
- 로컬 파일 편집은 `apply_patch`를 사용한다. 사용자 변경이나 비밀 파일을 임의로 덮어쓰지 않는다.
- Worker 변경 시 `npm --prefix worker test`와 고정 경로·인증·오류 비노출 회귀 테스트를 실행한다.
- Swift 변경 시 가능한 범위에서 `swiftc -parse`, `plutil -lint`, `git diff --check`를 실행한다.
- 전체 Xcode가 있으면 지정 Simulator에서 `xcodebuild test`를 실행한다. 실행하지 못한 XCTest,
  실기기, 전광판 검증을 완료했다고 표현하지 않고 승인 검증표에 남긴다.
- 정적 번들 변경 시 생성 스크립트와 독립 검증 스크립트를 모두 실행한다.
- 배포 전에는 테스트 통과, 고정 경로 확인, Secret 파일 ignored·untracked 확인을 완료한다.

## 5. Git 기록과 push

- 하나의 Phase가 완료되면 관련 검증을 실행한 뒤, 별도 요청을 기다리지 않고 현재 추적 브랜치에
  커밋하고 push한다.
- Phase 진행 중에도 의미 있는 수정이나 새 내용이 하나의 일관된 변경 단위를 이루면 검증 후
  커밋하고 push해 기록을 남긴다.
- 실패하는 빌드·테스트나 일시적인 작업 중간 상태는 push하지 않는다. 먼저 안전한 상태로
  정리하거나 실패 원인을 기록한다.
- 비밀키, 토큰, 개인 설정, 로컬 API 응답, DerivedData, 임시 생성물은 커밋하거나 push하지 않는다.
- 커밋 전 `git status --short --ignored`로 보호 파일이 ignored인지 확인하되 내용을 출력하지 않는다.
- 커밋 메시지는 변경 목적을 짧고 구체적으로 표현한다.
- 인증·권한·네트워크 문제로 push가 불가능하면 재인증을 임의로 요구하지 말고 원인을 검증한 뒤
  사용자에게 알린다.
- GitHub DNS·timeout·sandbox 오류는 인증 만료 증거가 아니다. 네트워크 가능한 구조화된 인증
  검사에서 401 또는 `Bad credentials`가 확인되기 전에는 재로그인을 요구하지 않는다.

## 6. 배포와 문서

- 기존 Cloudflare Workers Free 플랜과 기본 `workers.dev` 주소를 유지한다.
- Worker 배포는 자동 테스트 통과 후에만 수행하고, 배포 후 `/health`, 무인증 401, 인증된 실제
  고정 경로를 종단간 검증한다.
- 원본 API 키 교체 시 로컬 ignored 파일과 Cloudflare Worker Secret을 함께 갱신하고 기존 키가
  폐기되었는지 사용자에게 확인한다.
- 기능·API·배포 상태가 바뀌면 `PLAN.md`, `README.md`, `Docs/API_SETUP.md`,
  `Docs/WORKER_SETUP.md`와 해당 Phase 승인표를 함께 갱신한다.
- 문서에는 실제 실행한 검증과 남은 검증을 구분하고 날짜·환경·결과를 과장 없이 기록한다.
