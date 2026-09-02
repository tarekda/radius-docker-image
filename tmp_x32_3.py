"""Confirm the ICMP rule is ahead of the reject, then see if xn32 settles.

Rule ordering has bitten this work twice already, so read positions from the
raw chain print rather than trusting the insert. Then watch whether the
flapping accounts hold a session once their keepalive can succeed.
"""
import subprocess
import time

import paramiko

CONTAINER = "radius-docker-image-freeradius-1"
_MYSQL = ('mysql -h "$SQL_SERVER" -P "$SQL_PORT" -u "$SQL_USER" '
          '-p"$SQL_PASSWORD" "$SQL_DATABASE" --batch --raw --skip-column-names')


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


print("=== forward chain in true order ===")
out, _ = rr('/ip firewall filter print without-paging where chain=forward')
pos = None
order = []
for line in out.splitlines():
    s = line.strip()
    if s and s[0].isdigit() and ";;;" in s:
        num = s.split()[0]
        cmt = s.split(";;;", 1)[1].strip()
        order.append((int(num), cmt))
    elif s.startswith(";;;") and pos is not None:
        pass
for num, cmt in order:
    tag = ""
    if cmt.startswith("WG-02"):
        tag = "   <-- icmp"
    if cmt.startswith("WG-09"):
        tag = "   <-- catch-all reject"
    print(f"  {num:>3d}  {cmt[:80]}{tag}")

icmp_pos = next((n for n, cm in order if cm.startswith("WG-02")), None)
rej_pos = next((n for n, cm in order if cm.startswith("WG-09")), None)
print(f"\n  icmp at {icmp_pos}, reject at {rej_pos} -> "
      f"{'CORRECT' if icmp_pos is not None and rej_pos is not None and icmp_pos < rej_pos else 'WRONG ORDER'}")

print("\n=== watching flapping accounts for 5 minutes ===")
watch = ["xn32", "xnet-load-4", "xn175"]
quoted = '" or name="'.join(watch)
for minute in range(5):
    time.sleep(60)
    out, _ = rr(f':foreach s in=[/ppp active find where name="{quoted}"] do={{'
                f':put ([/ppp active get $s name] . "|" . [/ppp active get $s uptime])}}')
    live = dict(l.strip().split("|") for l in out.splitlines() if l.count("|") == 1)
    icmp, _ = rr(':put [/ip firewall filter get [:pick [/ip firewall filter find '
                 'where comment~"WG-02"] 0] packets]')
    states = "  ".join(f"{w}={live.get(w, 'off')}" for w in watch)
    print(f"  t+{minute + 1}   icmp_accepts={icmp.strip():>6s}   {states}")

print("\n=== session churn since the icmp rule went in ===")
for r in sql("""
SELECT a.username, COUNT(*) AS sessions, ROUND(AVG(a.acctsessiontime)) AS avg_secs
  FROM radacct a JOIN raduserprofile p ON p.username = a.username
 WHERE p.account_status='expired'
   AND a.acctstarttime > NOW() - INTERVAL 6 MINUTE
 GROUP BY a.username ORDER BY sessions DESC;
"""):
    print(f"  {r[0]:14s} {r[1]:>3s} sessions in 6 min   avg {r[2]}s")

print("\n=== how much data are quarantined users actually moving? ===")
out, _ = rr(':foreach r in=[/ip firewall address-list find where list="expired"] do={'
            ':local a [/ip firewall address-list get $r address]; '
            ':foreach s in=[/ppp active find] do={'
            ':if ([/ppp active get $s address]=$a) do={'
            ':put ("  " . [/ppp active get $s name] . "  up " '
            '. [/ppp active get $s uptime] . "  in=" '
            '. ([/ppp active get $s bytes-in]/1024) . "KiB  out=" '
            '. ([/ppp active get $s bytes-out]/1024) . "KiB")}}}')
print(out or "  none online")

print("\n=== redirects still being served ===")
p = subprocess.run(["docker", "logs", "--since", "6m", "walled-garden-redirect"],
                   capture_output=True, text=True, encoding="utf-8",
                   errors="ignore", timeout=60)
blob = (p.stdout or "") + (p.stderr or "")
print("  302s served:", len([l for l in blob.splitlines() if '" 302 ' in l]))
c.close()
