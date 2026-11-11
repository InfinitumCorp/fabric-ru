#!/bin/bash
# HTTPS for Fabric Russia: nginx + Let's Encrypt in front of Synapse (127.0.0.1:8008). Re-runnable.
# Needs the A record ru.infinitumfabric.app -> the server's static IP first.
set -euo pipefail
DOMAIN=ru.infinitumfabric.app

if ! command -v nginx >/dev/null || ! command -v certbot >/dev/null; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get -qq update >/dev/null
  sudo DEBIAN_FRONTEND=noninteractive apt-get -qq install -y nginx certbot >/dev/null
fi
sudo mkdir -p /var/www/acme

# Step 1: plain HTTP site that only serves ACME challenges and redirects the rest.
sudo tee /etc/nginx/sites-available/default >/dev/null <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $DOMAIN _;
    server_tokens off;
    location /.well-known/acme-challenge/ { root /var/www/acme; }
    location / { return 301 https://$DOMAIN\$request_uri; }
}
EOF
sudo nginx -t -q && sudo systemctl reload nginx

if ! sudo test -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem; then
  sudo certbot certonly --webroot -w /var/www/acme -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email --quiet
fi

# Step 2: HTTPS site. Only Matrix client endpoints reach Synapse; admin API stays local.
sudo tee /etc/nginx/sites-available/fabric-russia >/dev/null <<EOF
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name $DOMAIN;
    server_tokens off;

    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options nosniff always;

    client_max_body_size 50M;

    location = /.well-known/matrix/client {
        default_type application/json;
        add_header Access-Control-Allow-Origin * always;
        return 200 '{"m.homeserver":{"base_url":"https://$DOMAIN"}}';
    }
    location /_synapse/admin { return 404; }
    location ~ ^(/_matrix/client|/_synapse/client) {
        proxy_pass http://127.0.0.1:8008;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
        proxy_http_version 1.1;
    }
    location / { return 404; }
}
EOF
sudo ln -sf /etc/nginx/sites-available/fabric-russia /etc/nginx/sites-enabled/fabric-russia
sudo nginx -t -q && sudo systemctl reload nginx

# Reload nginx when certbot renews (certbot's systemd timer handles renewal).
echo -e '#!/bin/sh\nsystemctl reload nginx' | sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh >/dev/null
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

echo "cert: $(sudo openssl x509 -in /etc/letsencrypt/live/$DOMAIN/fullchain.pem -noout -enddate)"
echo "renew timer: $(systemctl is-active certbot.timer)"
