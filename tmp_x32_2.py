"""Two questions about xn32.

1. Is it actually being quarantined? One of its sessions moved 74 MB outbound,
   which the garden should not permit.
2. If it is, the CPE is hanging up (terminate cause is User-Request) - most
   likely because its keepalive pings and the quarantine rejects ICMP.
"""
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


print(f"=== what does RADIUS actually reply for {USER}? ===")
rows = sql(f"SELECT value FROM radcheck WHERE username='{USER}' "
           f"AND attribute='Cleartext-Password' LIMIT 1;")
if rows:
    pw = rows[0][0]
    pkt = (f'User-Name = "{USER}"\\nUser-Password = "{pw}"\\n'
           f'NAS-IP-Address = 172.8.16.2\\nNAS-Port = 0\\n'
           f'Calling-Station-Id = "20:23:51:98:E1:86"')
    cmd = (f'printf "{pkt}" | radclient -x -r 1 -t 6 127.0.0.1:1812 auth '
           f'"${{HEALTHCHECK_SECRET:-radius-healthcheck}}"')
    p = subprocess.run(["docker", "exec", "-i", CONTAINER, "sh", "-c", cmd],
                       capture_output=True, text=True, encoding="utf-8",
                       errors="ignore", timeout=60)
    blob = (p.stdout or "") + (p.stderr or "")
    lines = blob.splitlines()
    st = next((i for i, l in enumerate(lines) if l.startswith("Received ")), len(lines))
    print("  " + (lines[st] if st < len(lines) else "no reply"))
    for l in lines[st + 1:]:
        if l.startswith(("\t", "  ")) and "=" in l:
            print("    " + l.strip())
else:
    print("  no cleartext password stored - cannot test directly")

print(f"\n=== watching for {USER} to reconnect, then checking quarantine ===")
seen = False
for i in range(20):
    out, _ = rr(f':foreach s in=[/ppp active find where name="{USER}"] do={{'
                f':put [/ppp active get $s address]}}')
    ip = out.strip()
    if ip:
        n, _ = rr(f':put [:len [/ip firewall address-list find where list="expired" '
                  f'and address="{ip}"]]')
        q = n.strip() not in ("0", "")
        print(f"  online on {ip} -> {'QUARANTINED' if q else '*** NOT QUARANTINED ***'}")
        seen = True
        break
    time.sleep(6)
if not seen:
    print("  did not come online during the watch window")

print("\n=== add ICMP so CPE keepalives stop killing the session ===")
# Without this a CPE that pings to test its uplink sees 100% loss, decides the
# WAN is down and hangs up - trading the RADIUS reject loop for a PPPoE one.
# ICMP also carries fragmentation-needed, which the portal needs over HTTPS.
rr('/ip firewall filter remove [find where comment~"WG-02 icmp"]')
out, err = rr(':local dst [:pick [/ip firewall filter find where comment~"WG-09"] 0]; '
              '/ip firewall filter add chain=forward action=accept protocol=icmp '
              'src-address-list=expired '
              'comment="WG-02 icmp - CPE keepalives and path MTU discovery" '
              'place-before=$dst; :put "ok"')
print("  " + (out or err))
out, _ = rr('/ip firewall filter print terse without-paging where comment~"WG-02"')
print("  " + out.strip()[:140])

print("\n=== are other quarantined accounts flapping too? ===")
for r in sql("""
SELECT a.username, COUNT(*) AS sessions,
       ROUND(AVG(a.acctsessiontime)) AS avg_secs,
       SUM(a.acctsessiontime < 30) AS under_30s
  FROM radacct a
  JOIN raduserprofile p ON p.username = a.username
 WHERE p.account_status = 'expired'
   AND a.acctstarttime > NOW() - INTERVAL 90 MINUTE
 GROUP BY a.username ORDER BY sessions DESC;
"""):
    flag = "  <-- flapping" if r[3] and int(r[3]) > 3 else ""
    print(f"  {r[0]:14s} {r[1]:>4s} sessions  avg {r[2]:>6s}s  "
          f"{r[3]} under 30s{flag}")
c.close()
