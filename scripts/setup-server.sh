#!/bin/bash
# Fabric Russia homeserver: Docker, Postgres and Synapse in /opt/fabric. Re-runnable.
# Secrets (DB password, Synapse keys) are generated on the server and never leave it.
# Usage on the server: sudo bash scripts/setup-server.sh   (from a checkout of this repo)
set -euo pipefail
SERVER_NAME=ru.infinitumfabric.app
HERE=$(cd "$(dirname "$0")/.." && pwd)
DIR=${FABRIC_DIR:-/opt/fabric}

if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get -qq update >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get -qq install -y docker.io docker-compose-v2 >/dev/null
  systemctl enable --now docker >/dev/null
fi

install -d -m 0755 "$DIR"
install -m 0644 "$HERE/server/docker-compose.yml" "$DIR/docker-compose.yml"
if [ ! -f "$DIR/.env" ]; then
  install -m 0600 /dev/null "$DIR/.env"
  echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)" > "$DIR/.env"
fi
cd "$DIR"

if [ ! -f data/homeserver.yaml ]; then
  docker run --rm -v "$DIR/data:/data" -e SYNAPSE_SERVER_NAME=$SERVER_NAME -e SYNAPSE_REPORT_STATS=no \
    matrixdotorg/synapse:v1.164.2 generate >/dev/null
  # Postgres instead of the generated SQLite block.
  pw=$(sed -n 's/^POSTGRES_PASSWORD=//p' .env)
  python3 - "$DIR/data/homeserver.yaml" "$pw" <<'PY'
import re, sys
path, pw = sys.argv[1], sys.argv[2]
text = open(path).read()
pg = ("database:\n  name: psycopg2\n  args:\n    user: synapse\n    password: %s\n"
      "    database: synapse\n    host: db\n    cp_min: 5\n    cp_max: 10\n" % pw)
text = re.sub(r"database:\n(?:  .*\n)+", pg, text, count=1)
# Client API only: drop the federation listener resource (either YAML style Synapse may emit).
text = re.sub(r"\n\s*- federation\n", "\n", text)
text = text.replace("names: [client, federation]", "names: [client]")
if "federation" in text.split("database:")[0]:
    sys.exit("federation is still in the listener block")
open(path, "w").write(text)
PY
fi
if ! grep -q "Infinitum Fabric (Russia)" data/homeserver.yaml; then
  cat "$HERE/server/homeserver.russia.yaml" >> data/homeserver.yaml
fi

docker compose up -d --quiet-pull
for _ in $(seq 1 60); do curl -fsS http://127.0.0.1:8008/health >/dev/null 2>&1 && break; sleep 2; done
echo "synapse health: $(curl -s http://127.0.0.1:8008/health)"
