#!/usr/bin/env bash
cd "$(dirname "$0")/../app" || exit 1
ok=0
echo "== Test 1: frontend -> db mora PASTI"
if docker compose exec -T frontend sh -c 'nc -zv -w2 db 5432' 2>&1; then echo "FAIL"; ok=1; else echo "PASS"; fi
echo "== Test 2: backend -> db mora PROCI"
if docker compose exec -T backend python -c "import socket;socket.create_connection(('db',5432),2)"; then echo "PASS"; else echo "FAIL"; ok=1; fi
echo "== Test 3: db port nije objavljen na hostu"
if nc -z -w2 localhost 5432 2>/dev/null; then echo "FAIL"; ok=1; else echo "PASS"; fi
echo "== Test 4: aplikacija odgovara"
if curl -sf localhost:8080/api/ready >/dev/null; then echo "PASS"; else echo "FAIL"; ok=1; fi
exit $ok
