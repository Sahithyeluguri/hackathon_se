# One image for every host except the database.
FROM debian:12-slim
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssh-server openssh-client sshpass nmap smbclient samba curl ca-certificates \
      netcat-openbsd iproute2 iputils-ping nftables ulogd2 nginx openssl python3 \
      postgresql-client tcpdump procps \
 && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash it && echo 'it:Summer2024' | chpasswd \
 && mkdir -p /run/sshd /srv/share && chown it:it /srv/share \
 && openssl req -x509 -nodes -newkey rsa:2048 -days 365 -subj "/CN=web.corp.lab" \
      -keyout /etc/ssl/private/web.key -out /etc/ssl/certs/web.crt 2>/dev/null
ENTRYPOINT ["/bin/bash", "/lab/entry.sh"]
