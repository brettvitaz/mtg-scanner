# Synology API deployment

The API runs on `root@192.168.168.251:2222` with Docker Engine 24 and
Compose 2.20. Use `/usr/local/bin/docker` in SSH sessions; Synology does not
include it in the noninteractive shell PATH.

## Layout and runtime

Everything lives under `/volume1/docker/mtg-scanner`:

- `compose.yaml`: deployed copy of `deploy/synology/compose.yaml`.
- `.env`: `MTG_SCANNER_IMAGE_TAG=<deployment commit>`; contains no credentials.
- `config/.env`: existing provider configuration, mounted read-only. Preserve it.
- `source/`: source archive used to build the image, including the Dockerfile.
- `data/mtgjson`, `data/ck_prices`, `data/pricing`: persistent runtime data.
- `artifacts/`: persistent recognition uploads, crops, responses, and metadata.
- `logs/`: rotating application log files, in addition to Docker console logs.

The image uses Python 3.14, production dependencies, and UID/GID `10001:10001`.
Uvicorn runs one worker without reload. Docker restarts the service unless it
was explicitly stopped; the health check reports health but does not itself
restart an unhealthy process. Logs rotate at three files of 10 MB each.

The existing `config/.env` is read by Pydantic rather than Compose, preserving
literal credential values. Compose overrides bind settings and container data
paths. The background pricing-refresh setting is preserved from that file.
No provider credentials or local databases are included in the image.

## Initial deployment

Run repository checks first: `make api-bootstrap`, `make api-test`, and
`make api-lint`. Commit the Docker changes in a task worktree before archiving.
From that worktree, prepare and transfer only runtime source:

```bash
commit=$(git rev-parse HEAD)
printf 'Deployment commit: %s\n' "$commit"
git archive --format=tar HEAD Dockerfile .dockerignore services/api/app \
  services/api/pyproject.toml services/api/data/pricing/model_prices.json \
  prompts packages/schemas scripts > /tmp/mtg-scanner-source.tar
ssh -p 2222 root@192.168.168.251 \
  'mkdir -p /volume1/docker/mtg-scanner/source'
ssh -p 2222 root@192.168.168.251 \
  'cat > /volume1/docker/mtg-scanner/source.tar' < /tmp/mtg-scanner-source.tar
ssh -p 2222 root@192.168.168.251 \
  'cat > /volume1/docker/mtg-scanner/compose.yaml' < deploy/synology/compose.yaml
ssh -p 2222 root@192.168.168.251 \
  'cd /volume1/docker/mtg-scanner && release=$(mktemp -d source.XXXXXX) && tar -xf source.tar -C "$release" && mv source "source.previous.$(date +%s)" && mv "$release" source'
```

Seed `data/mtgjson/mtgjson.sqlite` and `data/ck_prices/ck_prices.sqlite` from
consistent SQLite backups of the existing local databases. Use Python's
`sqlite3.Connection.backup` rather than copying a live database file. Copy the
MTGJSON `manifest.json` alongside its database. Seed
`data/pricing/model_prices.json` from the committed source copy. Do not overwrite
existing runtime data during subsequent deployments.

For initial seeding, run this locally (adjust the original checkout path if
needed). It verifies populated tables as well as SQLite integrity:

```bash
python3 - <<'PYTHON'
from pathlib import Path
import sqlite3

base = Path("/Users/brettvitaz/Development/mtg-scanner/services/api/data")
out = Path("/tmp/mtg-scanner-docker-data")
for folder, name, table in [("mtgjson", "mtgjson.sqlite", "cards"),
                            ("ck_prices", "ck_prices.sqlite", "ck_prices")]:
    source_path = base / folder / name
    target = out / folder / name
    target.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(source_path.as_uri() + "?mode=ro", uri=True) as source, sqlite3.connect(target) as backup:
        source.backup(backup)
        assert backup.execute("PRAGMA integrity_check").fetchone() == ("ok",)
        assert backup.execute(f"SELECT count(*) FROM {table}").fetchone()[0] > 0
(out / "mtgjson/manifest.json").write_bytes((base / "mtgjson/manifest.json").read_bytes())
PYTHON
COPYFILE_DISABLE=1 tar --no-xattrs -cf /tmp/mtg-scanner-data.tar -C /tmp/mtg-scanner-docker-data .
ssh -p 2222 root@192.168.168.251 \
  'mkdir -p /volume1/docker/mtg-scanner/data && tar -xf - -C /volume1/docker/mtg-scanner/data' < /tmp/mtg-scanner-data.tar
```

