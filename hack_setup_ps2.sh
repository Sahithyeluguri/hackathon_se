#!/usr/bin/env bash
# PS-2 Flatland setup. Run inside WSL2 Ubuntu with Docker Desktop running (WSL integration on).
# Run this at home with good internet: it pre-builds the lab images so the venue Wi-Fi doesn't matter.
set -u
cd "$(dirname "$0")"
docker version >/dev/null 2>&1 || { echo "Docker not reachable. Start Docker Desktop + enable WSL integration."; exit 1; }

echo "== Host packages (analysis only; attacks run inside containers) =="
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y git jq curl nmap tshark tcpdump nftables zip

echo "== Pull base images + pre-build lab images =="
docker pull debian:12-slim && docker pull postgres:16
docker compose -p flat -f docker-compose.flat.yml build
docker compose -p seg  -f docker-compose.seg.yml  build

echo "== Smoke test (both labs) =="
./run.sh flat up && ./run.sh flat attack && ./run.sh flat business && ./run.sh flat down
./run.sh seg  up && ./run.sh seg  attack && ./run.sh seg  business && ./run.sh seg fw && ./run.sh seg down
echo "Expected: flat = 5/5 attacks + DATA TAMPERED; seg = 0/5 attacks + DATA INTACT; business 10/10 in both."
