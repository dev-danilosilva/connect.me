#!/usr/bin/env bash
# One-time bootstrap for Let's Encrypt certificates via nginx + certbot.
#
# Requirements before running this:
#   - DOMAIN's DNS A/AAAA record must already point at this server's public IP.
#   - Ports 80 and 443 must be reachable from the internet.
#   - DOMAIN and LETSENCRYPT_EMAIL must be set in .env.
#
# Usage: ./init-letsencrypt.sh

set -euo pipefail
cd "$(dirname "$0")"

COMPOSE="docker compose -f docker-compose.prod.yml"

if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

if [ -z "${DOMAIN:-}" ] || [ -z "${LETSENCRYPT_EMAIL:-}" ]; then
    echo "DOMAIN and LETSENCRYPT_EMAIL must be set in .env" >&2
    exit 1
fi

CERT_PATH="/etc/letsencrypt/live/$DOMAIN"

echo "### Creating a dummy certificate so nginx can start ..."
$COMPOSE run --rm --entrypoint sh certbot -c "
  mkdir -p '$CERT_PATH' &&
  apk add --no-cache openssl >/dev/null 2>&1
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout '$CERT_PATH/privkey.pem' \
    -out '$CERT_PATH/fullchain.pem' \
    -subj '/CN=localhost'
"

echo "### Starting nginx with the dummy certificate ..."
$COMPOSE up -d nginx

echo "### Deleting dummy certificate ..."
$COMPOSE run --rm --entrypoint sh certbot -c "rm -rf '$CERT_PATH'"

echo "### Requesting the real Let's Encrypt certificate ..."
$COMPOSE run --rm certbot certonly --webroot -w /var/www/certbot \
    -d "$DOMAIN" \
    --email "$LETSENCRYPT_EMAIL" \
    --rsa-key-size 2048 \
    --agree-tos \
    --non-interactive

echo "### Reloading nginx with the real certificate ..."
$COMPOSE exec nginx nginx -s reload

echo "Done. $DOMAIN is now serving over HTTPS."
