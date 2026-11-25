#!/usr/bin/env bash
# Pokreće terraform u terraform/dns s IP adresom DNS servera i TSIG tajnom.
# Tajna se čita iz ansible-vaulta i ide samo kroz env varijablu (ne u fajl, ne u Git).
# Primjer: ./scripts/tf-dns.sh plan
set -euo pipefail
cd "$(dirname "$0")/.."

TSIG=$(cd ansible && ansible-vault view group_vars/app/vault.yml | awk -F'"' '/vault_tsig_secret/{print $2}')
VM_IP=$(terraform -chdir=terraform/vm output -raw vm_ip)

export TF_VAR_tsig_secret="$TSIG"
export TF_VAR_dns_server="$VM_IP"
terraform -chdir=terraform/dns "$@"
