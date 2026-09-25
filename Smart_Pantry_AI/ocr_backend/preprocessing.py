"""Evaluation and runtime preprocessing variants for package OCR."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps


@dataclass(frozen=True)
class PreprocessedImage:
    name: str
    image: np.ndarray
    description: str


MAX_DIMENSION = 480
KEYWORDS = (
    "MFD",
    "MFG",
    "EXP",
    "EXPIRY",
    "USE BY",
    "BEST BEFORE",
    "MRP",
    "NET WT",
    "QTY",
    "BATCH",
    "LOT",
    "PKD",
    "DOM",
)


def _resize(image: np.ndarray, max_dimension: int = MAX_DIMENSION) -> np.ndarray:
    height, width = image.shape[:2]
    scale = min(1.0, max_dimension / max(height, width))
    if scale == 1.0:
        return image.copy()
    return cv2.resize(
        image,
        (round(width * scale), round(height * scale)),
        interpolation=cv2.INTER_AREA,
    )


def _upscale(image: np.ndarray, target: int = 900) -> np.ndarray:
    height, width = image.shape[:2]
    scale = min(2.0, max(1.0, target / max(height, width)))
    upscaled = cv2.resize(
        image,
        (round(width * scale), round(height * scale)),
        interpolation=cv2.INTER_CUBIC,
    )
    return _resize(upscaled, max_dimension=target)


def _pil_oriented(path: Path) -> np.ndarray:
    with Image.open(path) as source:
        oriented = ImageOps.exif_transpose(source).convert("RGB")
        return cv2.cvtColor(np.asarray(oriented), cv2.COLOR_RGB2BGR)


def _grayscale(image: np.ndarray) -> np.ndarray:
    return cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)


def _clahe_gray(gray: np.ndarray) -> np.ndarray:
    clahe = cv2.createCLAHE(clipLimit=2.2, tileGridSize=(8, 8))
    return clahe.apply(gray)


def _sharpen(gray: np.ndarray) -> np.ndarray:
    kernel = np.array([[0, -1, 0], [-1, 5, -1], [0, -1, 0]], dtype=np.float32)
    return cv2.filter2D(gray, -1, kernel)


def _denoise(gray: np.ndarray) -> np.ndarray:
    return cv2.fastNlMeansDenoising(gray, None, 8, 7, 21)


def _adaptive_threshold(gray: np.ndarray) -> np.ndarray:
    return cv2.adaptiveThreshold(
        gray,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        31,
        9,
    )


def _otsu_threshold(gray: np.ndarray) -> np.ndarray:
    _, thresholded = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    return thresholded


def _brightness_contrast(image: np.ndarray) -> np.ndarray:
    adjusted = cv2.convertScaleAbs(image, alpha=1.15, beta=8)
    return adjusted


def _dark_text_on_light(image: np.ndarray) -> np.ndarray:
    gray = _grayscale(image)
    gray = cv2.equalizeHist(gray)
    return cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)


def _light_text_on_dark(image: np.ndarray) -> np.ndarray:
    gray = _grayscale(image)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    inverted = cv2.bitwise_not(blurred)
    return cv2.cvtColor(inverted, cv2.COLOR_GRAY2BGR)


def build_variants(path: Path) -> list[PreprocessedImage]:
    """Build several useful OCR variants without replacing the source image."""

    oriented = _resize(_pil_oriented(path))
    gray = _grayscale(oriented)
    clahe = _clahe_gray(gray)
    sharpened = _sharpen(clahe)
    denoised = _denoise(sharpened)
    adaptive = _adaptive_threshold(denoised)
    otsu = _otsu_threshold(gray)
    bright = _brightness_contrast(oriented)
    dark = _dark_text_on_light(oriented)
    light = _light_text_on_dark(oriented)

    return [
        PreprocessedImage(
            "original_roi",
            oriented,
            "Original ROI with EXIF normalization and bounded scale",
        ),
        PreprocessedImage(
            "upscaled_roi",
            _upscale(oriented),
            "Upscaled ROI for small package text",
        ),
        PreprocessedImage(
            "grayscale_upscaled",
            cv2.cvtColor(_upscale(cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)), cv2.COLOR_BGR2GRAY),
            "Grayscale with upscale for fine print",
        ),
        PreprocessedImage(
            "clahe_upscaled",
            cv2.cvtColor(_upscale(cv2.cvtColor(clahe, cv2.COLOR_GRAY2BGR)), cv2.COLOR_BGR2GRAY),
            "CLAHE contrast enhancement with upscale",
        ),
        PreprocessedImage(
            "sharpened_upscaled",
            cv2.cvtColor(_upscale(cv2.cvtColor(sharpened, cv2.COLOR_GRAY2BGR)), cv2.COLOR_BGR2GRAY),
            "Sharpened + upscaled text for date fields",
        ),
        PreprocessedImage(
            "denoised_upscaled",
            cv2.cvtColor(_upscale(cv2.cvtColor(denoised, cv2.COLOR_GRAY2BGR)), cv2.COLOR_BGR2GRAY),
            "Denoised + upscaled candidate",
        ),
        PreprocessedImage(
            "adaptive_threshold",
            cv2.cvtColor(adaptive, cv2.COLOR_GRAY2BGR),
            "Adaptive thresholding for low-contrast small text",
        ),
        PreprocessedImage(
            "otsu_threshold",
            cv2.cvtColor(otsu, cv2.COLOR_GRAY2BGR),
            "Otsu thresholding for high-contrast packaging",
        ),
        PreprocessedImage(
            "brightness_contrast",
            bright,
            "Brightness and contrast correction for glare and faded ink",
        ),
        PreprocessedImage(
            "dark_ink_on_light",
            dark,
            "Optimized for dark ink on light packaging",
        ),
        PreprocessedImage(
            "light_ink_on_dark",
            light,
            "Optimized for light ink on dark packaging",
        ),
    ]


def save_variant(image: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(path), image)


def keyword_crop(
    image: np.ndarray,
    detections: list[dict[str, object]],
) -> np.ndarray | None:
    """Crop around a detected label keyword for numeric/date follow-up OCR."""

    height, width = image.shape[:2]
    matching_boxes = []
    for detection in detections:
        text = str(detection.get("text", "")).upper()
        if not any(keyword in text for keyword in KEYWORDS):
            continue
        box = np.asarray(detection.get("box"), dtype=np.float32)
        if box.shape != (4, 2):
            continue
        matching_boxes.append(box)

    if not matching_boxes:
        return None

    points = np.concatenate(matching_boxes)
    left, top = np.floor(points.min(axis=0)).astype(int)
    right, bottom = np.ceil(points.max(axis=0)).astype(int)
    padding_x = max(40, (right - left) * 3)
    padding_y = max(40, (bottom - top) * 8)
    left = max(0, left - padding_x)
    top = max(0, top - padding_y)
    right = min(width, right + padding_x)
    bottom = min(height, bottom + padding_y)

    if right - left < 32 or bottom - top < 32:
        return None
    return image[top:bottom, left:right]