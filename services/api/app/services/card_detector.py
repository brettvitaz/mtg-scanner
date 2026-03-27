"""Card detection using OpenCV to find multiple cards in an image."""

from dataclasses import dataclass

import cv2
import numpy as np


@dataclass(frozen=True, slots=True)
class CardRegion:
    """Represents a detected card region in an image."""

    x: int
    y: int
    width: int
    height: int
    confidence: float
    corners: tuple[tuple[int, int], tuple[int, int], tuple[int, int], tuple[int, int]] | None = None

    @property
    def area(self) -> int:
        return self.width * self.height


@dataclass(frozen=True, slots=True)
class DetectionResult:
    """Result of card detection."""

    regions: list[CardRegion]
    original_shape: tuple[int, int]  # height, width

    @property
    def count(self) -> int:
        return len(self.regions)


class CardDetector:
    """Detects Magic: The Gathering card boundaries in images using OpenCV."""

    TARGET_ASPECT_RATIO = 2.5 / 3.5
    ASPECT_RATIO_TOLERANCE = 0.25
    MIN_CARD_AREA_PERCENT = 0.04
    MAX_CARD_AREA_PERCENT = 0.70
    CROP_PADDING_PERCENT = 0.03
    MIN_RECT_FILL_RATIO = 0.58
    CROP_REFINE_BAND_PERCENT = 0.18
    CROP_REFINE_MIN_INSET_PERCENT = 0.01
    CROP_REFINE_MAX_TRIM_PERCENT = 0.12
    CROP_REFINE_SAFE_MARGIN_PERCENT = 0.012
    CROP_REFINE_MIN_EDGE_CONTRAST = 10.0

    def __init__(
        self,
        aspect_ratio_tolerance: float = ASPECT_RATIO_TOLERANCE,
        min_card_area_percent: float = MIN_CARD_AREA_PERCENT,
        max_card_area_percent: float = MAX_CARD_AREA_PERCENT,
    ) -> None:
        self._aspect_ratio_tolerance = aspect_ratio_tolerance
        self._min_card_area_percent = min_card_area_percent
        self._max_card_area_percent = max_card_area_percent

    def detect(self, image_bytes: bytes) -> DetectionResult:
        image_array = np.frombuffer(image_bytes, dtype=np.uint8)
        image = cv2.imdecode(image_array, cv2.IMREAD_COLOR)

        if image is None:
            return DetectionResult(regions=[], original_shape=(0, 0))

        height, width = image.shape[:2]
        image_area = width * height
        min_card_area = int(image_area * self._min_card_area_percent)
        max_card_area = int(image_area * self._max_card_area_percent)

        candidate_specs = self._build_candidate_specs(image)
        candidates: list[CardRegion] = []
        seen_signatures: set[tuple[int, int, int, int]] = set()

        for mask, retrieval_mode in candidate_specs:
            contours, _ = cv2.findContours(mask, retrieval_mode, cv2.CHAIN_APPROX_SIMPLE)
            for contour in contours:
                candidate = self._candidate_from_contour(contour, min_card_area, max_card_area)
                if candidate is None:
                    continue

                signature = (
                    int(round(candidate.x / 8)),
                    int(round(candidate.y / 8)),
                    int(round(candidate.width / 8)),
                    int(round(candidate.height / 8)),
                )
                if signature in seen_signatures:
                    continue
                seen_signatures.add(signature)
                candidates.append(candidate)

        candidates.extend(self._infer_dense_grid_regions(candidates, image.shape[:2]))

        candidates = self._remove_container_regions(candidates)

        candidates.sort(key=lambda r: (r.confidence, r.area), reverse=True)
        filtered_regions = self._filter_overlapping(candidates)
        filtered_regions.sort(key=lambda r: (r.y, r.x))

        return DetectionResult(regions=filtered_regions, original_shape=(height, width))

    def _build_candidate_specs(self, image: np.ndarray) -> list[tuple[np.ndarray, int]]:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)

        # Edge mask catches strong borders and skewed cards.
        edges = cv2.Canny(blurred, 40, 140)
        edge_kernel = np.ones((5, 5), np.uint8)
        edge_mask = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, edge_kernel, iterations=2)
        edge_mask = cv2.dilate(edge_mask, edge_kernel, iterations=1)

        # Background-distance mask helps when edge detection merges or misses one card.
        bg_mask = self._background_distance_mask(image)

        combined = cv2.bitwise_or(edge_mask, bg_mask)
        combined = cv2.morphologyEx(combined, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8), iterations=2)

        adaptive_mask = cv2.adaptiveThreshold(
            blurred,
            255,
            cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
            cv2.THRESH_BINARY_INV,
            51,
            7,
        )
        adaptive_mask = cv2.morphologyEx(adaptive_mask, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8), iterations=1)
        adaptive_mask = cv2.morphologyEx(adaptive_mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8), iterations=1)

        return [
            (combined, cv2.RETR_EXTERNAL),
            (bg_mask, cv2.RETR_EXTERNAL),
            (edge_mask, cv2.RETR_EXTERNAL),
            (adaptive_mask, cv2.RETR_EXTERNAL),
            (adaptive_mask, cv2.RETR_LIST),
        ]

    def _background_distance_mask(self, image: np.ndarray) -> np.ndarray:
        height, width = image.shape[:2]
        patch_h = max(16, height // 10)
        patch_w = max(16, width // 10)

        lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB).astype(np.float32)
        patches = [
            lab[:patch_h, :patch_w],
            lab[:patch_h, width - patch_w :],
            lab[height - patch_h :, :patch_w],
            lab[height - patch_h :, width - patch_w :],
        ]
        bg_colors = np.array([np.median(p.reshape(-1, 3), axis=0) for p in patches], dtype=np.float32)

        distances = np.stack([np.linalg.norm(lab - color, axis=2) for color in bg_colors], axis=2)
        min_distance = distances.min(axis=2)
        normalized = cv2.normalize(min_distance, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)
        _, mask = cv2.threshold(normalized, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)

        kernel = np.ones((7, 7), np.uint8)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=2)
        return mask

    def _candidate_from_contour(
        self,
        contour: np.ndarray,
        min_card_area: int,
        max_card_area: int,
    ) -> CardRegion | None:
        contour_area = cv2.contourArea(contour)
        if contour_area <= 0:
            return None

        rect = cv2.minAreaRect(contour)
        (_, _), (rect_w, rect_h), _ = rect
        if rect_w <= 1 or rect_h <= 1:
            return None

        rect_area = rect_w * rect_h
        if rect_area < min_card_area or rect_area > max_card_area:
            return None

        short_side = min(rect_w, rect_h)
        long_side = max(rect_w, rect_h)
        if long_side <= 0:
            return None

        aspect_ratio = short_side / long_side
        expected_ratio = self.TARGET_ASPECT_RATIO
        ratio_diff = abs(aspect_ratio - expected_ratio) / expected_ratio
        if ratio_diff > self._aspect_ratio_tolerance:
            return None

        fill_ratio = contour_area / rect_area if rect_area > 0 else 0.0
        if fill_ratio < self.MIN_RECT_FILL_RATIO:
            return None

        box = cv2.boxPoints(rect).astype(np.float32)
        ordered = self._order_points(box)
        x, y, w, h = cv2.boundingRect(ordered.astype(np.int32))
        if w <= 0 or h <= 0:
            return None

        shape_confidence = 1.0 - min(1.0, ratio_diff / max(self._aspect_ratio_tolerance, 1e-6))
        fill_confidence = min(1.0, max(0.0, (fill_ratio - self.MIN_RECT_FILL_RATIO) / 0.3))
        confidence = float(0.7 * shape_confidence + 0.3 * fill_confidence)

        corners = tuple((int(round(p[0])), int(round(p[1]))) for p in ordered)
        return CardRegion(
            x=x,
            y=y,
            width=w,
            height=h,
            confidence=round(confidence, 3),
            corners=corners,
        )

    def _infer_dense_grid_regions(
        self,
        candidates: list[CardRegion],
        image_shape: tuple[int, int],
    ) -> list[CardRegion]:
        dense_candidates = [candidate for candidate in candidates if candidate.confidence >= 0.75]
        if len(dense_candidates) < 8:
            return []

        widths = np.array([candidate.width for candidate in dense_candidates], dtype=np.float32)
        heights = np.array([candidate.height for candidate in dense_candidates], dtype=np.float32)
        median_width = float(np.median(widths))
        median_height = float(np.median(heights))
        if median_width <= 0 or median_height <= 0:
            return []

        normalized_candidates = [
            candidate
            for candidate in dense_candidates
            if 0.75 <= candidate.width / median_width <= 1.35 and 0.75 <= candidate.height / median_height <= 1.35
        ]
        if len(normalized_candidates) < 5:
            return []

        x_centers = [candidate.x + candidate.width / 2 for candidate in normalized_candidates]
        y_centers = [candidate.y + candidate.height / 2 for candidate in normalized_candidates]

        x_clusters = self._cluster_axis(x_centers, threshold=max(80.0, median_width * 0.35))
        y_clusters = self._cluster_axis(y_centers, threshold=max(80.0, median_height * 0.30))
        if len(x_clusters) != 3 or len(y_clusters) != 3:
            return []

        if not self._clusters_are_regular(x_clusters) or not self._clusters_are_regular(y_clusters):
            return []

        inferred_regions: list[CardRegion] = []
        image_height, image_width = image_shape
        match_x_threshold = median_width * 0.28
        match_y_threshold = median_height * 0.28
        occupied_cells = 0

        for y_cluster in y_clusters:
            for x_cluster in x_clusters:
                center_x = float(np.mean(x_cluster))
                center_y = float(np.mean(y_cluster))
                matching_candidates = [
                    candidate
                    for candidate in normalized_candidates
                    if abs((candidate.x + candidate.width / 2) - center_x) <= match_x_threshold
                    and abs((candidate.y + candidate.height / 2) - center_y) <= match_y_threshold
                ]

                if matching_candidates:
                    occupied_cells += 1
                    inferred_regions.append(max(matching_candidates, key=lambda region: (region.confidence, region.area)))
                    continue

                x = max(0, int(round(center_x - median_width / 2)))
                y = max(0, int(round(center_y - median_height / 2)))
                width = min(int(round(median_width)), image_width - x)
                height = min(int(round(median_height)), image_height - y)
                if width <= 0 or height <= 0:
                    continue

                inferred_regions.append(
                    CardRegion(
                        x=x,
                        y=y,
                        width=width,
                        height=height,
                        confidence=0.61,
                        corners=None,
                    )
                )

        return inferred_regions if len(inferred_regions) == 9 and occupied_cells >= 8 else []

    def _cluster_axis(self, values: list[float], threshold: float) -> list[list[float]]:
        if not values:
            return []

        clusters: list[list[float]] = []
        for value in sorted(values):
            if not clusters:
                clusters.append([value])
                continue

            if abs(value - float(np.mean(clusters[-1]))) <= threshold:
                clusters[-1].append(value)
            else:
                clusters.append([value])

        return [cluster for cluster in clusters if cluster]

    def _clusters_are_regular(self, clusters: list[list[float]]) -> bool:
        if len(clusters) != 3:
            return False

        centers = [float(np.mean(cluster)) for cluster in clusters]
        gaps = [centers[index + 1] - centers[index] for index in range(len(centers) - 1)]
        if any(gap <= 0 for gap in gaps):
            return False

        gap_ratio = max(gaps) / min(gaps)
        return gap_ratio <= 1.4

    def _remove_container_regions(self, regions: list[CardRegion]) -> list[CardRegion]:
        if len(regions) < 2:
            return regions

        filtered: list[CardRegion] = []
        for region in regions:
            enclosed_regions = [other for other in regions if other is not region and self._contains(region, other)]
            if len(enclosed_regions) >= 2:
                contained_coverage = max((self._intersection_ratio(region, other) for other in enclosed_regions), default=0.0)
                enclosed_area_ratio = sum(other.area for other in enclosed_regions) / max(region.area, 1)
                if enclosed_area_ratio >= 0.8 and contained_coverage < 0.95:
                    continue

            filtered.append(region)
        return filtered

    def _contains(self, outer: CardRegion, inner: CardRegion, tolerance: int = 24) -> bool:
        return (
            inner.x >= outer.x - tolerance
            and inner.y >= outer.y - tolerance
            and inner.x + inner.width <= outer.x + outer.width + tolerance
            and inner.y + inner.height <= outer.y + outer.height + tolerance
        )

    def _filter_overlapping(self, regions: list[CardRegion], iou_threshold: float = 0.45) -> list[CardRegion]:
        if not regions:
            return []

        filtered: list[CardRegion] = []
        for region in regions:
            is_overlapping = False
            for existing in filtered:
                overlap = self._polygon_iou(region, existing) if region.corners and existing.corners else self._iou(region, existing)
                if overlap > iou_threshold:
                    is_overlapping = True
                    break

                if self._is_nested_subregion(existing, region):
                    is_overlapping = True
                    break
                if self._is_nested_subregion(region, existing):
                    filtered.remove(existing)
                    break
            if not is_overlapping:
                filtered.append(region)
        return filtered

    def _is_nested_subregion(self, outer: CardRegion, inner: CardRegion) -> bool:
        width_ratio = inner.width / max(outer.width, 1)
        height_ratio = inner.height / max(outer.height, 1)
        area_ratio = inner.area / max(outer.area, 1)
        center_distance_x = abs((inner.x + inner.width / 2) - (outer.x + outer.width / 2))
        intersection_ratio = self._intersection_ratio(outer, inner)
        strong_containment = self._contains(outer, inner, tolerance=32) or intersection_ratio >= 0.92
        almost_fully_contained_smaller = intersection_ratio >= 0.98 and area_ratio <= 0.6
        confidence_tolerance = 0.35 if almost_fully_contained_smaller else 0.3
        return (
            strong_containment
            and (center_distance_x <= outer.width * 0.18 or almost_fully_contained_smaller)
            and max(width_ratio, height_ratio) <= 0.97
            and area_ratio <= 0.75
            and inner.confidence >= outer.confidence - confidence_tolerance
        )

    def _intersection_ratio(self, outer: CardRegion, inner: CardRegion) -> float:
        x1 = max(outer.x, inner.x)
        y1 = max(outer.y, inner.y)
        x2 = min(outer.x + outer.width, inner.x + inner.width)
        y2 = min(outer.y + outer.height, inner.y + inner.height)

        if x2 <= x1 or y2 <= y1:
            return 0.0

        intersection = (x2 - x1) * (y2 - y1)
        return intersection / max(inner.area, 1)

    def _iou(self, r1: CardRegion, r2: CardRegion) -> float:
        x1 = max(r1.x, r2.x)
        y1 = max(r1.y, r2.y)
        x2 = min(r1.x + r1.width, r2.x + r2.width)
        y2 = min(r1.y + r1.height, r2.y + r2.height)

        if x2 <= x1 or y2 <= y1:
            return 0.0

        intersection = (x2 - x1) * (y2 - y1)
        union = r1.area + r2.area - intersection
        return intersection / union if union > 0 else 0.0

    def _polygon_iou(self, r1: CardRegion, r2: CardRegion) -> float:
        if not r1.corners or not r2.corners:
            return self._iou(r1, r2)

        poly1 = np.array(r1.corners, dtype=np.float32)
        poly2 = np.array(r2.corners, dtype=np.float32)
        intersection_area, _ = cv2.intersectConvexConvex(poly1, poly2)
        union_area = cv2.contourArea(poly1) + cv2.contourArea(poly2) - intersection_area
        if union_area <= 0:
            return 0.0
        return float(intersection_area / union_area)

    def crop_region(self, image_bytes: bytes, region: CardRegion) -> tuple[bytes, str]:
        image_array = np.frombuffer(image_bytes, dtype=np.uint8)
        image = cv2.imdecode(image_array, cv2.IMREAD_COLOR)

        if image is None:
            return image_bytes, "image/jpeg"

        if region.corners:
            cropped = self._perspective_crop(image, region)
        else:
            cropped = self._bounding_box_crop(image, region)

        cropped = self._refine_cropped_card(cropped)

        _, encoded = cv2.imencode(".jpg", cropped)
        return encoded.tobytes(), "image/jpeg"

    def _bounding_box_crop(self, image: np.ndarray, region: CardRegion) -> np.ndarray:
        padding_x = int(region.width * self.CROP_PADDING_PERCENT)
        padding_y = int(region.height * self.CROP_PADDING_PERCENT)
        x1 = max(0, region.x - padding_x)
        y1 = max(0, region.y - padding_y)
        x2 = min(image.shape[1], region.x + region.width + padding_x)
        y2 = min(image.shape[0], region.y + region.height + padding_y)
        return image[y1:y2, x1:x2]

    def _perspective_crop(self, image: np.ndarray, region: CardRegion) -> np.ndarray:
        corners = np.array(region.corners, dtype=np.float32)
        tl, tr, br, bl = corners

        expanded = self._expand_quad(corners, self.CROP_PADDING_PERCENT)
        tl, tr, br, bl = expanded

        width_top = np.linalg.norm(tr - tl)
        width_bottom = np.linalg.norm(br - bl)
        height_right = np.linalg.norm(br - tr)
        height_left = np.linalg.norm(bl - tl)

        measured_width = max(float(width_top), float(width_bottom), 1.0)
        measured_height = max(float(height_right), float(height_left), 1.0)
        long_side = max(measured_width, measured_height)
        target_height = max(int(round(long_side)), 1)
        target_width = max(int(round(target_height * self.TARGET_ASPECT_RATIO)), 1)

        destination = np.array(
            [
                [0, 0],
                [target_width - 1, 0],
                [target_width - 1, target_height - 1],
                [0, target_height - 1],
            ],
            dtype=np.float32,
        )

        transform = cv2.getPerspectiveTransform(expanded, destination)
        warped = cv2.warpPerspective(image, transform, (target_width, target_height))
        return warped

    def debug_overlay(self, image_bytes: bytes, detection_result: DetectionResult) -> bytes:
        """Render detected card outlines on top of the original image for diagnosis."""
        image_array = np.frombuffer(image_bytes, dtype=np.uint8)
        image = cv2.imdecode(image_array, cv2.IMREAD_COLOR)
        if image is None:
            return image_bytes

        for index, region in enumerate(detection_result.regions, start=1):
            color = (0, 255, 0)
            if region.corners:
                points = np.array(region.corners, dtype=np.int32).reshape((-1, 1, 2))
                cv2.polylines(image, [points], True, color, 3)
                anchor = tuple(points[0][0])
            else:
                cv2.rectangle(image, (region.x, region.y), (region.x + region.width, region.y + region.height), color, 3)
                anchor = (region.x, region.y)
            cv2.putText(
                image,
                f"{index}:{region.confidence:.2f}",
                (anchor[0], max(20, anchor[1] - 10)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.7,
                (0, 255, 255),
                2,
                cv2.LINE_AA,
            )

        _, encoded = cv2.imencode(".jpg", image)
        return encoded.tobytes()

    def _refine_cropped_card(self, crop: np.ndarray) -> np.ndarray:
        refined = crop
        for _ in range(2):
            if refined.size == 0:
                return refined

            height, width = refined.shape[:2]
            min_dimension = min(height, width)
            if min_dimension < 80:
                return refined

            gray = cv2.cvtColor(refined, cv2.COLOR_BGR2GRAY)
            gray = cv2.GaussianBlur(gray, (5, 5), 0)

            row_signal = cv2.GaussianBlur(gray.mean(axis=1).astype(np.float32).reshape(-1, 1), (1, 15), 0).ravel()
            col_signal = cv2.GaussianBlur(gray.mean(axis=0).astype(np.float32).reshape(-1, 1), (1, 15), 0).ravel()

            trim = self._find_trim_bounds(row_signal, col_signal, width, height)
            if trim is None:
                break

            left, top, right, bottom = trim
            candidate = refined[top : bottom + 1, left : right + 1]
            if candidate.size == 0 or candidate.shape == refined.shape:
                break

            refined = candidate

        return refined

    def _find_trim_bounds(
        self,
        row_signal: np.ndarray,
        col_signal: np.ndarray,
        width: int,
        height: int,
    ) -> tuple[int, int, int, int] | None:
        min_inset_x = max(2, int(round(width * self.CROP_REFINE_MIN_INSET_PERCENT)))
        min_inset_y = max(2, int(round(height * self.CROP_REFINE_MIN_INSET_PERCENT)))
        band_x = max(min_inset_x + 10, int(round(width * self.CROP_REFINE_BAND_PERCENT)))
        band_y = max(min_inset_y + 10, int(round(height * self.CROP_REFINE_BAND_PERCENT)))
        max_trim_x = max(min_inset_x + 1, int(round(width * self.CROP_REFINE_MAX_TRIM_PERCENT)))
        max_trim_y = max(min_inset_y + 1, int(round(height * self.CROP_REFINE_MAX_TRIM_PERCENT)))

        left = self._edge_trim_position(col_signal, min_inset_x, min(band_x, width - min_inset_x - 2), side="left")
        right = self._edge_trim_position(col_signal, max(width - band_x - 1, min_inset_x + 1), width - min_inset_x - 2, side="right")
        top = self._edge_trim_position(row_signal, min_inset_y, min(band_y, height - min_inset_y - 2), side="top")
        bottom = self._edge_trim_position(row_signal, max(height - band_y - 1, min_inset_y + 1), height - min_inset_y - 2, side="bottom")

        if None in (left, right, top, bottom):
            return None

        assert left is not None and right is not None and top is not None and bottom is not None

        left = min(left, max_trim_x)
        top = min(top, max_trim_y)
        right = max(right, width - max_trim_x - 1)
        bottom = max(bottom, height - max_trim_y - 1)

        if right <= left + width * 0.55 or bottom <= top + height * 0.55:
            return None

        trimmed_width = right - left + 1
        trimmed_height = bottom - top + 1
        aspect_ratio = trimmed_width / max(trimmed_height, 1)
        ratio_diff = abs(aspect_ratio - self.TARGET_ASPECT_RATIO) / self.TARGET_ASPECT_RATIO
        if ratio_diff > 0.10:
            return None

        area_ratio = (trimmed_width * trimmed_height) / max(width * height, 1)
        if not 0.78 <= area_ratio <= 0.99:
            return None

        return left, top, right, bottom

    def _edge_trim_position(self, signal: np.ndarray, start: int, end: int, side: str) -> int | None:
        if end <= start:
            return None

        window = signal[start : end + 1].astype(np.float32)
        if window.size < 6:
            return None

        reversed_side = side in {"right", "bottom"}
        search_window = window[::-1] if reversed_side else window

        sample_span = max(4, min(12, search_window.size // 2))
        outer_mean = float(search_window[:sample_span].mean())
        darkest_index = int(np.argmin(search_window))
        darkest_mean = float(
            search_window[max(0, darkest_index - 1) : min(search_window.shape[0], darkest_index + sample_span)].mean()
        )
        contrast = outer_mean - darkest_mean

        threshold = outer_mean - max(self.CROP_REFINE_MIN_EDGE_CONTRAST, contrast * 0.35)
        run_length = max(2, min(4, search_window.size // 8))
        edge_index: int | None = None
        if contrast >= self.CROP_REFINE_MIN_EDGE_CONTRAST:
            for index in range(0, search_window.size - run_length + 1):
                segment = search_window[index : index + run_length]
                if float(segment.mean()) <= threshold:
                    edge_index = index
                    break

        if edge_index is None:
            fallback_contrast = outer_mean - float(search_window[darkest_index])
            if fallback_contrast < self.CROP_REFINE_MIN_EDGE_CONTRAST * 0.55:
                return None
            edge_index = darkest_index

        safe_margin = max(2, int(round(signal.shape[0] * self.CROP_REFINE_SAFE_MARGIN_PERCENT)))
        if reversed_side:
            edge_position = end - edge_index
            return min(signal.shape[0] - 1, edge_position + safe_margin)

        edge_position = start + edge_index
        return max(0, edge_position - safe_margin)

    def _expand_quad(self, corners: np.ndarray, padding_percent: float) -> np.ndarray:
        center = corners.mean(axis=0)
        expanded = center + (corners - center) * (1.0 + padding_percent)
        return expanded.astype(np.float32)

    def _order_points(self, points: np.ndarray) -> np.ndarray:
        rect = np.zeros((4, 2), dtype=np.float32)
        s = points.sum(axis=1)
        rect[0] = points[np.argmin(s)]
        rect[2] = points[np.argmax(s)]

        diff = np.diff(points, axis=1)
        rect[1] = points[np.argmin(diff)]
        rect[3] = points[np.argmax(diff)]
        return rect


def get_card_detector() -> CardDetector:
    return CardDetector()
