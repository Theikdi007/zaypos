#!/usr/bin/env python3
"""QA round 17: tiny host helper for tests that run on a REAL iPhone without a driver connection.

The phone cannot read files on the Mac, so the test talks to this server over the LAN:
  GET  /otp?phone=+959...      -> the dev OTP codes for that phone from the API log, one per line (oldest first)
  POST /note?run=r             -> body appended to <evidence>/logs/<r>.log (QA_NOTE lines, results)
  POST /shot?name=x            -> body (PNG) saved as <evidence>/x.png
  GET  /step                   -> '<step>|<expect>' from r17_step.txt next to the API log (Android steps)
  GET  /cmd?c=api_log_500      -> host checks (count of 5xx / unhandled exceptions in the API log)
Only OTP lines are ever returned from the API log (no tokens).

  python3 -I r17_host.py <api.log> <evidence-dir> <run-name> [port]
"""
import http.server
import subprocess
import threading
import time
import os
import re
import sys
import urllib.parse

API_LOG, EVD, RUN = sys.argv[1], sys.argv[2], sys.argv[3]
PORT = int(sys.argv[4]) if len(sys.argv) > 4 else 8765
os.makedirs(os.path.join(EVD, "logs"), exist_ok=True)
LOG = os.path.join(EVD, "logs", RUN + ".log")


def api_log():
    with open(API_LOG, encoding="utf-8", errors="replace") as f:
        return f.read()


SERIAL = os.environ.get("ANDROID_SERIAL", "emulator-5554")


def adb(*a):
    r = subprocess.run(["adb", "-s", SERIAL, "shell", *a], capture_output=True, text=True)
    return (r.stdout + r.stderr).strip()


def note_host(s):
    with open(os.path.join(EVD, "logs", "r17_host_cmds.log"), "a", encoding="utf-8") as f:
        f.write("%s %s\n" % (time.strftime("%H:%M:%S"), s))


def airplane_window(seconds):
    def run():
        adb("cmd", "connectivity", "airplane-mode", "enable")
        note_host("airplane-mode now: %s" % adb("cmd", "connectivity", "airplane-mode"))
        time.sleep(seconds)
        adb("cmd", "connectivity", "airplane-mode", "disable")
        note_host("airplane-mode now: %s" % adb("cmd", "connectivity", "airplane-mode"))
    return run


def setting(*a):
    def run():
        adb(*a)
        note_host("%s -> font_scale=%s" % (" ".join(a), adb("settings", "get", "system", "font_scale")))
    return run


# Android host actions for driverless runs (the app cannot reach the host while airplane mode is on, so airplane mode is
# switched off again by the host after a fixed window).
ADB_CMDS = {
    "airplane_window_90": airplane_window(90),
    "font_max": setting("settings", "put", "system", "font_scale", "2.0"),
    "font_default": setting("settings", "put", "system", "font_scale", "1.0"),
}


class H(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body=b"", ctype="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path == "/otp":
            phone = q.get("phone", [""])[0]
            codes = re.findall(r"DEV SMS to " + re.escape(phone) + r": ZayPOS code: (\d{6})", api_log())
            return self._send(200, "\n".join(codes).encode())
        if u.path == "/cmd" and q.get("c", [""])[0].startswith("screencap_"):
            name = re.sub(r"[^A-Za-z0-9_.-]", "_", q["c"][0][len("screencap_"):])
            png = subprocess.run(["adb", "-s", SERIAL, "exec-out", "screencap", "-p"], capture_output=True).stdout
            with open(os.path.join(EVD, name + ".png"), "wb") as f:
                f.write(png)
            note_host("screencap %s.png (%d bytes)" % (name, len(png)))
            return self._send(200, b"ok")
        if u.path == "/cmd" and q.get("c", [""])[0] in ADB_CMDS:
            c = q["c"][0]
            note_host("cmd %s" % c)
            threading.Thread(target=ADB_CMDS[c], daemon=True).start()
            return self._send(200, b"ok")
        if u.path == "/cmd" and q.get("c", [""])[0] == "api_log_500":
            text = api_log()
            n = len(re.findall(r"status code 5\d\d|Unhandled exception|An unhandled exception", text))
            return self._send(200, str(n).encode())
        if u.path == "/step":  # round 17 Android: one APK for every step; the step comes from <api.log dir>/r17_step.txt
            with open(os.path.join(os.path.dirname(API_LOG), "r17_step.txt"), encoding="utf-8") as f:
                return self._send(200, f.read().strip().encode())
        if u.path == "/ping":
            return self._send(200, b"pong")
        return self._send(404)

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if u.path == "/note":
            run = re.sub(r"[^A-Za-z0-9_.-]", "_", q.get("run", [RUN])[0])
            with open(os.path.join(EVD, "logs", run + ".log"), "a", encoding="utf-8") as f:
                f.write(body.decode("utf-8", "replace").rstrip("\n") + "\n")
            return self._send(200, b"ok")
        if u.path == "/shot":
            name = re.sub(r"[^A-Za-z0-9_.-]", "_", q.get("name", ["shot"])[0])
            with open(os.path.join(EVD, name + ".png"), "wb") as f:
                f.write(body)
            return self._send(200, b"ok")
        return self._send(404)

    def log_message(self, fmt, *args):
        sys.stderr.write("[host] %s %s\n" % (self.address_string(), fmt % args))


http.server.ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
