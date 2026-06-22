#!/bin/bash
# Container healthcheck: verify the server actually ANSWERS RADIUS, not just
# that the config parses (`freeradius -C` passes even when the daemon is dead).
#
# Sends a Status-Server request to the auth listener. Requires:
# - the `healthcheck` client in clients.conf (127.0.0.1, HEALTHCHECK_SECRET)
# - status_server = yes (FreeRADIUS default)
set -u

SECRET="${HEALTHCHECK_SECRET:-radius-healthcheck}"

echo "Message-Authenticator = 0x00" | radclient -q -r 1 -t 3 127.0.0.1:1812 status "$SECRET"
