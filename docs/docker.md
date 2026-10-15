# Running the API with Docker

The Dockerfile and root `compose.yaml` run the API on any host with Docker
Engine and Docker Compose. The image contains production dependencies, prompts,
and schema fixtures. Uvicorn listens on container port 8000 with one worker and
no development reload. No API route or response contract changes are required.

## Run the image directly

```bash
docker build -t mtg-scanner-api:local .
docker run --rm -p 8000:8000 mtg-scanner-api:local
```

The default provider is `mock`. Pass provider settings with Docker environment
variables for real recognition. The standalone image writes artifacts and logs
as its non-root user; use volumes to retain them when the container is removed.
Compose below supplies the configuration and persistent mounts together.

## Start with Compose

Run from a checkout of this repository:

```bash
mkdir -p config data/mtgjson data/ck_prices data/pricing artifacts logs
test -f config/.env || cp services/api/.env.example config/.env
test -f data/pricing/model_prices.json || cp services/api/data/pricing/model_prices.json data/pricing/
```

Edit `config/.env` to select the recognition provider and supply its credentials.
The example defaults to `mock`. For OpenAI, set `MTG_SCANNER_LLM_PROVIDER=openai`
and `OPENAI_API_KEY`. Keep this file outside the image and out of Git.

The container runs as UID/GID `10001:10001`. Grant that identity access to the
runtime directories and read access to the configuration file:

```bash
sudo chown -R 10001:10001 data artifacts logs
sudo chown root:10001 config/.env
sudo chmod 640 config/.env
docker compose build
docker compose up -d
curl --fail http://localhost:8000/health
```

The host port defaults to 8000. To use another port, set
`MTG_SCANNER_HOST_PORT` in the root `.env` file, for example
`MTG_SCANNER_HOST_PORT=8001`. The container continues listening on port 8000.
Point the iOS app at `http://<server-address>:<host-port>`, or configure your
reverse proxy to forward to that published port for HTTPS.

## Configuration and persistent storage

Compose mounts `config/.env` read-only at the API's expected environment-file
location. Pydantic reads it directly, preserving literal credential values.
Compose sets the container's API bind address and database/artifact paths.

Runtime state stays outside the image, relative to the Compose project directory:

| Host directory | Contents |
| --- | --- |
| `data/mtgjson` | MTGJSON SQLite index and optional import manifest |
| `data/ck_prices` | Card Kingdom SQLite prices |
| `data/pricing` | Writable model-pricing JSON, initially seeded from the repository |
| `artifacts` | Recognition and correction-feedback evidence |
| `logs` | Rotating application log files |

MTGJSON and Card Kingdom databases are optional for starting the server. Missing
data disables the corresponding validation or price lookups. To use existing
local databases, create consistent SQLite backups into the matching host
directories before starting the server; do not copy a live SQLite file directly.
For example, after the normal local import workflow has populated them:

```bash
sudo python3 - <<'PYTHON'
from pathlib import Path
import sqlite3

for folder, name in [("mtgjson", "mtgjson.sqlite"), ("ck_prices", "ck_prices.sqlite")]:
    source_path = (Path("services/api/data") / folder / name).resolve()
    target = Path("data") / folder / name
    with sqlite3.connect(source_path.as_uri() + "?mode=ro", uri=True) as source, sqlite3.connect(target) as backup:
        source.backup(backup)
        assert backup.execute("PRAGMA integrity_check").fetchone() == ("ok",)
PYTHON
sudo chown -R 10001:10001 data
```

Use permissions appropriate to the user running the backup command. Provider
configuration changes require restarting or recreating the service, including
when an editor replaces the mounted configuration file.

## Verification

```bash
docker compose ps
docker compose logs --tail=100 api
curl --fail http://localhost:8000/health
```

Use your configured host port for health checks. The health endpoint checks
liveness; it does not validate provider credentials or dataset readiness.

Verify the standalone image without mounts or datasets:

```bash
docker run --rm -e MTG_SCANNER_LLM_PROVIDER=mock \
  -e MTG_SCANNER_ENABLE_LLM_CORRECTION=false \
  mtg-scanner-api:local python scripts/smoke-api-container.py --standalone
```

After seeding both databases, run the full container smoke test:

```bash
docker compose run --rm -T --no-deps \
  -e MTG_SCANNER_LLM_PROVIDER=mock \
  -e MTG_SCANNER_ENABLE_LLM_CORRECTION=false \
  -e MTG_SCANNER_ENABLE_MTG_VALIDATION=true \
  -e MTG_SCANNER_PRICING_REFRESH_INTERVAL_HOURS=0 \
  api python scripts/smoke-api-container.py
```

It verifies database contents and integrity, HTTP health, card lookup, mock
recognition, validation metadata, artifact writes, and application logging.
Provider overrides apply only to this disposable container; no paid recognition
request is sent. Artifacts remain in the mounted directory for inspection.

## Updates and operations

```bash
docker compose restart api
docker compose stop api
docker compose up -d
docker compose up -d --build
docker compose up -d --force-recreate
```

Update the source checkout and use `docker compose up -d --build` to rebuild.
Keep `config`, `data`, `artifacts`, and `logs` between deployments. If transferring
source archives, extract each into a fresh source directory so deleted modules
do not remain in the next build. Back up persistent state separately from images.

For tagged deployments, set `MTG_SCANNER_IMAGE_TAG` in the root `.env` to a commit
or release tag before building. The default is `local`; the value also labels
the image revision. To roll back to a retained image, select its tag and run
`docker compose up -d --no-build`. Image rollback does not restore runtime data.
Docker restarts the service unless explicitly stopped and rotates console logs
at three files of 10 MB. The health check reports health but does not itself
restart an unhealthy process.
