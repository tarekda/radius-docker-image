"""Check profile 14 rates, whether Address-List is really applied, and WG rule health."""
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


c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("172.9.16.2", username="apiuser", password="123456", timeout=20,
          look_for_keys=False, allow_agent=False)


def rr(cmd, timeout=200):
    _i, o, e = c.exec_command(cmd, timeout=timeout)
    return (o.read().decode(errors="ignore").strip(),
            e.read().decode(errors="ignore").strip())


print("=== profile 14 (xn32) ===")
for r in sql("""
SELECT id, name FROM radprofile WHERE id=14;
"""):
    print(f"  {r}")
for r in sql("""
SELECT groupname, attribute, value FROM radgroupreply
 WHERE groupname IN (SELECT name FROM radprofile WHERE id=14)
    OR groupname LIKE '%14%' OR groupname='14';
"""):
    print(f"  reply {r}")

# How profiles map in this schema
for r in sql("""
SHOW TABLES LIKE '%profile%';
"""):
    print("  table", r[0])
for r in sql("""
SELECT COLUMN_NAME FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='radprofile';
"""):
    print("  col", r[0])

print("\n=== radtest xn32 accept attrs ===")
rows = sql("SELECT value FROM radcheck WHERE username='xn32' AND attribute='Cleartext-Password' LIMIT 1;")
if rows:
    pw = rows[0][0].replace('"', '\\"')
    pkt = (f'User-Name = "xn32"\\nUser-Password = "{pw}"\\n'
           f'NAS-IP-Address = 172.8.16.2\\nCalling-Station-Id = "20:23:51:98:E1:86"')
    cmd = (f'printf "{pkt}" | radclient -x -r 1 -t 6 127.0.0.1:1812 auth '
           f'"${{HEALTHCHECK_SECRET:-radius-healthcheck}}"')
    p = subprocess.run(["docker", "exec", "-i", CONTAINER, "sh", "-c", cmd],
                       capture_output=True, text=True, encoding="utf-8",
                       errors="ignore", timeout=60)
    blob = p.stdout + p.stderr
    for l in blob.splitlines():
        if "Mikrotik" in l or "Session" in l or "Idle" in l or "Reply" in l or "Received" in l:
            print(" ", l.strip()[:120])

print("\n=== WG filter counters / enabled ===")
out, _ = rr('/ip firewall filter print without-paging where comment~"WG-"')
print(out[:2500])

print("\n=== expired address-list size ===")
out, _ = rr(':put [:len [/ip firewall address-list find where list="expired"]]')
print("  entries:", out)

print("\n=== mac vendor / ppp only-one ===")
out, _ = rr('/ppp profile get [find name="profile2-10"] only-one')
print("  sample only-one:", out)
# which profile does xn32 get from radius?
out, _ = rr('/ppp aaa print')
print(out)
c.close()
