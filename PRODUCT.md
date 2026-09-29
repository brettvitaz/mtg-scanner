# Product

<!-- impeccable:product-schema 1 -->

Migrated from confirmed project context in `AGENTS.md`, `README.md`, and
`.impeccable.md`. This record introduces no new product or design decisions.

## Platform

ios

## Users

MTG players cataloguing cards at home and tournament/store players identifying
cards quickly in varied lighting. Both groups need clear, readable card data.

## Product Purpose

An iPhone-first Magic: The Gathering card scanner that captures and crops cards
on-device, recognizes them through a FastAPI backend, validates printings against
MTGJSON, and returns structured identifications for card cataloguing.

## Capabilities and Constraints

Swift 6, SwiftUI, iOS 18 and later, with iPhone as the primary platform.
The backend uses mock recognition for tests and supports hosted OpenAI and
OpenAI-compatible providers. Preserve API contracts and native affordances.
Camera and Vision processing use dedicated queues.

## Brand Commitments

Clean, fast, confident. A precision reference tool that respects MTG players'
expertise. Preserve the existing identity and product truth during refinements.
Legacy visual preferences remain in `.impeccable.md`; they are existing direction,
not evidence that every documented token or font is currently implemented.

## Accessibility & Inclusion

Maintain readable light and dark themes, VoiceOver, Dynamic Type, reduced motion,
and indicators that communicate state without relying on color alone.
