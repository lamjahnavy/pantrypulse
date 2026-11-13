"""Export custom recognizer weights without serializing Keras-OCR Lambdas."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


ALPHABET = " -./0123456789ABCDEFGJLMNOPRSTUVY"
ROOT = Path(__file__).resolve().parent
TRAINING_ROOT = ROOT / "dataset" / "training_runs" / "custom_recognizer_pilot_retry"
DEFAULT_OUTPUT = ROOT / "dataset" / "training_runs" / "custom_recognizer_export"


def build_recognizer():
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

    return keras_ocr.recognition.Recognizer(alphabet=ALPHABET, weights="kurapan")


def choose_checkpoint() -> tuple[Path, int, float]:
    history = json.loads((TRAINING_ROOT / "history.json").read_text(encoding="utf-8"))
    losses = history["val_loss"]
    epoch_index = min(range(len(losses)), key=losses.__getitem__)
    epoch = epoch_index + 1
    checkpoint = TRAINING_ROOT / f"checkpoint_{epoch:02d}.weights.h5"
    if not checkpoint.is_file():
        raise FileNotFoundError(f"Best checkpoint is missing: {checkpoint}")
    return checkpoint, epoch, float(losses[epoch_index])


def export(output_root: Path) -> dict[str, object]:
    if output_root.exists():
        raise FileExistsError(f"Refusing to overwrite export directory: {output_root}")
    checkpoint, epoch, validation_loss = choose_checkpoint()
    recognizer = build_recognizer()
    recognizer.training_model.load_weights(checkpoint)
    if recognizer.model.output_shape[-1] != len(ALPHABET) + 1:
        raise ValueError("Reconstructed model has an unexpected output width")
    output_root.mkdir(parents=True)
    weights_path = output_root / "recognizer.weights.h5"
    recognizer.model.save_weights(weights_path)
    metadata = {
        "format": "keras_ocr_recognizer_weights_only",
        "source_checkpoint": str(checkpoint),
        "selected_epoch": epoch,
        "selected_validation_loss": validation_loss,
        "alphabet": ALPHABET,
        "output_width": recognizer.model.output_shape[-1],
        "output_timesteps": recognizer.model.output_shape[1],
        "pretrained_backbone_reused": True,
        "pretrained_classification_head_reused": False,
        "spatial_transformer_enabled": True,
        "load_instruction": "Rebuild Recognizer(alphabet=metadata alphabet, weights='kurapan') and load recognizer.weights.h5 into recognizer.model.",
    }
    (output_root / "metadata.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    return metadata


def test_best_checkpoint_exists() -> None:
    checkpoint, epoch, _ = choose_checkpoint()
    assert epoch == 3
    assert checkpoint.name == "checkpoint_03.weights.h5"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    print(json.dumps(export(args.output_root), indent=2, ensure_ascii=False))
