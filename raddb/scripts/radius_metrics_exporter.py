#!/usr/bin/env python3
"""Minimal FreeRADIUS Status-Server → Prometheus text exporter."""
from __future__ import annotations

import os
import re
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("RADIUS_METRICS_PORT", "9812"))
BIND = os.environ.get("RADIUS_METRICS_BIND", "0.0.0.0")
SECRET = os.environ.get("HEALTHCHECK_SECRET", "radius-healthcheck")
STATUS_HOST = os.environ.get("RADIUS_STATUS_HOST", "127.0.0.1")
STATUS_PORT = os.environ.get("RADIUS_STATUS_PORT", "1812")
REFRESH_SEC = float(os.environ.get("RADIUS_METRICS_REFRESH_SEC", "15"))

# FreeRADIUS status attribute → prometheus metric name
ATTR_MAP = {
    "FreeRADIUS-Total-Access-Requests": "freeradius_access_requests_total",
    "FreeRADIUS-Total-Access-Accepts": "freeradius_access_accepts_total",
    "FreeRADIUS-Total-Access-Rejects": "freeradius_access_rejects_total",
    "FreeRADIUS-Total-Accounting-Requests": "freeradius_accounting_requests_total",
    "FreeRADIUS-Total-Accounting-Responses": "freeradius_accounting_responses_total",
    "FreeRADIUS-Total-Proxy-Requests": "freeradius_proxy_requests_total",
    "FreeRADIUS-Total-Auth-Responses": "freeradius_auth_responses_total",
}

ATTR_RE = re.compile(r"^\s*([A-Za-z0-9_-]+)\s*=\s*(-?\d+)\s*$")

_lock = threading.Lock()
_cache = {"up": 0, "attrs": {}, "ts": 0.0}


def probe_status() -> tuple[int, dict[str, int]]:
    try:
        proc = subprocess.run(
            [
                "radclient",
                "-x",
                "-r",
                "1",
                "-t",
                "2",
                f"{STATUS_HOST}:{STATUS_PORT}",
                "status",
                SECRET,
            ],
            input="Message-Authenticator = 0x00\n",
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        attrs: dict[str, int] = {}
        for line in out.splitlines():
            m = ATTR_RE.match(line.strip().rstrip(","))
            if not m:
                # radclient -x often prints "\tAttr = value"
                m = ATTR_RE.match(line.replace("\t", "").strip())
            if m and m.group(1) in ATTR_MAP:
                attrs[m.group(1)] = int(m.group(2))
        # Consider up if we got any known counters or exit 0 with "Received response"
        up = 1 if attrs or ("Received response" in out and proc.returncode == 0) else 0
        if proc.returncode != 0 and not attrs:
            up = 0
        return up, attrs
    except Exception:
        return 0, {}


def refresh_loop() -> None:
    while True:
        up, attrs = probe_status()
        with _lock:
            _cache["up"] = up
            _cache["attrs"] = attrs
            _cache["ts"] = time.time()
        time.sleep(REFRESH_SEC)


def render_metrics() -> str:
    with _lock:
        up = int(_cache["up"])
        attrs = dict(_cache["attrs"])
    lines = [
        "# HELP freeradius_up 1 if Status-Server probe succeeded",
        "# TYPE freeradius_up gauge",
        f"freeradius_up {up}",
    ]
    for attr, metric in ATTR_MAP.items():
        val = attrs.get(attr, 0)
        lines.append(f"# HELP {metric} FreeRADIUS status counter ({attr})")
        lines.append(f"# TYPE {metric} counter")
        lines.append(f"{metric} {val}")
    # Document SQL pool config (static from env; actual used sockets not in Status-Server)
    pool_max = int(os.environ.get("RADIUS_SQL_POOL_MAX", "128"))
    lines.append("# HELP freeradius_sql_pool_max Configured rlm_sql pool.max")
    lines.append("# TYPE freeradius_sql_pool_max gauge")
    lines.append(f"freeradius_sql_pool_max {pool_max}")
    lines.append("")
    return "\n".join(lines)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        if self.path.split("?")[0] not in ("/metrics", "/"):
            self.send_response(404)
            self.end_headers()
            return
        body = render_metrics().encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt: str, *args) -> None:  # noqa: A003
        return


def main() -> None:
    threading.Thread(target=refresh_loop, name="radius-metrics-refresh", daemon=True).start()
    # Initial probe before serving
    up, attrs = probe_status()
    with _lock:
        _cache["up"] = up
        _cache["attrs"] = attrs
        _cache["ts"] = time.time()
    httpd = ThreadingHTTPServer((BIND, PORT), Handler)
    print(f"RADIUS metrics exporter listening on {BIND}:{PORT}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
