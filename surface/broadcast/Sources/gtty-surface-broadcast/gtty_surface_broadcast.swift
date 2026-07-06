//
//  SPDX-License-Identifier: MIT
//  Copyright (c) 2026 Paal Øye-Strømme
//
//  gtty_surface_broadcast.swift
//  libgtty
//

import Darwin
import Foundation

// MARK: - Errors

enum BroadcastError: Error, CustomStringConvertible {
    case noBundleId
    case scriptCreationFailed
    case scriptCompilationFailed(String)
    case scriptExecutionFailed(String)
    case unexpectedResponse(String, String)
    case offsetOutOfRange(Int, Int, Int)
    case invalidOffset(String)

    var description: String {
        switch self {
        case .noBundleId:
            return "Not running inside Ghostty (__CFBundleIdentifier not in environment)"
        case .scriptCreationFailed:
            return "Failed to create NSAppleScript"
        case .scriptCompilationFailed(let e):
            return "AppleScript compilation failed: \(e)"
        case .scriptExecutionFailed(let e):
            return "AppleScript execution failed: \(e)"
        case .unexpectedResponse(let h, let v):
            return "Unexpected response from '\(h)': \(v)"
        case .offsetOutOfRange(let o, let me, let count):
            return "Pane offset \(o) out of range (have \(count) panes, I am at \(me))"
        case .invalidOffset(let s):
            return "Invalid offset '\(s)': use e.g. +1, -1, or -2..+1"
        }
    }
}

// MARK: - Key Tables

// Mirrors CHAR_TO_KEY in lib.nu — maps printable chars to (ghostty_key_name, needs_shift)
// swift-format-ignore
private let charToGhostty: [Character: (name: String, shift: Bool)] = [
    " ": ("space",        false),
    "`": ("backquote",    false), "~":  ("backquote",    true),
    "1": ("digit1",       false), "!":  ("digit1",       true),
    "2": ("digit2",       false), "@":  ("digit2",       true),
    "3": ("digit3",       false), "#":  ("digit3",       true),
    "4": ("digit4",       false), "$":  ("digit4",       true),
    "5": ("digit5",       false), "%":  ("digit5",       true),
    "6": ("digit6",       false), "^":  ("digit6",       true),
    "7": ("digit7",       false), "&":  ("digit7",       true),
    "8": ("digit8",       false), "*":  ("digit8",       true),
    "9": ("digit9",       false), "(":  ("digit9",       true),
    "0": ("digit0",       false), ")":  ("digit0",       true),
    "-": ("minus",        false), "_":  ("minus",        true),
    "=": ("equal",        false), "+":  ("equal",        true),
    "[": ("bracketLeft",  false), "{":  ("bracketLeft",  true),
    "]": ("bracketRight", false), "}":  ("bracketRight", true),
    "\\": ("backslash",   false), "|":  ("backslash",    true),
    ";": ("semicolon",    false), ":":  ("semicolon",    true),
    "'": ("quote",        false), "\"": ("quote",        true),
    ",": ("comma",        false), "<":  ("comma",        true),
    ".": ("period",       false), ">":  ("period",       true),
    "/": ("slash",        false), "?":  ("slash",        true),
]

// MARK: - Target Script

// One compiled NSAppleScript per target pane.
// The bundle ID, terminal index, and tab index are baked in as literals so the
// compiler never sees them as variables — avoiding tokenisation clashes with
// AppleScript keywords (e.g. "bundleId" → "bundle id", "tab tabIdx" → property ref).
// Only the key name, modifiers, and text vary per call and are safe string params.
final class TargetScript: @unchecked Sendable {

    private let script: NSAppleScript

    // Apple Event constants for calling a named handler inside an NSAppleScript
    private static let suite: AEEventClass = 0x6173_6372  // 'ascr'
    private static let subr: AEEventID = 0x7073_6272  // 'psbr'
    private static let hname: AEKeyword = 0x736E_616D  // 'snam'
    private static let dobj: AEKeyword = 0x2D2D_2D2D  // '----'

    init(bundleId: String, termIndex: Int, tabIndex: Int) throws {
        let src = """
            on do_send_key(keyName)
                tell application id "\(bundleId)"
                    send key keyName to terminal \(termIndex) of tab \(tabIndex) of front window
                end tell
            end do_send_key

            on do_send_key_mods(keyName, modsStr)
                tell application id "\(bundleId)"
                    send key keyName modifiers modsStr to terminal \(termIndex) of tab \(tabIndex) of front window
                end tell
            end do_send_key_mods

            on do_input_text(theText)
                tell application id "\(bundleId)"
                    input text theText to terminal \(termIndex) of tab \(tabIndex) of front window
                end tell
            end do_input_text
            """

        guard let s = NSAppleScript(source: src) else {
            throw BroadcastError.scriptCreationFailed
        }
        var errDict: NSDictionary?
        s.compileAndReturnError(&errDict)
        if let err = errDict {
            throw BroadcastError.scriptCompilationFailed(err.description)
        }
        self.script = s
    }

