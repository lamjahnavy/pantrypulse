"""Evaluate the trained custom recognizer on held-out Products-Real/evaluation.

This is a recognition-only comparison. Ground-truth boxes from the held-out
annotations are cropped for both the trained and pretrained recognizers, so
the result does not measure detector performance. The held-out dataset is
never used for training, tuning, or model selection.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import time
from collections import Counter
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent
REPOSITORY_ROOT = ROOT.parent.parent
DEFAULT_DATASET_ROOT = REPOSITORY_ROOT / "Smart_Pantry_Datasets"
DEFAULT_MODEL = (
    ROOT
    / "dataset"
    / "training_runs"
    / "custom_recognizer_export"
    / "recognizer.weights.h5"
)
DEFAULT_RESULTS = ROOT / "dataset" / "results" / "final_custom_recognizer_evaluation"


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip())


def edit_distance(first: str, second: str) -> int:
    previous = list(range(len(second) + 1))
    for row, first_character in enumerate(first, 1):
        current = [row]
        for column, second_character in enumerate(second, 1):
            current.append(
                min(
                    current[-1] + 1,
                    previous[column] + 1,
                    previous[column - 1] + (first_character != second_character),
                )
            )
        previous = current
    return previous[-1]


def cer(expected: str, actual: str) -> float:
    return edit_distance(expected, actual) / len(expected) if expected else 0.0


def wer(expected: str, actual: str) -> float:
    expected_words = expected.split()
    actual_words = actual.split()
    if not expected_words:
        return 0.0 if not actual_words else 1.0
    previous = list(range(len(expected_words) + 1))
    for row, actual_word in enumerate(actual_words, 1):
        current = [row]
        for column, expected_word in enumerate(expected_words, 1):
            current.append(
                min(
                    current[-1] + 1,
                    previous[column] + 1,
                    previous[column - 1] + (actual_word != expected_word),
                )
            )
        previous = current
    return previous[-1] / len(expected_words)


def bbox(value: list[Any]) -> tuple[int, int, int, int]:
    if len(value) != 4:
        raise ValueError(f"Expected four bbox coordinates: {value!r}")
    x1, y1, x2, y2 = (int(float(item)) for item in value)
    return min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2)


def load_records(dataset_root: Path) -> list[dict[str, Any]]:
    folder = dataset_root / "Products-Real" / "evaluation"
    annotations = json.loads(
        (folder / "annotations.json").read_text(encoding="utf-8")
    )
    records = []
    for image_name, image_record in annotations.items():
        image_path = folder / "images" / image_name
        for annotation_index, annotation in enumerate(image_record.get("ann", [])):
            if annotation.get("cls") != "exp" or "transcription" not in annotation:
                continue
            components = {
                item["cls"]: {
                    "bbox": item["bbox"],
                    "text": str(item["transcription"]),
                }
                for item in annotation.get("dmy_ann", [])
                if item.get("cls") in {"day", "month", "year"}
                and "bbox" in item
                and "transcription" in item
            }
            records.append(
                {
                    "image": image_name,
                    "image_path": str(image_path),
                    "annotation_index": annotation_index,
                    "bbox": annotation["bbox"],
                    "ground_truth_raw": str(annotation["transcription"]),
                    "components": components,
                }
            )
    return records


def crop(path: Path, coordinates: list[Any]) -> np.ndarray:
    left, top, right, bottom = bbox(coordinates)
    with Image.open(path) as image:
        width, height = image.size
        if not (0 <= left < right <= width and 0 <= top < bottom <= height):
            raise ValueError(
                f"bbox {coordinates!r} is outside decoded image {width}x{height}"
            )
        return np.asarray(
            image.convert("RGB").crop((left, top, right, bottom))
        )


def load_engines(model_path: Path, alphabet: str):
    import os

    os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")
    if not hasattr(np, "sctypes"):
        np.sctypes = {
            "int": [np.int8, np.int16, np.int32, np.int64],
            "uint": [np.uint8, np.uint16, np.uint32, np.uint64],
            "float": [np.float16, np.float32, np.float64],
            "complex": [np.complex64, np.complex128],
            "others": [bool, object, bytes, str, np.void],
        }
    import keras_ocr
    import tensorflow as tf

    trained_recognizer = keras_ocr.recognition.Recognizer(
        alphabet=alphabet, weights="kurapan"
    )
    trained_recognizer.model.load_weights(model_path)
    if trained_recognizer.model.output_shape[-1] != len(alphabet) + 1:
        raise ValueError(
            f"Saved model output width {trained_recognizer.model.output_shape[-1]} does not "
            f"match alphabet size {len(alphabet)} plus CTC blank"
        )
    pretrained = keras_ocr.recognition.Recognizer(weights="kurapan")
    return trained_recognizer, pretrained, keras_ocr.tools, tf


def predict_trained(model: Any, tools: Any, tf: Any, image: np.ndarray, alphabet: str) -> str:
    fitted = tools.read_and_fit(
        image,
        width=model.model.input_shape[2],
        height=model.model.input_shape[1],
        cval=0,
    )
    if model.model.input_shape[-1] == 1 and fitted.shape[-1] == 3:
        import cv2

        fitted = cv2.cvtColor(fitted, cv2.COLOR_RGB2GRAY)[..., np.newaxis]
    values = model.model.predict(
        fitted[np.newaxis].astype("float32") / 255.0, verbose=0
    )
    decoded = tf.keras.backend.ctc_decode(
        values,
        input_length=np.full((values.shape[0],), values.shape[1]),
    )[0][0].numpy()
    blank = len(alphabet)
    return "".join(
        alphabet[index]
        for index in decoded[0]
        if index not in (-1, blank)
    )


def aggregate(rows: list[dict[str, Any]], engine_key: str) -> dict[str, Any]:
    total = len(rows)
    exact = sum(row[engine_key]["normalized"] == row["ground_truth_normalized"] for row in rows)
    return {
        "valid_records": total,
        "exact_normalized_text_accuracy": exact / total if total else 0.0,
        "mean_cer": sum(row[engine_key]["cer"] for row in rows) / total if total else 0.0,
        "mean_wer": sum(row[engine_key]["wer"] for row in rows) / total if total else 0.0,
        "exact_matches": exact,
        "failures": sum(not row[engine_key]["prediction_raw"] for row in rows),
    }


def component_accuracy(rows: list[dict[str, Any]], engine_key: str) -> dict[str, Any]:
    output = {}
    for component in ("day", "month", "year"):
        values = [
            row["components"][component]["text"]
            for row in rows
            if component in row["components"]
            and component in row[engine_key]["components"]
        ]
        predictions = [
            row[engine_key]["components"][component]["normalized"]
            for row in rows
            if component in row["components"]
            and component in row[engine_key]["components"]
        ]
        output[component] = {
            "records": len(values),
            "exact_accuracy": (
                sum(
                    normalize_text(a) == normalize_text(b)
                    for a, b in zip(predictions, values)
                )
                / len(values)
                if values
                else None
            ),
        }
    return output


def evaluate(
    dataset_root: Path,
    model_path: Path,
    results_root: Path,
    alphabet: str,
) -> dict[str, Any]:
    if results_root.exists():
        raise FileExistsError(f"Refusing to overwrite results directory: {results_root}")
    records = load_records(dataset_root)
    trained_model, pretrained, tools, tf = load_engines(model_path, alphabet)
    results_root.mkdir(parents=True)
    output_rows = []
    skipped = []
    failures = []
    start = time.perf_counter()
    for record in records:
        try:
            image = crop(Path(record["image_path"]), record["bbox"])
            trained_text = predict_trained(trained_model, tools, tf, image, alphabet)
            pretrained_text = pretrained.recognize(image)
            result = {
                **record,
                "ground_truth_normalized": normalize_text(record["ground_truth_raw"]),
                "trained": {
                    "prediction_raw": trained_text,
                    "normalized": normalize_text(trained_text),
                    "components": {},
                },
                "pretrained": {
                    "prediction_raw": pretrained_text,
                    "normalized": normalize_text(pretrained_text),
                    "components": {},
                },
            }
            for component, component_record in record["components"].items():
                component_image = crop(
                    Path(record["image_path"]), component_record["bbox"]
                )
                result["trained"]["components"][component] = {
                    "normalized": normalize_text(
                        predict_trained(
                            trained_model, tools, tf, component_image, alphabet
                        )
                    )
                }
                result["pretrained"]["components"][component] = {
                    "normalized": normalize_text(pretrained.recognize(component_image))
                }
            for key in ("trained", "pretrained"):
                expected = result["ground_truth_normalized"]
                actual = result[key]["normalized"]
                result[key]["cer"] = cer(expected, actual)
                result[key]["wer"] = wer(expected, actual)
            output_rows.append(result)
        except Exception as error:
            failures.append(
                {
                    "image": record["image"],
                    "error": f"{type(error).__name__}: {error}",
                }
            )
    duration = time.perf_counter() - start
    for row in output_rows:
        row.pop("image_path", None)
    summary = {
        "evaluation_type": "recognition_only_ground_truth_crops",
        "dataset": "Products-Real/evaluation",
        "model": str(model_path),
        "custom_alphabet": alphabet,
        "model_output_width": int(trained_model.model.output_shape[-1]),
        "expected_output_width": len(alphabet) + 1,
        "normalization": "trim and collapse whitespace only",
        "matching": "ground-truth bbox crop; no detector matching",
        "total_valid_records": len(output_rows),
        "total_annotation_records": len(records),
        "skipped_records": skipped,
        "inference_failures": failures,
        "duration_seconds": duration,
        "metrics": {
            "trained_custom_recognizer": aggregate(output_rows, "trained"),
            "pretrained_recognizer_same_crops": aggregate(output_rows, "pretrained"),
        },
        "component_accuracy": {
            "trained_custom_recognizer": component_accuracy(output_rows, "trained"),
            "pretrained_recognizer_same_crops": component_accuracy(output_rows, "pretrained"),
        },
    }
    (results_root / "predictions.jsonl").write_text(
        "\n".join(json.dumps(row, ensure_ascii=False) for row in output_rows) + "\n",
        encoding="utf-8",
    )
    (results_root / "summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    report = [
        "# Final Held-Out Custom Recognizer Evaluation",
        "",
        "Dataset: `Products-Real/evaluation`.",
        "Evaluation uses ground-truth expiry/component crops for both recognizers; detector performance is not measured.",
        "Normalization trims and collapses whitespace only. WER is edit distance over whitespace-token strings.",
        "No evaluation record was used for training, tuning, or model selection.",
        "",
        "## Results",
        "",
        "| Engine | Valid | CER | WER | Exact accuracy | Failures |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for key, label in (
        ("trained_custom_recognizer", "Trained custom recognizer"),
        ("pretrained_recognizer_same_crops", "Pretrained recognizer"),
    ):
        value = summary["metrics"][key]
        report.append(
            f"| {label} | {value['valid_records']} | {value['mean_cer']:.6f} | "
            f"{value['mean_wer']:.6f} | {value['exact_normalized_text_accuracy']:.6f} | "
            f"{value['failures']} |"
        )
    report.extend(["", "## Component exact accuracy", ""])
    for key, value in summary["component_accuracy"].items():
        report.append(f"### {key}")
        for component, metrics in value.items():
            report.append(
                f"- {component}: {metrics['exact_accuracy']} "
                f"({metrics['records']} records)"
            )
    report.extend(
        [
            "",
            f"Valid records: {len(output_rows)} / {len(records)}.",
            f"Inference failures: {len(failures)}.",
            f"Runtime seconds: {duration:.3f}.",
        ]
    )
    (results_root / "report.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset-root", type=Path, default=DEFAULT_DATASET_ROOT)
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--results-root", type=Path, default=DEFAULT_RESULTS)
    parser.add_argument(
        "--alphabet",
        default=" -./0123456789ABCDEFGJLMNOPRSTUVY",
    )
    args = parser.parse_args()
    print(json.dumps(evaluate(args.dataset_root, args.model, args.results_root, args.alphabet), indent=2))


if __name__ == "__main__":
    main()
