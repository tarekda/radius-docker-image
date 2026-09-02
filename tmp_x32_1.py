"""xn32 connects then drops immediately. Find out who is hanging up.

A strong candidate: many CPEs run a keepalive that pings a public address and
redial the WAN when it fails. The quarantine's WG-09 rejects everything that
is not DNS, the portal or permitted TLS - ICMP included - so a CPE like that
would conclude the link is dead and loop.
"""
import subprocess

import paramiko

CONTAINER = "radius-docker-image-freeradius-1"
_MYSQL = ('mysql -h "$SQL_SERVER" -P "$SQL_PORT" -u "$SQL_USER" '
          '-p"$SQL_PASSWORD" "$SQL_DATABASE" --batch --raw --skip-column-names')
USER = "xn32"


def sql(q):
    p = subprocess.run(["docker", "exec", "-i", CONTAINER, "sh", "-c", _MYSQL],
                       input=q, capture_output=True, text=True,
                       encoding="utf-8", errors="ignore", timeout=600)
    err = "\n".join(l for l in (p.stderr or "").splitlines()
                    if "Using a password" not in l).strip()
    if err:
        print("  SQL:", err[:250])
    return [l.split("\t") for l in (p.stdout or "").strip().splitlines() if l.strip()]


c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("172.9.16.2", username="apiuser", password="123456", timeout=20,
          look_for_keys=False, allow_agent=False)


def rr(cmd, timeout=200):
    _i, o, e = c.exec_command(cmd, timeout=timeout)
    return (o.read().decode(errors="ignore").strip(),
            e.read().decode(errors="ignore").strip())


print(f"=== router log for {USER} ===")
out, _ = rr(f'/log print without-paging where message~"{USER}"')
for line in out.splitlines()[-25:]:
    print("  " + line.strip()[:150])
if not out.strip():
    print("  nothing in the log buffer")

print(f"\n=== is {USER} online right now? ===")
out, _ = rr(f':foreach s in=[/ppp active find where name="{USER}"] do={{'
            f':put ("  " . [/ppp active get $s address] . "  up " '
            f'. [/ppp active get $s uptime] . "  caller=" '
            f'. [/ppp active get $s caller-id])}}')
print(out or "  offline")

print(f"\n=== {USER} session history in the database ===")
for r in sql(f"""
SELECT status, COUNT(*), MIN(timestamp), MAX(timestamp)
  FROM connection_logs
 WHERE username='{USER}' AND timestamp > NOW() - INTERVAL 60 MINUTE
 GROUP BY status ORDER BY COUNT(*) DESC;
"""):
    print(f"  {r[0]:12s} x{r[1]:<5s} {r[2]}  ..  {r[3]}")

print(f"\n=== recent radacct rows (session starts/stops) ===")
for r in sql(f"""
SELECT acctsessionid, acctstarttime, acctstoptime, acctterminatecause,
       acctsessiontime
  FROM radacct WHERE username='{USER}'
 ORDER BY acctstarttime DESC LIMIT 8;
"""):
    print(f"  start={r[1]}  stop={r[2]}  cause={r[3]}  secs={r[4]}")

print(f"\n=== how {USER} compares to a working quarantined account ===")
for r in sql(f"""
SELECT p.username, p.account_status, p.profile_id,
       (SELECT COUNT(*) FROM user_mac m WHERE m.username=p.username) AS macs
  FROM raduserprofile p WHERE p.username IN ('{USER}','xn60','xn175');
"""):
    print(f"  {r[0]:10s} status={r[1]:9s} profile={r[2]:5s} mac-bindings={r[3]}")

print("\n=== is ICMP permitted inside the quarantine? ===")
out, _ = rr(':local icmp 0; :foreach r in=[/ip firewall filter find where '
            'chain="forward"] do={:local p ""; '
            ':do {:set p [/ip firewall filter get $r protocol]} on-error={}; '
            ':if ($p="icmp") do={:set icmp ($icmp + 1)}}; '
            ':put ("  icmp accept rules for quarantined users = " . $icmp)')
print(out)
out, _ = rr(':put ("  WG-09 reject (catches ICMP) pkts = " . [/ip firewall filter get '
            '[:pick [/ip firewall filter find where comment~"WG-09"] 0] packets])')
print(out)

print("\n=== ppp profile settings that could drop a session ===")
out, _ = rr('/ppp profile print detail without-paging where name~"profile"')
print(out[:1500])

print("\n=== ppp aaa ===")
out, _ = rr('/ppp aaa print')
print(out)
c.close()
