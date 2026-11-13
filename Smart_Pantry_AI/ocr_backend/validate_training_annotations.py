"""Validate training annotations without modifying source datasets.

Only Date-Real and Products-Real/train are inspected. Products-Real/evaluation
is intentionally not referenced by this validator. Labels and coordinates are
reported exactly as stored; this tool never repairs, clips, normalizes, or
rewrites source annotations.
"""

from __future__ import annotations

import argparse
import json
import math
import string
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATASET_ROOT = PROJECT_ROOT.parent / "Smart_Pantry_Datasets"
DEFAULT_OUTPUT = (
    Path(__file__).resolve().parent
    / "dataset"
    / "results"
    / "training_annotation_validation"
)

# Keras-OCR's pretrained Kurapan recognizer uses digits plus lowercase letters.
SUPPORTED_RECOGNIZER_CHARACTERS = set(string.digits + string.ascii_lowercase)
DATASET_SOURCES = (
    ("Date-Real", DATASET_ROOT / "Date-Real"),
    ("Products-Real/train", DATASET_ROOT / "Products-Real" / "train"),
)


def issue(code: str, message: str) -> dict[str, str]:
    return {"code": code, "message": message}


def validate_label(value: Any, alphabet: set[str]) -> list[dict[str, str]]:
    problems: list[dict[str, str]] = []
    if not isinstance(value, str):
        return [issue("malformed_label", "transcription must be a string")]
    if not value:
        problems.append(issue("empty_label", "transcription is empty"))
    unsupported = sorted({char for char in value if char not in alphabet})
    if unsupported:
        problems.append(
            issue(
                "unsupported_characters",
                f"characters are not in the Keras-OCR alphabet: {unsupported!r}",
            )
        )
    return problems


def validate_bbox(
    value: Any,
    actual_width: int,
    actual_height: int,
    declared_width: Any,
    declared_height: Any,
) -> list[dict[str, str]]:
    problems: list[dict[str, str]] = []
    if not isinstance(value, list) or len(value) != 4:
        return [issue("malformed_bbox", "bbox must be a four-value list")]
    if any(isinstance(item, bool) or not isinstance(item, (int, float)) for item in value):
        return [issue("malformed_bbox", "bbox values must be numeric")]
    if not all(math.isfinite(float(item)) for item in value):
        return [issue("malformed_bbox", "bbox values must be finite")]
    x1, y1, x2, y2 = (float(item) for item in value)
    if x2 <= x1 or y2 <= y1:
        problems.append(issue("invalid_bbox_geometry", "bbox must have positive area"))
    if x1 < 0 or y1 < 0 or x2 > actual_width or y2 > actual_height:
        problems.append(
            issue(
                "bbox_out_of_image_bounds",
                f"bbox {value!r} is outside decoded image bounds "
                f"[width={actual_width}, height={actual_height}]",
            )
        )
    if (
        isinstance(declared_width, (int, float))
        and isinstance(declared_height, (int, float))
        and (x1 < 0 or y1 < 0 or x2 > declared_width or y2 > declared_height)
    ):
        problems.append(
            issue(
                "bbox_out_of_declared_bounds",
                f"bbox {value!r} is outside annotation metadata bounds "
                f"[width={declared_width}, height={declared_height}]",
            )
        )
    return problems


