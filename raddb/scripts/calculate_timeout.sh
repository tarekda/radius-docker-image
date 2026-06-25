#!/bin/bash
# Print seconds until the next LOCAL midnight (used as Session-Timeout so
# sessions re-authenticate right after the daily quota reset).
#
# NOTE: the old `date +%s % 86400` math measured seconds since *UTC* midnight,
# which with TZ=Asia/Beirut made sessions outlive the 00:00 local reset by ~3h.
now=$(date +%s)
midnight=$(date -d "tomorrow 00:00" +%s 2>/dev/null || date -d "tomorrow 00:00:00" +%s)
echo $(( midnight - now ))
