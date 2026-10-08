# ADR 0009: Measure serverless migration before production integration

Date: 2026-10-07
Status: Accepted for Phase 1 diagnostics

## Context

The intended release removes the Python application server, uses user-supplied AI keys, and downloads upstream card/price data directly. Replacing the whole pipeline at once would mix provider, data, validation and release risks.

## Decision

Introduce an opt-in Debug launch probe in the existing fixture target. Keep normal scanning on the API. Measure direct recognition and staged native SQLite installation on a physical iPhone and compare the stored data with Python before production adoption.

Use MTGJSON's compressed SQLite export rather than materializing AllPrintings JSON on iPhone. Verify SHA-256 and project a compact database. Stream Card Kingdom's feed one object at a time. Close validated staging databases before atomic activation; preserve the active snapshot on cancellation or malformed input.

## Consequences

[The Phase 1 report](../plans/migration-feasibility.md) records successful native resource/parity measurements and remaining provider/distribution questions. The probe adds no production key storage or transport switch. Later increments must implement production lifecycle, consent, local validation and end-to-end parity before removing Python.
