#!/usr/bin/env bash
# Test izolacije slojeva (AO-6). Pokreće se NA VM-u:
#   ssh student@<vm_ip> 'bash -s' < tests/izolacija.sh
# exec dobija </dev/null jer bi inace pojeo ostatak skripte sa stdin-a
# Sve adrese su DNS imena iz zone biljeznica.lab (AO-7).
cd /opt/biljeznica || exit 1
dc="sudo docker compose"
ok=0

echo "== 1: frontend -> backend.biljeznica.lab:8000 mora PROCI (kontrola da nc radi)"
if $dc exec -T frontend nc -z -w2 backend.biljeznica.lab 8000 </dev/null; then echo PASS; else echo FAIL; ok=1; fi

echo "== 2: frontend razrjesava db.biljeznica.lab (DNS radi, pa pad u testu 3 nije zbog imena)"
$dc exec -T frontend nslookup db.biljeznica.lab </dev/null 2>&1 | grep -A1 "Name:"

echo "== 3: frontend -> db.biljeznica.lab:5432 mora PASTI (nema mreznog puta)"
if $dc exec -T frontend nc -z -w2 db.biljeznica.lab 5432 </dev/null; then echo FAIL; ok=1; else echo PASS; fi

echo "== 4: backend -> db.biljeznica.lab:5432 mora PROCI"
if $dc exec -T backend python -c "import socket;socket.create_connection(('db.biljeznica.lab',5432),2)" </dev/null; then echo PASS; else echo FAIL; ok=1; fi

echo "== 5: port 5432 nije otvoren na VM-u"
if sudo ss -ltn | grep -q ':5432 '; then echo FAIL; ok=1; else echo PASS; fi

echo "== 6: podaci baze su na volumenu (AO-10)"
sudo docker volume inspect biljeznica_pgdata --format '{{ .Mountpoint }}' && echo PASS || { echo FAIL; ok=1; }

exit $ok
