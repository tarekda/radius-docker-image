"""Nail down who terminates the sessions and why.

Two candidates left. Either the CPE hangs up because its connectivity probe
gets a 302, or something server-side is cutting the session near the 5 minute
interim-update boundary. The disconnect timing and terminate cause separate
the two.
"""
import subprocess

import paramiko

CONTAINER = "radius-docker-image-freeradius-1"
_MYSQL = ('mysql -h "$SQL_SERVER" -P "$SQL_PORT" -u "$SQL_USER" '
          '-p"$SQL_PASSWORD" "$SQL_DATABASE" --batch --raw --skip-column-names')


def sql(q):
    p = subprocess.run(["docker", "exec", "-i", CONTAINER, "sh", "-c", _MYSQL],
                       input=q, capture_output=True, text=True,
                       encoding="utf-8", errors="ignore", timeout=600)
    return [l.split("\t") for l in (p.stdout or "").strip().splitlines() if l.strip()]


print("=== session lengths for flapping accounts - is there a 5 min cliff? ===")
for r in sql("""
SELECT username, acctstarttime, acctstoptime, acctsessiontime, acctterminatecause
  FROM radacct
 WHERE username IN ('xn175','xn32')
   AND acctstarttime > NOW() - INTERVAL 60 MINUTE
 ORDER BY acctstarttime DESC LIMIT 15;
"""):
    print(f"  {r[0]:8s} {r[1]}  {r[3]:>6s}s  {r[4]}")

print("\n=== do healthy (non-expired) sessions last longer than 5 min? ===")
for r in sql("""
SELECT p.account_status,
       COUNT(*) AS sessions,
       ROUND(AVG(a.acctsessiontime)) AS avg_secs,
       SUM(a.acctsessiontime BETWEEN 280 AND 320) AS near_5min
  FROM radacct a JOIN raduserprofile p ON p.username = a.username
 WHERE a.acctstoptime > NOW() - INTERVAL 60 MINUTE
 GROUP BY p.account_status ORDER BY sessions DESC;
"""):
    print(f"  {r[0]:12s} {r[1]:>5s} closed  avg {r[2]:>6s}s   "
          f"{r[3]} landed near the 5 min mark")

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("172.9.16.2", username="apiuser", password="123456", timeout=20,
          look_for_keys=False, allow_agent=False)


def rr(cmd, timeout=200):
    _i, o, e = c.exec_command(cmd, timeout=timeout)
    return (o.read().decode(errors="ignore").strip(),
            e.read().decode(errors="ignore").strip())


print("\n=== router's account of xn175 ===")
out, _ = rr('/log print without-paging where message~"xn175"')
for l in [x.strip() for x in out.splitlines() if x.strip()][-14:]:
    print("  " + l[:140])

print("\n=== is anything server-side killing sessions? ===")
# A terminate the router initiated would say so; 'terminating...' with no
# preceding LCP terminate from the peer points the other way.
out, _ = rr('/log print without-paging where topics~"error" or topics~"critical"')
tail = [l.strip() for l in out.splitlines() if l.strip()][-8:]
print("\n".join("  " + l[:140] for l in tail) or "  no errors logged")

print("\n=== Session-Timeout being handed out ===")
# Session-Timeout was 53291 for xn32, far past 5 minutes, so it is not the
# cause - but confirm nothing hands out a short one.
for r in sql("""
SELECT username, attribute, value FROM radreply
 WHERE attribute IN ('Session-Timeout','Idle-Timeout')
   AND username IN ('xn175','xn32') ;
"""):
    print(f"  {r[0]:8s} {r[1]:16s} {r[2]}")
rows = sql("""
SELECT key_attribute, value, if_enabled FROM settings
 WHERE key_attribute LIKE '%Timeout%' OR key_attribute LIKE '%Session%';
""")
for r in rows:
    print(f"  global  {r[0]:26s} {r[1]:>10s}  enabled={r[2]}")
c.close()
