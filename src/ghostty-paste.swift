import Cocoa

// Ghostty에서 Cmd+V를 눌렀을 때 클립보드에 이미지가 있으면 PNG로 저장한 뒤
// 그 경로를 타이핑한다(Claude Code 등이 경로를 이미지 첨부로 인식).
// 텍스트면 손대지 않고 평소처럼 그대로 붙여넣는다.
//
// 설정은 환경변수로 덮어쓸 수 있다(LaunchAgent의 EnvironmentVariables 참고):
//   GHOSTTY_PASTE_BUNDLE_ID  대상 앱 번들 ID (기본: com.mitchellh.ghostty)
//   GHOSTTY_PASTE_CACHE_DIR  이미지 저장 폴더 (기본: ~/.cache/ghostty-paste)

let env = ProcessInfo.processInfo.environment

let kTargetBundleID = env["GHOSTTY_PASTE_BUNDLE_ID"] ?? "com.mitchellh.ghostty"
let kCacheDir = ((env["GHOSTTY_PASTE_CACHE_DIR"] ?? "~/.cache/ghostty-paste") as NSString)
    .expandingTildeInPath
let kVKeyCode: Int64 = 9  // kVK_ANSI_V

nonisolated(unsafe) var eventTap: CFMachPort?

func ensureCacheDir() {
    try? FileManager.default.createDirectory(
        atPath: kCacheDir, withIntermediateDirectories: true)
}

// 클립보드에 이미지가 있으면 PNG로 저장하고 경로를 돌려준다. 없으면 nil.
func saveClipboardImageToFile() -> String? {
    let pb = NSPasteboard.general
    var png: Data?
    if let d = pb.data(forType: .png) {
        png = d
    } else if let tiff = pb.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: tiff) {
        png = rep.representation(using: .png, properties: [:])
    }
    guard let data = png else { return nil }

    let fmt = DateFormatter()
    fmt.dateFormat = "yyyyMMdd-HHmmss-SSS"
    let path = "\(kCacheDir)/img-\(fmt.string(from: Date())).png"
    do {
        try data.write(to: URL(fileURLWithPath: path))
        return path
    } catch {
        return nil
    }
}

// 문자열을 키 입력으로 삽입한다(유니코드 직접 주입이라 키맵과 무관).
func typeString(_ s: String) {
    let src = CGEventSource(stateID: .combinedSessionState)
    var chars = Array(s.utf16)
    if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
        down.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
        down.post(tap: .cghidEventTap)
    }
    if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
        up.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
        up.post(tap: .cghidEventTap)
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

    // Cmd+V가 아니면 그대로 통과.
    guard keycode == kVKeyCode, cmdOnly else {
        return Unmanaged.passUnretained(event)
    }
    // 최상위 앱이 대상(Ghostty)이 아니면 그대로 통과.
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == kTargetBundleID else {
        return Unmanaged.passUnretained(event)
    }
    // 클립보드가 이미지가 아니면(텍스트 등) 원래 Cmd+V를 그대로 통과.
    guard let path = saveClipboardImageToFile() else {
        return Unmanaged.passUnretained(event)
    }
    // 이미지면: 원래 Cmd+V는 삼키고 경로를 대신 타이핑(뒤에 공백 하나로 토큰 확정).
    DispatchQueue.main.async { typeString(path + " ") }
    return nil
}

ensureCacheDir()

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
    callback: callback,
    userInfo: nil
) else {
    FileHandle.standardError.write(Data(
        "ghostty-paste: 이벤트 탭 생성 실패. 손쉬운 사용(Accessibility) 권한을 켜세요.\n".utf8))
    exit(1)
}
eventTap = tap

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
NSLog("ghostty-paste: running — target=\(kTargetBundleID) cache=\(kCacheDir)")
CFRunLoopRun()
