"""HTTP API for the Phase 1 Keras-OCR backend."""

from __future__ import annotations

import io
import logging
import os
import re
import threading
import time
import uuid
from dataclasses import dataclass
from typing import Any, Protocol

import cv2
import numpy as np
from flask import Flask, jsonify, request
from PIL import Image, ImageOps, UnidentifiedImageError


MAX_IMAGE_BYTES = 10 * 1024 * 1024
ALLOWED_IMAGE_PREFIX = "image/"
DATE_LABELS = (
    "MFD",
    "MFG",
    "PKD",
    "EXP",
    "EXPIRY",
    "USE BY",
    "BEST BEFORE",
)
RECOGNIZER_MODES = ("pretrained", "date_custom", "custom_all")
LOGGER = logging.getLogger(__name__)


class OcrEngine(Protocol):
    """Minimal contract used by the HTTP layer and tests."""

    def recognize(self, image: np.ndarray) -> list[tuple[str, Any]]:
        """Return recognized text and its polygon for one image."""

    def recognize_date(self, image: np.ndarray) -> list[tuple[str, Any]]:
        """Recognize a date-focused image when custom mode is enabled."""

    def recognize_date_candidates(
        self,
        image: np.ndarray,
        detections: list[dict[str, Any]],
    ) -> list[tuple[str, Any]]:
        """Recognize bounded crops selected from an existing detector pass."""


