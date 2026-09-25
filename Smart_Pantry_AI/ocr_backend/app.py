"""HTTP API for the Phase 1 Keras-OCR backend."""

from __future__ import annotations

import io
import os
from dataclasses import dataclass
from typing import Any, Protocol

import cv2
import numpy as np
from flask import Flask, jsonify, request
from PIL import Image, UnidentifiedImageError


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


class OcrEngine(Protocol):
    """Minimal contract used by the HTTP layer and tests."""

    def recognize(self, image: np.ndarray) -> list[tuple[str, Any]]:
        """Return recognized text and its polygon for one image."""


class KerasOcrEngine:
    """Lazy wrapper around the pretrained Keras-OCR pipeline."""

    def __init__(self) -> None:
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

    def recognize(self, image: np.ndarray) -> list[tuple[str, Any]]:
        predictions = self._pipeline.recognize([image])
        return list(predictions[0]) if predictions else []

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
            return np.asarray(image.convert("RGB"))
    except (UnidentifiedImageError, OSError) as error:
        raise BackendError(400, "The uploaded file is not a readable image.") from error


def _json_value(value: Any) -> Any:
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, (np.integer, np.floating)):
        return value.item()
    if isinstance(value, (list, tuple)):
        return [_json_value(item) for item in value]
    return value


def _serialize_detections(predictions: list[tuple[str, Any]]) -> list[dict[str, Any]]:
    detections = []
    for prediction in predictions:
        if not isinstance(prediction, (list, tuple)) or len(prediction) < 2:
            continue
        text, box = prediction[0], prediction[1]
        detections.append({"text": str(text), "box": _json_value(box)})
    return detections


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
    for text, _ in predictions:
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
        combined_text = "\n".join(str(text) for text, _ in items)
        score = _quality_score(combined_text)
        for text, _ in items:
            if str(text).upper().startswith(("MFD", "MFG", "PKD", "EXP", "BEST BEFORE", "USE BY")):
                score += 8
        if score > best_score:
            best = items
            best_score = score
    return best


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


def create_app(engine: OcrEngine | None = None) -> Flask:
    """Create the API app, optionally with an injected engine for tests."""

    app = Flask(__name__)
    app.config["OCR_ENGINE"] = engine

    @app.errorhandler(BackendError)
    def handle_backend_error(error: BackendError):
        return jsonify({"error": error.message}), error.status_code

    @app.post("/ocr")
    def recognize_image():
        image = _read_image()
        mode = request.form.get("mode", "normal").lower()
        ocr_engine = app.config["OCR_ENGINE"]
        if ocr_engine is None:
            ocr_engine = KerasOcrEngine()
            app.config["OCR_ENGINE"] = ocr_engine

        try:
            prediction_batches = [ocr_engine.recognize(image)]
            if mode == "date":
                normal_detections = _serialize_detections(prediction_batches[0])
                keyword_region = _keyword_crop(image, normal_detections)
                date_image = keyword_region if keyword_region is not None else image
                date_variants = _date_variants(date_image)
                for variant in date_variants[:1]:
                    try:
                        prediction_batches.append(ocr_engine.recognize(variant))
                    except Exception:
                        continue
            predictions = _choose_best_prediction(prediction_batches)
            if mode == "date":
                texts = _candidate_texts(predictions)
                if not texts:
                    predictions = prediction_batches[0]
        except Exception as error:
            app.logger.exception("OCR inference failed")
            return jsonify({"error": "OCR inference failed.", "detail": str(error)}), 502

        detections = _serialize_detections(predictions)
        return jsonify(
            {
                "engine": "keras_ocr",
                "text": "\n".join(item["text"] for item in detections),
                "detections": detections,
            }
        )

    @app.get("/health")
    def health_check():
        return jsonify({"status": "ok", "engine": "keras_ocr"})

    return app


app = create_app()


if __name__ == "__main__":
    # Load the model before accepting phone requests so the first capture does
    # not block while Keras-OCR downloads/builds its pipeline.
    app.config["OCR_ENGINE"] = KerasOcrEngine()
    app.run(host="0.0.0.0", port=8000, debug=False)