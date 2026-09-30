#!/usr/bin/env bash
# One-time setup of a fresh Ubuntu/Debian GCP VM for Tarajuu.
# Run on the VM from the repo root:  bash deploy/setup-vm.sh
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v docker >/dev/null; then
  echo "==> Installing Docker"
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER" || true
fi

if [ ! -f .env ]; then
  echo "==> Creating deploy/.env with generated secrets"
  IP=$(curl -fsS -H 'Metadata-Flavor: Google' \
    http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip \
    || curl -fsS https://api.ipify.org)
  cp .env.example .env
  sed -i "s|^DOMAIN=.*|DOMAIN=${IP//./-}.sslip.io|" .env
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 24)|" .env
  sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$(openssl rand -hex 32)|" .env
fi

echo "==> Building and starting"
sudo docker compose up -d --build
sudo docker compose ps
DOMAIN=$(grep '^DOMAIN=' .env | cut -d= -f2 )
echo
echo "API: https://${DOMAIN}/api/health  (first HTTPS request may take ~30s while the certificate is issued)"
