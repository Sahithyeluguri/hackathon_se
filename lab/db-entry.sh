#!/bin/bash
[ -n "${GW:-}" ] && ip route replace default via "$GW"
ssh-keygen -A >/dev/null 2>&1; /usr/sbin/sshd
# Stretch: host-based micro-segmentation on the database
if [ "${MICROSEG:-0}" = 1 ]; then
  mkdir -p /var/log/ulog; ulogd -d
  nft -f /lab/conf/db-host.nft || sed 's/log group 0 prefix "[^"]*" //' /lab/conf/db-host.nft | nft -f -
fi
exec docker-entrypoint.sh "$@"
