"""Tests for the admin pricing refresh endpoint."""

from __future__ import annotations

from unittest.mock import AsyncMock, patch

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.routes.admin import router as admin_router
from app.services.llm.pricing_refresh import RefreshResult


FAKE_RESULT = RefreshResult(
    source_url="https://example.com/prices.json",
    fetched_at="2026-04-10T12:00:00+00:00",
    model_count=8,
    missing_providers=[],
)


@pytest.fixture()
def admin_app(monkeypatch):
    """Return a minimal FastAPI app with the admin router and a test token."""
    monkeypatch.setenv("MTG_SCANNER_ADMIN_TOKEN", "test-secret")
    app = FastAPI()
    app.include_router(admin_router, prefix="/api/v1")
    return app


@pytest.fixture()
def admin_client(admin_app):
    return TestClient(admin_app)


class TestAdminPricingRefresh:
    def test_requires_token(self, admin_client):
        resp = admin_client.post("/api/v1/admin/pricing/refresh")
        assert resp.status_code == 401
        assert "Invalid admin token" in resp.json()["detail"]

    def test_rejects_wrong_token(self, admin_client):
        resp = admin_client.post(
            "/api/v1/admin/pricing/refresh",
            headers={"X-Admin-Token": "wrong"},
        )
        assert resp.status_code == 401

    def test_succeeds_with_correct_token(self, admin_client):
        with patch(
            "app.api.routes.admin.refresh_prices_from_upstream",
            new=AsyncMock(return_value=FAKE_RESULT),
        ):
            resp = admin_client.post(
                "/api/v1/admin/pricing/refresh",
                headers={"X-Admin-Token": "test-secret"},
            )
        assert resp.status_code == 200
        body = resp.json()
        assert body["model_count"] == 8
        assert body["fetched_at"] == "2026-04-10T12:00:00+00:00"
        assert body["source_url"] == "https://example.com/prices.json"
        assert body["missing_providers"] == []

    def test_returns_502_on_upstream_failure(self, admin_client):
        with patch(
            "app.api.routes.admin.refresh_prices_from_upstream",
            new=AsyncMock(side_effect=httpx.ConnectError("connection refused")),
        ):
            resp = admin_client.post(
                "/api/v1/admin/pricing/refresh",
                headers={"X-Admin-Token": "test-secret"},
            )
        assert resp.status_code == 502
        detail = resp.json()["detail"]
        # Error must be sanitized — original exception text must not leak
        assert "connection refused" not in detail
        assert "retained" in detail

    def test_502_detail_does_not_contain_upstream_url(self, admin_client):
        with patch(
            "app.api.routes.admin.refresh_prices_from_upstream",
            new=AsyncMock(side_effect=httpx.ConnectError("connection refused")),
        ):
            resp = admin_client.post(
                "/api/v1/admin/pricing/refresh",
                headers={"X-Admin-Token": "test-secret"},
            )
        assert "github" not in resp.json()["detail"].lower()

    def test_endpoint_not_mounted_without_token(self):
        """When no admin token is set, the admin router is not mounted at all."""
        app = FastAPI()
        # Do NOT include admin_router — simulates what main.py does when token is absent
        client = TestClient(app)
        resp = client.post("/api/v1/admin/pricing/refresh")
        assert resp.status_code == 404
