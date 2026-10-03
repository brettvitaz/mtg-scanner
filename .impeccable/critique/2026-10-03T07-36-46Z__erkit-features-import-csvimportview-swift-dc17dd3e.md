---
target: CSV import page
total_score: 26
max_score: 40
na_heuristics:
p0_count: 0
p1_count: 2
target_identity: "file:/Users/brettvitaz/Development/mtg-scanner-worktrees/simplify-csv-import/apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Import/CSVImportView.swift"
target_fingerprint: "sha256:8bce8896fb4ad10e78e646b8c0ac49bc00c9c0fa2d06759a3966067af0c0dec4"
target_path: /Users/brettvitaz/Development/mtg-scanner-worktrees/simplify-csv-import/apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Import/CSVImportView.swift
timestamp: 2026-10-03T07-36-46Z
slug: erkit-features-import-csvimportview-swift-dc17dd3e
closed: true
---
Method: dual-agent (A: /root/import_design_review; B: /root/import_design_evidence).

The CSV import screen feels like a settings form. The large file block, separate
summary, repeated warnings, and similarly emphasized text compete with the cards
requiring a decision. The problems-first information structure is sound, but the
composition needs work. The visual language is largely interchangeable with a
generic import utility; product character should come from precise card review.

| Heuristic | Score / 4 | Key issue |
| --- | --- | --- |
| System status | 3 | Ready count leads even while import is blocked. |
| Familiar language | 3 | Cards and CSV rows require interpretation. |
| User control | 3 | Bulk skipping has individual restoration but no batch undo. |
| Consistency | 3 | Native controls; typography differs from card lists. |
| Error prevention | 3 | Eligibility is guarded; bulk exclusion lacks a consequence count. |
| Recognition over recall | 3 | Card context present; detail title is a row number. |
| Efficiency | 2 | Detail/picker navigation repeated per card. |
| Aesthetic simplicity | 2 | Large administrative blocks and repeated footer copy. |
| Error recovery | 2 | Invalid CSV data must be fixed externally or skipped. |
| Contextual help | 2 | Generic matching language; inconsistent next-action clarity. |
| **Total** | **26/40** | **Acceptable; significant improvements needed.** |

## What works

Problems-first review; native navigation and controls; exact import quantity and
additive import semantics. Preserve these foundations and matching safeguards.

## Cognitive load and emotional journey

Visual hierarchy fails: administration and fixed instructions outrank recovery.
Chunking conditionally fails in details with title plus six source fields.
Grouping, single focus, progressive disclosure, working-memory support and minimal
choices broadly pass. No demonstrated decision point exceeds four choices.
Matching offers reassurance, then repeated attention messages and a disabled
button create a valley. Completion gives a clear confirmation.

## Priority issues

1. **P1 — Fixed footer overwhelms large text.** Roughly 42% of the large-text
   iPhone screenshot is the fixed panel; no problem card is initially visible.
   Keep only a compact action fixed and move explanation/additive warning into
   scrolling content. Use an inline action at accessibility sizes if necessary.
   Keep full text, Dynamic Type and import eligibility. Command: impeccable adapt.
2. **P1 — File administration outranks review.** Combine destination, filename
   and status into one compact review header. Lead blocked imports with the
   attention count and put problem cards directly below. Commands: impeccable
   layout and distill.
3. **P2 — Weak typography hierarchy and app inconsistency.** Names, metadata,
   errors and warnings have similarly strong emphasis. Align with existing card
   list typography using Dynamic Type; distinguish supporting information with
   size, weight and verified contrast. Command: impeccable typeset.
4. **P2 — Bulk skip appears primary.** A full-height blue action precedes cards.
   Preserve Skip All Unmatched, include its affected count and make it secondary.
   A batch Undo would improve recovery. Commands: impeccable clarify and polish.

## Persona red flags

- First-time importer: 4 cards versus 1 row needs clearer context; printing jargon
  obscures the next action.
- Frequent collector: detail-to-picker navigation and individual restoration
  introduce repeated work.
- Large-text user: fixed instructions displace recovery content; VoiceOver was
  not exercised.

## Minor observations

Use card-name detail titles with subordinate CSV row numbers; hide empty Skipped
navigation; tighten iPad content width. Explain external CSV repair clearly rather
than introducing editing or retry features as a side effect of visual refinement.

## Evidence

Detector real attempt returned exit 0 and JSON [], with zero findings. Non-HTML
regex scanning does not validate native SwiftUI layout. Native screenshot and
source review are the primary evidence; no DOM/browser overlay applies. Dark and
iPad captures predate the bulk-skip addition, so they establish retained layout
but not the new action's large-text rendering. No source/UI edits were made.

## Questions to consider

1. Composition: a compact review header and one focused list (recommended), or
   retain separate grouped sections and tighten their spacing?
2. Styling: align with existing card-list typography and colors (recommended),
   or retain system styling and focus only on layout?
