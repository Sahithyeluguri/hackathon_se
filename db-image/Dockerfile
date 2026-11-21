# Postgres 16 + sshd (so the "SSH to the database host" attack has a target).
FROM postgres:16
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssh-server iproute2 nftables ulogd2 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash it && echo 'it:Summer2024' | chpasswd && mkdir -p /run/sshd
ENTRYPOINT ["/bin/bash", "/lab/db-entry.sh"]
CMD ["postgres"]
