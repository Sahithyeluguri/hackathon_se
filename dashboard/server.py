#!/usr/bin/env python3
"""Flatland dashboard - local control + visualisation for the PS-2 lab.

Run from the flatland folder:   python3 dashboard/server.py
Then open:                      http://localhost:8000

Listens on 127.0.0.1 only. Only whitelisted ./run.sh commands can be started.
Python standard library only (no pip installs).
"""
import json, os, re, subprocess, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # flatland/
HERE = os.path.dirname(os.path.abspath(__file__))
RUN = os.environ.get("FLATLAND_RUN", os.path.join(ROOT, "run.sh"))
PORT = int(os.environ.get("FLATLAND_DASH_PORT", "8000"))

MODES = {"flat", "seg"}
COMMANDS = {"up", "down", "reset", "attack", "business", "integrity", "fw"}
SEQUENCES = {"demo": ["business", "attack", "fw"]}          # fw skipped automatically in flat mode

BASELINE = [l for l in open(os.path.join(ROOT, "lab", "conf", "employees.baseline")).read().splitlines() if l]

# ---------------- job runner (one job at a time) ----------------
lock = threading.Lock()
log = []            # list of dicts {i, t, kind, text}
job = {"running": False, "mode": None, "cmd": None, "started": None}


def emit(kind, text):
    with lock:
        log.append({"i": len(log), "t": time.time(), "kind": kind, "text": text})
        if len(log) > 20000:              # keep memory bounded
            del log[:5000]
            for n, e in enumerate(log):
                e["i"] = n


def run_job(mode, steps):
    try:
        if steps[0] in ("up", "reset"):              # both labs publish :8443 - stop the other one first
            other = "seg" if mode == "flat" else "flat"
            if lab_state().get(other):
                steps = ["__down_other"] + steps
        for cmd in steps:
            if cmd == "fw" and mode != "seg":
                continue
            if cmd == "__down_other":
                other = "seg" if mode == "flat" else "flat"
                emit("line", f"[dashboard] stopping the {other} lab first (both use port 8443)")
                p = subprocess.run([RUN, other, "down"], cwd=ROOT, capture_output=True, text=True)
                emit("line", f"[dashboard] {other} lab stopped (rc={p.returncode})")
                continue
            emit("start", json.dumps({"mode": mode, "cmd": cmd}))
            env = dict(os.environ, BUILDKIT_PROGRESS="plain", COMPOSE_PROGRESS="plain")
            p = subprocess.Popen([RUN, mode, cmd], cwd=ROOT, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, text=True, bufsize=1, env=env)
            for line in p.stdout:
                emit("line", line.rstrip("\n"))
            rc = p.wait()
            emit("end", json.dumps({"mode": mode, "cmd": cmd, "rc": rc}))
    except Exception as e:  # noqa
        emit("line", f"[dashboard] error: {e}")
    finally:
        with lock:
            job.update(running=False)
        emit("idle", "")


def compose(mode, *args, timeout=20):
    cmd = ["docker", "compose", "-p", mode, "-f", os.path.join(ROOT, f"docker-compose.{mode}.yml"), *args]
    try:
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout
    except Exception as e:  # noqa
        return 1, str(e)

# ---------------- read-only views ----------------

def lab_state():
    out = {}
    for m in MODES:
        rc, so = compose(m, "ps", "--services", "--status", "running", timeout=10)
        out[m] = sorted(so.split()) if rc == 0 else []
    return out


def db_view(mode):
    rc, so = compose(mode, "exec", "-T", "db", "psql", "-U", "appuser", "-d", "corp", "-tA", "-F", "|",
                     "-c", "select id,name,dept,role,salary from employees order by id")
    if rc != 0:
        return {"ok": False, "rows": [], "error": "database not running"}
    base = {l.split("|")[0]: l.split("|") for l in BASELINE}
    rows = []
    for line in [l for l in so.splitlines() if l]:
        cols = line.split("|")
        b = base.get(cols[0])
        changed = [] if b is None else [i for i, (x, y) in enumerate(zip(cols, b)) if x != y]
        rows.append({"cols": cols, "baseline": b, "changed": changed, "new": b is None})
    tampered = any(r["changed"] or r["new"] for r in rows) or len(rows) != len(BASELINE)
    return {"ok": True, "rows": rows, "tampered": tampered}


