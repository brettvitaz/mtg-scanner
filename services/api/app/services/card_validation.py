from __future__ import annotations

from dataclasses import dataclass, field
import logging
import sqlite3
from typing import cast

from app.models.recognition import RecognizedCard, RecognitionResponse
from app.services.mtgjson_index import (
    CardRecord,
    MTGJSONIndex,
    normalize_collector_number,
    normalize_set_code,
    normalize_set_name,
    normalize_title,
)

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class ValidationTrace:
    original: dict[str, object]
    normalized_inputs: dict[str, object]
    status: str
    matched_uuid: str | None
    matched_set_code: str | None
    matched_collector_number: str | None
    confidence_before: float
    confidence_after: float
    reason: str


@dataclass(frozen=True, slots=True)
class ValidatedCardResult:
    card: RecognizedCard
    trace: ValidationTrace
    correction_candidates: list[CardRecord] = field(default_factory=list)


@dataclass(frozen=True, slots=True)
class ValidationBatchResult:
    response: RecognitionResponse
    traces: list[ValidationTrace]
    enabled: bool
    available: bool
    correction_candidates: list[list[CardRecord]] = field(default_factory=list)


class CardValidationService:
    def __init__(self, *, index: MTGJSONIndex, max_fuzzy_candidates: int = 10) -> None:
        self._index = index
        self._max_fuzzy_candidates = max_fuzzy_candidates

    def validate_response(self, response: RecognitionResponse) -> ValidationBatchResult:
        if not self._index.is_available():
            traces = [self._unavailable_trace(card) for card in response.cards]
            return ValidationBatchResult(
                response=response,
                traces=traces,
                enabled=True,
                available=False,
                correction_candidates=[[] for _ in response.cards],
            )

        try:
            results = [self.validate_card(card) for card in response.cards]
        except sqlite3.Error as exc:
            logger.warning("MTGJSON database error during validation: %s", exc)
            traces = [
                self._unavailable_trace(
                    card, reason="MTGJSON database unreadable; validation skipped."
                )
                for card in response.cards
            ]
            return ValidationBatchResult(
                response=response,
                traces=traces,
                enabled=True,
                available=False,
                correction_candidates=[[] for _ in response.cards],
            )

        results = _drop_face_name_redundancies(results, self._index)
        return ValidationBatchResult(
            response=RecognitionResponse(cards=[result.card for result in results]),
            traces=[result.trace for result in results],
            enabled=True,
            available=True,
            correction_candidates=[result.correction_candidates for result in results],
        )

    def validate_card(self, card: RecognizedCard) -> ValidatedCardResult:
        normalized_title = normalize_title(card.title)
        normalized_set = normalize_set_code(card.edition)
        normalized_set_name = normalize_set_name(card.edition)
        normalized_number = normalize_collector_number(card.collector_number)

        trace_base = {
            "original": card.model_dump(),
            "normalized_inputs": {
                "title": normalized_title,
                "edition_set_code": normalized_set,
                "edition_set_name": normalized_set_name,
                "collector_number": normalized_number,
            },
            "confidence_before": card.confidence,
        }

        if not normalized_title:
            return self._result(
                card, trace_base, "no_match", None, "Missing title; validation skipped."
            )

        resolved_set_code = self._index.resolve_set(card.edition or "")
        # Track if the LLM's set claim was wrong: either the set doesn't exist, or the
        # card title is absent from the resolved set. Either case warrants correction.
        wrong_set = bool(card.edition) and resolved_set_code is None

        if normalized_number and resolved_set_code:
            match = self._index.lookup_exact(
                title=card.title or "",
                set_code=resolved_set_code,
                collector_number=card.collector_number or "",
            )
            if match is not None:
                return self._matched(
                    card,
                    trace_base,
                    match,
                    "exact_match",
                    "Exact title/set/collector match.",
                )

        if resolved_set_code:
            candidates = self._index.lookup_by_name_and_set(
                title=card.title or "", set_code=resolved_set_code
            )
            if not candidates:
                wrong_set = True
            if normalized_number:
                narrowed = [
                    c
                    for c in candidates
                    if c.normalized_collector_number == normalized_number
                ]
                if len(narrowed) == 1:
                    return self._matched(
                        card,
                        trace_base,
                        narrowed[0],
                        "normalized_match",
                        "Resolved set and collector number after title match.",
                    )
                if len(narrowed) > 1:
                    return self._result(
                        card,
                        trace_base,
                        "ambiguous_match",
                        None,
                        "Multiple printings share the same title and collector number in the resolved set.",
                    )
                # Collector not in set — fall through to cross-set lookup
            elif len(candidates) == 1:
                return self._matched(
                    card,
                    trace_base,
                    candidates[0],
                    "normalized_match",
                    "Resolved set and title to a single printing.",
                )
            elif len(candidates) > 1:
                return self._result(
                    card,
                    trace_base,
                    "ambiguous_match",
                    None,
                    "Multiple printings share the same title in the resolved set.",
                )
            # Title not in the resolved set — fall through to cross-set lookup

        if normalized_number:
            candidates = self._index.lookup_by_name_and_number(
                title=card.title or "", collector_number=card.collector_number or ""
            )
            if len(candidates) == 1:
                status = "corrected_match" if wrong_set else "normalized_match"
                reason = (
                    "Auto-corrected: matched title and collector number across sets; original set was invalid."
                    if wrong_set
                    else "Matched title and collector number across sets."
                )
                return self._matched(card, trace_base, candidates[0], status, reason)
            if len(candidates) > 1:
                if wrong_set:
                    return self._needs_correction(
                        card,
                        trace_base,
                        candidates,
                        "Title and collector number matched multiple printings; original set was invalid.",
                    )
                return self._result(
                    card,
                    trace_base,
                    "ambiguous_match",
                    None,
                    "Title and collector number matched multiple printings across sets.",
                )

        candidates = self._index.search_candidates(
            title=card.title or "",
            set_code=resolved_set_code,
            collector_number=card.collector_number,
            limit=self._max_fuzzy_candidates,
        )
        if len(candidates) == 1:
            status = "corrected_match" if wrong_set else "normalized_match"
            reason = (
                "Auto-corrected: single normalized candidate; original set was invalid."
                if wrong_set
                else "Single normalized candidate match."
            )
            return self._matched(card, trace_base, candidates[0], status, reason)
        if len(candidates) > 1:
            if wrong_set:
                return self._needs_correction(
                    card,
                    trace_base,
                    candidates,
                    "Multiple normalized candidates; original set was invalid.",
                )
            return self._result(
                card,
                trace_base,
                "ambiguous_match",
                None,
                "Multiple normalized candidates remain; keeping recognizer output.",
            )

        # Final fallback: look up all printings by title to enable auto-correction
        all_printings = self._index.lookup_all_printings_by_name(title=card.title or "")
        if len(all_printings) == 1:
            return self._matched(
                card,
                trace_base,
                all_printings[0],
                "corrected_match",
                "Auto-corrected: title found in exactly one set; original set/collector ignored.",
            )
        if len(all_printings) > 1:
            return self._needs_correction(
                card,
                trace_base,
                all_printings,
                "Title found in multiple sets; cannot auto-correct without LLM retry.",
            )

        # Face-name fallback for split cards
        face_matches = self._index.lookup_by_face_name(title=card.title or "")
        if len(face_matches) == 1:
            return self._matched(
                card, trace_base, face_matches[0], "corrected_match",
                "Auto-corrected: matched as face name of split card.",
            )
        if len(face_matches) > 1:
            narrowed = _narrow_face_matches(face_matches, resolved_set_code, normalized_number)
            if len(narrowed) == 1:
                return self._matched(
                    card, trace_base, narrowed[0], "corrected_match",
                    "Auto-corrected: matched as face name of split card.",
                )
            return self._needs_correction(
                card, trace_base, face_matches,
                "Title matched as face name of split card in multiple sets.",
            )

        return self._result(
            card,
            trace_base,
            "no_match",
            None,
            "No MTGJSON match found; keeping recognizer output.",
        )

    def _matched(
        self,
        card: RecognizedCard,
        trace_base: dict[str, object],
        match: CardRecord,
        status: str,
        reason: str,
    ) -> ValidatedCardResult:
        confidence_after = _adjust_confidence(card.confidence, status)
        notes = _merge_notes(card.notes, f"Validated against MTGJSON ({status}).")

        foil_note, foil_penalty = _check_foil_mismatch(card.foil, match)
        if foil_note:
            notes = _merge_notes(notes, foil_note)
        confidence_after = max(0.0, round(confidence_after - foil_penalty, 4))

        image_url = (
            f"https://api.scryfall.com/cards/{match.scryfall_id}?format=image&version=normal"
            if match.scryfall_id
            else None
        )
        set_symbol_url = (
            f"https://svgs.scryfall.io/sets/{match.set_code.lower()}.svg"
            if match.set_code
            else None
        )
        validated_card = card.model_copy(
            update={
                "title": match.name,
                "edition": match.set_name or card.edition,
                "collector_number": match.collector_number or card.collector_number,
                "confidence": confidence_after,
                "notes": notes,
                "set_code": match.set_code,
                "rarity": match.rarity,
                "type_line": match.type_line,
                "oracle_text": match.oracle_text,
                "mana_cost": match.mana_cost,
                "power": match.power,
                "toughness": match.toughness,
                "loyalty": match.loyalty,
                "defense": match.defense,
                "scryfall_id": match.scryfall_id,
                "image_url": image_url,
                "set_symbol_url": set_symbol_url,
                "card_kingdom_url": match.card_kingdom_url,
                "card_kingdom_foil_url": match.card_kingdom_foil_url,
                "color_identity": match.color_identity,
            }
        )
        return ValidatedCardResult(
            card=validated_card,
            trace=ValidationTrace(
                original=cast(dict[str, object], trace_base["original"]),
                normalized_inputs=cast(
                    dict[str, object], trace_base["normalized_inputs"]
                ),
                status=status,
                matched_uuid=match.uuid,
                matched_set_code=match.set_code,
                matched_collector_number=match.collector_number,
                confidence_before=card.confidence,
                confidence_after=confidence_after,
                reason=reason,
            ),
        )

    def _result(
        self,
        card: RecognizedCard,
        trace_base: dict[str, object],
        status: str,
        match: CardRecord | None,
        reason: str,
    ) -> ValidatedCardResult:
        confidence_after = _adjust_confidence(card.confidence, status)
        update: dict[str, object] = {"confidence": confidence_after}
        if status in {"ambiguous_match", "no_match"}:
            update["notes"] = _merge_notes(card.notes, reason)
        validated_card = card.model_copy(update=update)
        return ValidatedCardResult(
            card=validated_card,
            trace=ValidationTrace(
                original=cast(dict[str, object], trace_base["original"]),
                normalized_inputs=cast(
                    dict[str, object], trace_base["normalized_inputs"]
                ),
                status=status,
                matched_uuid=match.uuid if match else None,
                matched_set_code=match.set_code if match else None,
                matched_collector_number=match.collector_number if match else None,
                confidence_before=card.confidence,
                confidence_after=confidence_after,
                reason=reason,
            ),
        )

    def _needs_correction(
        self,
        card: RecognizedCard,
        trace_base: dict[str, object],
        candidates: list[CardRecord],
        reason: str,
    ) -> ValidatedCardResult:
        confidence_after = _adjust_confidence(card.confidence, "needs_correction")
        validated_card = card.model_copy(
            update={
                "confidence": confidence_after,
                "notes": _merge_notes(card.notes, reason),
            }
        )
        return ValidatedCardResult(
            card=validated_card,
            trace=ValidationTrace(
                original=cast(dict[str, object], trace_base["original"]),
                normalized_inputs=cast(
                    dict[str, object], trace_base["normalized_inputs"]
                ),
                status="needs_correction",
                matched_uuid=None,
                matched_set_code=None,
                matched_collector_number=None,
                confidence_before=card.confidence,
                confidence_after=confidence_after,
                reason=reason,
            ),
            correction_candidates=candidates,
        )

    def _unavailable_trace(
        self,
        card: RecognizedCard,
        *,
        reason: str = "MTGJSON database unavailable; validation skipped.",
    ) -> ValidationTrace:
        return ValidationTrace(
            original=card.model_dump(),
            normalized_inputs={
                "title": normalize_title(card.title),
                "edition_set_code": normalize_set_code(card.edition),
                "edition_set_name": normalize_set_name(card.edition),
                "collector_number": normalize_collector_number(card.collector_number),
            },
            status="validation_unavailable",
            matched_uuid=None,
            matched_set_code=None,
            matched_collector_number=None,
            confidence_before=card.confidence,
            confidence_after=card.confidence,
            reason=reason,
        )


