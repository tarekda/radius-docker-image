"""Confirm xn175 survives the next */5 cron tick after the zombie-row fix."""
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


print("=== watching through the next cron boundary ===")
for minute in range(7):
    time.sleep(60)
    out, _ = rr(':foreach s in=[/ppp active find where name="xn175" or name="xn32" '
                'or name="xn60" or name="xn275"] do={'
                ':put ([/ppp active get $s name] . "|" . [/ppp active get $s uptime])}}')
    live = {l.split("|")[0]: l.split("|")[1] for l in out.splitlines() if "|" in l}
    p = subprocess.run(
        ["docker", "logs", "xnet-backend", "--since", "2m"],
        capture_output=True, text=True, encoding="utf-8", errors="ignore", timeout=30,
    )
    ticks = [l for l in (p.stdout + p.stderr).splitlines()
             if "[expiry-disconnect] tick" in l]
    # Prefer the full object from recent logs
    full = ""
    blob = p.stdout + p.stderr
    idx = blob.rfind("[expiry-disconnect] tick")
    if idx >= 0:
        full = " ".join(blob[idx:idx + 220].split())
    print(f"  t+{minute + 1}m  xn175={live.get('xn175', 'off'):>8s}  "
          f"xn32={live.get('xn32', 'off'):>8s}  "
          f"xn60={live.get('xn60', 'off'):>8s}  "
          f"xn275={live.get('xn275', 'off'):>8s}")
    if full:
        print(f"         {full[:180]}")

print("\n=== router log tail xn175 ===")
out, _ = rr('/log print without-paging where message~"xn175"')
for l in [x.strip() for x in out.splitlines() if x.strip()][-8:]:
    print("  " + l[:140])
c.close()
