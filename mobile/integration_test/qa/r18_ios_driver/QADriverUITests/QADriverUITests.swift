// QA round 18: an XCUITest "driver" for the iOS simulator, the iOS twin of integration_test/qa/adb_ui.py.
// Standalone project (no change to ios/Runner). It drives the installed app `app.zaypos` from outside, so it can
// also tap what Flutter's integration_test cannot: the system alert "… Wants to Use accounts.google.com to Sign In"
// and Google's web page (account chooser) inside the authentication sheet.
//
// The host writes one command per file into $QA_IOS_DIR/cmd (created by r18_ios_ui.sh); the test answers in
// $QA_IOS_DIR/out and deletes the command. Commands:
//   dump                    visible labels of the app + Google sheet + system alerts (one per line)
//   tap <substr> [index]    tap the index-th element whose label/value contains substr (app, then sheet, then alerts)
//   tapxy <x> <y>           tap a point of the screen (points)
//   type <text>             type into the focused field
//   launch | activate | terminate
//   quit                    end the test
//   swipeup | swipedown     (round 19) scroll the app one screen
//   auto off | auto on      (round 19) stop / resume auto-tapping "Continue", to read the alert first
// Every "Continue" button of a system alert is tapped automatically (the Google sign-in prompt).
import XCTest

final class QADriverUITests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "app.zaypos")
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let webSheet = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
    var autoOn = true

    func testServe() throws {
        let dir = ProcessInfo.processInfo.environment["QA_IOS_DIR"] ?? "/tmp/zaypos_qa_ios"
        let fm = FileManager.default
        let cmdPath = dir + "/cmd", outPath = dir + "/out"
        try? fm.removeItem(atPath: outPath)
        write(outPath, "ready")
        let end = Date().addingTimeInterval(60 * 60)
        while Date() < end {
            autoContinue()
            if let data = fm.contents(atPath: cmdPath), let cmd = String(data: data, encoding: .utf8) {
                try? fm.removeItem(atPath: cmdPath)
                let line = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
                if line == "quit" { write(outPath, "bye"); return }
                write(outPath, run(line))
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    private func write(_ path: String, _ s: String) {
        try? (s + "\n").write(toFile: path + ".tmp", atomically: true, encoding: .utf8)
        _ = try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.moveItem(atPath: path + ".tmp", toPath: path)
    }

    /// The system sign-in prompt is a SpringBoard alert; accept it whenever it shows.
    private func autoContinue() {
        guard autoOn else { return }
        let b = springboard.alerts.buttons["Continue"]
        if b.exists { b.tap() }
    }

    private func elements(_ a: XCUIApplication) -> [XCUIElement] {
        guard a.state == .runningForeground || a.state == .runningBackground else { return [] }
        return a.descendants(matching: .any).allElementsBoundByIndex
    }

    private func visible(_ e: XCUIElement) -> Bool {
        e.exists && e.frame.width > 0 && e.frame.height > 0
    }

    private func text(_ e: XCUIElement) -> String {
        let v = (e.value as? String) ?? ""
        return v.isEmpty ? e.label : (e.label.isEmpty ? v : e.label + " | " + v)
    }

    private func run(_ line: String) -> String {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let op = parts.first ?? ""
        let arg = parts.count > 1 ? parts[1] : ""
        switch op {
        case "auto": autoOn = arg != "off"; return "ok auto \(autoOn ? "on" : "off")"
        case "swipeup": app.swipeUp(); return "ok swipeup"
        case "swipedown": app.swipeDown(); return "ok swipedown"
        case "launch": app.launch(); return "ok launch"
        case "activate": app.activate(); return "ok activate"
        case "terminate": app.terminate(); return "ok terminate"
        case "dump":
            var out: [String] = []
            for (name, a) in [("app", app), ("sheet", webSheet), ("springboard", springboard)] {
                for e in elements(a) where visible(e) {
                    let t = text(e)
                    if t.isEmpty { continue }
                    if name == "springboard" && e.elementType != .button && e.elementType != .staticText { continue }
                    let f = e.frame
                    out.append("\(name) | \(e.elementType.rawValue) | \(t.replacingOccurrences(of: "\n", with: "\\n")) | "
                               + "[\(Int(f.minX)),\(Int(f.minY)),\(Int(f.maxX)),\(Int(f.maxY))]")
                }
                if name == "springboard" { out = out.filter { !$0.hasPrefix("springboard") || $0.contains("Continue") || $0.contains("Cancel") || $0.contains("Wants") } }
            }
            return out.joined(separator: "\n")
        case "tap":
            var sub = arg, idx = 0
            if let sp = arg.lastIndex(of: " "), let n = Int(arg[arg.index(after: sp)...]) {
                sub = String(arg[..<sp]); idx = n
            }
            for a in [app, webSheet, springboard] {
                let hits = elements(a).filter { visible($0) && text($0).contains(sub) }
                if hits.count > idx {
                    let e = hits[idx]
                    let f = e.frame
                    e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    return "tapped \(sub) [\(Int(f.midX)),\(Int(f.midY))]"
                }
            }
            return "NOT FOUND: \(sub)"
        case "tapxy":
            let xy = arg.split(separator: " ").compactMap { Double($0) }
            guard xy.count == 2 else { return "bad tapxy" }
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: xy[0], dy: xy[1])).tap()
            return "tapped xy \(xy[0]) \(xy[1])"
        case "type":
            app.typeText(arg)
            return "typed \(arg.count) chars"
        default:
            return "unknown: \(line)"
        }
    }
}
