# ledger deploy stack

Self-host on a small always-on box (Mac mini / Raspberry Pi). Brings up Postgres, runs migrations
once, and starts the API. Expose it to your phone with a Cloudflare Tunnel — no ports opened on your
router, free TLS, a stable hostname.

## Run

```bash
cp .env.example .env        # set POSTGRES_PASSWORD and API_TOKEN (openssl rand -hex 32)
docker compose up -d --build
docker compose logs -f api
```

The `migrate` service applies migrations and exits before `api` starts. Re-running `up` re-applies any
new migrations.

## Cloudflare Tunnel

Point a tunnel at the API container's published port (`API_PORT`, default `48080`):

```bash
cloudflared tunnel create ledger
# route a hostname to the tunnel, then in the tunnel config:
#   ingress:
#     - hostname: ledger.example.com
#       service: http://localhost:48080
#     - service: http_status:404
cloudflared tunnel run ledger
```

Set the iOS app's server URL to `https://ledger.example.com` and its token to your `API_TOKEN`.

For an extra layer, put Cloudflare Access in front of the hostname so only your identity reaches the
origin — the bearer token still gates the API itself.

## Backups

Everything lives in Postgres under `LEDGER_DATA_DIR`. Back it up with `pg_dump`:

```bash
docker compose exec postgres pg_dump -U ledger ledger | gzip > ledger-$(date +%F).sql.gz
```
