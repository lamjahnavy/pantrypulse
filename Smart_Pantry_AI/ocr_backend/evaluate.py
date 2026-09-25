"""Run the pretrained Keras-OCR baseline against the Phase 2 manifest."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Iterable

import numpy as np
from PIL import Image

from ocr_backend.app import KerasOcrEngine


ROOT = Path(__file__).parent
MANIFEST_PATH = ROOT / "dataset" / "manifest.json"
RESULTS_PATH = ROOT / "dataset" / "results" / "keras_ocr_baseline.json"


def normalize(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", value.lower())


def edit_distance(first: list[str], second: list[str]) -> int:
    previous = list(range(len(second) + 1))
    for first_index, first_char in enumerate(first, start=1):
        current = [first_index]
        for second_index, second_char in enumerate(second, start=1):
            current.append(
                min(
                    current[-1] + 1,
                    previous[second_index] + 1,
                    previous[second_index - 1] + (first_char != second_char),
                )
            )
        previous = current
    return previous[-1]


def error_rate(expected: str, actual: str, unit: str) -> float | None:
    expected_units = expected.split() if unit == "word" else list(expected)
    actual_units = actual.split() if unit == "word" else list(actual)
    denominator = len(expected_units)
    if denominator == 0:
        return None
    return edit_distance(expected_units, actual_units) / denominator


def detection_texts(predictions: Iterable[tuple[str, object]]) -> list[str]:
    return [str(text) for text, _ in predictions]


def evaluate_fields(fields: dict[str, str | None], actual: str) -> dict[str, bool | None]:
    normalized_actual = normalize(actual)
    return {
        field: None if expected is None else normalize(expected) in normalized_actual
        for field, expected in fields.items()
    }


def main() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    engine = KerasOcrEngine()
    results = []

    images = []
    for item in manifest:
        image_path = ROOT / "dataset" / item["image"]
        with Image.open(image_path) as image:
            image = image.convert("RGB")
            image.thumbnail((1200, 1200), Image.Resampling.LANCZOS)
            images.append(np.asarray(image))

    predictions_by_image = engine.recognize_batch(images)

    for item, predictions in zip(manifest, predictions_by_image):

        texts = detection_texts(predictions)
        actual_text = " ".join(texts)
        expected_text = " ".join(item["visible_targets"])
        field_results = evaluate_fields(item["fields"], actual_text)
        results.append(
            {
                "id": item["id"],
                "split": item["split"],
                "image": item["image"],
                "source": item["source"],
                "conditions": item["conditions"],
                "expected_visible_text": item["visible_targets"],
                "detections": [
                    {
                        "text": text,
                        "box": np.asarray(box).tolist(),
                    }
                    for text, box in predictions
                ],
                "raw_text": actual_text,
                "cer": error_rate(
                    normalize(expected_text),
                    normalize(actual_text),
                    "character",
                ),
                "wer": error_rate(expected_text.lower(), actual_text.lower(), "word"),
                "field_results": field_results,
            }
        )

    measured_field_values = [
        value
        for result in results
        for value in result["field_results"].values()
        if value is not None
    ]
    summary = {
        "engine": "keras_ocr",
        "model_status": "pretrained baseline; no training or customization",
        "sample_count": len(results),
        "front_count": sum(result["split"] == "front" for result in results),
        "back_count": sum(result["split"] == "back" for result in results),
        "mean_cer": sum(result["cer"] for result in results) / len(results),
        "mean_wer": sum(result["wer"] for result in results) / len(results),
        "field_accuracy": (
            sum(measured_field_values) / len(measured_field_values)
            if measured_field_values
            else None
        ),
    }
    RESULTS_PATH.write_text(
        json.dumps(
            {
                "summary": summary,
                "samples": results,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()