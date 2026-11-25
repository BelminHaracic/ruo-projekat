#!/usr/bin/env bash
# Provjera da aplikacija odgovara izvana (samo frontend je objavljen, port 8080).
# Primjer: ./tests/aplikacija.sh 192.168.122.17
IP=${1:?treba IP adresa VM-a}
URL="http://$IP:8080"
ok=0

if curl -sf "$URL/api/ready"; then echo "  PASS ready"; else echo "FAIL ready"; ok=1; fi

id=$(curl -sf -X POST "$URL/api/notes" -H 'Content-Type: application/json' \
  -d '{"tekst":"test iz make test"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')
if [ -n "$id" ]; then echo "PASS dodana biljeska id=$id"; else echo "FAIL dodavanje"; ok=1; fi

if curl -sf "$URL/api/notes" | grep -q "test iz make test"; then echo "PASS biljeska se vidi u listi"; else echo "FAIL lista"; ok=1; fi
curl -sf -X DELETE "$URL/api/notes/$id" >/dev/null && echo "PASS obrisana biljeska $id"

# baza ne smije biti dostupna izvana
if timeout 3 bash -c "echo > /dev/tcp/$IP/5432" 2>/dev/null; then echo "FAIL 5432 dostupan izvana"; ok=1; else echo "PASS 5432 nije dostupan izvana"; fi
exit $ok
