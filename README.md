# fabric-ru: FabriC++ Russia homeserver

The Russia version of FabriC++'s server: a closed Matrix homeserver at **https://ru.infinitumfabric.app**, running on Yandex Cloud (VM `fabric-russia`, zone ru-central1-d).

Fabric's main deployment (infinitumfabric.app on Cloudflare) is unchanged. This repo is an additional Russia deployment, not a move. The app code stays in [InfinitumCorp/fabric](https://github.com/InfinitumCorp/fabric); this repo holds what is different for Russia.

## What is different from the main server

| | Russia (`ru.infinitumfabric.app`) |
|---|---|
| Hosting | Yandex Cloud, static IP, Cloudflare DNS-only A record |
| Registration | Closed (no token: 403) |
| Federation | Off (listener removed, empty whitelist, no trusted key servers) |
| Public surface | Only `/_matrix/client`, `/_synapse/client` and `/.well-known/matrix/client`; admin API and everything else 404 |
| TLS | nginx + Let's Encrypt (webroot), auto-renew with an nginx reload hook |
| Backups | Nightly `pg_dump` at 23:40 UTC, then a Yandex disk snapshot at 00:00 UTC (7 kept of each) |

`server_name` is `ru.infinitumfabric.app` and is permanent: it is part of every user ID.

## Layout

- `server/docker-compose.yml`: Postgres 16 + Synapse v1.164.2 (Synapse on 127.0.0.1:8008 only).
- `server/homeserver.russia.yaml`: the Russia-only Synapse settings, appended to the generated config.
- `scripts/setup-server.sh`: Docker, `/opt/fabric`, generated secrets, Synapse config, start.
- `scripts/setup-tls.sh`: nginx + Let's Encrypt and the public routing rules.
- `scripts/setup-backups.sh`: the nightly database dump (systemd timer).
- `scripts/check.sh`: outside checks; also runs from the `check` workflow on demand.

All scripts are re-runnable. Run them on the server in this order: `setup-server.sh`, `setup-tls.sh`, `setup-backups.sh`.

```bash
ssh fabric-russia
git clone https://github.com/InfinitumCorp/fabric-ru && cd fabric-ru
sudo bash scripts/setup-server.sh && bash scripts/setup-tls.sh && bash scripts/setup-backups.sh
```

## Secrets

None are in this repo (it is public). The DB password lives only in `/opt/fabric/.env` (mode 600). Synapse's keys (`registration_shared_secret`, `macaroon_secret_key`, `form_secret`, the signing key) are generated on the server in `/opt/fabric/data`. Never commit either.

## Restore

- Database: stop `synapse`, then `docker compose exec -T db pg_restore -U synapse -d synapse --clean < /var/backups/fabric/synapse-YYYYMMDD.dump`.
- Whole server: create a disk from the newest `daily-data-servers` snapshot in Yandex Cloud, then a VM from that disk, and move the static IP to it.

## Sign-in

Fabric signs people in with Cumulus ID (id.cumuluscloud.app), which loads from inside Yandex Cloud without a VPN. Consumer ISPs in Russia are not yet tested.

The homeserver itself signs people in with Cumulus://ID only (`server/homeserver.cumulus-id.yaml`, appended by `setup-server.sh`): Synapse's OIDC provider against `https://id.cumuluscloud.app/realms/cumulus` as the public client `fabric` (no secret, PKCE S256), with password sign-in off. Clients see the `m.login.sso` flow; the callback is `https://ru.infinitumfabric.app/_synapse/client/oidc/callback`, served through the existing `/_synapse/client` route. A Matrix user's localpart is their Cumulus ID username. An account that was created with a password before this change cannot sign in until it is linked (`allow_existing_users` stays off so a username alone never takes over an account).

Server inventory, costs and the firewall: `infra/yandex-cloud.md` in InfinitumCorp/infinitum-revenue.
