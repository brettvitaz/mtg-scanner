FROM python:3.14-slim-trixie

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/services/api \
    PIP_NO_CACHE_DIR=1
WORKDIR /app

COPY services/api/pyproject.toml services/api/pyproject.toml
COPY services/api/app services/api/app
RUN python -m pip install ./services/api \
    && groupadd --gid 10001 scanner \
    && useradd --uid 10001 --gid scanner --no-create-home scanner

COPY prompts prompts
COPY packages/schemas packages/schemas
COPY scripts/*.py scripts/
COPY services/api/data/pricing/model_prices.json services/api/data/pricing/model_prices.json

RUN mkdir -p services/api/logs services/.artifacts \
    && chown scanner:scanner services/api/logs services/.artifacts services/api/data/pricing

ARG SOURCE_REVISION=local
LABEL org.opencontainers.image.revision=$SOURCE_REVISION

USER 10001:10001
EXPOSE 8000
CMD ["python", "-m", "uvicorn", "app.main:app", "--app-dir", "services/api", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
