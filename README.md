# Sub2API NAS Deployment

Reusable Docker Compose deployment for [Sub2API](https://github.com/Wei-Shaw/sub2api), with an optional dedicated Tailscale identity for private remote access. PostgreSQL, Redis, application data, and Tailscale state are stored in local directories so the deployment is easy to back up and move.

The two supported access paths are:

- LAN: `http://NAS-IP:18080`
- Tailnet: `https://sub2api.<tailnet-name>.ts.net`

The Tailscale endpoint uses HTTPS but is not public. It is reachable only by devices and people authorized in the Tailnet; Tailscale Funnel is explicitly disabled.
Entering the Tailnet hostname without a scheme is also supported: HTTP port 80 only sends a permanent redirect to the HTTPS URL and never proxies application traffic directly.

## Deployment model

The Git repository is the source of truth for the versioned deployment files. Each deployment host keeps its own untracked `.env` and runtime directories. Do not commit or overwrite `.env`, `data/`, `postgres_data/`, `redis_data/`, or `tailscale/state/` when synchronizing repository changes.

## Requirements

- A NAS or Linux server with Docker Engine, Docker Compose v2, and `/dev/net/tun`
- Git and OpenSSL
- About 2 GB of free memory as a practical starting point
- A Tailscale account if private remote access is wanted

## First deployment

If Git is installed on the server:

```bash
git clone <repository-url>
cd sub2api-deploy
./setup.sh
docker compose up -d
docker compose ps
```

If the NAS does not provide Git, download the repository archive on another computer, extract it, and upload the project files with the NAS file manager. Do not upload `data/`, `postgres_data/`, or `redis_data/` from a running deployment. Then connect over SSH and run:

```bash
cd /path/to/sub2api-deploy
./setup.sh
sudo docker compose -f docker-compose.yaml up -d
sudo docker compose -f docker-compose.yaml ps
```

Open `http://NAS-IP:18080`. The setup script prints the generated admin password. It can also be read locally from `.env`:

```bash
grep -E '^ADMIN_(EMAIL|PASSWORD)=' .env
```

`setup.sh` creates `.env` with random admin, database, Redis, JWT, and TOTP secrets. It does not require a system administrator password. If your NAS restricts Docker access, prefix Docker commands with `sudo` or run them from the NAS Docker application.

The Tailscale container may wait for authentication when `TS_AUTHKEY` is empty. This does not prevent Sub2API, PostgreSQL, or Redis from starting. Complete the Tailscale setup below when remote access is wanted.

The admin account is created only during the first database initialization. Changing `ADMIN_PASSWORD` in `.env` later does not reset an existing account password; change it in the web dashboard instead.

## Tailscale setup

For a personal interactive deployment, no auth key is required:

1. In the [Tailscale DNS settings](https://login.tailscale.com/admin/dns), enable MagicDNS and HTTPS certificates.
2. Leave `TS_AUTHKEY=` empty in `.env` and start the service:

   ```bash
   sudo docker compose -f docker-compose.yaml up -d tailscale
   sudo docker compose -f docker-compose.yaml logs -f tailscale
   ```

3. Open the newest `https://login.tailscale.com/a/...` URL from the logs and authorize the `sub2api` device. Complete this promptly: until authorization succeeds, the container can restart and replace an older URL.
4. Confirm that `sub2api` appears in the [Tailscale Machines page](https://login.tailscale.com/admin/machines). Disable key expiry for this always-on server unless periodic reauthentication is preferred.
5. Open the device's MagicDNS URL, such as `https://sub2api.example-tailnet.ts.net`.

For an unattended first deployment, create a **one-off, non-ephemeral, untagged** key on the [Tailscale Keys page](https://login.tailscale.com/admin/settings/keys). Do not use a reusable key. Keep it untagged if this machine may later be shared with family members. Put it temporarily in the untracked `.env` file:

```dotenv
TS_AUTHKEY=tskey-auth-...
```

Start or recreate the service:

```bash
sudo docker compose -f docker-compose.yaml up -d --force-recreate tailscale
sudo docker compose -f docker-compose.yaml logs -f tailscale
```

After registration succeeds, set `TS_AUTHKEY=` again and recreate the service. The identity remains active because it is persisted in `tailscale/state/`:

```bash
sudo docker compose -f docker-compose.yaml up -d --force-recreate tailscale
```

Do not paste `.env`, `docker compose config`, or `docker inspect sub2api-tailscale` output into an issue or chat while an auth key is present: Docker environment inspection can reveal it. Removing the key after registration keeps this exposure short-lived.

For a family member, either invite them to the Tailnet or use **Share** on the `sub2api` machine. Machine sharing grants access only to this Tailscale node, which is the narrower choice. A tagged machine cannot be shared this way. Each person should still have a separate Sub2API account or API key.

## Daily commands

```bash
# Status
docker compose ps

# Follow application logs
docker compose logs -f sub2api

# Follow private-access logs
docker compose logs -f tailscale

# Restart everything
docker compose restart

# Stop without deleting data
docker compose down

# Start again
docker compose up -d
```

On a NAS where the SSH user cannot access `/var/run/docker.sock`, use `sudo docker compose ...` for every Docker command. The top-level Compose project name is fixed to `sub2api`, so CLI commands and a NAS Docker UI refer to the same project.

## Upgrade

Check the [Sub2API releases](https://github.com/Wei-Shaw/sub2api/releases). For a Sub2API image upgrade, update the image tag for the `sub2api` service in the Git-tracked `docker-compose.yaml` and commit the change. The Compose file is the single source of truth for the deployed Sub2API version; no matching host `.env` change is needed.

Use this image-based workflow for Docker deployments. An update started from the Sub2API dashboard replaces the executable only inside the current container and is lost when that container is recreated.

If Git is available on the deployment host, update the versioned files with `git pull --ff-only`. Otherwise, upload only the tracked files listed in the **Files and data** section. Never replace `.env` or a runtime directory with files from another machine.

After updating, compare `.env.example` with `.env` and deliberately add any new keys. Never copy `.env.example` over `.env`. Then apply the update:

```bash
cd /path/to/sub2api-deploy
sudo docker compose -f docker-compose.yaml pull
sudo docker compose -f docker-compose.yaml up -d
sudo docker compose -f docker-compose.yaml ps
```

Sub2API is pinned so its upgrades and rollbacks are visible in Git. Tailscale defaults to its official `latest` image; set `TAILSCALE_VERSION` to an explicit release in both `.env.example` and `.env` if fully reproducible upgrades are preferred.

## Backup and restore

For a consistent full backup, briefly stop the service:

```bash
docker compose down
tar -czf "backups/sub2api-$(date +%Y%m%d-%H%M%S).tar.gz" \
  .env data postgres_data redis_data tailscale/state
docker compose up -d
```

Copy the archive somewhere outside this directory. To restore, stop the stack, extract the archive into the repository directory, and start the stack again.

Do not copy `postgres_data/` while PostgreSQL is running. A live file-level copy can produce a database whose catalog references files that were never copied. Use the stop-and-archive procedure above, or use `pg_dump` for an online logical backup.

## LAN and remote access

The default `BIND_HOST=0.0.0.0` exposes host port `18080` on every NAS network interface. Devices on the home network can use `http://NAS-IP:18080` if the NAS firewall permits it. The application still listens on port `8080` inside its container. Use HTTP, not HTTPS, when accessing the host port directly.

For remote access, the `tailscale` service runs as its own Tailnet machine and proxies Tailscale HTTPS traffic to `http://sub2api:8080` over the private Docker network. It publishes no host port, advertises no subnet route or exit node, and has Tailscale Funnel disabled.

Do not forward `18080`, `8080`, or a Tailscale container port on the home router. Tailscale works through NAT without a public inbound port. Changing `18080` can avoid a local collision, but does not itself improve security.

### Clash TUN coexistence

Tailscale and a Clash-based TUN can often coexist on macOS or Windows, but this is not guaranteed: both products install routes and may manage DNS. Keep Tailscale in its normal split-tunnel mode and do not select an exit node. In the Clash client, exclude or route these destinations directly so the operating system can send them through Tailscale:

- Tailscale IPv4: `100.64.0.0/10`
- Tailscale IPv6: `fd7a:115c:a1e0::/48`
- Tailscale DNS resolver: `100.100.100.100/32`
- MagicDNS names: `+.ts.net` (exclude from fake-IP handling as well)

The exact fields differ among Clash Verge Rev, ClashX, Clash for Windows derivatives, and Mihomo-based clients. After changing them, test both paths:

```bash
tailscale ping sub2api
curl -fsS https://sub2api.<tailnet-name>.ts.net/health
curl -I https://www.google.com
```

On iOS and Android, the operating system normally permits only one active VPN tunnel. A Tailscale app and a Clash app therefore generally cannot both run in VPN/TUN mode at the same time. Use one tunnel, move the proxy function to a router, or use an app-specific proxy instead.

## NAS Docker UI notes

The repository intentionally uses `docker-compose.yaml`, which the NAS Docker application recognizes. Prefer managing this repository through SSH, or explicitly select the same file used by the NAS UI:

```bash
sudo docker compose -f docker-compose.yaml ps
sudo docker compose -f docker-compose.yaml logs -f sub2api
```

Keep only this one active Compose file. If a container was originally created from another file name, recreate the project once from `docker-compose.yaml` so the NAS UI and CLI refer to the same definition.

## Client use

### API Base URL shown by the dashboard

The dashboard setting **Admin → Settings → Site → API Base URL** is application data stored in PostgreSQL. It is not configured by this repository, `.env`, or `data/config.yaml`.

When this setting is empty, the client configuration dialog uses the origin of the page currently open in the browser. Opening the dashboard through Tailscale therefore produces the Tailnet URL, while opening it through a LAN URL can produce the LAN address. To make generated client instructions independent of the access path, set the field explicitly to the preferred root URL, without `/v1`:

```text
https://sub2api.<tailnet-name>.ts.net
```

If the Tailnet DNS name changes later, update this dashboard setting as well.

After adding upstream accounts and creating an API key in the Sub2API dashboard, use the displayed endpoint and key in an OpenAI-compatible client. A typical configuration is:

```text
Base URL: https://sub2api.<tailnet-name>.ts.net/v1
API key:  the key created in the Sub2API dashboard
```

The exact endpoint can differ by provider. Copy the endpoint shown by the dashboard for Claude, OpenAI/Codex, Gemini, or Antigravity integrations.

## Files and data

| Path | Purpose | In Git |
| --- | --- | --- |
| `docker-compose.yaml` | Sub2API, PostgreSQL, Redis, and Tailscale services | Yes |
| `.env.example` | Versioned defaults | Yes |
| `.env` | Deployment-specific secrets and settings | No |
| `tailscale/config/serve.json` | Private HTTPS proxy; Funnel is disabled | Yes |
| `tailscale/state/` | Tailscale device identity and state | No |
| `data/` | Sub2API application data | No |
| `postgres_data/` | PostgreSQL database | No |
| `redis_data/` | Redis persistence | No |

Deleting `data/`, `postgres_data/`, or `redis_data/` permanently removes service data. Deleting `tailscale/state/` removes this container's Tailscale identity and requires registering it again. Because this deployment uses bind mounts, `docker compose down -v` does not remove those directories, although it may remove unrelated named volumes added in the future.
