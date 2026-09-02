"""Allow common HTTPS connectivity-check hosts so TP-Link detect can pass.

HTTP probes are answered by nginx; some firmwares also hit these over 443.
Keep the allow list tiny — only well-known captive-check names.
"""
import paramiko

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("172.9.16.2", username="apiuser", password="123456", timeout=20,
          look_for_keys=False, allow_agent=False)


def rr(cmd, timeout=200):
    _i, o, e = c.exec_command(cmd, timeout=timeout)
    return (o.read().decode(errors="ignore").strip(),
            e.read().decode(errors="ignore").strip())


# Keep this narrow — tls-host cannot match paths, so a wide glob like
# *.gstatic.com would open a real content CDN inside the garden.
hosts = [
    ("WG-A5", "connectivitycheck.gstatic.com",
     "Android/Chrome HTTPS connectivity check"),
    ("WG-A6", "captive.apple.com",
     "Apple captive portal probe host"),
    ("WG-A7", "detectportal.firefox.com",
     "Firefox network-detect host"),
]

# Insert before WG-REC / WG-06 so SNI allow wins over the catch-alls.
rr('/ip firewall filter remove [find where comment~"WG-A5"]')
rr('/ip firewall filter remove [find where comment~"WG-A6"]')
rr('/ip firewall filter remove [find where comment~"WG-A7"]')
rr('/ip firewall filter remove [find where comment~"WG-A8"]')

anchor, _ = rr(':put [:pick [/ip firewall filter find where comment~"WG-REC"] 0]')
print("anchor WG-REC:", anchor)

for tag, host, note in reversed(hosts):
    out, err = rr(
        f':local dst [:pick [/ip firewall filter find where comment~"WG-REC"] 0]; '
        f'/ip firewall filter add chain=forward action=accept protocol=tcp '
        f'src-address-list=expired dst-port=443 tls-host="{host}" '
        f'comment="{tag} {note}" place-before=$dst; :put "added {tag}"'
    )
    print(out or err)

out, _ = rr('/ip firewall filter print without-paging where comment~"WG-A"')
print(out)
c.close()
