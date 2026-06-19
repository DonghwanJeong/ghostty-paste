# ghostty-paste

Ghostty에서 **`Cmd+V` 한 키로** 클립보드 이미지를 붙여넣게 해주는 작은 macOS 데몬.
Claude Code 같은 터미널 앱에 이미지를 붙일 때 `Ctrl+V`를 따로 누를 필요가 없어진다.
텍스트 붙여넣기는 손대지 않으므로 평소처럼 동작한다.

## 왜 필요한가

터미널 에뮬레이터(Ghostty 포함)는 클립보드의 **이미지**를 붙여넣지 못한다. `Cmd+V`는
표준 텍스트 붙여넣기라 텍스트만 전달된다. 그래서 Claude Code는 비표준 `Ctrl+V` 핸들러로
클립보드 이미지를 직접 읽는데, 결국 키가 텍스트(`Cmd+V`)/이미지(`Ctrl+V`)로 갈라진다.

`ghostty-paste`는 전역 키 이벤트 탭으로 `Cmd+V`를 가로채서:

- **Ghostty가 최상위 앱이고** 클립보드에 **이미지**가 있으면 → PNG로 저장한 뒤 원래
  `Cmd+V`는 삼키고 그 파일 경로를 타이핑한다 (앱이 경로를 이미지 첨부로 인식).
- 그 외(텍스트이거나 다른 앱) → 전혀 개입하지 않고 그대로 통과시킨다.

## 요구사항

- macOS
- Xcode Command Line Tools — `xcode-select --install` (`swift`/`swiftc` 제공)
- Ghostty

## 설치

```bash
git clone <이-저장소-URL> ghostty-paste
cd ghostty-paste
make install
```

`make install`은 다음을 한다:

1. release 바이너리 빌드 (`swiftc -O`)
2. `~/.local/bin/ghostty-paste`로 복사 (`PREFIX`로 변경 가능)
3. 현재 경로가 채워진 LaunchAgent를 `~/Library/LaunchAgents/`에 생성 후 로드 (로그인 시 자동 실행)

### 마지막 한 단계 — 손쉬운 사용 권한 (필수)

전역 키 후킹이라 **손쉬운 사용(Accessibility) 권한**이 반드시 필요하다.

1. **시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용**
2. `~/.local/bin/ghostty-paste`를 목록에 추가하고 토글을 켠다
3. 권한을 켠 뒤 데몬 재시작:

```bash
make reload
```

이제 이미지를 복사하고 Ghostty에서 `Cmd+V`를 누르면 경로가 입력된다.

## 제거

```bash
make uninstall
```

(손쉬운 사용 권한 목록의 항목은 시스템 설정에서 직접 지운다.)

## 설정

환경변수로 동작을 바꿀 수 있다. LaunchAgent로 적용하려면 plist의 `EnvironmentVariables`
(`launchagent/...plist.template`의 주석 참고)에 넣는다.

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `GHOSTTY_PASTE_BUNDLE_ID` | `com.mitchellh.ghostty` | 개입할 앱의 번들 ID |
| `GHOSTTY_PASTE_CACHE_DIR` | `~/.cache/ghostty-paste` | 저장된 PNG 위치 |

번들 ID 확인: `osascript -e 'id of app "Ghostty"'`

## 다른 PC에 적용

각 PC에서 `git clone` 후 `make install`. 바이너리는 그 PC에서 컴파일되므로 아키텍처
(Apple Silicon/Intel)를 신경 쓸 필요가 없고, 경로는 `$HOME` 기준으로 자동 생성된다.
단 **손쉬운 사용 권한은 PC마다 수동으로** 켜야 한다(보안상 자동화 불가).

## 트러블슈팅

### `error: redefinition of module 'SwiftBridging'`

Command Line Tools를 업데이트할 때 옛 `module.modulemap`이 남아 최신
`bridging.modulemap`과 같은 모듈을 중복 정의해서 생기는 **툴체인 버그**다(이 저장소와 무관,
머신의 모든 Swift 빌드가 막힌다). 옛 파일을 비활성화하면 해결된다:

```bash
sudo mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap \
        /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap.disabled
```

되돌리려면 `.disabled`를 떼서 원래 이름으로 `mv`. 또는 CLT를 깨끗이 재설치:
`sudo rm -rf /Library/Developer/CommandLineTools && sudo xcode-select --install`

### `Cmd+V`를 눌러도 이미지가 안 붙는다

- 손쉬운 사용 권한이 켜져 있는지 확인 → 켠 뒤 `make reload`
- 데몬이 떠 있는지: `launchctl print gui/$(id -u)/com.github.ghostty-paste`
- 로그 확인: `cat /tmp/ghostty-paste.log`
- 대상 번들 ID가 맞는지: `osascript -e 'id of app "Ghostty"'`

## 동작 방식 한눈에

```
Cmd+V (Ghostty 최상위)
   │
   ├─ 클립보드가 이미지?  ── 예 ─▶ PNG 저장 → 원래 Cmd+V 삼킴 → 경로 타이핑
   │
   └─ 아니오(텍스트/다른 앱) ─▶ 그대로 통과 (평범한 Cmd+V)
```
