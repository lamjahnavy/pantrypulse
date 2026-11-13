"""Prepare and optionally train a small custom-alphabet Keras-OCR pilot.

The default command runs only the smoke test. Training requires ``--train``.
This module reads only the Stage 2 custom-alphabet manifests and never reads
Products-Real/evaluation.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
from pathlib import Path
from typing import Any, Iterator

import numpy as np
from PIL import Image
import tensorflow as tf


SEED = 20261029
DEFAULT_MANIFEST_ROOT = Path(__file__).resolve().parent / "dataset" / "training_manifests"
DEFAULT_OUTPUT_ROOT = (
    Path(__file__).resolve().parent / "dataset" / "training_runs" / "custom_recognizer_pilot"
)
DEFAULT_BATCH_SIZE = 4
DEFAULT_EPOCHS = 3


def _edit_distance(actual: str, expected: str) -> int:
    previous = list(range(len(expected) + 1))
    for row_index, actual_character in enumerate(actual, 1):
        current = [row_index]
        for column_index, expected_character in enumerate(expected, 1):
            current.append(
                min(
                    current[-1] + 1,
                    previous[column_index] + 1,
                    previous[column_index - 1]
                    + (actual_character != expected_character),
                )
            )
        previous = current
    return previous[-1]


def _normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip())


def evaluate_rows(recognizer: Any, rows: list[dict[str, Any]]) -> dict[str, Any]:
    total_distance = 0
    total_reference_characters = 0
    exact_matches = 0
    predictions = []
    for row in rows:
        image, label = crop_record(row)
        prediction = recognizer.recognize(image)
        normalized_prediction = _normalize_text(prediction)
        normalized_label = _normalize_text(label)
        total_distance += _edit_distance(normalized_prediction, normalized_label)
        total_reference_characters += len(normalized_label)
        exact_matches += normalized_prediction == normalized_label
        predictions.append(
            {
                "image": row["image"],
                "ground_truth_raw": label,
                "prediction_raw": prediction,
            }
        )
    return {
        "records": len(rows),
        "character_error_rate": (
            total_distance / total_reference_characters
            if total_reference_characters
            else 0.0
        ),
        "exact_normalized_text_accuracy": (
            exact_matches / len(rows) if rows else 0.0
        ),
        "predictions": predictions,
    }


class ValidationMetricsCallback(tf.keras.callbacks.Callback):
    def __init__(self, recognizer: Any, rows: list[dict[str, Any]], output_path: Path):
        super().__init__()
        self.recognizer = recognizer
        self.rows = rows
        self.output_path = output_path

    def on_epoch_end(self, epoch: int, logs: dict[str, Any] | None = None) -> None:
        metrics = evaluate_rows(self.recognizer, self.rows)
        record = {"epoch": epoch + 1, **{key: value for key, value in metrics.items() if key != "predictions"}}
        with self.output_path.open("a", encoding="utf-8") as output:
            output.write(json.dumps(record) + "\n")
        if logs is not None:
            logs["validation_cer"] = metrics["character_error_rate"]
            logs["validation_exact_accuracy"] = metrics[
                "exact_normalized_text_accuracy"
            ]


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        row = json.loads(line)
        if not isinstance(row, dict):
            raise ValueError(f"{path}:{line_number} is not a JSON object")
        rows.append(row)
    if not rows:
        raise ValueError(f"Manifest is empty: {path}")
    return rows


def load_manifests(manifest_root: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]], str]:
    metadata = json.loads((manifest_root / "manifest_metadata.json").read_text(encoding="utf-8"))
    if metadata.get("evaluation_data_used") is not False:
        raise ValueError("Manifest metadata does not prove evaluation data was excluded")
    alphabet = metadata.get("custom_alphabet")
    if not isinstance(alphabet, str) or not alphabet:
        raise ValueError("Manifest metadata has no custom alphabet")
    train = load_jsonl(manifest_root / "recognizer_custom_alphabet_train.jsonl")
    validation = load_jsonl(manifest_root / "recognizer_custom_alphabet_validation.jsonl")
    for split, rows in (("train", train), ("validation", validation)):
        for row in rows:
            if row.get("split") != split:
                raise ValueError(f"Manifest row has incorrect split: {row}")
            if not isinstance(row.get("label_raw"), str) or not row["label_raw"]:
                raise ValueError("Recognizer manifest contains an empty label")
            if any(character not in alphabet for character in row["label_raw"]):
                raise ValueError("Recognizer manifest contains a character outside its alphabet")
            if "evaluation" in str(row.get("image_path", "")).lower():
                raise ValueError("Held-out evaluation path found in training manifest")
    train_images = {row["image_path"] for row in train}
    validation_images = {row["image_path"] for row in validation}
    if train_images & validation_images:
        raise ValueError("Training and validation images overlap")
    return train, validation, alphabet


def crop_record(row: dict[str, Any]) -> tuple[np.ndarray, str]:
    image_path = Path(row["image_path"])
    bbox = row.get("bbox_raw")
    if not isinstance(bbox, list) or len(bbox) != 4:
        raise ValueError(f"Invalid bbox for {image_path}: {bbox!r}")
    left, top, right, bottom = (int(value) for value in bbox)
    with Image.open(image_path) as image:
        width, height = image.size
        if not (0 <= left < right <= width and 0 <= top < bottom <= height):
            raise ValueError(f"Out-of-bounds bbox for {image_path}: {bbox!r}")
        return np.asarray(image.convert("RGB").crop((left, top, right, bottom))), row["label_raw"]


def sample_generator(
    rows: list[dict[str, Any]], width: int = 200, height: int = 31
) -> Iterator[tuple[np.ndarray, str]]:
    os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")
    if not hasattr(np, "sctypes"):
        np.sctypes = {
            "int": [np.int8, np.int16, np.int32, np.int64],
            "uint": [np.uint8, np.uint16, np.uint32, np.uint64],
            "float": [np.float16, np.float32, np.float64],
            "complex": [np.complex64, np.complex128],
            "others": [bool, object, bytes, str, np.void],
        }
    from keras_ocr import tools

    while True:
        for row in rows:
            image, label = crop_record(row)
            yield tools.read_and_fit(
                image, width=width, height=height, cval=0
            ), label


def encode_label(label: str, alphabet: str, max_length: int) -> np.ndarray:
    if not label or any(character not in alphabet for character in label):
        raise ValueError("Label contains an empty or out-of-alphabet value")
    if len(label) > max_length:
        raise ValueError(f"Label length {len(label)} exceeds model capacity {max_length}")
    return np.asarray(
        [alphabet.index(character) for character in label]
        + [-1] * (max_length - len(label)),
        dtype=np.int32,
    )


def decode_label(encoded: list[int] | np.ndarray, alphabet: str) -> str:
    blank = len(alphabet)
    return "".join(alphabet[index] for index in encoded if index not in (-1, blank))


def build_recognizer(alphabet: str):
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

    return keras_ocr.recognition.Recognizer(alphabet=alphabet, weights="kurapan")


def run_smoke_test(manifest_root: Path) -> dict[str, Any]:
    train, validation, alphabet = load_manifests(manifest_root)
    recognizer = build_recognizer(alphabet)
    max_length = recognizer.training_model.input_shape[1][1]
    image, label = crop_record(train[0])
    encoded = encode_label(label, alphabet, max_length)
    decoded = decode_label(encoded, alphabet)
    if decoded != label:
        raise AssertionError(f"Label round trip failed: {label!r} != {decoded!r}")
    output_width = recognizer.model.output_shape[-1]
    expected_width = len(alphabet) + 1
    if output_width != expected_width:
        raise AssertionError(f"Output width {output_width} != {expected_width}")
    prediction = recognizer.recognize(image)
    return {
        "train_records": len(train),
        "validation_records": len(validation),
        "alphabet": alphabet,
        "alphabet_size": len(alphabet),
        "max_string_length": max_length,
        "output_width": output_width,
        "round_trip_label": label,
        "smoke_prediction": prediction,
        "pretrained_head_reused": False,
        "pretrained_backbone_reused": True,
    }


def train_pilot(
    manifest_root: Path,
    output_root: Path,
    epochs: int,
    batch_size: int,
) -> dict[str, Any]:
    if epochs <= 0 or batch_size <= 0:
        raise ValueError("epochs and batch_size must be positive")
    train, validation, alphabet = load_manifests(manifest_root)
    random.seed(SEED)
    np.random.seed(SEED)
    recognizer = build_recognizer(alphabet)
    recognizer.compile()
    train_steps = max(1, len(train) // batch_size)
    validation_steps = max(1, len(validation) // batch_size)
    output_root.mkdir(parents=True, exist_ok=False)
    baseline_metrics = evaluate_rows(recognizer, validation)
    baseline_metrics.pop("predictions")
    config = {
        "seed": SEED,
        "epochs": epochs,
        "batch_size": batch_size,
        "train_records": len(train),
        "validation_records": len(validation),
        "alphabet": alphabet,
        "architecture": {
            "type": "keras_ocr.recognition.Recognizer",
            "weights": "kurapan",
            "pretrained_backbone_reused": True,
            "pretrained_classification_head_reused": False,
            "output_width": len(alphabet) + 1,
        },
    }
    (output_root / "config.json").write_text(
        json.dumps(config, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    (output_root / "baseline_validation_metrics.json").write_text(
        json.dumps(baseline_metrics, indent=2), encoding="utf-8"
    )
    import tensorflow as tf

    callbacks = [
        ValidationMetricsCallback(
            recognizer, validation, output_root / "validation_metrics.jsonl"
        ),
        tf.keras.callbacks.CSVLogger(output_root / "training_log.csv"),
        tf.keras.callbacks.ModelCheckpoint(
            filepath=output_root / "checkpoint_{epoch:02d}.weights.h5",
            monitor="val_loss",
            save_best_only=True,
            save_weights_only=True,
        ),
    ]
    history = recognizer.training_model.fit(
        recognizer.get_batch_generator(
            sample_generator(
                train,
                width=recognizer.model.input_shape[2],
                height=recognizer.model.input_shape[1],
            ),
            batch_size=batch_size,
        ),
        steps_per_epoch=train_steps,
        validation_data=recognizer.get_batch_generator(
            sample_generator(
                validation,
                width=recognizer.model.input_shape[2],
                height=recognizer.model.input_shape[1],
            ),
            batch_size=batch_size,
        ),
        validation_steps=validation_steps,
        epochs=epochs,
        callbacks=callbacks,
    )
    history_data = {key: [float(value) for value in values] for key, values in history.history.items()}
    (output_root / "history.json").write_text(
        json.dumps(history_data, indent=2), encoding="utf-8"
    )
    recognizer.model.save(output_root / "recognizer_final.keras")
    return {"config": config, "history": history_data}


def test_label_encoding_round_trip() -> None:
    alphabet = " -./0123456789AB"
    label = "AB 12/03"
    encoded = encode_label(label, alphabet, 12)
    assert decode_label(encoded, alphabet) == label


def test_manifest_loading_is_split_isolated() -> None:
    train, validation, alphabet = load_manifests(DEFAULT_MANIFEST_ROOT)
    assert train and validation and alphabet
    assert {row["image_path"] for row in train}.isdisjoint(
        {row["image_path"] for row in validation}
    )


def test_output_dimension_matches_custom_alphabet() -> None:
    alphabet = "0123"
    assert len(alphabet) + 1 == 5


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest-root", type=Path, default=DEFAULT_MANIFEST_ROOT)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--train", action="store_true", help="Launch the pilot training run")
    parser.add_argument("--epochs", type=int, default=DEFAULT_EPOCHS)
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE)
    args = parser.parse_args()
    if args.train:
        print(json.dumps(train_pilot(args.manifest_root, args.output_root, args.epochs, args.batch_size), indent=2))
    else:
        print(json.dumps(run_smoke_test(args.manifest_root), indent=2, ensure_ascii=False))