LOGRE = re.compile(r"^(\w+ +\d+ [\d:]+) \S+ (\S+) .*?SRC=(\S+) DST=(\S+).*?PROTO=(\S+)(?:.*?DPT=(\d+))?")
CNTRE = re.compile(r"counter packets (\d+) bytes \d+(.*)$")


def fw_view():
    rc, so = compose("seg", "exec", "-T", "router", "sh", "-c", "tail -n 60 /var/log/ulog/syslogemu.log")
    drops = []
    if rc == 0:
        for l in so.splitlines():
            m = LOGRE.search(l)
            if m:
                drops.append({"time": m[1], "rule": m[2], "src": m[3], "dst": m[4], "proto": m[5], "dport": m[6]})
    rc2, so2 = compose("seg", "exec", "-T", "router", "nft", "list", "table", "inet", "lab")
    counters = {}
    if rc2 == 0:
        for l in so2.splitlines():
            m = CNTRE.search(l)
            if not m:
                continue
            n, tail = int(m[1]), m[2]
            if "FWD-DROP" in tail:
                counters["dropped"] = n
            elif "dport 443" in l:
                counters["user_to_web_443"] = n
            elif "dport 8080" in l:
                counters["web_to_app_8080"] = n
            elif "dport 22" in l and "accept" in tail and "limit" not in l:
                counters["admin_ssh"] = n
            elif "SSH-RATELIMIT" in tail:
                counters["ssh_ratelimited"] = n
    return {"ok": rc == 0 or rc2 == 0, "drops": drops[-40:], "counters": counters}

# ---------------- HTTP ----------------

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code, body, ctype="application/json"):
        b = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(b)

    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj))

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        mode = (q.get("mode") or ["flat"])[0]
        if u.path in ("/", "/index.html"):
            return self._send(200, open(os.path.join(HERE, "index.html"), "rb").read(), "text/html; charset=utf-8")
        if u.path == "/api/state":
            with lock:
                j = dict(job)
            return self._json({"lab": lab_state(), "job": j})
        if u.path == "/api/db":
            if mode not in MODES:
                return self._json({"error": "bad mode"}, 400)
            return self._json(db_view(mode))
        if u.path == "/api/fw":
            return self._json(fw_view())
        if u.path == "/api/stream":
            return self.stream(int((q.get("from") or ["0"])[0]))
        self._send(404, "not found", "text/plain")

    def do_POST(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if u.path != "/api/run":
            return self._send(404, "not found", "text/plain")
        mode = (q.get("mode") or [""])[0]
        cmd = (q.get("cmd") or [""])[0]
        if mode not in MODES or (cmd not in COMMANDS and cmd not in SEQUENCES):
            return self._json({"error": "not allowed"}, 400)
        with lock:
            if job["running"]:
                return self._json({"error": f"busy: {job['mode']} {job['cmd']}"}, 409)
            job.update(running=True, mode=mode, cmd=cmd, started=time.time())
        steps = SEQUENCES.get(cmd, [cmd])
        threading.Thread(target=run_job, args=(mode, steps), daemon=True).start()
        self._json({"ok": True, "steps": steps})

    def stream(self, start):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        i, last_ping = start, time.time()
        try:
            while True:
                with lock:
                    batch = log[i:] if i <= len(log) else log[:]
                    if i > len(log):
                        i = 0
                for e in batch:
                    self.wfile.write(f"data: {json.dumps(e)}\n\n".encode())
                    i = e["i"] + 1
                if batch:
                    self.wfile.flush()
                if time.time() - last_ping > 15:
                    self.wfile.write(b": ping\n\n"); self.wfile.flush(); last_ping = time.time()
                time.sleep(0.15)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    srv.daemon_threads = True
    print(f"Flatland dashboard: http://localhost:{PORT}   (Ctrl+C to stop)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
