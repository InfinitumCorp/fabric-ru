#!/bin/bash
# Nightly pg_dump of Fabric Russia's Synapse DB at 23:40 UTC, 20 min before the 00:00 UTC disk snapshot.
set -euo pipefail
sudo install -d -m 0700 /var/backups/fabric
sudo tee /usr/local/sbin/fabric-pgdump >/dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
out=/var/backups/fabric/synapse-$(date -u +%Y%m%d).dump
docker compose -f /opt/fabric/docker-compose.yml exec -T db pg_dump -U synapse -Fc synapse > "$out.tmp"
mv "$out.tmp" "$out"
ls -1t /var/backups/fabric/synapse-*.dump | tail -n +8 | xargs -r rm -f
echo "dumped $out ($(stat -c %s "$out") bytes)"
EOF
sudo chmod 0750 /usr/local/sbin/fabric-pgdump
sudo tee /etc/systemd/system/fabric-pgdump.service >/dev/null <<'EOF'
[Unit]
Description=Fabric Russia Synapse database dump
After=docker.service
[Service]
Type=oneshot
UMask=0077
ExecStart=/usr/local/sbin/fabric-pgdump
EOF
sudo tee /etc/systemd/system/fabric-pgdump.timer >/dev/null <<'EOF'
[Unit]
Description=Nightly Fabric Russia database dump (before the 00:00 UTC snapshot)
[Timer]
OnCalendar=*-*-* 23:40:00 UTC
Persistent=true
[Install]
WantedBy=timers.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now fabric-pgdump.timer >/dev/null 2>&1
sudo systemctl start fabric-pgdump.service
sudo journalctl -u fabric-pgdump.service -n 3 --no-pager | tail -2
sudo ls -l /var/backups/fabric
sudo docker run --rm -v /var/backups/fabric:/b:ro postgres:16 pg_restore --list /b/synapse-$(date -u +%Y%m%d).dump | grep -c "TABLE DATA" | sed 's/^/tables in dump: /'
systemctl list-timers fabric-pgdump.timer --no-pager | sed -n 2p
