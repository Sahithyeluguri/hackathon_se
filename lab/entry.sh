#!/bin/bash
# Common start-up for all lab hosts. ROLE decides which services run.
# GW (optional) = router IP; used only in the segmented lab.
[ -n "${GW:-}" ] && ip route replace default via "$GW"
ssh-keygen -A >/dev/null 2>&1

load_nft() {   # load a ruleset; if NFLOG logging is unsupported by the kernel, retry without it
  nft -f "$1" 2>/tmp/nft.err && return 0
  echo "WARN: $(cat /tmp/nft.err) -- retrying without NFLOG log statements"
  sed 's/log group 0 prefix "[^"]*" //' "$1" | nft -f - && echo "WARN: loaded without logging (use counters)"
}

case "${ROLE:-}" in
  router)
    mkdir -p /var/log/ulog; ulogd -d
    [ "${FW:-0}" = 1 ] && load_nft /lab/conf/router.nft
    ;;
  web)
    cp /lab/conf/nginx-web.conf /etc/nginx/sites-enabled/default
    nginx; /usr/sbin/sshd ;;
  app)
    nohup python3 /lab/app.py >/var/log/app.log 2>&1 &
    /usr/sbin/sshd ;;
  files)
    cp /lab/conf/smb.conf /etc/samba/smb.conf
    printf 'Summer2024\nSummer2024\n' | smbpasswd -s -a it >/dev/null
    smbd -D; /usr/sbin/sshd ;;
  ws|admin)
    /usr/sbin/sshd ;;
esac
echo "[$ROLE] up: $(hostname -I) default via $(ip route | awk '/default/{print $3}')"
exec sleep infinity
