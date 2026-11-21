# Employee Portal (app server). Reads the employees table from the db.
#   /        -> HTML portal page (served to users through web:443)
#   /health  -> "app ok"
import html, os, subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

def query(sql):
    r = subprocess.run(["psql", "-h", "db", "-U", "appuser", "-d", "corp", "-tA", "-F", "|", "-c", sql],
                       capture_output=True, text=True, timeout=8,
                       env={**os.environ, "PGPASSWORD": "AppDb2024", "PGCONNECT_TIMEOUT": "5"})
    return r.returncode == 0, (r.stdout if r.returncode == 0 else r.stderr).strip()

def portal():
    ok, out = query("select id,name,dept,role,salary from employees order by id")
    if not ok:
        return f"<h1>Employee Portal</h1><p>db FAIL: {html.escape(out)}</p>"
    rows = "".join("<tr>" + "".join(f"<td>{html.escape(c)}</td>" for c in line.split("|")) + "</tr>"
                   for line in out.splitlines() if line)
    return ("<!doctype html><title>Corp Employee Portal</title>"
            "<style>body{font-family:sans-serif;margin:2em}table{border-collapse:collapse}"
            "td,th{border:1px solid #999;padding:6px 12px}th{background:#eee}</style>"
            "<h1>Employee Portal</h1><p>status: db ok</p>"
            "<table><tr><th>ID</th><th>Name</th><th>Dept</th><th>Role</th><th>Salary</th></tr>"
            f"{rows}</table>")

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/health"):
            body, ctype = "app ok\n", "text/plain"
        else:
            body, ctype = portal(), "text/html"
        b = body.encode()
        self.send_response(200); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass

if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), H).serve_forever()
