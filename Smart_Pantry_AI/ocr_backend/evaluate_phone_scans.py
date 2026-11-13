"""Incremental evaluation of the fixed real phone back-label photo set.

This evaluator intentionally uses an explicit allow-list. It does not infer
ground truth from OCR output and does not include screenshots or date variants.
Run it once with ``--mode baseline`` and once with ``--mode custom``.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import shutil
import time
from pathlib import Path
from typing import Any

from PIL import Image

from .app import KerasOcrEngine, create_app


ROOT = Path(__file__).resolve().parent
DEFAULT_INPUT = ROOT / "debug" / "phone_scans"
DEFAULT_OUTPUT = ROOT / "dataset" / "results" / "phone_scans"
FIXED_BACK_PHOTOS = (
    "f13cff27cf1048fc8a35c5549b6a895d_input.jpg",
    "54aea8ada2b24e7f8ca8062f09449489_input.jpg",
    "5ed14a6d29de4494bfa9c20c287f38f3_input.jpg",
)
GROUND_TRUTH = {
    "mfd": "15/07/2024",
    "exp": "14/01/2025",
    "quantity": "5 kg",
    "price": "285.00",
}


def _load_results(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {"mode": None, "images": []}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"mode": None, "images": []}
    return value if isinstance(value, dict) else {"mode": None, "images": []}


def _write_results(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    temporary.replace(path)


def _normalise_mode(mode: str) -> tuple[str, str]:
    if mode == "baseline":
        return "pretrained", "pretrained_fallback"
    return "pretrained", "custom_lightweight"


def _hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _persist_parser_output(output_path: Path) -> None:
    parser_script = ROOT.parent / "tool" / "evaluate_phone_parser.dart"
    if not parser_script.is_file():
        raise RuntimeError(f"Flutter parser evaluator is missing: {parser_script}")
    dart = shutil.which("dart")
    if dart is None:
        flutter = shutil.which("flutter")
        if flutter:
            flutter_bin = Path(flutter).resolve().parent
            candidate = flutter_bin / "cache" / "dart-sdk" / "bin" / "dart.exe"
            if candidate.is_file():
                dart = str(candidate)
    if dart is None:
        raise RuntimeError("Dart SDK was not found on PATH or beside Flutter.")
    subprocess.run(
        [
            dart,
            "run",
            str(parser_script.relative_to(ROOT.parent)),
            "--input",
            str(output_path),
            "--output",
            str(output_path),
        ],
        cwd=ROOT.parent,
        check=True,
    )


def _update_metrics(payload: dict[str, Any]) -> None:
    rows = [
        row
        for row in payload.get("images", [])
        if isinstance(row, dict) and row.get("status") == "ok"
    ]
    fields = ("mfd", "exp", "quantity", "price")
    metrics: dict[str, Any] = {"image_count": len(rows), "fields": {}}
    for field in fields:
        truth = str(payload["ground_truth"][field]).replace(" ", "").upper()
        exact = 0
        matching_digits = 0
        total_digits = sum(character.isdigit() for character in truth)
        for row in rows:
            output = str(row.get("parser_output", {}).get(field, ""))
            normalized = output.replace(" ", "").upper()
            if normalized == truth:
                exact += 1
            predicted_digits = "".join(
                character for character in normalized if character.isdigit()
            )
            truth_digits = "".join(character for character in truth if character.isdigit())
            matching_digits += sum(
                predicted == expected
                for predicted, expected in zip(predicted_digits, truth_digits)
            )
        metrics["fields"][field] = {
            "exact": exact,
            "total": len(rows),
            "exact_accuracy": exact / len(rows) if rows else 0.0,
            "digit_accuracy": (
                matching_digits / (total_digits * len(rows))
                if rows and total_digits
                else 0.0
            ),
        }
    payload["metrics"] = metrics


def evaluate(input_dir: Path, output_path: Path, mode: str) -> None:
    recognizer_mode, date_retry_mode = _normalise_mode(mode)
    payload = _load_results(output_path)
    payload["mode"] = mode
    payload["recognizer_mode"] = recognizer_mode
    payload["date_retry_mode"] = date_retry_mode
    payload["fixed_images"] = list(FIXED_BACK_PHOTOS)
    payload["ground_truth"] = GROUND_TRUTH
    payload["distinct_image_count"] = 0
    payload["distinct_hashes"] = []
    done = {
        row.get("sha256")
        for row in payload.get("images", [])
        if isinstance(row, dict) and row.get("status") == "ok"
    }

    os.environ["OCR_RECOGNIZER_MODE"] = recognizer_mode
    os.environ["OCR_DATE_RETRY_MODE"] = date_retry_mode
    engine = KerasOcrEngine(recognizer_mode, date_retry_mode)
    client = create_app(engine).test_client()

    for index, filename in enumerate(FIXED_BACK_PHOTOS, 1):
        if filename in done:
            print(f"[{index}/3] skip {filename} (already written)", flush=True)
            continue
        image_path = input_dir / filename
        if not image_path.is_file():
            row = {"file": filename, "status": "missing"}
            payload["images"].append(row)
            _write_results(output_path, payload)
            print(f"[{index}/3] missing {filename}", flush=True)
            continue
        image_hash = _hash_file(image_path)
        if image_hash in done:
            duplicate = {
                "file": filename,
                "status": "duplicate",
                "sha256": image_hash,
            }
            existing_index = next(
                (
                    position
                    for position, item in enumerate(payload["images"])
                    if isinstance(item, dict) and item.get("file") == filename
                ),
                None,
            )
            if existing_index is None:
                payload["images"].append(duplicate)
            else:
                payload["images"][existing_index] = duplicate
            _write_results(output_path, payload)
            _persist_parser_output(output_path)
            payload = _load_results(output_path)
            _update_metrics(payload)
            _write_results(output_path, payload)
            print(f"[{index}/3] skip {filename} (duplicate SHA-256)", flush=True)
            continue

        started = time.perf_counter()
        try:
            with image_path.open("rb") as image_file:
                response = client.post(
                    "/ocr",
                    data={
                        "mode": "date",
                        "source": "full",
                        "image": (image_file, filename),
                    },
                    content_type="multipart/form-data",
                )
            result = response.get_json() or {}
            with Image.open(image_path) as image:
                dimensions = list(image.size)
            row = {
                "file": filename,
                "status": "ok" if response.status_code == 200 else "http_error",
                "http_status": response.status_code,
                "dimensions": dimensions,
                "sha256": image_hash,
                "elapsed_ms": round((time.perf_counter() - started) * 1000, 2),
                "processing_ms": result.get("processing_ms"),
                "text": result.get("text", ""),
                "detections": result.get("detections", []),
                "lines": result.get("lines", []),
                "source": result.get("source"),
                "input_size": result.get("input_size"),
                "date_candidates": result.get("date_candidates", []),
                "error_code": result.get("error_code"),
            }
        except Exception as error:
            row = {
                "file": filename,
                "status": "exception",
                "error": f"{type(error).__name__}: {error}",
                "elapsed_ms": round((time.perf_counter() - started) * 1000, 2),
            }
        existing_index = next(
            (
                position
                for position, item in enumerate(payload["images"])
                if isinstance(item, dict) and item.get("file") == filename
            ),
            None,
        )
        if existing_index is None:
            payload["images"].append(row)
        else:
            payload["images"][existing_index] = row
        if row.get("status") == "ok":
            done.add(image_hash)
        payload["distinct_hashes"] = sorted(
            {
                item.get("sha256")
                for item in payload["images"]
                if isinstance(item, dict) and item.get("sha256")
            }
        )
        payload["distinct_image_count"] = len(payload["distinct_hashes"])
        _write_results(output_path, payload)
        _persist_parser_output(output_path)
        payload = _load_results(output_path)
        _update_metrics(payload)
        _write_results(output_path, payload)
        print(
            f"[{index}/3] wrote {filename}: status={row['status']} "
            f"distinct={payload['distinct_image_count']} "
            f"processing_ms={row.get('processing_ms')}",
            flush=True,
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("baseline", "custom"), required=True)
    parser.add_argument("--input-dir", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = args.output or DEFAULT_OUTPUT / f"{args.mode}.json"
    evaluate(args.input_dir, output, args.mode)


if __name__ == "__main__":
    main()
