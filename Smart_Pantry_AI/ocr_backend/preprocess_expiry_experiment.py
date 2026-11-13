"""Compare preprocessing variants on Products-Real expiry crops.

This is an offline experiment. It does not modify source images, production
OCR code, or model weights. Each annotated expiry region is cropped in memory,
processed deterministically, and sent to the existing pretrained Keras-OCR
recognizer.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Callable

import cv2
import numpy as np
from PIL import Image

from ocr_backend.app import KerasOcrEngine


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATASET_ROOT = PROJECT_ROOT.parent / "Smart_Pantry_Datasets"
ANNOTATIONS_PATH = DATASET_ROOT / "Products-Real" / "evaluation" / "annotations.json"
IMAGE_ROOT = DATASET_ROOT / "Products-Real" / "evaluation" / "images"
RESULTS_ROOT = Path(__file__).resolve().parent / "dataset" / "results" / "expiry_preprocessing"


def normalize_text(value: str) -> str:
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


def cer(expected: str, actual: str) -> float:
    if not expected:
        return 0.0 if not actual else 1.0
    return edit_distance(expected, actual) / len(expected)


def crop_box(image: np.ndarray, bbox: list[float]) -> np.ndarray:
    height, width = image.shape[:2]
    x1, y1, x2, y2 = [round(float(value)) for value in bbox]
    left = max(0, min(x1, x2))
    top = max(0, min(y1, y2))
    right = min(width, max(x1, x2))
    bottom = min(height, max(y1, y2))
    if right <= left or bottom <= top:
        raise ValueError(f"Invalid crop box {bbox!r} for image {width}x{height}")
    return image[top:bottom, left:right].copy()


def resize(image: np.ndarray, scale: float) -> np.ndarray:
    height, width = image.shape[:2]
    return cv2.resize(
        image,
        (max(1, round(width * scale)), max(1, round(height * scale))),
        interpolation=cv2.INTER_CUBIC if scale > 1 else cv2.INTER_AREA,
    )


def grayscale_contrast(image: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
    enhanced = cv2.createCLAHE(clipLimit=2.2, tileGridSize=(8, 8)).apply(gray)
    return cv2.cvtColor(enhanced, cv2.COLOR_GRAY2RGB)


def adaptive_threshold(image: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
    thresholded = cv2.adaptiveThreshold(
        gray,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        31,
        7,
    )
    return cv2.cvtColor(thresholded, cv2.COLOR_GRAY2RGB)


def sharpened_contrast(image: np.ndarray) -> np.ndarray:
    enhanced = cv2.cvtColor(grayscale_contrast(image), cv2.COLOR_RGB2GRAY)
    sharpened = cv2.addWeighted(
        enhanced,
        1.35,
        cv2.GaussianBlur(enhanced, (0, 0), 1.0),
        -0.35,
        0,
    )
    return cv2.cvtColor(sharpened, cv2.COLOR_GRAY2RGB)


VARIANTS: dict[str, Callable[[np.ndarray], np.ndarray]] = {
    "original_crop": lambda image: image,
    "upscaled_crop": lambda image: resize(image, 3.0),
    "grayscale_contrast": grayscale_contrast,
    "adaptive_threshold": adaptive_threshold,
    "upscaled_contrast": lambda image: grayscale_contrast(resize(image, 3.0)),
    "upscaled_adaptive": lambda image: adaptive_threshold(resize(image, 3.0)),
    "upscaled_sharpened_contrast": lambda image: sharpened_contrast(resize(image, 3.0)),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--limit",
        type=int,
        default=50,
        help="Number of expiry records to process; 0 processes all records.",
    )
    parser.add_argument("--results-root", type=Path, default=RESULTS_ROOT)
    return parser.parse_args()


def load_records(limit: int) -> list[dict[str, object]]:
    annotations = json.loads(ANNOTATIONS_PATH.read_text(encoding="utf-8"))
    records = []
    for image_name, record in annotations.items():
        for annotation in record.get("ann", []):
            if annotation.get("cls") != "exp" or "transcription" not in annotation:
                continue
            records.append(
                {
                    "image_name": image_name,
                    "image_path": IMAGE_ROOT / image_name,
                    "bbox": annotation["bbox"],
                    "ground_truth_raw": str(annotation["transcription"]),
                }
            )
    records.sort(key=lambda item: str(item["image_name"]))
    return records if limit == 0 else records[:limit]


def run(args: argparse.Namespace) -> None:
    records = load_records(args.limit)
    engine = KerasOcrEngine()
    rows: list[dict[str, object]] = []
    failures: list[dict[str, str]] = []

    for index, record in enumerate(records, start=1):
        image_path = Path(record["image_path"])
        try:
            with Image.open(image_path) as source:
                image = np.asarray(source.convert("RGB"))
            crop = crop_box(image, record["bbox"])
            for variant_name, transform in VARIANTS.items():
                variant_image = transform(crop)
                predictions = engine.recognize(variant_image)
                prediction_raw = " ".join(str(text) for text, _ in predictions).strip()
                ground_truth_raw = str(record["ground_truth_raw"])
                ground_truth = normalize_text(ground_truth_raw)
                prediction = normalize_text(prediction_raw)
                rows.append(
                    {
                        "image": record["image_name"],
                        "ground_truth_raw": ground_truth_raw,
                        "ground_truth_normalized": ground_truth,
                        "prediction_raw": prediction_raw,
                        "prediction_normalized": prediction,
                        "variant": variant_name,
                        "exact_match": prediction == ground_truth,
                        "cer": cer(ground_truth, prediction),
                        "crop_bbox": record["bbox"],
                    }
                )
        except Exception as error:
            failures.append(
                {
                    "image": str(record["image_name"]),
                    "error": f"{type(error).__name__}: {error}",
                }
            )
        print(f"Processed {index}/{len(records)}: {record['image_name']}", flush=True)

    summary: dict[str, object] = {
        "engine": "keras_ocr",
        "model_status": "pretrained baseline; no training or fine-tuning",
        "dataset": "Products-Real/evaluation",
        "records_requested": len(records),
        "records_with_failures": len(failures),
        "normalization": "trim and collapse whitespace only",
        "variants": {},
        "failures": failures,
    }
    for variant_name in VARIANTS:
        variant_rows = [row for row in rows if row["variant"] == variant_name]
        correct = sum(bool(row["exact_match"]) for row in variant_rows)
        summary["variants"][variant_name] = {
            "records_processed": len(variant_rows),
            "correct_predictions": correct,
            "failed_predictions": len(variant_rows) - correct,
            "exact_normalized_text_accuracy": (
                correct / len(variant_rows) if variant_rows else None
            ),
            "mean_cer": (
                sum(float(row["cer"]) for row in variant_rows) / len(variant_rows)
                if variant_rows
                else None
            ),
        }

    args.results_root.mkdir(parents=True, exist_ok=True)
    summary_path = args.results_root / "summary.json"
    predictions_path = args.results_root / "predictions.jsonl"
    report_path = args.results_root / "report.md"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    with predictions_path.open("w", encoding="utf-8") as output:
        for row in rows:
            output.write(json.dumps(row, ensure_ascii=False) + "\n")

    ranked = sorted(
        summary["variants"].items(),
        key=lambda item: (
            -(item[1]["exact_normalized_text_accuracy"] or 0),
            item[1]["mean_cer"] if item[1]["mean_cer"] is not None else float("inf"),
        ),
    )
    report_lines = [
        "# Expiry-Crop Preprocessing Experiment",
        "",
        "Engine: existing pretrained Keras-OCR pipeline; no training or fine-tuning.",
        "Ground truth: Products-Real/evaluation `exp` transcription and bounding box.",
        "Each crop was created in memory; source images were not modified.",
        "Normalization: trim and collapse whitespace only.",
        "",
        "## A. Baseline result",
        "",
        "The baseline variant is `original_crop`; this is a crop-only comparison and is not the full-image external baseline.",
        "",
        "## B. Preprocessing variants tested",
        "",
    ]
    report_lines.extend(f"- `{name}`" for name in VARIANTS)
    report_lines.extend(["", "## C. Metrics", "", "| Variant | Processed | Correct | Failed | Exact accuracy | Mean CER |", "|---|---:|---:|---:|---:|---:|"])
    for name in VARIANTS:
        value = summary["variants"][name]
        report_lines.append(
            f"| {name} | {value['records_processed']} | {value['correct_predictions']} | "
            f"{value['failed_predictions']} | {value['exact_normalized_text_accuracy']:.6f} | "
            f"{value['mean_cer']:.6f} |"
        )
    best_name = ranked[0][0] if ranked else "NOT AVAILABLE"
    report_lines.extend(
        [
            "",
            "## D. Best-performing variant",
            "",
            f"`{best_name}` ranked by exact normalized accuracy, then mean CER.",
            "",
            "## E. Representative before/after examples",
            "",
        ]
    )
    for image_name in sorted({str(row["image"]) for row in rows})[:10]:
        image_rows = [row for row in rows if row["image"] == image_name]
        ground_truth = image_rows[0]["ground_truth_raw"]
        report_lines.append(f"- `{image_name}` — ground truth: `{ground_truth}`")
        for row in image_rows:
            report_lines.append(
                f"  - `{row['variant']}`: `{row['prediction_raw']}` "
                f"(CER {row['cer']:.4f}, exact={row['exact_match']})"
            )
    report_lines.extend(
        [
            "",
            "## F. Whether preprocessing alone appears sufficient",
            "",
            "This experiment measures crop-level recognition only. It cannot establish production sufficiency without comparing the best variant against the full-image baseline and testing runtime cost.",
            "",
            "## G. Whether fine-tuning should be considered next",
            "",
            "Fine-tuning should only be considered after reviewing these measured results and confirming that preprocessing alone does not meet the expiry-date requirement. No fine-tuning was performed.",
            "",
            "## Failures",
            "",
        ]
    )
    if failures:
        report_lines.extend(f"- `{item['image']}`: {item['error']}" for item in failures)
    else:
        report_lines.append("None.")
    report_path.write_text("\n".join(report_lines) + "\n", encoding="utf-8")
    print(json.dumps({"summary": str(summary_path), "report": str(report_path)}, indent=2))


if __name__ == "__main__":
    run(parse_args())