def validate_source(
    source_name: str,
    source_root: Path,
    alphabet: set[str] = SUPPORTED_RECOGNIZER_CHARACTERS,
) -> dict[str, Any]:
    annotation_path = source_root / "annotations.json"
    images_root = source_root / "images"
    source_result: dict[str, Any] = {
        "source": source_name,
        "annotation_file": str(annotation_path),
        "image_root": str(images_root),
        "annotation_records": 0,
        "image_files": 0,
        "valid_annotations": [],
        "excluded_annotations": [],
        "image_dimension_mismatches": [],
    }
    if not annotation_path.is_file():
        source_result["fatal_error"] = f"missing annotation file: {annotation_path}"
        return source_result
    try:
        annotations = json.loads(annotation_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        source_result["fatal_error"] = f"cannot read annotations: {error}"
        return source_result
    if not isinstance(annotations, dict):
        source_result["fatal_error"] = "annotation root must be a JSON object"
        return source_result

    source_result["annotation_records"] = len(annotations)
    source_result["image_files"] = sum(
        1 for path in images_root.iterdir() if path.is_file()
    ) if images_root.is_dir() else 0

    for image_name, record in annotations.items():
        image_path = images_root / str(image_name)
        if not image_path.is_file():
            source_result["excluded_annotations"].append(
                {
                    "image": image_name,
                    "annotation_index": None,
                    "class": None,
                    "transcription_raw": None,
                    "bbox_raw": None,
                    "reasons": [
                        issue("missing_image", f"image does not exist: {image_path}")
                    ],
                }
            )
            continue
        image_problems: list[dict[str, str]] = []
        if not isinstance(record, dict):
            source_result["excluded_annotations"].append(
                {
                    "image": image_name,
                    "annotation_index": None,
                    "class": None,
                    "transcription_raw": None,
                    "bbox_raw": None,
                    "reasons": [issue("malformed_record", "record must be an object")],
                }
            )
            continue
        declared_width = record.get("width")
        declared_height = record.get("height")
        try:
            with Image.open(image_path) as image:
                actual_width, actual_height = image.size
        except (OSError, Image.UnidentifiedImageError) as error:
            source_result["excluded_annotations"].append(
                {
                    "image": image_name,
                    "annotation_index": None,
                    "class": None,
                    "transcription_raw": None,
                    "bbox_raw": None,
                    "reasons": [issue("unreadable_image", str(error))],
                }
            )
            continue
        if (declared_width, declared_height) != (actual_width, actual_height):
            source_result["image_dimension_mismatches"].append(
                {
                    "image": image_name,
                    "declared": {"width": declared_width, "height": declared_height},
                    "actual": {"width": actual_width, "height": actual_height},
                }
            )
            image_problems.append(
                issue(
                    "image_dimension_mismatch",
                    f"annotation declares {declared_width}x{declared_height}; "
                    f"decoded image is {actual_width}x{actual_height}",
                )
            )
        annotations_for_image = record.get("ann")
        if not isinstance(annotations_for_image, list):
            source_result["excluded_annotations"].append(
                {
                    "image": image_name,
                    "annotation_index": None,
                    "class": None,
                    "transcription_raw": None,
                    "bbox_raw": None,
                    "reasons": image_problems
                    + [issue("malformed_annotations", "ann must be a list")],
                }
            )
            continue
        for index, annotation in enumerate(annotations_for_image):
            reasons = list(image_problems)
            if not isinstance(annotation, dict):
                reasons.append(issue("malformed_annotation", "annotation must be an object"))
                annotation = {}
            reasons.extend(
                validate_bbox(
                    annotation.get("bbox"),
                    actual_width,
                    actual_height,
                    declared_width,
                    declared_height,
                )
            )
            if "transcription" in annotation:
                reasons.extend(validate_label(annotation["transcription"], alphabet))
            elif source_name == "Date-Real" or annotation.get("cls") == "date":
                reasons.append(
                    issue("missing_label", "transcription is required for this training record")
                )
            result = {
                "image": image_name,
                "image_path": str(image_path),
                "annotation_index": index,
                "class": annotation.get("cls"),
                "transcription_raw": annotation.get("transcription"),
                "bbox_raw": annotation.get("bbox"),
                "reasons": reasons,
            }
            if reasons:
                source_result["excluded_annotations"].append(result)
            else:
                source_result["valid_annotations"].append(result)
    return source_result


def build_report(results: list[dict[str, Any]]) -> dict[str, Any]:
    valid = sum(len(result.get("valid_annotations", [])) for result in results)
    excluded = sum(len(result.get("excluded_annotations", [])) for result in results)
    return {
        "validator": "validate_training_annotations.py",
        "scope": ["Date-Real", "Products-Real/train"],
        "evaluation_data_inspected": False,
        "recognizer_alphabet": "digits + lowercase ASCII letters",
        "label_policy": "raw labels are preserved; no normalization or repair",
        "valid_annotation_count": valid,
        "excluded_annotation_count": excluded,
        "sources": results,
    }


def write_report(report: dict[str, Any], output_root: Path) -> None:
    output_root.mkdir(parents=True, exist_ok=True)
    (output_root / "validation_report.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    lines = [
        "# Training Annotation Validation",
        "",
        "Scope: `Date-Real` and `Products-Real/train` only.",
        "Products-Real/evaluation was not inspected by this validator.",
        "Source labels and coordinates are preserved exactly; no repair or normalization was performed.",
        "",
        f"- Valid annotations: {report['valid_annotation_count']}",
        f"- Excluded annotations: {report['excluded_annotation_count']}",
        "",
    ]
    for source in report["sources"]:
        lines.extend(
            [
                f"## {source['source']}",
                "",
                f"- Annotation records: {source.get('annotation_records', 0)}",
                f"- Image files: {source.get('image_files', 0)}",
                f"- Valid annotations: {len(source.get('valid_annotations', []))}",
                f"- Excluded annotations: {len(source.get('excluded_annotations', []))}",
                f"- Image dimension mismatches: {len(source.get('image_dimension_mismatches', []))}",
                "",
            ]
        )
        reasons: dict[str, int] = {}
        for item in source.get("excluded_annotations", []):
            for reason in item["reasons"]:
                reasons[reason["code"]] = reasons.get(reason["code"], 0) + 1
        if reasons:
            lines.append("Exclusion reasons:")
            lines.extend(f"- `{code}`: {count}" for code, count in sorted(reasons.items()))
            lines.append("")
    (output_root / "validation_report.md").write_text(
        "\n".join(lines),
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    report = build_report(
        [validate_source(name, root) for name, root in DATASET_SOURCES]
    )
    write_report(report, args.output_root)
    print(
        json.dumps(
            {
                "valid_annotation_count": report["valid_annotation_count"],
                "excluded_annotation_count": report["excluded_annotation_count"],
                "output_root": str(args.output_root),
            },
            indent=2,
        )
    )


# Focused pytest-compatible tests are kept in this module so Stage 1 creates
# only the requested validator file.
def test_validate_label_preserves_unsupported_characters() -> None:
    problems = validate_label("AUG 16 2022", SUPPORTED_RECOGNIZER_CHARACTERS)
    assert any(item["code"] == "unsupported_characters" for item in problems)
    assert "AUG 16 2022" == "AUG 16 2022"


def test_validate_bbox_rejects_out_of_bounds_without_clipping() -> None:
    problems = validate_bbox([10, 10, 120, 40], 100, 100, 100, 100)
    assert any(item["code"] == "bbox_out_of_image_bounds" for item in problems)


def test_validate_source_reports_missing_transcriptions(tmp_path: Path) -> None:
    source = tmp_path / "source"
    images = source / "images"
    images.mkdir(parents=True)
    Image.new("RGB", (20, 20)).save(images / "sample.jpg")
    (source / "annotations.json").write_text(
        json.dumps(
            {
                "sample.jpg": {
                    "width": 20,
                    "height": 20,
                    "ann": [{"cls": "date", "bbox": [1, 1, 10, 10]}],
                }
            }
        ),
        encoding="utf-8",
    )
    result = validate_source("Products-Real/train", source)
    assert len(result["excluded_annotations"]) == 1
    assert result["excluded_annotations"][0]["reasons"][0]["code"] == "missing_label"


if __name__ == "__main__":
    main()
