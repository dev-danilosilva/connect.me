#!/bin/sh
# Run by the nginx image's entrypoint (from /docker-entrypoint.d/) before nginx
# starts. certbot renews the certificate on disk, but nginx keeps the one it
# loaded in memory until reloaded, so reload periodically in the background.
# Reloading is graceful: in-flight requests finish on the old workers.
interval="${NGINX_RELOAD_INTERVAL:-21600}"  # seconds; default 6h

(
    while :; do
        sleep "$interval"
        nginx -s reload
    done
) &
