"""xn32: User-Request flaps + 248MB in 15m. Is address-list applied? What leaks?"""
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


print("=== RADIUS reply attributes for xn32 (from last auth path) ===")
# Check radreply / group reply / dynamic garden
for r in sql(f"""
SELECT attribute, op, value FROM radreply WHERE username='{USER}'
 UNION ALL
SELECT attribute, op, value FROM radcheck WHERE username='{USER}' AND attribute NOT LIKE '%Password%';
"""):
    print(f"  {r[0]} {r[1]} {r[2]}")

print("\n=== waiting up to 3 min for xn32 to dial ===")
ip = None
for i in range(12):
    out, _ = rr(f':foreach s in=[/ppp active find where name="{USER}"] do={{'
                f':put ([/ppp active get $s address] . "|" . [/ppp active get $s uptime] '
                f'. "|" . [/ppp active get $s caller-id] . "|" '
                f'. [/ppp active get $s service])}}')
    if out.strip() and "|" in out:
        parts = out.strip().split("|")
        ip = parts[0]
        print(f"  online: ip={parts[0]} up={parts[1]} mac={parts[2]} svc={parts[3]}")
        break
    time.sleep(15)
    print(f"  ...still offline ({(i + 1) * 15}s)")

if not ip:
    print("  did not come online - cannot check address-list live")
    # Still dump WG counters and recent nginx
else:
    n, _ = rr(f'/ip firewall address-list print where list="expired" and address="{ip}"')
    print(f"\n=== address-list for {ip} ===\n{n or '  NOT LISTED'}")

    print("\n=== dynamic queues / rate-limit ===")
    out, _ = rr(f'/queue simple print terse where name~"{USER}" or target~"{ip}"')
    print(out or "  (no simple queue)")
    out, _ = rr(f'/ppp active print detail where name="{USER}"')
    print(out[:800])

    print("\n=== sample bytes over 30s + which WG rules pass ===")
    before = {}
    for tag in ["WG-A1", "WG-A2", "WG-A3", "WG-A4", "WG-03", "WG-04", "WG-07", "WG-02", "WG-09"]:
        out, _ = rr(f':local f [/ip firewall filter find where comment~"{tag}"]; '
                    f':if ([:len $f]>0) do={{:put [/ip firewall filter get [:pick $f 0] bytes]}} else={{:put 0}}')
        before[tag] = int(out.strip() or 0)
    rx0, _ = rr(f':put [/interface get [find name="<pppoe-{USER}>"] rx-byte]')
    tx0, _ = rr(f':put [/interface get [find name="<pppoe-{USER}>"] tx-byte]')
    time.sleep(30)
    rx1, _ = rr(f':put [/interface get [find name="<pppoe-{USER}>"] rx-byte]')
    tx1, _ = rr(f':put [/interface get [find name="<pppoe-{USER}>"] tx-byte]')
    try:
        print(f"  to-client +{(int(tx1) - int(tx0)) / 1024:.1f} KiB/30s  "
              f"from-client +{(int(rx1) - int(rx0)) / 1024:.1f} KiB/30s")
    except Exception as e:
        print(f"  iface counters failed: {e} rx={rx0!r} tx={tx0!r}")
    for tag in before:
        out, _ = rr(f':local f [/ip firewall filter find where comment~"{tag}"]; '
                    f':if ([:len $f]>0) do={{:put [/ip firewall filter get [:pick $f 0] bytes]}} else={{:put 0}}')
        d = int(out.strip() or 0) - before[tag]
        if d:
            print(f"  {tag} +{d / 1024:.1f} KiB")

print("\n=== ICMP rule still present? ===")
out, _ = rr('/ip firewall filter print terse where comment~"WG-02"')
print("  " + (out.strip()[:160] or "MISSING"))

print("\n=== nginx probes last 20m ===")
p = subprocess.run(["docker", "logs", "--since", "20m", "walled-garden-redirect"],
                   capture_output=True, text=True, encoding="utf-8", errors="ignore", timeout=30)
blob = p.stdout + p.stderr
paths = {}
for l in blob.splitlines():
    if "GET " in l or "HEAD " in l:
        import re
        m = re.search(r'"(?:GET|HEAD) ([^ ]+)', l)
        if m:
            paths[m.group(1)] = paths.get(m.group(1), 0) + 1
for k, v in sorted(paths.items(), key=lambda x: -x[1])[:10]:
    print(f"  x{v}  {k}")

print("\n=== compare: other expired online uptimes ===")
out, _ = rr(':foreach r in=[/ip firewall address-list find where list="expired"] do={'
            ':local a [/ip firewall address-list get $r address]; '
            ':foreach s in=[/ppp active find] do={'
            ':if ([/ppp active get $s address]=$a) do={'
            ':put ([/ppp active get $s name] . "|" . [/ppp active get $s uptime])}}}')
for l in out.splitlines():
    if "|" in l:
        print("  " + l.strip())
c.close()
