#!/bin/bash
# Data integrity check - runs on the HOST. Reads the table from inside the db container
# (trusted path, not over the network) and compares it with the known-good baseline.
# Usage: bash lab/integrity.sh "<docker compose command prefix>"
dc="$1"
cur=$($dc exec -T db psql -U appuser -d corp -tA -F '|' -c "select id,name,dept,role,salary from employees order by id" 2>&1)
base=$(cat "$(dirname "$0")/conf/employees.baseline")
echo "=== Data integrity check $(date -Is) ==="
if [ "$cur" = "$base" ]; then
  echo "DATA INTACT: all $(wc -l <<<"$base") employee records match the baseline"
else
  echo "DATA TAMPERED: changed records (- baseline / + current):"
  diff <(echo "$base") <(echo "$cur") | grep '^[<>]' | sed 's/^< /  - /; s/^> /  + /'
fi
