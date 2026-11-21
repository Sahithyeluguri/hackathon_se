#!/bin/bash
# Business flow test - runs on the HOST, executes each flow from its real source container.
# Usage: bash lab/business.sh "<docker compose command prefix>"
dc="$1"
SSH="sshpass -p Summer2024 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR"
pass=0; total=0
flow(){ local name="$1" src="$2" expect="$3" cmd="$4"; total=$((total+1))
  out=$($dc exec -T "$src" bash -c "$cmd" 2>&1)
  if grep -q -- "$expect" <<<"$out"; then echo "PASS  $name"
    pass=$((pass+1)); else echo "FAIL  $name   -> $(tr '\n' ' ' <<<"$out" | head -c 160)"; fi; }

echo "=== Flatland business test $(date -Is) ==="
flow "B1 ws    -> web:443   HTTPS reachable"           ws    "web ok"  "curl -sk --max-time 5 https://web/web-health"
flow "B2 ws    -> Employee Portal (web->app->db)"     ws    "db ok"   "curl -sk --max-time 12 https://web/"
flow "B3 web   -> app:8080  API"                       web   "app ok"  "curl -s --max-time 5 http://app:8080/health"
flow "B4 app   -> db:5432   SQL"                       app   "4242"    "PGCONNECT_TIMEOUT=5 PGPASSWORD=AppDb2024 psql -h db -U appuser -d corp -tAc 'select 4242'"
flow "B5 app   -> files:445 SMB report share"          app   "blocks"  "smbclient //files/share -U it%Summer2024 -c ls"
for h in ws web app db files; do
flow "B6 admin -> $h:22 SSH management"                admin "^$h\$"   "$SSH it@$h hostname"
done
echo "=== RESULT: $pass/$total business flows passed ==="
