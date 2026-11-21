#!/usr/bin/env bash
# Flatland control script.  Usage: ./run.sh <flat|seg> <up|down|reset|attack|business|integrity|fw|status>
set -u
mode=${1:?usage: ./run.sh flat|seg up|down|reset|attack|business|integrity|fw|status}
cmd=${2:?usage: ./run.sh flat|seg up|down|reset|attack|business|integrity|fw|status}
cd "$(dirname "$0")"
dc="docker compose -p $mode -f docker-compose.$mode.yml"
mkdir -p evidence; ts=$(date +%H%M%S)
case $cmd in
  up)     $dc up -d --build; sleep 6; $dc ps --format 'table {{.Service}}\t{{.Status}}' ;;
  down)   $dc down -v ;;
  reset)  $dc down -v; $dc up -d --build; sleep 6 ;;   # fresh, untampered data
  status) $dc ps; $dc logs --tail 3 ;;
  attack)
    $dc exec -d ws sh -c 'tcpdump -i any -nn -w /tmp/attack.pcap >/dev/null 2>&1'; sleep 1
    $dc exec -T ws bash /lab/attack.sh | tee "evidence/attack_${mode}_$ts.txt"
    $dc exec -T ws pkill tcpdump; sleep 1
    docker cp "$($dc ps -q ws)":/tmp/attack.pcap "evidence/attack_${mode}_$ts.pcap" >/dev/null && echo "pcap -> evidence/attack_${mode}_$ts.pcap"
    echo; bash lab/integrity.sh "$dc" | tee -a "evidence/attack_${mode}_$ts.txt" ;;
  integrity)
    bash lab/integrity.sh "$dc" | tee "evidence/integrity_${mode}_$ts.txt" ;;
  business)
    bash lab/business.sh "$dc" | tee "evidence/business_${mode}_$ts.txt" ;;
  fw)
    [ "$mode" = seg ] || { echo "fw only exists in seg mode"; exit 1; }
    $dc exec -T router nft list table inet lab | tee "evidence/ruleset_counters_$ts.txt"
    echo "--- last dropped packets (NFLOG via ulogd) ---"
    $dc exec -T router sh -c 'tail -n 40 /var/log/ulog/syslogemu.log 2>/dev/null || echo "no log file (see counters above)"' \
      | tee "evidence/fw_drops_$ts.txt" ;;
  *) echo "unknown command $cmd"; exit 1 ;;
esac