On the NAS, prepare ownership and configuration (replace `<commit>` with the
commit printed above). These commands assume the initial data transfer is done:

```bash
cd /volume1/docker/mtg-scanner
mkdir -p data/mtgjson data/ck_prices data/pricing artifacts logs
# Only for initial setup, if pricing has not been seeded:
test -f data/pricing/model_prices.json || cp source/services/api/data/pricing/model_prices.json data/pricing/
chown -R 10001:10001 data artifacts logs
chown root:10001 config/.env
chmod 640 config/.env
printf 'MTG_SCANNER_IMAGE_TAG=%s\n' '<commit>' > .env
/usr/local/bin/docker compose config --quiet
/usr/local/bin/docker compose build
/usr/local/bin/docker compose up -d
/usr/local/bin/docker compose ps
curl --fail http://127.0.0.1:8001/health
```

If Synology ACLs prevent the container user from accessing the files, adjust
permissions only for this project directory. Do not change other Docker apps.

## HTTPS reverse proxy

In DSM, open **Control Panel → Login Portal → Advanced → Reverse Proxy**.
Create a rule with your chosen HTTPS hostname and certificate as the source,
and **HTTP**, hostname **127.0.0.1**, port **8001** as the destination.
Configure the iOS app's API base URL to `https://<your-hostname>`.

Port 8000 belongs to Portainer. Port 8001 is bound to both NAS loopback and
the NAS LAN address `192.168.168.251`. For direct LAN access, set the iOS API
base URL to `http://192.168.168.251:8001`. The reverse proxy can continue using
`127.0.0.1:8001` as its destination.
No DSM proxy or certificate settings are changed by this deployment.

## Verification

Check health from SSH and then through your HTTPS hostname. Test a card upload
from the iPhone after configuring the proxy. Real-provider recognition uses the
provider and credentials in `config/.env` and may incur provider charges.

For a free mock smoke test, run this from the task worktree. It starts a
disposable container, verifies database integrity, card printing lookup, real
HTTP recognition, and persistent artifacts. The provider overrides affect only
that disposable container; no paid request is sent.

```bash
ssh -p 2222 root@192.168.168.251 \
  'cd /volume1/docker/mtg-scanner && /usr/local/bin/docker compose run --rm -T --no-deps -e MTG_SCANNER_LLM_PROVIDER=mock -e MTG_SCANNER_ENABLE_LLM_CORRECTION=false -e MTG_SCANNER_ENABLE_MTG_VALIDATION=true -e MTG_SCANNER_PRICING_REFRESH_INTERVAL_HOURS=0 api python -' \
  < deploy/synology/smoke.py
```

After `docker compose up -d --force-recreate`, confirm health and that the same
databases and recognition artifacts remain. Missing databases degrade validation
and pricing, so a healthy `/health` response alone does not prove data readiness.

## Operations and updates

```bash
ssh -p 2222 root@192.168.168.251
cd /volume1/docker/mtg-scanner
/usr/local/bin/docker compose ps
/usr/local/bin/docker compose logs --tail=100 api
/usr/local/bin/docker compose restart api
/usr/local/bin/docker compose stop api
/usr/local/bin/docker compose up -d
```

For an update, archive and transfer the desired committed runtime source using
the initial deployment commands. Preserve `config/`, `data/`, `artifacts/`, and `logs/`.
Extract each update into a fresh source directory as shown above, retaining the
previous source directory for review. This prevents deleted modules from
remaining in the next image. Set `MTG_SCANNER_IMAGE_TAG` in the root `.env` to the new commit, then run
`docker compose config --quiet`, `docker compose build`, and
`docker compose up -d --no-build`. Retain previous image tags; do not prune them
until the deployment has been reviewed.

To roll back, set the root `.env` image tag to the previous deployment commit
and run `/usr/local/bin/docker compose up -d --no-build`. This restores the old
image without rebuilding the newer source. Runtime data and credentials remain
in place. Back up persistent data separately; image rollback does not restore it.

Changing provider configuration requires editing `config/.env` on the NAS and
restarting the API. Never print it in deployment logs or commit it to Git.
