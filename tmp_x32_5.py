"""What are these CPEs probing to decide the link is dead?

The redirect responder sees every port-80 request from the garden, so its
access log names the exact connectivity checks. If a CPE probes a URL that
expects HTTP 204 and gets a 302 instead, it concludes there is no internet and
redials - which would explain flapping that allowing ICMP did not fix.
"""
import re
import subprocess

import paramiko

p = subprocess.run(["docker", "logs", "--since", "45m", "walled-garden-redirect"],
                   capture_output=True, text=True, encoding="utf-8",
                   errors="ignore", timeout=60)
blob = (p.stdout or "") + (p.stderr or "")
lines = [l for l in blob.splitlines() if '"' in l and " 302 " in l or " 200 " in l]

print(f"=== redirect responder: {len(lines)} requests in 45 min ===")

paths, agents, srcs = {}, {}, {}
for l in lines:
    m = re.search(r'"(?:GET|POST|HEAD) ([^ ]+)', l)
    if m:
        paths[m.group(1)] = paths.get(m.group(1), 0) + 1
    m = re.search(r'"[^"]*"\s*$', l)
    if m:
        ua = m.group(0).strip('" ')
        agents[ua[:70]] = agents.get(ua[:70], 0) + 1
    m = re.match(r'([\d.]+)', l)
    if m:
        srcs[m.group(1)] = srcs.get(m.group(1), 0) + 1

print("\n  paths requested:")
for k, v in sorted(paths.items(), key=lambda x: -x[1])[:12]:
    hint = ""
    if "generate_204" in k or "gen_204" in k or "ncsi" in k.lower():
        hint = "   <-- expects HTTP 204, a 302 reads as 'no internet'"
    if "hotspot-detect" in k or "success" in k:
        hint = "   <-- expects 200 'Success', a 302 reads as captive portal"
    print(f"    x{v:<5d} {k[:70]}{hint}")

print("\n  clients:")
for k, v in sorted(srcs.items(), key=lambda x: -x[1])[:8]:
    print(f"    x{v:<5d} {k}")

print("\n  user agents:")
for k, v in sorted(agents.items(), key=lambda x: -x[1])[:8]:
    print(f"    x{v:<5d} {k}")

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("172.9.16.2", username="apiuser", password="123456", timeout=20,
          look_for_keys=False, allow_agent=False)


def rr(cmd, timeout=200):
    _i, o, e = c.exec_command(cmd, timeout=timeout)
    return (o.read().decode(errors="ignore").strip(),
            e.read().decode(errors="ignore").strip())


print("\n=== what the garden is rejecting, by port ===")
# The reject counter alone does not say what is being blocked. Connection
# tracking still shows the attempts, so read the destinations being refused.
out, _ = rr(':foreach ct in=[/ip firewall connection find] do={'
            ':local s [:tostr [/ip firewall connection get $ct src-address]]; '
            ':if ([:find $s "192.15.16."]>=0) do={'
            ':local d [:tostr [/ip firewall connection get $ct dst-address]]; '
            ':put ([/ip firewall connection get $ct protocol] . ":" '
            '. [:pick $d ([:find $d ":"]+1) [:len $d]])}}')
seen = {}
for tok in out.split():
    seen[tok] = seen.get(tok, 0) + 1
for k, v in sorted(seen.items(), key=lambda x: -x[1])[:15]:
    print(f"    x{v:<4d} {k}")

print("\n=== session lengths for quarantined users, last 45 min ===")
out, _ = rr(':foreach r in=[/ip firewall address-list find where list="expired"] do={'
            ':local a [/ip firewall address-list get $r address]; '
            ':foreach s in=[/ppp active find] do={'
            ':if ([/ppp active get $s address]=$a) do={'
            ':put ("  " . [/ppp active get $s name] . "  up " '
            '. [/ppp active get $s uptime])}}}')
print(out or "  none")
c.close()
