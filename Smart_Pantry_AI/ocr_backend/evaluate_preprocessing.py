"""Compare pretrained Keras-OCR with evaluation-only preprocessing variants."""

from __future__ import annotations

import json
import gc
from pathlib import Path

import numpy as np
from PIL import Image

from ocr_backend.app import KerasOcrEngine
from ocr_backend.evaluate import error_rate, evaluate_fields, normalize
from ocr_backend.preprocessing import build_variants, keyword_crop, save_variant


ROOT = Path(__file__).parent
MANIFEST_PATH = ROOT / "dataset" / "manifest.json"
BASELINE_PATH = ROOT / "dataset" / "results" / "keras_ocr_baseline.json"
RESULTS_PATH = ROOT / "dataset" / "results" / "keras_ocr_preprocessing_results.json"
IMAGE_OUTPUT = ROOT / "dataset" / "preprocessed"


def _predictions_to_result(item, variant, predictions):
    raw_text = " ".join(str(text) for text, _ in predictions)
    expected_text = " ".join(item["visible_targets"])
    return {
        "id": item["id"],
        "split": item["split"],
        "variant": variant,
        "description": variant,
        "raw_text": raw_text,
        "detections": [
            {"text": str(text), "box": np.asarray(box).tolist()}
            for text, box in predictions
        ],
        "cer": error_rate(normalize(expected_text), normalize(raw_text), "character"),
        "wer": error_rate(expected_text.lower(), raw_text.lower(), "word"),
        "field_results": evaluate_fields(item["fields"], raw_text),
    }


def _aggregate(results):
    field_values = [
        value
        for result in results
        for value in result["field_results"].values()
        if value is not None
    ]
    return {
        "sample_count": len({result["id"] for result in results}),
        "variant_count": len({result["variant"] for result in results}),
        "mean_cer": sum(result["cer"] for result in results) / len(results),
        "mean_wer": sum(result["wer"] for result in results) / len(results),
        "field_accuracy": sum(field_values) / len(field_values),
    }


def main() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    baseline = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
    baseline_by_id = {item["id"]: item for item in baseline["samples"]}
    engine = KerasOcrEngine()
    all_results = []
    best_results = []
    variant_descriptions = {}
    variant_items = []
    for item in manifest:
        source_path = ROOT / "dataset" / item["image"]
        item_variants = []
        for variant in build_variants(source_path):
            variant_descriptions[variant.name] = variant.description
            save_path = IMAGE_OUTPUT / item["id"] / f"{variant.name}.png"
            save_variant(variant.image, save_path)
            item_variants.append((item, variant, save_path))
        variant_items.append(item_variants)

    work_items = [
        variant_items[item_index][variant_index]
        for variant_index in range(4)
        for item_index in range(len(manifest))
    ]
    images = [entry[1].image for entry in work_items]

    predictions = []
    for image in images:
        predictions.append(engine.recognize(image))
        gc.collect()
    candidates_by_id = {}
    for (item, variant, save_path), item_predictions in zip(work_items, predictions):
        result = _predictions_to_result(item, variant.name, item_predictions)
        result["description"] = variant.description
        result["image"] = item["image"]
        result["saved_image"] = str(save_path.relative_to(ROOT))
        candidates_by_id.setdefault(item["id"], []).append(result)
        all_results.append(result)

    for item in manifest:
        candidates = candidates_by_id[item["id"]]

        # Best is chosen by measured CER, then field failures, then WER.
        best = min(
            candidates,
            key=lambda result: (
                result["cer"],
                -sum(value is True for value in result["field_results"].values()),
                result["wer"],
            ),
        )
        best_results.append(
            {
                "id": item["id"],
                "baseline": baseline_by_id[item["id"]],
                "best_preprocessed": best,
                "improved_cer": best["cer"] < baseline_by_id[item["id"]]["cer"],
                "improved_wer": best["wer"] < baseline_by_id[item["id"]]["wer"],
            }
        )

        # Keyword crops are attempted only on back images when a keyword box
        # exists in the original baseline detections.
        if item["split"] == "back":
            crop = keyword_crop(build_variants(
                ROOT / "dataset" / item["image"]
            )[0].image, baseline_by_id[item["id"]]["detections"])
            if crop is not None:
                crop_path = IMAGE_OUTPUT / item["id"] / "keyword_crop.png"
                save_variant(crop, crop_path)
                crop_predictions = engine.recognize_batch([crop])[0]
                crop_result = _predictions_to_result(item, "keyword_crop", crop_predictions)
                crop_result["image"] = item["image"]
                crop_result["saved_image"] = str(crop_path.relative_to(ROOT))
                all_results.append(crop_result)

    report = {
        "engine": "keras_ocr",
        "model_status": "pretrained baseline; no training or customization",
        "phase": "Phase 3 preprocessing experiment",
        "variant_descriptions": variant_descriptions,
        "baseline_summary": baseline["summary"],
        "preprocessed_summary": _aggregate(all_results),
        "best_per_image": best_results,
        "all_variant_results": all_results,
        "notes": [
            "The Phase 2 baseline JSON was not overwritten.",
            "Unavailable fields remain null and are excluded from field accuracy.",
            "No automatic perspective correction was applied because no corner points were available.",
            "Keyword crops are only created when a baseline detection contains a target label keyword.",
        ],
    }
    RESULTS_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"baseline": baseline["summary"], "preprocessed": report["preprocessed_summary"]}, indent=2))


if __name__ == "__main__":
    main()