def _check_foil_mismatch(
    foil: bool | None, match: CardRecord
) -> tuple[str | None, float]:
    """Return (note_text, confidence_penalty) if the foil claim conflicts with known finishes."""
    if foil is None or not match.finishes:
        return None, 0.0

    if foil is True and not match.has_foil and not match.has_etched:
        return "This printing is not available in foil.", 0.05
    if foil is False and not match.has_non_foil:
        return "This printing is only available in foil/etched.", 0.05
    return None, 0.0


def _adjust_confidence(value: float, status: str) -> float:
    if status == "exact_match":
        return min(1.0, round(value + 0.02, 4))
    if status == "normalized_match":
        return round(value, 4)
    if status == "corrected_match":
        return max(0.0, round(value - 0.05, 4))
    if status == "fuzzy_match":
        return max(0.0, round(value - 0.05, 4))
    if status == "ambiguous_match":
        return max(0.0, round(value - 0.2, 4))
    if status == "needs_correction":
        return max(0.0, round(value - 0.1, 4))
    return max(0.0, round(value - 0.25, 4)) if status == "no_match" else round(value, 4)


def _narrow_face_matches(
    face_matches: list[CardRecord],
    resolved_set_code: str | None,
    normalized_number: str,
) -> list[CardRecord]:
    """Narrow multiple face-name matches using set and/or collector number context."""
    if resolved_set_code and normalized_number:
        candidates = [
            c for c in face_matches
            if c.set_code == resolved_set_code and c.normalized_collector_number == normalized_number
        ]
        if candidates:
            return candidates
    if resolved_set_code:
        candidates = [c for c in face_matches if c.set_code == resolved_set_code]
        if candidates:
            return candidates
    if normalized_number:
        candidates = [c for c in face_matches if c.normalized_collector_number == normalized_number]
        if candidates:
            return candidates
    return face_matches