class KerasOcrEngine:
    """Lazy wrapper around pretrained and optional custom Keras-OCR pipelines."""

    def __init__(
        self,
        recognizer_mode: str = "pretrained",
        date_retry_mode: str = "custom_lightweight",
    ) -> None:
        if recognizer_mode not in RECOGNIZER_MODES:
            raise ValueError(
                f"OCR_RECOGNIZER_MODE must be one of {', '.join(RECOGNIZER_MODES)}."
            )
        self.recognizer_mode = recognizer_mode
        self.date_retry_mode = date_retry_mode
        self._custom_pipeline = None
        self.debug_candidate_metadata: list[dict[str, Any]] = []
        self.debug_image_id = "ocr"
        self.last_detector_input_size: tuple[int, int] | None = None
        # Keras-OCR 0.9.3 currently imports imgaug, which still expects this
        # NumPy 1.x compatibility mapping. Keep the workaround local to the
        # backend import boundary until that dependency is updated.
        if not hasattr(np, "sctypes"):
            np.sctypes = {
                "int": [np.int8, np.int16, np.int32, np.int64],
                "uint": [np.uint8, np.uint16, np.uint32, np.uint64],
                "float": [np.float16, np.float32, np.float64],
                "complex": [np.complex64, np.complex128],
                "others": [bool, object, bytes, str, np.void],
            }
        os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")
        import keras_ocr

        self._pipeline = keras_ocr.pipeline.Pipeline()
        # Load the optional date recognizer once, before the first phone
        # request. Its detector is shared with the pretrained pipeline.
        if self.date_retry_mode == "custom_lightweight":
            self._get_custom_pipeline()

    def recognize(self, image: np.ndarray) -> list[tuple[str, Any]]:
        return self._recognize_scaled(self._pipeline, image)

    def recognize_date(self, image: np.ndarray) -> list[tuple[str, Any]]:
        if self.date_retry_mode != "custom_lightweight":
            return self.recognize(image)
        pipeline = self._get_custom_pipeline()
        return self._recognize_scaled(pipeline, image)

    def _recognize_scaled(self, pipeline: Any, image: np.ndarray) -> list[tuple[str, Any]]:
        height, width = image.shape[:2]
        long_side = max(height, width)
        detector_long_side = max(
            640.0,
            min(2400.0, float(os.environ.get("OCR_DETECTOR_LONG_SIDE", "1600"))),
        )
        scale = min(1.0, detector_long_side / long_side) if long_side else 1.0
        if scale < 1.0:
            detector_image = cv2.resize(
                image,
                (max(1, round(width * scale)), max(1, round(height * scale))),
                interpolation=cv2.INTER_AREA,
            )
        else:
            detector_image = image
        self.last_detector_input_size = (
            int(detector_image.shape[1]),
            int(detector_image.shape[0]),
        )
        predictions = pipeline.recognize([detector_image])
        if not predictions:
            return []
        if scale == 1.0:
            return list(predictions[0])
        mapped: list[tuple[str, Any]] = []
        for prediction in predictions[0]:
            if len(prediction) < 2:
                continue
            text, box = prediction[0], np.asarray(prediction[1], dtype=np.float32)
            mapped.append((text, box / scale, *prediction[2:]))
        return mapped

    def recognize_date_candidates(
        self,
        image: np.ndarray,
        detections: list[dict[str, Any]],
    ) -> list[tuple[str, Any]]:
        if self.date_retry_mode != "custom_lightweight":
            return self.recognize(image)
        recognizer = self._get_custom_pipeline().recognizer
        results: list[tuple[str, Any]] = []
        self.debug_candidate_metadata = []
        height, width = image.shape[:2]
        padding_percent = max(
            0.0,
            min(0.25, float(os.environ.get("OCR_DATE_CROP_PADDING", "0"))),
        )
        variant_limit = max(
            1, min(3, int(os.environ.get("OCR_DATE_VARIANT_LIMIT", "2")))
        )
        candidate_limit = max(
            1, min(15, int(os.environ.get("OCR_DATE_CANDIDATE_LIMIT", "8")))
        )
        upscale_mode = os.environ.get(
            "OCR_DATE_UPSCALE_MODE", "cubic"
        ).lower()
        for candidate_index, detection in enumerate(
            _select_date_candidates(detections, width, height, limit=candidate_limit), 1
        ):
            box = np.asarray(detection["box"], dtype=np.float32)
            left, top = np.floor(box.min(axis=0)).astype(int)
            right, bottom = np.ceil(box.max(axis=0)).astype(int)
            crop_width = right - left
            crop_height = bottom - top
            left -= round(crop_width * padding_percent)
            right += round(crop_width * padding_percent)
            top -= round(crop_height * padding_percent)
            bottom += round(crop_height * padding_percent)
            left, top = max(0, left), max(0, top)
            right, bottom = min(width, right), min(height, bottom)
            if right - left < 8 or bottom - top < 8:
                continue
            crop = image[top:bottom, left:right]
            variants = [crop]
            if max(crop.shape[:2]) < 1200:
                scale = min(
                    float(os.environ.get("OCR_DATE_UPSCALE_SCALE", "2")),
                    1200 / max(crop.shape[:2]),
                )
                variants.append(
                    cv2.resize(
                        crop,
                        (max(1, round(crop.shape[1] * scale)), max(1, round(crop.shape[0] * scale))),
                        interpolation=(
                            cv2.INTER_LANCZOS4
                            if upscale_mode == "lanczos"
                            else cv2.INTER_CUBIC
                        ),
                    )
                )
            if variant_limit >= 3:
                gray = cv2.cvtColor(variants[-1], cv2.COLOR_RGB2GRAY)
                variants.append(
                    cv2.cvtColor(
                        cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(gray),
                        cv2.COLOR_GRAY2RGB,
                    )
                )
            recognized: list[dict[str, Any]] = []
            for variant_index, variant in enumerate(variants[:variant_limit]):
                text = str(recognizer.recognize(variant)).strip()
                score = _date_text_score(text) + (
                    50 if _contains_valid_date(text) else 0
                )
                variant_name = (
                    "original"
                    if variant_index == 0
                    else "upscaled_lanczos"
                    if upscale_mode == "lanczos" and variant_index == 1
                    else "upscaled_cubic"
                    if variant_index == 1
                    else "clahe"
                )
                if _debug_enabled():
                    _save_debug_image(
                        variant,
                        (
                            f"{self.debug_image_id}_candidate{candidate_index:02d}_"
                            f"x{left}_y{top}_w{right-left}_h{bottom-top}_{variant_name}"
                        ),
                    )
                recognized.append(
                    {
                        "variant": variant_name,
                        "text": text,
                        "score": score,
                        "width": int(variant.shape[1]),
                        "height": int(variant.shape[0]),
                    }
                )
                if variant_index == 0 and _contains_valid_date(text):
                    break
            chosen = _choose_date_variant(recognized)
            text = chosen["text"]
            if text:
                results.append((text, box, "custom_date"))
            if _debug_enabled():
                self.debug_candidate_metadata.append(
                    {
                        "index": candidate_index,
                        "source_text": str(detection.get("text", "")),
                        "bounds": {
                            "left": int(left),
                            "top": int(top),
                            "right": int(right),
                            "bottom": int(bottom),
                        },
                        "crop_size": {
                            "width": int(right - left),
                            "height": int(bottom - top),
                        },
                        "right_edge_clipped": bool(right >= width),
                        "bottom_edge_clipped": bool(bottom >= height),
                        "variants": recognized,
                        "chosen_text": text,
                        "chosen_score": chosen["score"],
                    }
                )
        return results

    def _get_custom_pipeline(self):
        if self._custom_pipeline is None:
            from .custom_recognizer import build_custom_recognizer

            custom_recognizer = build_custom_recognizer()
            import keras_ocr

            self._custom_pipeline = keras_ocr.pipeline.Pipeline(
                detector=self._pipeline.detector,
                recognizer=custom_recognizer,
            )
        return self._custom_pipeline

    def recognize_batch(
        self,
        images: list[np.ndarray],
    ) -> list[list[tuple[str, Any]]]:
        predictions = self._pipeline.recognize(images)
        return [list(item) for item in predictions]


