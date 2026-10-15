---
target: price filter editing interactions
total_score: 24
max_score: 40
na_heuristics:
p0_count: 0
p1_count: 2
target_identity: "file:/Users/brettvitaz/Development/mtg-scanner-worktrees/fix-price-filter-editing/apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Shared/FilterSheet.swift"
target_fingerprint: "sha256:69728d7b2cc815b9859a6cc5899ee601f0d55a483250a193e12863d42eb6cd47"
target_path: /Users/brettvitaz/Development/mtg-scanner-worktrees/fix-price-filter-editing/apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Shared/FilterSheet.swift
timestamp: 2026-10-15T08-45-24Z
slug: nnerkit-features-shared-filtersheet-swift-1d2e83c9
closed: true
---
Method: dual-agent (A: /root/price_design_review · B: /root/price_design_evidence)

The price editor has a sound native foundation but an unstable editing surface. The recommendation is to keep its geometry fixed and give focused-empty fields an intentional state. No application code changed in this evaluation.

Design specificity: the native grouped form fits an MTG reference tool; retail, buylist, and Card Kingdom provide product meaning. Additional visual branding would not solve the interaction problem.

| Heuristic | Score /4 | Finding |
| --- | --- | --- |
| System status | 2 | Empty focus is ambiguous. |
| Real-world match | 3 | Familiar price bounds; currency implicit. |
| User control | 2 | Clear and Reset help; invalid input gates navigation. |
| Consistency | 2 | Value edge and row height vary by content. |
| Error prevention | 2 | Decimal keyboard helps; malformed text still possible. |
| Recognition | 3 | Four persistent labels reduce recall. |
| Efficiency | 3 | Previous/Next and per-field clear help. |
| Minimalism | 3 | Restrained form, disrupted by layout shifts. |
| Error recovery | 2 | Draft retained; error lacks format guidance. |
| Help | 2 | Price format/currency guidance absent in this surface. |
| Total | 24/40 | Acceptable; interaction changes needed. |

Working well: native text fields and decimal keyboard; draft-preserving entry; accessible clear labels and 44-point targets. Light and dark captures remain readable.

Priority issues:

1. [P1] Typing and clearing move the working area. FilterSheet.swift conditionally inserts a sibling with a 44-point minimum width/height. The field shrinks horizontally and the row grows vertically; clearing reverses both. Reserve the accessory width and minimum row height in all states. Hide and disable the empty clear action without removing its space; exclude it from accessibility. Keep the caret edge and baseline stable. Suggested command: $impeccable layout.
2. [P2] Focused-empty fields still show Any. Source always uses this placeholder, consistent with the user-reported cursor overlap; screenshots do not independently reproduce empty focus. Show Any only while empty and unfocused. While focused, show a bare caret; typing and clearing keep the same text edge. Retain accessible field identity and unrestricted-state meaning. Suggested command: $impeccable polish.
3. [P1, verification needed] Largest Dynamic Type capture has no visible Previous/Next/checkmark above the keyboard. Other captures have those controls. Replay at that size before diagnosing the cause; if reproducible, keep the accessory usable and reflow constrained labels/inputs. Suggested command: $impeccable adapt.

Cognitive load is moderate: unstable hierarchy and control disclosure that moves active content fail two checklist items. Four price fields are manageable, and no cross-screen memory is required. The five familiar MTG color choices elsewhere are not the issue here. The emotional journey starts orderly, becomes uncertain on empty focus, jolts on first typing, and shifts again on clear.

Persona risks: Casey, one-handed mobile user, must track moving content; Jordan, first-time user, may mistake Any for editable content; Sam, low-vision user, may lose keyboard navigation at maximum text size, pending runtime verification.

Minor observations: error text can remain until another commit attempt; invalid-input navigation gating is existing approved behavior and should not change incidentally. Currency is implicit. Tablet label/value separation is wide. These are secondary to stable entry.

Concrete design contract: empty/unfocused = Any; empty/focused = caret only; populated = text plus clear; clearing = empty/focused with keyboard retained. Across those states, label position, value trailing edge, accessory space, and minimum row height stay fixed. Validate the sequence with actual taps, typing, and clear, including all four fields and large text; still images and value assertions alone missed this regression.

Deterministic scan: exit 0, JSON [], zero findings. It cannot judge native interaction geometry. Source plus six existing Simulator captures support the layout diagnosis; empty caret overlap is user-reported and motion was not replayed. No DOM/overlay applies to this native screen.

Questions for next pass: focused-empty appearance — caret only (recommended) or numeric example? Scope — stable entry plus large-text verification (recommended), or stable entry only?

Implementation outcome: fixed accessory geometry, caret-only empty focus, and verified maximum-text keyboard navigation. The user explicitly deferred iPad-only keyboard minimization after the strengthened iPhone test passed. Native input probes were removed; SwiftUI remains. See docs/card-list-pricing.md and retained tmp/price-filter-keyboard-investigation.md for the known limitation.
