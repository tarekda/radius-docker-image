"""xn32 still flapping - who hangs up, and is the garden still applied?"""
import subprocess
import time

import paramiko

CONTAINER = "radius-docker-image-freeradius-1"
_MYSQL = ('mysql -h "$SQL_SERVER" -P "$SQL_PORT" -u "$SQL_USER" '
          '-p"$SQL_PASSWORD" "$SQL_DATABASE" --batch --raw --skip-column-names')
USER = "xn32"


def sql(q):
    p = subprocess.run(["docker", "exec", "-i", CONTAINER, "sh", "-c", _MYSQL],
                       input=q, capture_output=True, text=True,
                       encoding="utf-8", errors="ignore", timeout=600)
    return [l.split("\t") for l in (p.stdout or "").strip().splitlines() if l.strip()]


c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("172.9.16.2", username="apiuser", password="123456", timeout=20,
          look_for_keys=False, allow_agent=False)


def rr(cmd, timeout=200):
    _i, o, e = c.exec_command(cmd, timeout=timeout)
    return (o.read().decode(errors="ignore").strip(),
            e.read().decode(errors="ignore").strip())


print("=== profile / expires ===")
for r in sql(f"""
SELECT username, account_status, expires_at, profile_id
  FROM raduserprofile WHERE username='{USER}';
"""):
    print(f"  status={r[1]}  expires_at={r[2]}  profile={r[3]}")

print("\n=== recent sessions (cause + length) ===")
for r in sql(f"""
SELECT acctstarttime, acctstoptime, acctsessiontime, acctterminatecause,
       framedipaddress
  FROM radacct WHERE username='{USER}'
 ORDER BY acctstarttime DESC LIMIT 12;
"""):
    print(f"  start={r[0]}  stop={r[1]}  secs={r[2]}  cause={r[3]}  ip={r[4]}")

print("\n=== router log ===")
out, _ = rr(f'/log print without-paging where message~"{USER}"')
for l in [x.strip() for x in out.splitlines() if x.strip()][-20:]:
    print("  " + l[:150])

print("\n=== online now? ===")
out, _ = rr(f':foreach s in=[/ppp active find where name="{USER}"] do={{'
            f':put ("  " . [/ppp active get $s address] . " up=" '
            f'. [/ppp active get $s uptime] . " caller=" '
            f'. [/ppp active get $s caller-id])}}')
print(out or "  offline")
ip = ""
if out.strip():
    ip = out.strip().split()[0] if out.strip().split() else ""
    # first token after blank might be address
    for tok in out.replace("up=", " ").split():
        if tok.count(".") == 3:
            ip = tok
            break
    n, _ = rr(f':put [:len [/ip firewall address-list find where list="expired" '
              f'and address="{ip}"]]')
    print(f"  address-list expired for {ip}: {n.strip()}")

print("\n=== backend expiry ticks (15m) ===")
p = subprocess.run(["docker", "logs", "xnet-backend", "--since", "15m"],
                   capture_output=True, text=True, encoding="utf-8",
                   errors="ignore", timeout=30)
blob = p.stdout + p.stderr
idx = 0
count = 0
while True:
    i = blob.find("[expiry-disconnect] tick", idx)
    if i < 0:
        break
    print("  " + " ".join(blob[i:i + 200].split())[:180])
    idx = i + 1
    count += 1
    if count >= 4:
        break
if count == 0:
    print("  (none)")

print("\n=== watch 90s for reconnect / drop ===")
for i in range(6):
    time.sleep(15)
    out, _ = rr(f':foreach s in=[/ppp active find where name="{USER}"] do={{'
                f':put ([/ppp active get $s uptime] . "|" . [/ppp active get $s address])}}')
    print(f"  +{(i + 1) * 15}s  {out.strip() or 'offline'}")
c.close()
