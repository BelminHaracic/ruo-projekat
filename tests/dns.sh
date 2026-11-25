#!/usr/bin/env bash
# dig upiti prema BIND serveru na VM-u (AO-7, AO-8). Pokreće se s hosta.
# Primjer: ./tests/dns.sh 192.168.122.17
IP=${1:?treba IP adresa VM-a}
D="dig @$IP +time=2 +tries=1 +short"
ok=0
for ime in frontend backend db ns; do
  # PASS samo ako je odgovor stvarno IP adresa (ne poruka o gresci)
  odg=$($D "$ime.biljeznica.lab" A 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+){3}$')
  if [ -n "$odg" ]; then echo "PASS $ime.biljeznica.lab -> $odg"; else echo "FAIL $ime.biljeznica.lab"; ok=1; fi
done
echo "TXT: $($D biljeznica.lab TXT 2>/dev/null)"
echo "SOA: $($D biljeznica.lab SOA 2>/dev/null)"

# izmjena bez TSIG kljuca mora biti odbijena
odg=$(printf 'server %s\nzone biljeznica.lab\nupdate add test.biljeznica.lab 60 A 10.0.0.1\nsend\n' "$IP" | nsupdate 2>&1)
if echo "$odg" | grep -q REFUSED; then echo "PASS update bez kljuca -> REFUSED"; else echo "FAIL update bez kljuca: $odg"; ok=1; fi
exit $ok
