"""Why did xn175 still get kicked after the garden-aware filter?

Startup tick reported gardenOn=true but candidates=3 and skippedGarden=0,
which means every open expired session still looked like a pre-expiry auth.
That only happens if expires_at is somehow after acctstarttime, or the
filter expression is wrong for TypeORM/MySQL.
"""
import subprocess

CONTAINER = "radius-docker-image-freeradius-1"
_MYSQL = ('mysql -h "$SQL_SERVER" -P "$SQL_PORT" -u "$SQL_USER" '
          '-p"$SQL_PASSWORD" "$SQL_DATABASE" --batch --raw --skip-column-names')


def sql(q):
    p = subprocess.run(["docker", "exec", "-i", CONTAINER, "sh", "-c", _MYSQL],
                       input=q, capture_output=True, text=True,
                       encoding="utf-8", errors="ignore", timeout=600)
    err = "\n".join(l for l in (p.stderr or "").splitlines()
                    if "Using a password" not in l).strip()
    if err:
        print("  SQL:", err[:300])
    return [l.split("\t") for l in (p.stdout or "").strip().splitlines() if l.strip()]


print("=== MySQL NOW / time_zone ===")
for r in sql("SELECT NOW(), @@session.time_zone, @@global.time_zone, @@system_time_zone;"):
    print(f"  NOW={r[0]}  session_tz={r[1]}  global_tz={r[2]}  system_tz={r[3]}")

print("\n=== expired users: status vs expires_at vs open session start ===")
for r in sql("""
SELECT up.username, up.account_status, up.expires_at,
       ra.acctstarttime, ra.acctstoptime,
       CASE
         WHEN ra.radacctid IS NULL THEN 'offline'
         WHEN ra.acctstarttime < up.expires_at THEN 'PRE-expiry (would kick)'
         WHEN ra.acctstarttime >= up.expires_at THEN 'POST-expiry (garden, keep)'
         ELSE 'no-start'
       END AS verdict
  FROM raduserprofile up
  LEFT JOIN radacct ra ON ra.username = up.username AND ra.acctstoptime IS NULL
 WHERE up.account_status = 'expired'
    OR (up.expires_at IS NOT NULL AND up.expires_at < NOW())
 ORDER BY up.username;
"""):
    print(f"  {r[0]:14s} status={r[1]:9s} expires={r[2]}  "
          f"start={r[3]}  stop={r[4]}  -> {r[5]}")

print("\n=== what the job query would select right now ===")
print("  (garden ON: only acctstarttime < expires_at)")
for r in sql("""
SELECT DISTINCT ra.username, ra.acctstarttime, up.expires_at
  FROM radacct ra
  INNER JOIN raduserprofile up ON up.username = ra.username
 WHERE ra.acctstoptime IS NULL
   AND up.expires_at IS NOT NULL
   AND up.expires_at < CURRENT_TIMESTAMP
   AND ra.acctstarttime IS NOT NULL
   AND ra.acctstarttime < up.expires_at
 LIMIT 20;
"""):
    print(f"  KICK  {r[0]:14s} start={r[1]}  expires={r[2]}")

print("\n  (all open past-expires, no garden filter)")
for r in sql("""
SELECT DISTINCT ra.username, ra.acctstarttime, up.expires_at,
       IF(ra.acctstarttime < up.expires_at, 'kick', 'keep') AS v
  FROM radacct ra
  INNER JOIN raduserprofile up ON up.username = ra.username
 WHERE ra.acctstoptime IS NULL
   AND up.expires_at IS NOT NULL
   AND up.expires_at < CURRENT_TIMESTAMP
 LIMIT 20;
"""):
    print(f"  {r[3]:4s}  {r[0]:14s} start={r[1]}  expires={r[2]}")

print("\n=== Walled-Garden-expired setting ===")
for r in sql("SELECT key_attribute, if_enabled FROM settings WHERE key_attribute LIKE 'Walled-Garden%';"):
    print(f"  {r[0]} = {r[1]}")

print("\n=== latest backend tick ===")
p = subprocess.run(["docker", "logs", "xnet-backend", "--since", "10m"],
                   capture_output=True, text=True, encoding="utf-8",
                   errors="ignore", timeout=30)
lines = (p.stdout + p.stderr).splitlines()
for i, l in enumerate(lines):
    if "[expiry-disconnect] tick" in l:
        print("  " + "\n  ".join(lines[i:i + 9]))
        print()