@dataclass
class BackendError(Exception):
    status_code: int
    message: str


def _read_image() -> np.ndarray:
    uploaded = request.files.get("image")
    if uploaded is None or not uploaded.filename:
        raise BackendError(400, "Provide an image file in the 'image' form field.")

    if uploaded.content_type and not uploaded.content_type.startswith(ALLOWED_IMAGE_PREFIX):
        raise BackendError(415, "The uploaded file must have an image content type.")

    image_bytes = uploaded.read(MAX_IMAGE_BYTES + 1)
    if len(image_bytes) > MAX_IMAGE_BYTES:
        raise BackendError(413, "The image must be 10 MB or smaller.")

    try:
        with Image.open(io.BytesIO(image_bytes)) as image:
            oriented = ImageOps.exif_transpose(image)
            return np.asarray(oriented.convert("RGB"))
    except (UnidentifiedImageError, OSError) as error:
        raise BackendError(400, "The uploaded file is not a readable image.") from error


def _debug_enabled() -> bool:
    return os.environ.get("OCR_DEBUG", "").lower() in {"1", "true", "yes"}


def _save_debug_image(image: np.ndarray, label: str) -> None:
    directory = os.environ.get("OCR_DEBUG_DIR")
    if not _debug_enabled() or not directory:
        return
    try:
        os.makedirs(directory, exist_ok=True)
        safe_label = "".join(character if character.isalnum() else "_" for character in label)
        path = os.path.join(directory, f"{uuid.uuid4().hex}_{safe_label}.jpg")
        Image.fromarray(image).save(path, quality=95)
    except (OSError, ValueError) as error:
        LOGGER.warning("Unable to save OCR debug image: %s", error)


def _json_value(value: Any) -> Any:
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, (np.integer, np.floating)):
        return value.item()
    if isinstance(value, (list, tuple)):
        return [_json_value(item) for item in value]
    return value


def _prediction_box(prediction: tuple[str, Any]) -> np.ndarray | None:
    try:
        box = np.asarray(prediction[1], dtype=np.float32)
    except (IndexError, TypeError, ValueError):
        return None
    return box if box.shape == (4, 2) else None


