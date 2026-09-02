"""Measure what a quarantined session can actually pull.

xn32 moved 74 MB outbound in 353 seconds - about 1.7 Mbit, essentially the
full 2 Mbit quarantine rate. Either the garden leaks or that session was not
listed. Sample live interface counters for currently-listed users to find out,
and check which rule is passing the bytes.
"""
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


print("=== who is listed and online ===")
out, _ = rr(':foreach r in=[/ip firewall address-list find where list="expired"] do={'
            ':local a [/ip firewall address-list get $r address]; '
            ':foreach s in=[/ppp active find] do={'
            ':if ([/ppp active get $s address]=$a) do={'
            ':put ([/ppp active get $s name] . "|" . $a . "|" '
            '. [/ppp active get $s uptime])}}}')
listed = [l.strip().split("|") for l in out.splitlines() if l.count("|") == 2]
for n, a, u in listed:
    print(f"  {n:14s} {a:16s} up {u}")
if not listed:
    print("  nobody listed and online")


def iface_bytes():
    """Per-interface byte counters for the quarantined users' PPPoE links."""
    got = {}
    for n, _a, _u in listed:
        out, _ = rr(f':foreach i in=[/interface find where name="<pppoe-{n}>"] do={{'
                    f':put ([/interface get $i rx-byte] . "|" '
                    f'. [/interface get $i tx-byte])}}')
        s = out.strip()
        if s.count("|") == 1:
            rx, tx = s.split("|")
            got[n] = (int(rx), int(tx))
    return got


if listed:
    print("\n=== sampling throughput over 60s ===")
    before = iface_bytes()
    # Snapshot the garden's pass rules too, so any leak can be attributed to a
    # specific rule rather than guessed at.
    rules = {}
    for tag in ["WG-A1", "WG-A2", "WG-A3", "WG-A4", "WG-03", "WG-04", "WG-05",
                "WG-07", "WG-02", "WG-09"]:
        out, _ = rr(f':local f [/ip firewall filter find where comment~"{tag}"]; '
                    f':if ([:len $f]>0) do={{:put [/ip firewall filter get '
                    f'[:pick $f 0] bytes]}} else={{:put "0"}}')
        rules[tag] = int(out.strip() or 0)

    time.sleep(60)

    after = iface_bytes()
    for n in sorted(after):
        if n in before:
            rx = after[n][0] - before[n][0]
            tx = after[n][1] - before[n][1]
            verdict = "  <-- LEAK" if tx > 2_000_000 else ""
            print(f"  {n:14s} to-client {tx / 1024:9.1f} KiB/min   "
                  f"from-client {rx / 1024:8.1f} KiB/min{verdict}")

    print("\n=== which rule passed those bytes ===")
    for tag in ["WG-A1", "WG-A2", "WG-A3", "WG-A4", "WG-03", "WG-04", "WG-05",
                "WG-07", "WG-02", "WG-09"]:
        out, _ = rr(f':local f [/ip firewall filter find where comment~"{tag}"]; '
                    f':if ([:len $f]>0) do={{:put [/ip firewall filter get '
                    f'[:pick $f 0] bytes]}} else={{:put "0"}}')
        delta = int(out.strip() or 0) - rules[tag]
        if delta:
            print(f"  {tag:6s} +{delta / 1024:10.1f} KiB")

print("\n=== queue actually applied to a quarantined session ===")
out, _ = rr('/queue simple print terse without-paging where target~"192.15"')
for line in out.splitlines()[:6]:
    if line.strip():
        print("  " + line.strip()[:150])

print("\n=== xn32 status now ===")
out, _ = rr('/log print without-paging where message~"xn32"')
tail = [l.strip() for l in out.splitlines() if l.strip()][-6:]
for l in tail:
    print("  " + l[:140])
c.close()
