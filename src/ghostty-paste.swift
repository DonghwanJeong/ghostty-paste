import Cocoa
import ApplicationServices
import Carbon.HIToolbox

// Ghostty에서 Cmd+V를 눌렀을 때, 클립보드에 이미지가 있으면 대신 Ctrl+V를 합성해 보낸다.
// 그러면 Claude Code의 네이티브 클립보드 이미지 붙여넣기가 동작해 진짜 [Image] 첨부가 된다.
// 텍스트(또는 다른 앱)면 손대지 않고 평소처럼 Cmd+V를 그대로 통과시킨다.
//
// 설정(환경변수, LaunchAgent의 EnvironmentVariables 참고):
//   GHOSTTY_PASTE_BUNDLE_ID  대상 앱 번들 ID (기본: com.mitchellh.ghostty)

let env = ProcessInfo.processInfo.environment
let kTargetBundleID = env["GHOSTTY_PASTE_BUNDLE_ID"] ?? "com.mitchellh.ghostty"
let kVKeyCode: Int64 = Int64(kVK_ANSI_V)
let kLockPath = ("~/.cache/ghostty-paste/.lock" as NSString).expandingTildeInPath

nonisolated(unsafe) var eventTap: CFMachPort?

func inputSourceID(_ source: TISInputSource) -> String? {
    guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
        return nil
    }
    return unsafeBitCast(raw, to: CFString.self) as String
}

func preferredASCIIInputSource() -> TISInputSource? {
    guard let list = TISCreateInputSourceList([
        kTISPropertyInputSourceType: kTISTypeKeyboardLayout!,
        kTISPropertyInputSourceIsASCIICapable: true
    ] as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else {
        return nil
    }

    let preferred = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]
    return preferred.compactMap { id in
        list.first { inputSourceID($0) == id }
    }.first ?? list.first
}

func postKey(_ key: CGKeyCode, keyDown: Bool, flags: CGEventFlags) {
    let src = CGEventSource(stateID: .privateState)
    guard let event = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: keyDown) else {
        return
    }
    event.flags = flags
    event.post(tap: .cghidEventTap)
}

func postCtrlVKeyCombo() {
    let control = CGKeyCode(kVK_Control)
    let v = CGKeyCode(kVK_ANSI_V)

    postKey(control, keyDown: true, flags: .maskControl)
    postKey(v, keyDown: true, flags: .maskControl)
    postKey(v, keyDown: false, flags: .maskControl)
    postKey(control, keyDown: false, flags: [])
}

// Cmd+V 대신 Ctrl+V를 합성해 보낸다. 한글 입력 소스에서는 Ctrl+V가 ^V가 아니라
// 다른 문자로 해석될 수 있으므로 잠깐 ASCII 입력 소스로 전환했다가 복구한다.
func sendCtrlV() {
    let original = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let originalID = inputSourceID(original)
    let ascii = preferredASCIIInputSource()
    let asciiID = ascii.flatMap(inputSourceID)
    let needsSwitch = ascii != nil && originalID != asciiID

    if needsSwitch, let ascii {
        TISSelectInputSource(ascii)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + (needsSwitch ? 0.04 : 0)) {
        postCtrlVKeyCombo()
        if needsSwitch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                TISSelectInputSource(original)
            }
        }
    }
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    // macOS가 탭을 비활성화하면(타임아웃 등) 다시 켠다.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }

    let flags = event.flags
    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
    let cmdOnly = flags.contains(.maskCommand)
        && !flags.contains(.maskControl)
        && !flags.contains(.maskAlternate)
        && !flags.contains(.maskShift)

    // Cmd+V가 아니면 그대로 통과(합성한 Ctrl+V도 cmdOnly가 아니라 여기서 통과 → 무한루프 없음).
    guard keycode == kVKeyCode, cmdOnly else {
        return Unmanaged.passUnretained(event)
    }
    // 최상위 앱이 대상(Ghostty)이 아니면 그대로 통과.
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == kTargetBundleID else {
        return Unmanaged.passUnretained(event)
    }
    // 클립보드에 이미지 "타입"만 즉시 확인(디코딩 없음 → 콜백을 블록하지 않음).
    guard NSPasteboard.general.availableType(from: [.png, .tiff]) != nil else {
        return Unmanaged.passUnretained(event)   // 이미지 아님(텍스트 등) → 평범한 Cmd+V 통과
    }
    // 이미지면: 원래 Cmd+V는 삼키고, Cmd를 떼는 짧은 시간 뒤 Ctrl+V를 합성해 보낸다.
    NSLog("ghostty-paste: image Cmd+V intercepted; sending Ctrl+V")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { sendCtrlV() }
    return nil
}

// --- 시작 ---

// 단일 인스턴스 보장: 락을 못 잡으면 다른 인스턴스가 이미 실행 중이므로 즉시 종료한다.
try? FileManager.default.createDirectory(
    atPath: (kLockPath as NSString).deletingLastPathComponent,
    withIntermediateDirectories: true)
let lockFD = open(kLockPath, O_CREAT | O_RDWR, 0o644)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    NSLog("ghostty-paste: 이미 실행 중인 인스턴스가 있어 종료합니다")
    exit(0)
}

// 손쉬운 사용 권한이 없으면 시스템 권한 요청 다이얼로그를 띄운다(목록에 자동 등록됨).
if !AXIsProcessTrusted() {
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    NSLog("ghostty-paste: 손쉬운 사용 권한 대기 중… 토글을 켜면 자동으로 시작됩니다")
}

// 권한이 생길 때까지 이벤트 탭 생성을 재시도한다(권한 켜는 즉시 자동 활성화).
func makeTap() -> CFMachPort? {
    CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
        callback: callback,
        userInfo: nil)
}

var tapOpt = makeTap()
var tapAttempts = 0
while tapOpt == nil {
    Thread.sleep(forTimeInterval: 2)
    tapAttempts += 1
    if tapAttempts % 5 == 0 {
        NSLog("ghostty-paste: 이벤트 탭 생성 대기 중 — 손쉬운 사용 권한을 확인하세요")
    }
    tapOpt = makeTap()
}
let tap = tapOpt!
eventTap = tap

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
NSLog("ghostty-paste: running — target=\(kTargetBundleID), Cmd+V→Ctrl+V on image")
CFRunLoopRun()