def _sort_predictions(
    predictions: list[tuple[str, Any]],
) -> list[tuple[str, Any]]:
    valid = [item for item in predictions if _prediction_box(item) is not None]
    if len(valid) < 2:
        return valid

    heights = [
        float(np.max(_prediction_box(item)[:, 1]) - np.min(_prediction_box(item)[:, 1]))
        for item in valid
    ]
    line_tolerance = max(8.0, float(np.median(heights)) * 0.65)
    lines: list[list[tuple[str, Any]]] = []
    line_centers: list[float] = []
    for item in sorted(
        valid,
        key=lambda value: (
            float(np.mean(_prediction_box(value)[:, 1])),
            float(np.min(_prediction_box(value)[:, 0])),
        ),
    ):
        center_y = float(np.mean(_prediction_box(item)[:, 1]))
        match = next(
            (
                index
                for index, line_center in enumerate(line_centers)
                if abs(center_y - line_center) <= line_tolerance
            ),
            None,
        )
        if match is None:
            lines.append([item])
            line_centers.append(center_y)
        else:
            lines[match].append(item)
            line_centers[match] = float(
                np.mean([line_centers[match], center_y])
            )

    ordered: list[tuple[str, Any]] = []
    for line in sorted(zip(line_centers, lines), key=lambda value: value[0]):
        ordered.extend(
            sorted(
                line[1],
                key=lambda value: float(np.min(_prediction_box(value)[:, 0])),
            )
        )
    return ordered


def _serialize_detections(predictions: list[tuple[str, Any]]) -> list[dict[str, Any]]:
    detections = []
    for prediction in _sort_predictions(predictions):
        if not isinstance(prediction, (list, tuple)) or len(prediction) < 2:
            continue
        text, box = prediction[0], prediction[1]
        source = "pretrained"
        if len(prediction) >= 3 and prediction[2]:
            source = str(prediction[2])
        detections.append({"text": str(text), "box": _json_value(box), "recognizer": source})
    return detections


def _date_text_score(text: str) -> int:
    value = sum(character.isdigit() for character in text)
    value += 4 if any(separator in text for separator in ("/", "-", ".")) else 0
    value -= 3 if len(text) > 40 else 0
    return value


def _contains_valid_date(text: str) -> bool:
    for match in re.finditer(r"\b(\d{1,2})\s*[/.-]\s*(\d{1,2})\s*[/.-]\s*(\d{2,4})\b", text):
        day, month, year = (int(value) for value in match.groups())
        if year < 100:
            year += 2000
        if 1 <= day <= 31 and 1 <= month <= 12 and 2020 <= year <= 2035:
            return True
    return False


def _choose_date_variant(variants: list[dict[str, Any]]) -> dict[str, Any]:
    non_empty = [item for item in variants if item["text"]]
    if not non_empty:
        return variants[0]
    date_digit_sequences: dict[str, list[dict[str, Any]]] = {}
    for item in non_empty:
        digits = "".join(character for character in item["text"] if character.isdigit())
        if len(digits) >= 6:
            date_digit_sequences.setdefault(digits, []).append(item)
    repeated = [
        item
        for items in date_digit_sequences.values()
        if len(items) >= 2
        for item in items
    ]
    return max(repeated or non_empty, key=lambda item: item["score"])


def _select_date_candidates(
    detections: list[dict[str, Any]],
    width: int,
    height: int,
    limit: int = 15,
) -> list[dict[str, Any]]:
    scored = []
    for detection in detections:
        text = str(detection.get("text", "")).strip()
        box = np.asarray(detection.get("box"), dtype=np.float32)
        if not text or box.shape != (4, 2):
            continue
        upper = text.upper()
        score = 0
        if any(label in upper for label in DATE_LABELS):
            score += 100
        if sum(character.isdigit() for character in text) >= 2:
            score += 35
        if any(separator in text for separator in ("/", "-", ".")):
            score += 20
        center_y = float(np.mean(box[:, 1]))
        if center_y >= height * 0.55:
            score += 12
        score += max(0, 8 - len(scored))
        scored.append((score, center_y, detection))
    scored.sort(key=lambda item: (-item[0], item[1]))
    return [item[2] for item in scored[:limit]]


