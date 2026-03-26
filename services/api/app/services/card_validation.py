from __future__ import annotations

from dataclasses import dataclass
import sqlite3

from app.models.recognition import RecognizedCard, RecognitionResponse
from app.services.mtgjson_index import (
    CardRecord,
    MTGJSONIndex,
    normalize_collector_number,
    normalize_set_code,
    normalize_set_name,
    normalize_title,
)


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


@dataclass(frozen=True, slots=True)
class ValidationBatchResult:
    response: RecognitionResponse
    traces: list[ValidationTrace]
    enabled: bool
    available: bool


class CardValidationService:
    def __init__(self, *, index: MTGJSONIndex, max_fuzzy_candidates: int = 10) -> None:
        self._index = index
        self._max_fuzzy_candidates = max_fuzzy_candidates

    def validate_response(self, response: RecognitionResponse) -> ValidationBatchResult:
        if not self._index.is_available():
            traces = [self._unavailable_trace(card) for card in response.cards]
            return ValidationBatchResult(response=response, traces=traces, enabled=True, available=False)

        try:
            results = [self.validate_card(card) for card in response.cards]
        except sqlite3.Error:
            traces = [self._unavailable_trace(card, reason="MTGJSON database unreadable; validation skipped.") for card in response.cards]
            return ValidationBatchResult(response=response, traces=traces, enabled=True, available=False)

        return ValidationBatchResult(
            response=RecognitionResponse(cards=[result.card for result in results]),
            traces=[result.trace for result in results],
            enabled=True,
            available=True,
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
            return self._result(card, trace_base, "no_match", None, "Missing title; validation skipped.")

        resolved_set_code = self._index.resolve_set(card.edition or "")

        if normalized_number and resolved_set_code:
            match = self._index.lookup_exact(
                title=card.title or "",
                set_code=resolved_set_code,
                collector_number=card.collector_number or "",
            )
            if match is not None:
                return self._matched(card, trace_base, match, "exact_match", "Exact title/set/collector match.")

        if resolved_set_code:
            candidates = self._index.lookup_by_name_and_set(title=card.title or "", set_code=resolved_set_code)
            if normalized_number:
                narrowed = [c for c in candidates if c.normalized_collector_number == normalized_number]
                if len(narrowed) == 1:
                    return self._matched(card, trace_base, narrowed[0], "normalized_match", "Resolved set and collector number after title match.")
                if len(narrowed) > 1:
                    return self._result(card, trace_base, "ambiguous_match", None, "Multiple printings share the same title and collector number in the resolved set.")
                if candidates:
                    return self._result(card, trace_base, "no_match", None, "Resolved set and title matched MTGJSON, but collector number conflicts with every printing in that set.")
                return self._result(card, trace_base, "no_match", None, "Resolved set is valid, but title does not exist in that set.")

            if len(candidates) == 1:
                return self._matched(card, trace_base, candidates[0], "normalized_match", "Resolved set and title to a single printing.")
            if len(candidates) > 1:
                return self._result(card, trace_base, "ambiguous_match", None, "Multiple printings share the same title in the resolved set.")
            return self._result(card, trace_base, "no_match", None, "Resolved set is valid, but title does not exist in that set.")

        if normalized_number:
            candidates = self._index.lookup_by_name_and_number(title=card.title or "", collector_number=card.collector_number or "")
            if len(candidates) == 1:
                return self._matched(card, trace_base, candidates[0], "normalized_match", "Matched title and collector number across sets.")
            if len(candidates) > 1:
                return self._result(card, trace_base, "ambiguous_match", None, "Title and collector number matched multiple printings across sets.")

        candidates = self._index.search_candidates(
            title=card.title or "",
            set_code=resolved_set_code,
            collector_number=card.collector_number,
            limit=self._max_fuzzy_candidates,
        )
        if len(candidates) == 1:
            return self._matched(card, trace_base, candidates[0], "normalized_match", "Single normalized candidate match.")
        if len(candidates) > 1:
            return self._result(card, trace_base, "ambiguous_match", None, "Multiple normalized candidates remain; keeping recognizer output.")

        return self._result(card, trace_base, "no_match", None, "No MTGJSON match found; keeping recognizer output.")

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
        validated_card = card.model_copy(
            update={
                "title": match.name,
                "edition": match.set_name or card.edition,
                "collector_number": match.collector_number or card.collector_number,
                "confidence": confidence_after,
                "notes": notes,
            }
        )
        return ValidatedCardResult(
            card=validated_card,
            trace=ValidationTrace(
                original=trace_base["original"],
                normalized_inputs=trace_base["normalized_inputs"],
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
                original=trace_base["original"],
                normalized_inputs=trace_base["normalized_inputs"],
                status=status,
                matched_uuid=match.uuid if match else None,
                matched_set_code=match.set_code if match else None,
                matched_collector_number=match.collector_number if match else None,
                confidence_before=card.confidence,
                confidence_after=confidence_after,
                reason=reason,
            ),
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


def _adjust_confidence(value: float, status: str) -> float:
    if status == "exact_match":
        return min(1.0, round(value + 0.02, 4))
    if status == "normalized_match":
        return round(value, 4)
    if status == "fuzzy_match":
        return max(0.0, round(value - 0.05, 4))
    if status == "ambiguous_match":
        return max(0.0, round(value - 0.2, 4))
    return max(0.0, round(value - 0.25, 4)) if status == "no_match" else round(value, 4)


def _merge_notes(existing: str | None, addition: str) -> str:
    if existing and addition in existing:
        return existing
    if existing:
        return f"{existing} {addition}"
    return addition
