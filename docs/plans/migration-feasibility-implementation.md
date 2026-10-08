# Migration Feasibility Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans task-by-task.

**Goal:** Prove direct provider recognition, MTGJSON installation, and CK price refresh on iPhone without replacing the production API path.

**Architecture:** Debug-only MTGScannerFixtures services and a launch-argument runner. Stream download/decompression and SQLite projection into staged databases; export sanitized JSON evidence.

**Tech Stack:** Swift 6, Foundation URLSession, CryptoKit, zlib, SQLite3, XCTest.

**Spec:** Approved Phase 1 plan in the conversation; reproduced in the report's acceptance section.

## Global Constraints
- Minimum iOS 18; existing production scanning and persistence remain unchanged.
- Direct upstream only; no hosted gateway or static snapshots.
- Credentials never logged or committed; no automatic live retries.
- Import target: <300 seconds after download, <250 MB peak app memory.
- Retain worktree and all review artifacts.

## Review Focus
- Invalid confidence/enums must reject the LLM response rather than silently losing evidence.
- Cancellation and corrupt data must not replace the active database.
- Large feeds must be processed with bounded memory.
- Provider secrets must not appear in evidence or redirect to another host.
- Simulator results and HTTP access are not device or distribution permission evidence.

## Task 1: Direct-provider probe
Files: Sources/MTGScannerFixtures/Feasibility/ProbeProvider*.swift; Tests/MTGScannerKitTests/FeasibilityProviderTests.swift.
- [x] Write tests for request images/schema/modes, structured and raw response parsing, evidence preservation, invalid confidence, HTTP errors and cancellation.
- [x] Run targeted XCTest and confirm missing feature failures.
- [x] Implement ProbeProvider.request/recognize and ProbeOutput.decode using ephemeral URLSession, no retry, sanitized errors, same prompts/schema.
- [x] Run targeted XCTest; expected pass.

## Task 2: Native data import
Files: Sources/MTGScannerFixtures/Feasibility/Probe{SQLite,Catalog,Prices,Download,Metrics}.swift; Tests/MTGScannerKitTests/FeasibilityDataTests.swift.
- [x] Write small upstream SQLite/feed fixtures and tests for projection, face merge, normalization, foil/zero prices, corruption and cancellation retention.
- [x] Confirm RED; implement staged catalog and price imports with row iteration.
- [x] Add checksum/gzip tests and bounded file JSON parsing.
- [x] Confirm GREEN with targeted XCTest.

## Task 3: Repeatable device runner and evidence
Files: Sources/MTGScannerFixtures/Feasibility/FeasibilityProbe.swift; app DEBUG launch hook; scripts/phase1-*; docs/plans/migration-feasibility.md.
- [x] Add debug runner and prepare/launch helpers, preserving production flows.
- [x] Complete final full-suite verification after all fixes; baseline and intermediate checks recorded.
- [x] Install isolated diagnostic bundle on paired iPhone; execute bounded recognition, CK and full catalog tests.
- [x] Compare catalog and prices with Python reference using same release.
- [x] Record Pass/Fail/Unverified, measurements, official sources and limitations.
- [x] Finish independent review follow-up, commit and retain artifacts.
