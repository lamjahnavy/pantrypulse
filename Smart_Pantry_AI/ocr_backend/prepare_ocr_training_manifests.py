"""Prepare deterministic, derived OCR training manifests.

Only Date-Real and Products-Real/train are read. Products-Real/evaluation is
intentionally not referenced. Raw labels are preserved exactly; this module
does not lowercase, remove separators, or invent characters.

The generated recognizer manifests contain:
* default_alphabet: labels compatible with pretrained Kurapan's alphabet;
* custom_alphabet: all valid transcribed labels, preserving their raw text.

A custom recognizer alphabet cannot load the pretrained recognizer's final
classification layer. Keras-OCR can still load the pretrained backbone, but
the incompatible recognition head must be initialized for later training.
This module does not train either track.
"""

from __future__ import annotations

import argparse
import json
import random
import string
from collections import Counter
from pathlib import Path
from typing import Any

try:
    from .validate_training_annotations import (
        DATASET_SOURCES,
        SUPPORTED_RECOGNIZER_CHARACTERS,
        validate_bbox,
        validate_label,
    )
except ImportError:
    from validate_training_annotations import (
        DATASET_SOURCES,
        SUPPORTED_RECOGNIZER_CHARACTERS,
        validate_bbox,
        validate_label,
    )


SEED = 20261029
TRAIN_FRACTION = 0.8
DEFAULT_OUTPUT = (
    Path(__file__).resolve().parent
    / "dataset"
    / "training_manifests"
)


def load_source_records(source_name: str, source_root: Path) -> list[dict[str, Any]]:
    annotation_path = source_root / "annotations.json"
    images_root = source_root / "images"
    annotations = json.loads(annotation_path.read_text(encoding="utf-8"))
    records: list[dict[str, Any]] = []
    for image_name, record in annotations.items():
        image_path = images_root / str(image_name)
        if not image_path.is_file():
            records.append(
                {
                    "source": source_name,
                    "image": image_name,
                    "annotation_index": None,
                    "class": None,
                    "bbox_raw": None,
                    "label_raw": None,
                    "reasons": ["missing_image"],
                }
            )
            continue
        try:
            from PIL import Image

            with Image.open(image_path) as image:
                actual_width, actual_height = image.size
        except Exception as error:
            records.append(
                {
                    "source": source_name,
                    "image": image_name,
                    "annotation_index": None,
                    "class": None,
                    "bbox_raw": None,
                    "label_raw": None,
                    "reasons": [f"unreadable_image:{type(error).__name__}"],
                }
            )
            continue
        if not isinstance(record, dict) or not isinstance(record.get("ann"), list):
            records.append(
                {
                    "source": source_name,
                    "image": image_name,
                    "annotation_index": None,
                    "class": None,
                    "bbox_raw": None,
                    "label_raw": None,
                    "reasons": ["malformed_record"],
                }
            )
            continue
        dimension_reasons = []
        if (record.get("width"), record.get("height")) != (
            actual_width,
            actual_height,
        ):
            dimension_reasons.append("image_dimension_mismatch")
        for index, annotation in enumerate(record["ann"]):
            if not isinstance(annotation, dict):
                records.append(
                    {
                        "source": source_name,
                        "image": image_name,
                        "annotation_index": index,
                        "class": None,
                        "bbox_raw": None,
                        "label_raw": None,
                        "reasons": ["malformed_annotation"],
                    }
                )
                continue
            reasons = list(dimension_reasons)
            reasons.extend(
                item["code"]
                for item in validate_bbox(
                    annotation.get("bbox"),
                    actual_width,
                    actual_height,
                    record.get("width"),
                    record.get("height"),
                )
            )
            label = annotation.get("transcription")
            if label is not None:
                reasons.extend(
                    item["code"]
                    for item in validate_label(
                        label, SUPPORTED_RECOGNIZER_CHARACTERS
                    )
                )
            elif source_name == "Date-Real" or annotation.get("cls") == "date":
                reasons.append("missing_label")
            records.append(
                {
                    "source": source_name,
                    "image": image_name,
                    "image_path": str(image_path),
                    "annotation_index": index,
                    "class": annotation.get("cls"),
                    "bbox_raw": annotation.get("bbox"),
                    "label_raw": label,
                    "reasons": sorted(set(reasons)),
                }
            )
    return records


def split_images(records: list[dict[str, Any]], seed: int) -> dict[str, str]:
    image_paths = sorted(
        {
            record["image_path"]
            for record in records
            if record.get("image_path")
        }
    )
    shuffled = image_paths[:]
    random.Random(seed).shuffle(shuffled)
    train_count = int(len(shuffled) * TRAIN_FRACTION)
    return {
        image_path: ("train" if index < train_count else "validation")
        for index, image_path in enumerate(shuffled)
    }


def custom_alphabet(records: list[dict[str, Any]]) -> str:
    characters = {
        character
        for record in records
        if isinstance(record.get("label_raw"), str)
        for character in record["label_raw"]
    }
    return "".join(sorted(characters, key=lambda value: ord(value)))


def recognizer_compatible(record: dict[str, Any]) -> bool:
    return (
        not set(record["reasons"]) - {"unsupported_characters"}
        and isinstance(record.get("label_raw"), str)
        and bool(record["label_raw"])
        and all(
            character in SUPPORTED_RECOGNIZER_CHARACTERS
            for character in record["label_raw"]
        )
    )


