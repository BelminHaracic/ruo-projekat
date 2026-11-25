#!/usr/bin/env bash
# Demonstracija drifta DNS zapisa (AO-8):
# 1) mimo Terraforma (nsupdate) promijenim backend zapis
# 2) terraform plan pokaže razliku
# 3) terraform apply vrati stanje iz koda
set -euo pipefail
cd "$(dirname "$0")/.."
VM_IP=$(terraform -chdir=terraform/vm output -raw vm_ip)

# privremeni key fajl, da tajna ne bude u komandnoj liniji
KEY=$(mktemp); chmod 600 "$KEY"; trap 'rm -f "$KEY"' EXIT
TSIG=$(cd ansible && ansible-vault view group_vars/app/vault.yml | awk -F'"' '/vault_tsig_secret/{print $2}')
printf 'key "ruo-tf" { algorithm hmac-sha256; secret "%s"; };\n' "$TSIG" > "$KEY"

echo "### prije: $(dig @"$VM_IP" backend.biljeznica.lab +short)"

printf 'server %s\nzone biljeznica.lab\nupdate delete backend.biljeznica.lab. A\nupdate add backend.biljeznica.lab. 300 A 172.28.2.99\nsend\n' "$VM_IP" | nsupdate -k "$KEY"
echo "### nakon rucne izmjene: $(dig @"$VM_IP" backend.biljeznica.lab +short)"

echo "### terraform plan"
./scripts/tf-dns.sh plan -no-color || true

echo "### terraform apply"
./scripts/tf-dns.sh apply -auto-approve -no-color

echo "### poslije ispravke: $(dig @"$VM_IP" backend.biljeznica.lab +short)"
echo "### ponovni plan"
./scripts/tf-dns.sh plan -no-color
