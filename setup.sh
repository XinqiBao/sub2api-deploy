#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
cd "$script_dir"
umask 077

if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: openssl is required." >&2
  exit 1
fi

if [ -e .env ]; then
  echo ".env already exists; leaving it unchanged."
else
  cp .env.example .env
  postgres_password="$(openssl rand -hex 32)"
  redis_password="$(openssl rand -hex 32)"
  admin_password="$(openssl rand -hex 12)"
  jwt_secret="$(openssl rand -hex 32)"
  totp_key="$(openssl rand -hex 32)"

  sed -i.bak \
    -e "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${postgres_password}/" \
    -e "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=${redis_password}/" \
    -e "s/^ADMIN_PASSWORD=.*/ADMIN_PASSWORD=${admin_password}/" \
    -e "s/^JWT_SECRET=.*/JWT_SECRET=${jwt_secret}/" \
    -e "s/^TOTP_ENCRYPTION_KEY=.*/TOTP_ENCRYPTION_KEY=${totp_key}/" \
    .env
  rm -f .env.bak
  chmod 600 .env
  echo "Created .env with generated database and application secrets."
fi

mkdir -p data postgres_data redis_data tailscale/state backups

echo "Deployment is ready. Start it with: docker compose -f docker-compose.yaml up -d"
echo "Web UI: http://<NAS-IP>:$(sed -n 's/^SERVER_PORT=//p' .env)"
echo "Admin email: $(sed -n 's/^ADMIN_EMAIL=//p' .env)"
echo "Admin password: $(sed -n 's/^ADMIN_PASSWORD=//p' .env)"
echo "Tailscale will wait for first-time registration until TS_AUTHKEY is set."