def detector_compatible(record: dict[str, Any]) -> bool:
    detector_classes = {"day", "month", "year", "date", "due", "code", "prod"}
    return (
        not set(record["reasons"]) - {"unsupported_characters", "missing_label"}
        and record.get("class") in detector_classes
        and isinstance(record.get("bbox_raw"), list)
    )


def output_record(record: dict[str, Any], split: str) -> dict[str, Any]:
    return {
        "source": record["source"],
        "split": split,
        "image": record["image"],
        "image_path": record["image_path"],
        "annotation_index": record["annotation_index"],
        "class": record["class"],
        "bbox_raw": record["bbox_raw"],
        "label_raw": record["label_raw"],
    }


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8") as output:
        for row in rows:
            output.write(json.dumps(row, ensure_ascii=False) + "\n")


def prepare(output_root: Path = DEFAULT_OUTPUT) -> dict[str, Any]:
    all_records: list[dict[str, Any]] = []
    sources: list[dict[str, Any]] = []
    for source_name, source_root in DATASET_SOURCES:
        records = load_source_records(source_name, source_root)
        split_by_image = split_images(records, SEED)
        for record in records:
            record["split"] = split_by_image.get(record.get("image_path"))
        all_records.extend(records)
        sources.append(
            {
                "source": source_name,
                "annotation_records": len(
                    {record["image"] for record in records}
                ),
                "image_split_counts": {
                    split: len(
                        {
                            record["image_path"]
                            for record in records
                            if record.get("split") == split
                        }
                    )
                    for split in ("train", "validation")
                },
            }
        )

    output_root.mkdir(parents=True, exist_ok=True)
    default_rows = [
        output_record(record, record["split"])
        for record in all_records
        if recognizer_compatible(record)
    ]
    custom_rows = [
        output_record(record, record["split"])
        for record in all_records
        if not set(record["reasons"]) - {"unsupported_characters"}
        and isinstance(record.get("label_raw"), str)
        and bool(record["label_raw"])
    ]
    detector_rows = [
        output_record(record, record["split"])
        for record in all_records
        if detector_compatible(record)
    ]
    exclusions = []
    for record in all_records:
        if record["reasons"]:
            exclusions.append(
                {
                    **output_record(record, record.get("split")),
                    "exclusion_reasons": record["reasons"],
                }
            )
    custom_chars = custom_alphabet(all_records)
    metadata = {
        "seed": SEED,
        "train_fraction": TRAIN_FRACTION,
        "scope": ["Date-Real", "Products-Real/train"],
        "evaluation_data_used": False,
        "raw_labels_preserved": True,
        "label_transform": "none",
        "pretrained_alphabet": string.digits + string.ascii_lowercase,
        "custom_alphabet": custom_chars,
        "custom_alphabet_compatibility": (
            "pretrained recognizer backbone can be reused; pretrained recognition "
            "classification head is incompatible and must be newly initialized "
            "for a future custom-alphabet training run"
        ),
        "counts": {
            "all_annotation_records": len(all_records),
            "default_alphabet_recognizer": len(default_rows),
            "custom_alphabet_recognizer": len(custom_rows),
            "detector": len(detector_rows),
            "excluded": len(exclusions),
        },
        "sources": sources,
    }
    for prefix, rows in (
        ("recognizer_default_alphabet", default_rows),
        ("recognizer_custom_alphabet", custom_rows),
        ("detector", detector_rows),
    ):
        for split in ("train", "validation"):
            write_jsonl(
                output_root / f"{prefix}_{split}.jsonl",
                [row for row in rows if row["split"] == split],
            )
    write_jsonl(output_root / "excluded_annotations.jsonl", exclusions)
    (output_root / "manifest_metadata.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return metadata


def test_split_is_image_level_and_deterministic(tmp_path: Path) -> None:
    first = prepare(tmp_path / "first")
    second = prepare(tmp_path / "second")
    assert first == second
    for filename in (
        "recognizer_default_alphabet_train.jsonl",
        "recognizer_default_alphabet_validation.jsonl",
        "recognizer_custom_alphabet_train.jsonl",
        "recognizer_custom_alphabet_validation.jsonl",
        "detector_train.jsonl",
        "detector_validation.jsonl",
    ):
        first_rows = [
            json.loads(line)
            for line in (tmp_path / "first" / filename).read_text().splitlines()
        ]
        second_rows = [
            json.loads(line)
            for line in (tmp_path / "second" / filename).read_text().splitlines()
        ]
        assert first_rows == second_rows


def test_split_has_no_image_overlap(tmp_path: Path) -> None:
    prepare(tmp_path)
    for prefix in (
        "recognizer_default_alphabet",
        "recognizer_custom_alphabet",
        "detector",
    ):
        train = {
            json.loads(line)["image_path"]
            for line in (tmp_path / f"{prefix}_train.jsonl").read_text().splitlines()
        }
        validation = {
            json.loads(line)["image_path"]
            for line in (
                tmp_path / f"{prefix}_validation.jsonl"
            ).read_text().splitlines()
        }
        assert train.isdisjoint(validation)


def test_raw_labels_are_not_transformed(tmp_path: Path) -> None:
    prepare(tmp_path)
    rows = [
        json.loads(line)
        for line in (tmp_path / "recognizer_custom_alphabet_train.jsonl")
        .read_text(encoding="utf-8")
        .splitlines()
    ]
    assert any(
        isinstance(row["label_raw"], str)
        and any(character in row["label_raw"] for character in "/.- ")
        for row in rows
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT)
    arguments = parser.parse_args()
    print(json.dumps(prepare(arguments.output_root), indent=2, ensure_ascii=False))