def _group_detection_lines(
    detections: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    lines: list[dict[str, Any]] = []
    for detection in detections:
        box = np.asarray(detection.get("box"), dtype=np.float32)
        if box.shape != (4, 2):
            continue
        center_y = float(np.mean(box[:, 1]))
        line = next(
            (
                item
                for item in lines
                if abs(center_y - item["center_y"]) <= max(8.0, float(np.mean(item["height"])) * 0.65)
            ),
            None,
        )
        if line is None:
            lines.append(
                {
                    "center_y": center_y,
                    "height": box[:, 1].max() - box[:, 1].min(),
                    "detections": [detection],
                }
            )
        else:
            line["detections"].append(detection)
            line["center_y"] = (line["center_y"] + center_y) / 2
    result = []
    for line in sorted(lines, key=lambda item: item["center_y"]):
        items = sorted(
            line["detections"],
            key=lambda item: min(point[0] for point in item["box"]),
        )
        result.append(
            {
                "text": " ".join(item["text"].strip() for item in items if item["text"].strip()),
                "detections": items,
            }
        )
    return [line for line in result if line["text"]]


def _date_variants(image: np.ndarray) -> list[np.ndarray]:
    height, width = image.shape[:2]
    scale = min(3.0, 1800 / max(height, width))
    upscaled = cv2.resize(
        image,
        (max(1, round(width * scale)), max(1, round(height * scale))),
        interpolation=cv2.INTER_CUBIC,
    )
    gray = cv2.cvtColor(upscaled, cv2.COLOR_RGB2GRAY)
    contrast = cv2.createCLAHE(clipLimit=2.2, tileGridSize=(8, 8)).apply(gray)
    sharpened = cv2.addWeighted(
        contrast,
        1.35,
        cv2.GaussianBlur(contrast, (0, 0), 1.0),
        -0.35,
        0,
    )
    thresholded = cv2.adaptiveThreshold(
        sharpened,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        31,
        7,
    )
    inverted = cv2.bitwise_not(thresholded)
    return [
        upscaled,
        cv2.cvtColor(sharpened, cv2.COLOR_GRAY2RGB),
        cv2.cvtColor(thresholded, cv2.COLOR_GRAY2RGB),
        cv2.cvtColor(inverted, cv2.COLOR_GRAY2RGB),
    ]


def _quality_score(text: str) -> int:
    value = 0
    upper = text.upper()
    if any(label in upper for label in DATE_LABELS):
        value += 10
    if any(token in upper for token in ("MFD", "MFG", "PKD", "EXP", "EXPIRY", "BEST BEFORE")):
        value += 7
    if any(token in upper for token in ("MRP", "NET WT", "QTY", "BATCH", "LOT")):
        value += 3
    if any(ch.isdigit() for ch in text):
        value += 2
    if len(text.strip()) > 0 and len(text.strip()) < 200:
        value += 1
    if any(token in upper for token in ("#", "@", "@", "@@", "?")):
        value -= 2
    return value


def _candidate_texts(predictions: list[tuple[str, Any]]) -> list[str]:
    texts = []
    for item in predictions:
        text = item[0]
        cleaned = str(text).strip()
        if cleaned:
            texts.append(cleaned)
    return texts


def _choose_best_prediction(prediction_lists: list[list[tuple[str, Any]]]) -> list[tuple[str, Any]]:
    if not prediction_lists:
        return []
    if len(prediction_lists) == 1:
        return prediction_lists[0]

    best = prediction_lists[0]
    best_score = -10**9
    for items in prediction_lists:
        combined_text = "\n".join(str(item[0]) for item in items)
        score = _quality_score(combined_text)
        for item in items:
            text = item[0]
            if str(text).upper().startswith(("MFD", "MFG", "PKD", "EXP", "BEST BEFORE", "USE BY")):
                score += 8
        if score > best_score:
            best = items
            best_score = score
    return best


def _merge_predictions(
    prediction_lists: list[list[tuple[str, Any]]],
) -> list[tuple[str, Any]]:
    merged: list[tuple[str, Any]] = []
    seen: set[str] = set()
    for items in prediction_lists:
        for item in items:
            if not isinstance(item, (list, tuple)) or len(item) < 2:
                continue
            text = str(item[0]).strip()
            if not text or text in seen:
                continue
            seen.add(text)
            merged.append(tuple(item))
    return merged


def _keyword_crop(
    image: np.ndarray,
    detections: list[dict[str, Any]],
) -> np.ndarray | None:
    height, width = image.shape[:2]
    boxes = []
    for detection in detections:
        text = str(detection.get("text", "")).upper()
        if not any(label in text for label in DATE_LABELS):
            continue
        box = np.asarray(detection.get("box"), dtype=np.float32)
        if box.shape == (4, 2):
            boxes.append(box)
    if not boxes:
        return None

    points = np.concatenate(boxes)
    left, top = np.floor(points.min(axis=0)).astype(int)
    right, bottom = np.ceil(points.max(axis=0)).astype(int)
    horizontal_padding = max(80, (right - left) * 5)
    vertical_padding = max(100, (bottom - top) * 12)
    left = max(0, left - horizontal_padding)
    top = max(0, top - vertical_padding)
    right = min(width, right + horizontal_padding)
    bottom = min(height, bottom + vertical_padding)
    if right - left < 40 or bottom - top < 40:
        return None
    return image[top:bottom, left:right]


def _fallback_date_regions(image: np.ndarray) -> list[np.ndarray]:
    height = image.shape[0]
    regions = [image]
    for fraction in (0.45, 0.60):
        top = round(height * fraction)
        if height - top >= 40:
            regions.append(image[top:, :])
    return regions


def create_app(engine: OcrEngine | None = None) -> Flask:
    """Create the API app, optionally with an injected engine for tests."""

    app = Flask(__name__)
    app.config["OCR_ENGINE"] = engine
    recognizer_mode = os.environ.get("OCR_RECOGNIZER_MODE", "pretrained").lower()
    if recognizer_mode not in RECOGNIZER_MODES:
        raise ValueError(
            f"OCR_RECOGNIZER_MODE must be one of {', '.join(RECOGNIZER_MODES)}."
        )
    app.config["OCR_RECOGNIZER_MODE"] = recognizer_mode
    app.config["OCR_DATE_RETRY_MODE"] = os.environ.get(
        "OCR_DATE_RETRY_MODE", "custom_lightweight"
    ).lower()
    app.config["OCR_REQUEST_LOCK"] = threading.Lock()
    app.config["OCR_SERIALIZE_REQUESTS"] = os.environ.get(
        "OCR_SERIALIZE_REQUESTS", "0"
    ).lower() in {"1", "true", "yes"}

    @app.errorhandler(BackendError)
    def handle_backend_error(error: BackendError):
        return jsonify({"error": error.message}), error.status_code

    @app.post("/ocr")
    def recognize_image():
        started = time.perf_counter()
        timing_ms: dict[str, float | None] = {
            "image_decode_ms": None,
            "normal_ocr_ms": None,
            "detector_ms": None,
            "date_retry_ms": 0.0,
            "line_grouping_ms": None,
            "response_build_ms": None,
            "total_ms": None,
        }
        image_decode_started = time.perf_counter()
        image = _read_image()
        timing_ms["image_decode_ms"] = round(
            (time.perf_counter() - image_decode_started) * 1000, 2
        )
        _save_debug_image(image, "input")
        mode = request.form.get("mode", "normal").lower()
        source = request.form.get("source", "unknown").lower()
        if source not in {"roi", "full", "unknown"}:
            source = "unknown"
        ocr_engine = app.config["OCR_ENGINE"]
        if ocr_engine is None:
            ocr_engine = KerasOcrEngine(app.config["OCR_RECOGNIZER_MODE"])
            app.config["OCR_ENGINE"] = ocr_engine

        request_lock = app.config["OCR_REQUEST_LOCK"]
        serialize_requests = app.config["OCR_SERIALIZE_REQUESTS"]
        if serialize_requests:
            request_lock.acquire()
        try:
            normal_started = time.perf_counter()
            if hasattr(ocr_engine, "debug_candidate_metadata"):
                ocr_engine.debug_candidate_metadata = []
                ocr_engine.debug_image_id = uuid.uuid4().hex
            prediction_batches = [ocr_engine.recognize(image)]
            timing_ms["normal_ocr_ms"] = round(
                (time.perf_counter() - normal_started) * 1000, 2
            )
            if mode == "date":
                normal_detections = _serialize_detections(prediction_batches[0])
                if (
                    app.config["OCR_DATE_RETRY_MODE"] == "custom_lightweight"
                    and hasattr(ocr_engine, "recognize_date_candidates")
                ):
                    try:
                        date_started = time.perf_counter()
                        prediction_batches.append(
                            ocr_engine.recognize_date_candidates(
                                image, normal_detections
                            )
                        )
                        timing_ms["date_retry_ms"] = round(
                            (time.perf_counter() - date_started) * 1000, 2
                        )
                    except Exception as error:
                        timing_ms["date_retry_ms"] = round(
                            (time.perf_counter() - date_started) * 1000, 2
                        )
                        app.logger.warning("Lightweight date retry failed: %s", error)
                else:
                    date_recognize = (
                        ocr_engine.recognize_date
                        if app.config["OCR_RECOGNIZER_MODE"] != "pretrained"
                        else ocr_engine.recognize
                    )
                    keyword_region = _keyword_crop(image, normal_detections)
                    date_regions = (
                        [keyword_region]
                        if keyword_region is not None
                        else _fallback_date_regions(image)
                    )
                    for date_region in date_regions:
                        for variant in _date_variants(date_region):
                            _save_debug_image(variant, "date_variant")
                            try:
                                prediction_batches.append(date_recognize(variant))
                            except Exception as error:
                                app.logger.warning("Date retry variant failed: %s", error)
                                continue
                predictions = _merge_predictions(prediction_batches)
            else:
                predictions = _choose_best_prediction(prediction_batches)
            if mode == "date":
                texts = _candidate_texts(predictions)
                if not texts:
                    predictions = prediction_batches[0]
        except Exception as error:
            if serialize_requests:
                request_lock.release()
            app.logger.exception("OCR inference failed")
            return jsonify({"error": "OCR inference failed.", "detail": str(error)}), 502
        if serialize_requests:
            request_lock.release()

        detections = _serialize_detections(predictions)
        text = "\n".join(item["text"] for item in detections)
        grouping_started = time.perf_counter()
        lines = _group_detection_lines(detections)
        timing_ms["line_grouping_ms"] = round(
            (time.perf_counter() - grouping_started) * 1000, 2
        )
        if _debug_enabled():
            app.logger.info("OCR raw ordered detections=%s", detections)
            app.logger.info("OCR grouped lines=%s", lines)
        timing_ms["response_build_ms"] = round(
            (time.perf_counter() - grouping_started) * 1000, 2
        )
        timing_ms["total_ms"] = round((time.perf_counter() - started) * 1000, 2)
        return jsonify(
            {
                "engine": "keras_ocr",
                "status": "ok" if text else "empty",
                "text": text,
                "detections": detections,
                "lines": lines,
                "source": source,
                "input_size": {
                    "width": int(image.shape[1]),
                    "height": int(image.shape[0]),
                },
                "detector_input_size": (
                    {
                        "width": ocr_engine.last_detector_input_size[0],
                        "height": ocr_engine.last_detector_input_size[1],
                    }
                    if getattr(ocr_engine, "last_detector_input_size", None)
                    else None
                ),
                "date_candidates": getattr(
                    ocr_engine, "debug_candidate_metadata", []
                )
                if _debug_enabled()
                else [],
                "processing_ms": timing_ms["total_ms"],
                "timing_ms": timing_ms,
                "timing_notes": [
                    "detector_ms is null because Keras-OCR exposes detector and recognizer as one pipeline call.",
                    "normal_ocr_ms includes detector and pretrained recognition.",
                    "date_retry_ms includes custom date candidate recognition when mode=date.",
                ],
                "error_code": None if text else "EMPTY_OCR",
            }
        )

    @app.get("/health")
    def health_check():
        return jsonify(
            {
                "status": "ok",
                "engine": "keras_ocr",
                "recognizer_mode": app.config["OCR_RECOGNIZER_MODE"],
                "date_retry_mode": app.config["OCR_DATE_RETRY_MODE"],
            }
        )

    return app


app = create_app()


if __name__ == "__main__":
    # Load the model before accepting phone requests so the first capture does
    # not block while Keras-OCR downloads/builds its pipeline.
    app.config["OCR_ENGINE"] = KerasOcrEngine(
        os.environ.get("OCR_RECOGNIZER_MODE", "pretrained").lower(),
        os.environ.get("OCR_DATE_RETRY_MODE", "custom_lightweight").lower(),
    )
    app.run(host="0.0.0.0", port=8000, debug=False)