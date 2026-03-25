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
    MIN_CARD_AREA_PERCENT = 0.06
    MAX_CARD_AREA_PERCENT = 0.70
    CROP_PADDING_PERCENT = 0.03

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

        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        edges = cv2.Canny(blurred, 50, 150)

        kernel = np.ones((5, 5), np.uint8)
        dilated = cv2.dilate(edges, kernel, iterations=2)

        contours, _ = cv2.findContours(dilated, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)

        regions: list[CardRegion] = []
        for contour in contours:
            hull = cv2.convexHull(contour)
            epsilon = 0.02 * cv2.arcLength(hull, True)
            approx = cv2.approxPolyDP(hull, epsilon, True)

            if len(approx) != 4:
                continue

            points = approx.reshape(4, 2).astype(np.float32)
            ordered = self._order_points(points)

            x, y, w, h = cv2.boundingRect(approx)
            if h == 0:
                continue

            area = w * h
            if area < min_card_area or area > max_card_area:
                continue

            width_a = np.linalg.norm(ordered[2] - ordered[3])
            width_b = np.linalg.norm(ordered[1] - ordered[0])
            height_a = np.linalg.norm(ordered[1] - ordered[2])
            height_b = np.linalg.norm(ordered[0] - ordered[3])
            card_width = max(width_a, width_b)
            card_height = max(height_a, height_b)
            if card_height == 0:
                continue

            aspect_ratio = min(card_width, card_height) / max(card_width, card_height)
            expected_ratio = self.TARGET_ASPECT_RATIO
            ratio_diff = abs(aspect_ratio - expected_ratio) / expected_ratio
            if ratio_diff > self._aspect_ratio_tolerance:
                continue

            shape_confidence = float(max(0.0, 1.0 - ratio_diff / self._aspect_ratio_tolerance))
            corners = tuple((int(p[0]), int(p[1])) for p in ordered)
            regions.append(
                CardRegion(
                    x=x,
                    y=y,
                    width=w,
                    height=h,
                    confidence=round(shape_confidence, 3),
                    corners=corners,
                )
            )

        regions.sort(key=lambda r: r.area, reverse=True)
        filtered_regions = self._filter_overlapping(regions)

        return DetectionResult(regions=filtered_regions, original_shape=(height, width))

    def _filter_overlapping(self, regions: list[CardRegion], iou_threshold: float = 0.3) -> list[CardRegion]:
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
        x1 = max(r1.x, r2.x)
        y1 = max(r1.y, r2.y)
        x2 = min(r1.x + r1.width, r2.x + r2.width)
        y2 = min(r1.y + r1.height, r2.y + r2.height)

        if x2 <= x1 or y2 <= y1:
            return 0.0

        intersection = (x2 - x1) * (y2 - y1)
        union = r1.area + r2.area - intersection
        return intersection / union if union > 0 else 0.0

    def crop_region(self, image_bytes: bytes, region: CardRegion) -> tuple[bytes, str]:
        image_array = np.frombuffer(image_bytes, dtype=np.uint8)
        image = cv2.imdecode(image_array, cv2.IMREAD_COLOR)

        if image is None:
            return image_bytes, "image/jpeg"

        if region.corners:
            cropped = self._perspective_crop(image, region)
        else:
            cropped = self._bounding_box_crop(image, region)

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

        width_top = np.linalg.norm(tr - tl)
        width_bottom = np.linalg.norm(br - bl)
        height_right = np.linalg.norm(br - tr)
        height_left = np.linalg.norm(bl - tl)

        target_width = max(int(max(width_top, width_bottom)), 1)
        target_height = max(int(max(height_right, height_left)), 1)

        if target_width > target_height:
            target_width, target_height = target_height, target_width

        padded_width = max(int(target_width * (1 + self.CROP_PADDING_PERCENT * 2)), 1)
        padded_height = max(int(target_height * (1 + self.CROP_PADDING_PERCENT * 2)), 1)
        offset_x = int((padded_width - target_width) / 2)
        offset_y = int((padded_height - target_height) / 2)

        destination = np.array(
            [
                [offset_x, offset_y],
                [offset_x + target_width - 1, offset_y],
                [offset_x + target_width - 1, offset_y + target_height - 1],
                [offset_x, offset_y + target_height - 1],
            ],
            dtype=np.float32,
        )

        transform = cv2.getPerspectiveTransform(corners, destination)
        warped = cv2.warpPerspective(image, transform, (padded_width, padded_height))
        return warped

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
