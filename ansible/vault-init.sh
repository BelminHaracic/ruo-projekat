#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
mkdir -p group_vars/app
[ -f .vault_pass ] || { openssl rand -base64 24 > .vault_pass; chmod 600 .vault_pass; }
if [ ! -f group_vars/app/vault.yml ]; then
  printf 'vault_postgres_password: "%s"\nvault_tsig_secret: "%s"\n' "$(openssl rand -hex 16)" "$(openssl rand -base64 32)" > group_vars/app/vault.yml
  ansible-vault encrypt group_vars/app/vault.yml
fi
