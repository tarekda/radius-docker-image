import paramiko
c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("172.9.16.2", username="apiuser", password="123456", timeout=20,
          look_for_keys=False, allow_agent=False)
_i, o, e = c.exec_command(
    '/ip firewall filter print detail without-paging where comment~"WG-A5" or comment~"WG-A6" or comment~"WG-A7"',
    timeout=120)
print(o.read().decode(errors="ignore"))
print(e.read().decode(errors="ignore"))
c.close()
