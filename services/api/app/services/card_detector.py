"""Card detection using OpenCV to find multiple cards in an image."""

from dataclasses import dataclass
from pathlib import Path

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

    # MTG cards have an aspect ratio of approximately 2.5:3.5 (width:height) = ~0.714
    # Allow some tolerance for perspective distortion
    TARGET_ASPECT_RATIO = 2.5 / 3.5
    ASPECT_RATIO_TOLERANCE = 0.25  # ±25% tolerance

    # Minimum card area as percentage of image area (bounding rect)
    MIN_CARD_AREA_PERCENT = 0.06  # Card must be at least 6% of image
    # Maximum card area as percentage of image area (filters background contour)
    MAX_CARD_AREA_PERCENT = 0.70  # Card must be at most 70% of image

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
        """Detect card regions in the given image bytes.

        Args:
            image_bytes: Raw image bytes (JPEG, PNG, etc.)

        Returns:
            DetectionResult containing detected card regions
        """
        # Decode image
        image_array = np.frombuffer(image_bytes, dtype=np.uint8)
        image = cv2.imdecode(image_array, cv2.IMREAD_COLOR)

        if image is None:
            return DetectionResult(regions=[], original_shape=(0, 0))

        height, width = image.shape[:2]
        image_area = width * height
        min_card_area = int(image_area * self._min_card_area_percent)
        max_card_area = int(image_area * self._max_card_area_percent)

        # Preprocess: convert to grayscale and blur
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)

        # Edge detection
        edges = cv2.Canny(blurred, 50, 150)

        # Dilate to connect edges
        kernel = np.ones((5, 5), np.uint8)
        dilated = cv2.dilate(edges, kernel, iterations=2)

        # Find contours — use RETR_LIST to capture all contours including inner card boundaries
        contours, _ = cv2.findContours(
            dilated, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE
        )

        regions: list[CardRegion] = []
        for contour in contours:
            # Use convexHull to normalize irregular/fragmented contours to convex shapes
            hull = cv2.convexHull(contour)
            epsilon = 0.02 * cv2.arcLength(hull, True)
            approx = cv2.approxPolyDP(hull, epsilon, True)

            # Check if it's a quadrilateral (4 corners)
            if len(approx) != 4:
                continue

            # Get bounding rectangle for size and aspect ratio check
            x, y, w, h = cv2.boundingRect(approx)
            if h == 0:
                continue

            # Use bounding rect area for size filtering (contour area is unreliable for
            # partial/fragmented contours where only some edges are detected)
            area = w * h
            if area < min_card_area or area > max_card_area:
                continue

            aspect_ratio = w / h
            expected_ratio = self.TARGET_ASPECT_RATIO
            ratio_diff = abs(aspect_ratio - expected_ratio) / expected_ratio

            if ratio_diff > self._aspect_ratio_tolerance:
                continue

            # Calculate confidence based on aspect ratio closeness to ideal MTG card ratio
            shape_confidence = max(0.0, 1.0 - ratio_diff / self._aspect_ratio_tolerance)

            regions.append(
                CardRegion(
                    x=x,
                    y=y,
                    width=w,
                    height=h,
                    confidence=round(shape_confidence, 3),
                )
            )

        # Sort by area (largest first) to prioritize main cards over artifacts
        regions.sort(key=lambda r: r.area, reverse=True)

        # Filter out overlapping regions (keep the larger one)
        filtered_regions = self._filter_overlapping(regions)

        return DetectionResult(
            regions=filtered_regions,
            original_shape=(height, width),
        )

    def _filter_overlapping(
        self, regions: list[CardRegion], iou_threshold: float = 0.3
    ) -> list[CardRegion]:
        """Filter out overlapping regions, keeping larger ones.

        Args:
            regions: List of detected regions
            iou_threshold: Intersection over Union threshold for overlap

        Returns:
            Filtered list of regions
        """
        if not regions:
            return []

        filtered: list[CardRegion] = []
        for region in regions:
            is_overlapping = False
            for existing in filtered:
                if self._iou(region, existing) > iou_threshold:
                    is_overlapping = True
                    break
            if not is_overlapping:
                filtered.append(region)
        return filtered

    def _iou(self, r1: CardRegion, r2: CardRegion) -> float:
        """Calculate Intersection over Union of two regions."""
        x1 = max(r1.x, r2.x)
        y1 = max(r1.y, r2.y)
        x2 = min(r1.x + r1.width, r2.x + r2.width)
        y2 = min(r1.y + r1.height, r2.y + r2.height)

        if x2 <= x1 or y2 <= y1:
            return 0.0

        intersection = (x2 - x1) * (y2 - y1)
        union = r1.area + r2.area - intersection

        return intersection / union if union > 0 else 0.0

    def crop_region(
        self, image_bytes: bytes, region: CardRegion
    ) -> tuple[bytes, str]:
        """Crop a region from the image and return as JPEG bytes.

        Args:
            image_bytes: Raw image bytes
            region: CardRegion to crop

        Returns:
            Tuple of (cropped_image_bytes, content_type)
        """
        image_array = np.frombuffer(image_bytes, dtype=np.uint8)
        image = cv2.imdecode(image_array, cv2.IMREAD_COLOR)

        if image is None:
            return image_bytes, "image/jpeg"

        # Add small padding (2%) to ensure we capture the full card
        padding_x = int(region.width * 0.02)
        padding_y = int(region.height * 0.02)

        x1 = max(0, region.x - padding_x)
        y1 = max(0, region.y - padding_y)
        x2 = min(image.shape[1], region.x + region.width + padding_x)
        y2 = min(image.shape[0], region.y + region.height + padding_y)

        cropped = image[y1:y2, x1:x2]

        # Encode as JPEG
        _, encoded = cv2.imencode(".jpg", cropped)
        return encoded.tobytes(), "image/jpeg"


def get_card_detector() -> CardDetector:
    """Factory function for CardDetector."""
    return CardDetector()
