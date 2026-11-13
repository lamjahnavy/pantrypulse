"""Evaluate the pretrained Keras-OCR pipeline on the external date datasets.

This evaluator never changes the source datasets or the production scanner.
It preserves raw OCR output and applies only whitespace normalization for
recognition comparisons. Detection matching is greedy, one-to-one, and uses
IoU >= 0.5.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image

from ocr_backend.app import KerasOcrEngine


PROJECT_ROOT = Path(__file__).resolve().parent.parent
REPOSITORY_ROOT = PROJECT_ROOT.parent
DATASET_ROOT = REPOSITORY_ROOT / "Smart_Pantry_Datasets"
RESULTS_ROOT = Path(__file__).resolve().parent / "dataset" / "results" / "external"
DEFAULT_PREDICTIONS = RESULTS_ROOT / "predictions.jsonl"
DEFAULT_SUMMARY = RESULTS_ROOT / "summary.json"
DEFAULT_REPORT = RESULTS_ROOT / "report.md"
IOU_THRESHOLD = 0.5


@dataclass(frozen=True)
class GroundTruth:
    dataset: str
    split: str
    image_path: Path
    image_name: str
    field_type: str
    class_name: str
    bbox: tuple[float, float, float, float]
    text: str
    components: dict[str, str] | None = None


@dataclass(frozen=True)
class Prediction:
    text: str
    polygon: list[list[float]]
    bbox: tuple[float, float, float, float]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset-root", type=Path, default=DATASET_ROOT)
    parser.add_argument("--results-root", type=Path, default=RESULTS_ROOT)
    return parser.parse_args()


def bbox_from_annotation(value: list[float]) -> tuple[float, float, float, float]:
    if len(value) != 4:
        raise ValueError(f"Expected [x1, y1, x2, y2], received {value!r}")
    x1, y1, x2, y2 = (float(item) for item in value)
    return (min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2))


def bbox_from_polygon(polygon: Any) -> tuple[float, float, float, float] | None:
    points = np.asarray(polygon, dtype=float)
    if points.shape != (4, 2) or not np.isfinite(points).all():
        return None
    return (
        float(points[:, 0].min()),
        float(points[:, 1].min()),
        float(points[:, 0].max()),
        float(points[:, 1].max()),
    )


def intersection_over_union(
    first: tuple[float, float, float, float],
    second: tuple[float, float, float, float],
) -> float:
    left = max(first[0], second[0])
    top = max(first[1], second[1])
    right = min(first[2], second[2])
    bottom = min(first[3], second[3])
    intersection = max(0.0, right - left) * max(0.0, bottom - top)
    first_area = max(0.0, first[2] - first[0]) * max(0.0, first[3] - first[1])
    second_area = max(0.0, second[2] - second[0]) * max(0.0, second[3] - second[1])
    union = first_area + second_area - intersection
    return intersection / union if union else 0.0


def normalize_text(value: str) -> str:
    """Normalize whitespace only; preserve digits, punctuation, and content."""

    return re.sub(r"\s+", " ", value.strip())


def edit_distance(first: str, second: str) -> int:
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


def character_error_rate(expected: str, actual: str) -> float:
    if not expected:
        return 0.0 if not actual else 1.0
    return edit_distance(expected, actual) / len(expected)


def load_ground_truth(dataset_root: Path) -> list[GroundTruth]:
    sources = [
        (
            "date_real",
            "date_real",
            dataset_root / "Date-Real",
            ("day", "month", "year"),
        ),
        (
            "products_real_evaluation",
            "evaluation",
            dataset_root / "Products-Real" / "evaluation",
            ("exp", "date"),
        ),
    ]
    records: list[GroundTruth] = []
    for dataset_name, split, folder, classes in sources:
        annotation_path = folder / "annotations.json"
        annotations = json.loads(annotation_path.read_text(encoding="utf-8"))
        image_folder = folder / "images"
        for image_name, record in annotations.items():
            image_path = image_folder / image_name
            if not image_path.is_file():
                raise FileNotFoundError(f"Missing image for annotation: {image_path}")
            for annotation in record.get("ann", []):
                class_name = annotation.get("cls")
                if class_name not in classes or "transcription" not in annotation:
                    continue
                components = None
                if annotation.get("dmy_ann"):
                    components = {
                        item["cls"]: str(item["transcription"])
                        for item in annotation["dmy_ann"]
                        if "cls" in item and "transcription" in item
                    }
                records.append(
                    GroundTruth(
                        dataset=dataset_name,
                        split=split,
                        image_path=image_path,
                        image_name=image_name,
                        field_type=(
                            "expiry_date"
                            if dataset_name == "products_real_evaluation"
                            and class_name == "exp"
                            else class_name
                        ),
                        class_name=class_name,
                        bbox=bbox_from_annotation(annotation["bbox"]),
                        text=str(annotation["transcription"]),
                        components=components,
                    )
                )
    return records


def predictions_from_engine(
    engine: KerasOcrEngine,
    image_path: Path,
) -> tuple[list[Prediction], str | None]:
    try:
        with Image.open(image_path) as source:
            image = np.asarray(source.convert("RGB"))
        raw_predictions = engine.recognize(image)
        predictions = []
        for text, polygon in raw_predictions:
            bbox = bbox_from_polygon(polygon)
            if bbox is None:
                continue
            predictions.append(
                Prediction(
                    text=str(text),
                    polygon=np.asarray(polygon).tolist(),
                    bbox=bbox,
                )
            )
        return predictions, None
    except Exception as error:
        return [], f"{type(error).__name__}: {error}"


def match_predictions(
    truths: list[GroundTruth],
    predictions: list[Prediction],
) -> tuple[dict[int, int], dict[int, float]]:
    candidates = []
    for truth_index, truth in enumerate(truths):
        for prediction_index, prediction in enumerate(predictions):
            overlap = intersection_over_union(truth.bbox, prediction.bbox)
            if overlap >= IOU_THRESHOLD:
                candidates.append((overlap, truth_index, prediction_index))
    matches: dict[int, int] = {}
    overlaps: dict[int, float] = {}
    used_truths: set[int] = set()
    used_predictions: set[int] = set()
    for overlap, truth_index, prediction_index in sorted(candidates, reverse=True):
        if truth_index in used_truths or prediction_index in used_predictions:
            continue
        matches[truth_index] = prediction_index
        overlaps[truth_index] = overlap
        used_truths.add(truth_index)
        used_predictions.add(prediction_index)
    return matches, overlaps


def parse_date_components(value: str) -> dict[str, str] | None:
    value = value.strip()
    match = re.fullmatch(r"(\d{4})\s*[./-]\s*(\d{1,2})\s*[./-]\s*(\d{1,2})", value)
    if match:
        return {"year": match.group(1), "month": match.group(2), "day": match.group(3)}
    match = re.fullmatch(r"(\d{1,2})\s*[./-]\s*(\d{1,2})\s*[./-]\s*(\d{2,4})", value)
    if not match:
        return None
    first, second, year = match.groups()
    if len(year) == 2:
        year = f"20{year}"
    return {"day": first, "month": second, "year": year}


def classify_error(
    truth: GroundTruth,
    prediction: Prediction | None,
) -> str | None:
    if prediction is None:
        return "missed detection"
    expected = normalize_text(truth.text)
    actual = normalize_text(prediction.text)
    if expected == actual:
        return None
    if truth.components:
        expected_components = truth.components
        actual_components = parse_date_components(actual)
        if actual_components is None:
            return "partial date" if any(char.isdigit() for char in actual) else "incorrect character"
        wrong_components = [
            component
            for component, value in expected_components.items()
            if actual_components.get(component) != value
        ]
        if wrong_components:
            return f"wrong {('/'.join(wrong_components))} component"
    if len(actual) < len(expected):
        return "missing character"
    if len(actual) > len(expected):
        return "extra character"
    return "incorrect character"


def metric_summary(
    truths: list[GroundTruth],
    predictions_by_image: dict[str, list[Prediction]],
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    grouped: dict[str, list[GroundTruth]] = {}
    for truth in truths:
        grouped.setdefault(truth.field_type, []).append(truth)

    output: dict[str, Any] = {}
    error_examples: list[dict[str, Any]] = []
    for field_type, field_truths in sorted(grouped.items()):
        by_image: dict[str, list[GroundTruth]] = {}
        for truth in field_truths:
            by_image.setdefault(str(truth.image_path), []).append(truth)
        matched_count = 0
        exact_count = 0
        cer_values = []
        component_counts = Counter()
        errors = Counter()
        total_predictions = 0
        for image_path, image_truths in by_image.items():
            image_predictions = predictions_by_image.get(image_path, [])
            total_predictions += len(image_predictions)
            matches, _ = match_predictions(image_truths, image_predictions)
            matched_count += len(matches)
            for truth_index, truth in enumerate(image_truths):
                prediction = (
                    image_predictions[matches[truth_index]]
                    if truth_index in matches
                    else None
                )
                actual = "" if prediction is None else normalize_text(prediction.text)
                expected = normalize_text(truth.text)
                exact_count += expected == actual
                cer_values.append(character_error_rate(expected, actual))
                error = classify_error(truth, prediction)
                if error:
                    errors[error] += 1
                    error_examples.append(
                        {
                            "image": truth.image_name,
                            "field_type": truth.field_type,
                            "error_type": error,
                            "ground_truth_raw": truth.text,
                            "prediction_raw": (
                                prediction.text if prediction is not None else ""
                            ),
                            "ground_truth_bbox": truth.bbox,
                            "prediction_bbox": (
                                prediction.bbox if prediction is not None else None
                            ),
                        }
                    )
                if truth.components:
                    actual_components = parse_date_components(actual) or {}
                    for component, expected_value in truth.components.items():
                        component_counts[f"{component}_correct"] += (
                            actual_components.get(component) == expected_value
                        )
                        component_counts[f"{component}_total"] += 1
        truth_count = len(field_truths)
        matched_predictions = matched_count
        output[field_type] = {
            "ground_truth_regions": truth_count,
            "predicted_regions": total_predictions,
            "matched_regions": matched_count,
            "unmatched_ground_truth": truth_count - matched_count,
            "unmatched_predictions": total_predictions - matched_predictions,
            "detection_precision": (
                matched_count / total_predictions if total_predictions else 0.0
            ),
            "detection_recall": matched_count / truth_count if truth_count else 0.0,
            "detection_f1": (
                2 * matched_count / (total_predictions + truth_count)
                if total_predictions + truth_count
                else 0.0
            ),
            "mean_cer": sum(cer_values) / len(cer_values) if cer_values else 0.0,
            "exact_normalized_text_accuracy": (
                exact_count / truth_count if truth_count else 0.0
            ),
            "component_accuracy": {},
            "error_counts": dict(errors),
        }
        component_accuracy = {}
        for component in ("day", "month", "year"):
            total = component_counts[f"{component}_total"]
            component_accuracy[component] = (
                component_counts[f"{component}_correct"] / total if total else None
            )
        output[field_type]["component_accuracy"] = component_accuracy
    return output, error_examples


def build_report(summary: dict[str, Any], failures: list[dict[str, str]]) -> str:
    lines = [
        "# External Keras-OCR Baseline Evaluation",
        "",
        "Engine: pretrained Keras-OCR pipeline used by `ocr_backend.app.KerasOcrEngine`.",
        f"Detection matching: one-to-one greedy matching with IoU >= {IOU_THRESHOLD}.",
        "Unmatched ground-truth regions count as false negatives; unmatched predictions count as false positives.",
        "Text normalization trims and collapses whitespace only. Raw values are preserved in predictions.jsonl.",
        "",
        "## A. Dataset summary",
        "",
        "| Dataset/field | Images | Ground-truth regions | Processed images | Failed images |",
        "|---|---:|---:|---:|---:|",
    ]
    for key, value in summary["metrics"].items():
        dataset_images = summary["image_counts"].get(key, "see summary")
        lines.append(
            f"| {key} | {dataset_images} | {value['ground_truth_regions']} | "
            f"{summary['processed_images'].get(key, 0)} | {summary['failed_images'].get(key, 0)} |"
        )
    lines.extend(["", "## B. Detection metrics", ""])
    for key, value in summary["metrics"].items():
        lines.extend(
            [
                f"### {key}",
                f"- Precision: {value['detection_precision']:.6f}",
                f"- Recall: {value['detection_recall']:.6f}",
                f"- F1: {value['detection_f1']:.6f}",
                f"- Matched regions: {value['matched_regions']}",
                f"- Unmatched ground truth: {value['unmatched_ground_truth']}",
                f"- Unmatched predictions: {value['unmatched_predictions']}",
                "",
            ]
        )
    lines.extend(["## C. OCR metrics", ""])
    for key, value in summary["metrics"].items():
        lines.extend(
            [
                f"### {key}",
                f"- Mean CER: {value['mean_cer']:.6f}",
                f"- Exact normalized text accuracy: {value['exact_normalized_text_accuracy']:.6f}",
                "",
            ]
        )
    lines.extend(["## D. Expiry metrics", ""])
    expiry = summary["metrics"].get("expiry_date")
    if expiry:
        lines.extend(
            [
                f"- Complete expiry-date accuracy: {expiry['exact_normalized_text_accuracy']:.6f}",
                f"- Day accuracy: {expiry['component_accuracy']['day']}",
                f"- Month accuracy: {expiry['component_accuracy']['month']}",
                f"- Year accuracy: {expiry['component_accuracy']['year']}",
            ]
        )
    else:
        lines.append("NOT AVAILABLE")
    lines.extend(["", "## E. Error examples", ""])
    for failure in failures[:20]:
        lines.extend(
            [
                f"- `{failure['image']}` ({failure['field_type']}): {failure['error_type']}",
                f"  - Ground truth: `{failure['ground_truth_raw']}`",
                f"  - Prediction: `{failure['prediction_raw']}`",
                f"  - Ground-truth box: `{failure['ground_truth_bbox']}`",
                f"  - Prediction box: `{failure['prediction_bbox']}`",
            ]
        )
    if not failures:
        lines.append("No failures recorded.")
    lines.extend(["", "## Runtime failures", ""])
    lines.extend(f"- `{failure['image']}`: {failure['error']}" for failure in failures if failure.get("runtime_failure"))
    if not any(failure.get("runtime_failure") for failure in failures):
        lines.append("None.")
    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    results_root = args.results_root
    results_root.mkdir(parents=True, exist_ok=True)
    truths = load_ground_truth(args.dataset_root)
    image_paths = sorted({truth.image_path for truth in truths})
    engine = KerasOcrEngine()
    predictions_by_image: dict[str, list[Prediction]] = {}
    failures: list[dict[str, str]] = []
    prediction_records = []

    for index, image_path in enumerate(image_paths, start=1):
        predictions, error = predictions_from_engine(engine, image_path)
        predictions_by_image[str(image_path)] = predictions
        prediction_records.append(
            {
                "dataset": "date_real"
                if "Date-Real" in str(image_path)
                else "products_real_evaluation",
                "image": image_path.name,
                "image_path": str(image_path),
                "predictions": [
                    {"text_raw": item.text, "box": item.polygon}
                    for item in predictions
                ],
                "error": error,
            }
        )
        if error:
            failures.append(
                {
                    "image": image_path.name,
                    "image_path": str(image_path),
                    "error": error,
                    "runtime_failure": "true",
                }
            )
        print(f"Processed {index}/{len(image_paths)}: {image_path.name}", flush=True)

    metrics, error_examples = metric_summary(truths, predictions_by_image)
    image_counts = {
        "day": len({str(t.image_path) for t in truths if t.field_type == "day"}),
        "month": len({str(t.image_path) for t in truths if t.field_type == "month"}),
        "year": len({str(t.image_path) for t in truths if t.field_type == "year"}),
        "expiry_date": len({str(t.image_path) for t in truths if t.field_type == "expiry_date"}),
        "date": len({str(t.image_path) for t in truths if t.field_type == "date"}),
    }
    failed_paths = {
        failure["image_path"]
        for failure in failures
        if failure.get("image_path")
    }
    summary = {
        "engine": "keras_ocr",
        "model_status": "pretrained baseline; no training or fine-tuning",
        "iou_threshold": IOU_THRESHOLD,
        "text_normalization": "trim and collapse whitespace only",
        "datasets": ["Date-Real", "Products-Real/evaluation"],
        "image_counts": image_counts,
        "total_unique_images": len(image_paths),
        "processed_images": {
            key: len({str(t.image_path) for t in truths if t.field_type == key})
            - len({str(t.image_path) for t in truths if t.field_type == key and str(t.image_path) in failed_paths})
            for key in metrics
        },
        "failed_images": {
            key: len({str(t.image_path) for t in truths if t.field_type == key and str(t.image_path) in failed_paths})
            for key in metrics
        },
        "ground_truth_regions_total": len(truths),
        "metrics": metrics,
        "error_examples": error_examples,
        "runtime_failures": failures,
        "generated_at": datetime.now().isoformat(),
    }
    DEFAULT_PREDICTIONS.parent.mkdir(parents=True, exist_ok=True)
    predictions_path = results_root / DEFAULT_PREDICTIONS.name
    summary_path = results_root / DEFAULT_SUMMARY.name
    report_path = results_root / DEFAULT_REPORT.name
    with predictions_path.open("w", encoding="utf-8") as output:
        for record in prediction_records:
            output.write(json.dumps(record, ensure_ascii=False) + "\n")
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    report_path.write_text(
        build_report(summary, error_examples + failures),
        encoding="utf-8",
    )
    print(json.dumps({"summary": str(summary_path), "report": str(report_path)}, indent=2))


if __name__ == "__main__":
    main()
