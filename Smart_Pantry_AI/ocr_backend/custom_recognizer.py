"""Load the verified weights-only custom Keras-OCR recognizer."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import numpy as np


CUSTOM_ALPHABET = " -./0123456789ABCDEFGJLMNOPRSTUVY"
EXPECTED_OUTPUT_WIDTH = len(CUSTOM_ALPHABET) + 1
EXPECTED_OUTPUT_TIMESTEPS = 48
BACKEND_ROOT = Path(__file__).resolve().parent
DEFAULT_WEIGHTS_PATH = (
    BACKEND_ROOT
    / "dataset"
    / "training_runs"
    / "custom_recognizer_export"
    / "recognizer.weights.h5"
)
DEFAULT_METADATA_PATH = DEFAULT_WEIGHTS_PATH.with_name("metadata.json")


def _prepare_legacy_imports() -> None:
    if not hasattr(np, "sctypes"):
        np.sctypes = {
            "int": [np.int8, np.int16, np.int32, np.int64],
            "uint": [np.uint8, np.uint16, np.uint32, np.uint64],
            "float": [np.float16, np.float32, np.float64],
            "complex": [np.complex64, np.complex128],
            "others": [bool, object, bytes, str, np.void],
        }
    os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")


def _read_metadata(metadata_path: Path) -> dict[str, Any]:
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"Could not read custom recognizer metadata: {metadata_path}") from error
    if metadata.get("alphabet") != CUSTOM_ALPHABET:
        raise RuntimeError("Custom recognizer metadata alphabet does not match the verified alphabet.")
    if metadata.get("output_width") != EXPECTED_OUTPUT_WIDTH:
        raise RuntimeError("Custom recognizer metadata has an unexpected output width.")
    if metadata.get("output_timesteps") != EXPECTED_OUTPUT_TIMESTEPS:
        raise RuntimeError("Custom recognizer metadata has unexpected output timesteps.")
    return metadata


def build_custom_recognizer(
    weights_path: Path = DEFAULT_WEIGHTS_PATH,
    metadata_path: Path = DEFAULT_METADATA_PATH,
) -> Any:
    """Rebuild Keras-OCR 0.9.3 and load weights without deserializing Lambda code."""

    weights_path = Path(weights_path)
    metadata_path = Path(metadata_path)
    if not weights_path.is_file():
        raise FileNotFoundError(f"Custom recognizer weights were not found: {weights_path}")
    _read_metadata(metadata_path)
    _prepare_legacy_imports()

    try:
        import keras_ocr
    except ImportError as error:
        raise RuntimeError("Keras-OCR is required to load the custom recognizer.") from error

    recognizer = keras_ocr.recognition.Recognizer(
        alphabet=CUSTOM_ALPHABET,
        weights="kurapan",
    )
    try:
        recognizer.model.load_weights(weights_path)
    except (OSError, ValueError) as error:
        raise RuntimeError(f"Could not load custom recognizer weights: {weights_path}") from error

    output_shape = recognizer.model.output_shape
    if output_shape[-1] != EXPECTED_OUTPUT_WIDTH:
        raise RuntimeError(
            f"Custom recognizer output width {output_shape[-1]} does not "
            f"match {EXPECTED_OUTPUT_WIDTH}."
        )
    if output_shape[1] != EXPECTED_OUTPUT_TIMESTEPS:
        raise RuntimeError(
            f"Custom recognizer output timesteps {output_shape[1]} does not "
            f"match {EXPECTED_OUTPUT_TIMESTEPS}."
        )
    return recognizer

