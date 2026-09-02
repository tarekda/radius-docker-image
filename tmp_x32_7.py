"""Confirm the expiry-disconnect job stopped flapping garden sessions.

Watch xn175 (was on a 5-minute NAS-Request loop) for >6 minutes after the
backend restart. Also print the next job tick from docker logs once it fires.
"""
import subprocess
import time

import paramiko

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("172.9.16.2", username="apiuser", password="123456", timeout=20,
          look_for_keys=False, allow_agent=False)


def rr(cmd, timeout=200):
    _i, o, e = c.exec_command(cmd, timeout=timeout)
    return (o.read().decode(errors="ignore").strip(),
            e.read().decode(errors="ignore").strip())


print("=== waiting for the next expiry-disconnect tick + xn175 hold ===")
for minute in range(7):
    time.sleep(60)
    out, _ = rr(':foreach s in=[/ppp active find where name="xn175" or name="xn32" '
                'or name="xn60" or name="xn275"] do={'
                ':put ([/ppp active get $s name] . "|" . [/ppp active get $s uptime])}}')
    live = {l.split("|")[0]: l.split("|")[1] for l in out.splitlines() if "|" in l}
    p = subprocess.run(
        ["docker", "logs", "xnet-backend", "--since", f"{minute + 1}m"],
        capture_output=True, text=True, encoding="utf-8", errors="ignore", timeout=30,
    )
    ticks = [l for l in (p.stdout + p.stderr).splitlines() if "[expiry-disconnect] tick" in l]
    tick = ticks[-1] if ticks else "(no tick yet)"
    print(f"  t+{minute + 1}m  xn175={live.get('xn175', 'off'):>8s}  "
          f"xn32={live.get('xn32', 'off'):>8s}  "
          f"xn60={live.get('xn60', 'off'):>8s}  "
          f"xn275={live.get('xn275', 'off'):>8s}")
    print(f"         last tick: {tick}")

print("\n=== recent router log for xn175 / xn32 ===")
out, _ = rr('/log print without-paging where message~"xn175" or message~"xn32"')
for l in [x.strip() for x in out.splitlines() if x.strip()][-10:]:
    print("  " + l[:140])
c.close()