def _drop_face_name_redundancies(
    results: list[ValidatedCardResult],
    index: MTGJSONIndex,
) -> list[ValidatedCardResult]:
    """Drop entries whose title is a face of a split card that another entry already matched.

    When the LLM returns both face names of a split card, one may be corrected
    (face-name match) and the other may fail (no_match or needs_correction).
    The unmatched half is redundant and should be dropped.

    Only entries matched via face-name correction trigger this — normal UUID
    matches from identical physical cards are not touched.
    """
    # Identify results that were matched by face-name correction and record
    # which UUIDs they resolved to.
    face_corrected_uuids: set[str] = set()
    face_corrected_indices: set[int] = set()
    for i, result in enumerate(results):
        if (
            result.trace.matched_uuid is not None
            and "face name of split card" in result.trace.reason
        ):
            face_corrected_uuids.add(result.trace.matched_uuid)
            face_corrected_indices.add(i)

    if not face_corrected_uuids:
        return results

    # UUIDs already claimed by non-face-corrected results take priority
    non_face_uuids: set[str] = {
        result.trace.matched_uuid
        for i, result in enumerate(results)
        if i not in face_corrected_indices and result.trace.matched_uuid is not None
    }

    # Collect (uuid, original_title) pairs for all face-corrected entries so we can
    # identify true siblings (different original title, same UUID) vs. duplicate
    # physical copies (same original title, same UUID).
    face_corrected_titles: dict[int, str] = {
        i: str(results[i].trace.original.get("title") or "")
        for i in face_corrected_indices
    }

    # For each result, decide whether to keep or drop it.
    output: list[ValidatedCardResult] = []
    for i, result in enumerate(results):
        if i in face_corrected_indices:
            uuid = result.trace.matched_uuid
            orig = face_corrected_titles[i]
            # Drop if a non-face-corrected result already covers this UUID
            if uuid in non_face_uuids:
                continue
            # Drop if another face-corrected entry with a DIFFERENT original title
            # already resolved to the same UUID (i.e. it was the sibling face)
            is_sibling_already_emitted = any(
                j != i
                and results[j].trace.matched_uuid == uuid
                and face_corrected_titles[j] != orig
                and j < i
                for j in face_corrected_indices
            )
            if is_sibling_already_emitted:
                continue
            output.append(result)
            continue
        original_title = str(result.trace.original.get("title") or "")
        face_parents = {r.uuid for r in index.lookup_by_face_name(title=original_title)}
        if face_parents & face_corrected_uuids:
            continue  # sibling face — drop
        output.append(result)
    return output


def _merge_notes(existing: str | None, addition: str) -> str:
    if existing and addition in existing:
        return existing
    if existing:
        return f"{existing} {addition}"
    return addition