    private func invoke(_ handler: String, _ args: [NSAppleEventDescriptor]) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let tgt = NSAppleEventDescriptor(processIdentifier: pid)
        let ev = NSAppleEventDescriptor(
            eventClass: Self.suite,
            eventID: Self.subr,
            targetDescriptor: tgt,
            returnID: AEReturnID(-1),
            transactionID: AETransactionID(0)
        )
        ev.setParam(.init(string: handler), forKeyword: Self.hname)
        let params = NSAppleEventDescriptor.list()
        for (i, a) in args.enumerated() { params.insert(a, at: i + 1) }
        ev.setParam(params, forKeyword: Self.dobj)
        var errDict: NSDictionary?
        _ = script.executeAppleEvent(ev, error: &errDict)
    }

    func sendKey(_ key: String) { invoke("do_send_key", [.init(string: key)]) }
    func sendKeyMods(_ key: String, _ mods: String) { invoke("do_send_key_mods", [.init(string: key), .init(string: mods)]) }
    func sendText(_ text: String) { invoke("do_input_text", [.init(string: text)]) }
}

// MARK: - One-off AppleScript helpers (startup queries only)

private func runAS(_ src: String) throws -> NSAppleEventDescriptor {
    guard let script = NSAppleScript(source: src) else {
        throw BroadcastError.scriptCreationFailed
    }
    var errDict: NSDictionary?
    let result = script.executeAndReturnError(&errDict)
    if let err = errDict {
        throw BroadcastError.scriptExecutionFailed(err.description)
    }
    return result
}

private func queryMyIndex(bundleId: String) throws -> (index: Int, count: Int) {
    let result = try runAS(
        """
        tell application id "\(bundleId)"
            set n to count terminals of selected tab of front window
            set fid to id of focused terminal of selected tab of front window
            repeat with i from 1 to n
                if id of terminal i of selected tab of front window is fid then
                    return (i as text) & ":" & (n as text)
                end if
            end repeat
        end tell
        """)
    let parts = (result.stringValue ?? "").split(separator: ":").map(String.init)
    guard parts.count == 2, let idx = Int(parts[0]), let cnt = Int(parts[1]) else {
        throw BroadcastError.unexpectedResponse("myIndex", result.stringValue ?? "nil")
    }
    return (idx, cnt)
}

private func queryTabIndex(bundleId: String) throws -> Int {
    let result = try runAS(
        """
        tell application id "\(bundleId)"
            return index of selected tab of front window as text
        end tell
        """)
    guard let s = result.stringValue, let n = Int(s) else {
        throw BroadcastError.unexpectedResponse("tabIndex", result.stringValue ?? "nil")
    }
    return n
}

private func focusSurface(bundleId: String, surfaceIndex: Int) {
    _ = try? runAS(
        """
        tell application id "\(bundleId)"
            focus terminal \(surfaceIndex) of selected tab of front window
        end tell
        """)
}

// MARK: - Raw Terminal Input

nonisolated(unsafe) private var savedTermios = termios()

private func enterRawMode() {
    tcgetattr(STDIN_FILENO, &savedTermios)
    var raw = savedTermios
    cfmakeraw(&raw)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
}

private func exitRawMode() {
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &savedTermios)
}

private enum KeyEvent {
    case exitSignal
    case escape
    case special(String)
    case char(String, ctrl: Bool, ascii: Bool)
}

