#!/usr/bin/env python3
"""QA round 15 (Android): drive the REAL app on the emulator with adb + uiautomator.

Flutter exposes its semantics tree to uiautomator, so labels/texts can be found and tapped.
Used for what an integration test cannot reach: the system back key, the share sheet, the dialer,
permission dialogs, rotation, font/display size, kill + reopen.

  adb_ui.py dump                       list visible nodes (text | content-desc | bounds | clickable)
  adb_ui.py has  <substr>              exit 0 if a node's text/desc contains substr
  adb_ui.py tap  <substr> [index]      tap the centre of the index-th (default 0) matching node
  adb_ui.py wait <substr> [timeout_s]  poll until a node matches; prints the elapsed time
  adb_ui.py shot <name>                screenshot into $EVD_DIR (default docs/qa/evidence/round-15)
  adb_ui.py back                       system BACK key
  adb_ui.py fg                         the resumed activity (who is in front)
Env: ANDROID_SERIAL (default emulator-5554).
"""
import os
import re
import subprocess
import sys
import time

SERIAL = os.environ.get("ANDROID_SERIAL", "emulator-5554")
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
EVD = os.environ.get("EVD_DIR", os.path.join(REPO, "docs", "qa", "evidence", "round-15"))


def adb(*args, check=True, binary=False):
    out = subprocess.run(["adb", "-s", SERIAL, *args], capture_output=True, check=check)
    return out.stdout if binary else out.stdout.decode("utf-8", "replace")


def nodes():
    for _ in range(3):
        out = adb("exec-out", "uiautomator", "dump", "/dev/tty", check=False)
        if "<hierarchy" in out:
            break
        time.sleep(0.5)
    xml = out[out.find("<?xml"):] if "<?xml" in out else out
    res = []
    for m in re.finditer(r"<node [^>]*>", xml):
        n = m.group(0)

        def g(k):
            mm = re.search(r' %s="([^"]*)"' % k, n)
            return mm.group(1) if mm else ""

        b = [int(v) for v in re.findall(r"\d+", g("bounds"))]
        res.append({"text": unescape(g("text")), "desc": unescape(g("content-desc")), "bounds": b,
                    "clickable": g("clickable"), "pkg": g("package"), "cls": g("class"),
                    "enabled": g("enabled"), "res": g("resource-id")})
    return res


def unescape(s):
    return (s.replace("&#10;", "\n").replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
            .replace("&quot;", '"').replace("&apos;", "'"))


def find(sub):
    return [n for n in nodes() if sub in n["text"] or sub in n["desc"]]


def centre(n):
    x1, y1, x2, y2 = n["bounds"]
    return (x1 + x2) // 2, (y1 + y2) // 2


def main():
    cmd = sys.argv[1]
    if cmd == "dump":
        for n in nodes():
            if n["text"] or n["desc"] or n["clickable"] == "true":
                print(repr(n["text"]), "|", repr(n["desc"]), "|", n["bounds"], "| click" if n["clickable"] == "true" else "",
                      "" if n["pkg"].startswith("com.zaypos") else n["pkg"])
    elif cmd == "has":
        sys.exit(0 if find(sys.argv[2]) else 1)
    elif cmd == "tap":
        idx = int(sys.argv[3]) if len(sys.argv) > 3 else 0
        hits = find(sys.argv[2])
        if len(hits) <= idx:
            print("NOT FOUND:", sys.argv[2])
            sys.exit(1)
        x, y = centre(hits[idx])
        adb("shell", "input", "tap", str(x), str(y))
        print("tapped", repr(sys.argv[2]), x, y)
    elif cmd == "wait":
        t0 = time.time()
        timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 20
        while time.time() - t0 < timeout:
            if find(sys.argv[2]):
                print("found %r after %.2f s" % (sys.argv[2], time.time() - t0))
                return
            time.sleep(0.2)
        print("TIMEOUT waiting for", sys.argv[2])
        sys.exit(1)
    elif cmd == "shot":
        os.makedirs(EVD, exist_ok=True)
        path = os.path.join(EVD, sys.argv[2] + ".png")
        with open(path, "wb") as f:
            f.write(adb("exec-out", "screencap", "-p", binary=True))
        print("shot", path)
    elif cmd == "back":
        adb("shell", "input", "keyevent", "KEYCODE_BACK")
    elif cmd == "fg":
        out = adb("shell", "dumpsys", "activity", "activities")
        m = re.search(r"(?:topResumedActivity|mResumedActivity|ResumedActivity)[:=]\s*ActivityRecord\{[^ ]+ [^ ]+ ([^ }]+)", out)
        print(m.group(1) if m else "?")
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