private func readKey() -> KeyEvent? {
    var buf = [UInt8](repeating: 0, count: 32)
    let n = Darwin.read(STDIN_FILENO, &buf, 32)
    guard n > 0 else { return nil }

    let b0 = buf[0]

    if n == 1 && (b0 == 3 || b0 == 4) { return .exitSignal }

    if b0 == 0x1B {
        if n == 1 { return .escape }
        if n >= 3 && buf[1] == 0x5B {
            switch buf[2] {
            case 0x41: return .special("arrowUp")
            case 0x42: return .special("arrowDown")
            case 0x43: return .special("arrowRight")
            case 0x44: return .special("arrowLeft")
            case 0x48: return .special("home")
            case 0x46: return .special("end")
            case 0x5A: return .special("backtab")
            case 0x32 where n >= 4 && buf[3] == 0x7E: return .special("insert")
            case 0x33 where n >= 4 && buf[3] == 0x7E: return .special("delete")
            case 0x35 where n >= 4 && buf[3] == 0x7E: return .special("pageUp")
            case 0x36 where n >= 4 && buf[3] == 0x7E: return .special("pageDown")
            default: break
            }
        }
        if n >= 3 && buf[1] == 0x4F {
            switch buf[2] {
            case 0x50: return .special("f1")
            case 0x51: return .special("f2")
            case 0x52: return .special("f3")
            case 0x53: return .special("f4")
            default: break
            }
        }
        if n >= 5 && buf[1] == 0x5B {
            switch (buf[2], buf[3], buf[4]) {
            case (0x31, 0x35, 0x7E): return .special("f5")
            case (0x31, 0x37, 0x7E): return .special("f6")
            case (0x31, 0x38, 0x7E): return .special("f7")
            case (0x31, 0x39, 0x7E): return .special("f8")
            case (0x32, 0x30, 0x7E): return .special("f9")
            case (0x32, 0x31, 0x7E): return .special("f10")
            case (0x32, 0x33, 0x7E): return .special("f11")
            case (0x32, 0x34, 0x7E): return .special("f12")
            default: break
            }
        }
        return nil
    }

    if n == 1 && b0 == 0x0D { return .special("enter") }
    if n == 1 && (b0 == 0x7F || b0 == 0x08) { return .special("backspace") }
    if n == 1 && b0 == 0x09 { return .special("tab") }

    if n == 1 && b0 >= 0x01 && b0 <= 0x1A {
        return .char(String(UnicodeScalar(b0 + 0x60)), ctrl: true, ascii: true)
    }

    if n == 1 && b0 >= 0x20 && b0 <= 0x7E {
        return .char(String(UnicodeScalar(b0)), ctrl: false, ascii: true)
    }

    if b0 >= 0x80, let s = String(bytes: Array(buf[0..<n]), encoding: .utf8) {
        return .char(s, ctrl: false, ascii: false)
    }

    return nil
}

// MARK: - Key Name Resolution

private func resolveChar(_ s: String, ctrl: Bool) -> (keyName: String, mods: String) {
    let ch = s.first!
    if let mapped = charToGhostty[ch] {
        var parts: [String] = []
        if mapped.shift { parts.append("shift") }
        if ctrl { parts.append("control") }
        return (mapped.name, parts.joined(separator: ","))
    }
    let lower = s.lowercased()
    var parts: [String] = []
    if s != lower { parts.append("shift") }
    if ctrl { parts.append("control") }
    return (lower, parts.joined(separator: ","))
}

// MARK: - Offset Parsing

private func parseOffsets(_ raw: String) throws -> [Int] {
    for sep in ["...", ".."] where raw.contains(sep) {
        let parts = raw.components(separatedBy: sep)
        guard parts.count == 2,
            let lo = Int(parts[0].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "+", with: "")),
            let hi = Int(parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "+", with: ""))
        else { throw BroadcastError.invalidOffset(raw) }
        return Array(lo...hi)
    }
    let trimmed = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "+", with: "")
    guard let n = Int(trimmed) else { throw BroadcastError.invalidOffset(raw) }
    return [n]
}

// MARK: - Entry Point

@main
struct Broadcast {
    static func main() {
        do { try run() } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run() throws {
        let args = CommandLine.arguments.dropFirst()
        guard let offsetArg = args.first else {
            fputs("Usage: gtty-surface-broadcast <offset>\n       offset: +1, -1, or -2..+1\n", stderr)
            exit(1)
        }

        guard let bundleId = ProcessInfo.processInfo.environment["__CFBundleIdentifier"] else {
            throw BroadcastError.noBundleId
        }

        let (myIdx, paneCount) = try queryMyIndex(bundleId: bundleId)
        let tab = try queryTabIndex(bundleId: bundleId)

        let targets: [TargetScript] = try parseOffsets(offsetArg).map { o in
            let idx = myIdx + o
            guard idx >= 1 && idx <= paneCount else {
                throw BroadcastError.offsetOutOfRange(o, myIdx, paneCount)
            }
            return try TargetScript(bundleId: bundleId, termIndex: idx, tabIndex: tab)
        }

        print("Broadcasting to \(targets.count) pane(s). Ctrl+C / Ctrl+D to stop.")
        print("> ", terminator: "")
        fflush(stdout)

        enterRawMode()
        defer { exitRawMode() }

        loop: while true {
            guard let key = readKey() else {
                usleep(1_000)
                continue
            }

            switch key {
            case .exitSignal:
                break loop

            case .escape:
                for t in targets { t.sendKey("escape") }
                focusSurface(bundleId: bundleId, surfaceIndex: myIdx)

            case .special(let name):
                if name == "backtab" {
                    for t in targets { t.sendKeyMods("tab", "shift") }
                } else {
                    for t in targets { t.sendKey(name) }
                }

            case .char(let s, let ctrl, let ascii):
                if ctrl && (s == "c" || s == "d") { break loop }
                if !ascii {
                    for t in targets { t.sendText(s) }
                } else {
                    let (keyName, mods) = resolveChar(s, ctrl: ctrl)
                    if mods.isEmpty {
                        for t in targets { t.sendKey(keyName) }
                    } else {
                        for t in targets { t.sendKeyMods(keyName, mods) }
                    }
                }
            }
        }

        print("\nBroadcast ended.")
    }
}
