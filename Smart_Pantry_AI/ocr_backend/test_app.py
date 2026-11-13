"""Tests for the Phase 1 HTTP boundary."""

import io
import json
import sys
import types

import numpy as np
from PIL import Image
import pytest

from ocr_backend.app import create_app
from ocr_backend.app import _group_detection_lines, _serialize_detections
from ocr_backend.custom_recognizer import (
    CUSTOM_ALPHABET,
    EXPECTED_OUTPUT_TIMESTEPS,
    EXPECTED_OUTPUT_WIDTH,
)


class FakeOcrEngine:
    def recognize(self, image: np.ndarray):
        assert image.shape == (8, 12, 3)
        return [("AMUL", np.array([[1, 2], [3, 2], [3, 4], [1, 4]]))]


class DateOcrEngine:
    date_calls = 0

    def recognize(self, image: np.ndarray):
        return [
            (
                "MFD 16.08.26",
                np.array([[1, 2], [3, 2], [3, 4], [1, 4]]),
            )
        ]

    def recognize_date(self, image: np.ndarray):
        self.date_calls += 1
        return [("EXP 03/2027", np.array([[1, 2], [3, 2], [3, 4], [1, 4]]))]


class CustomDateOcrEngine(DateOcrEngine):
    def recognize(self, image: np.ndarray):
        return [("BACK LABEL", np.array([[1, 2], [3, 2], [3, 4], [1, 4]]))]


class FailingOcrEngine:
    def recognize(self, image: np.ndarray):
        raise RuntimeError("detector or recognizer failed")


def image_upload():
    image = Image.new("RGB", (12, 8), color="white")
    stream = io.BytesIO()
    image.save(stream, format="PNG")
    stream.seek(0)
    return {"image": (stream, "sample.png")}


def test_ocr_endpoint_returns_text_and_detections():
    client = create_app(FakeOcrEngine()).test_client()

    response = client.post("/ocr", data=image_upload(), content_type="multipart/form-data")

    assert response.status_code == 200
    payload = response.get_json()
    assert payload["engine"] == "keras_ocr"
    assert payload["status"] == "ok"
    assert payload["text"] == "AMUL"
    assert payload["detections"] == [
        {
            "text": "AMUL",
            "box": [[1, 2], [3, 2], [3, 4], [1, 4]],
            "recognizer": "pretrained",
        }
    ]
    assert payload["lines"] == [
        {
            "text": "AMUL",
            "detections": [
                {
                    "text": "AMUL",
                    "box": [[1, 2], [3, 2], [3, 4], [1, 4]],
                    "recognizer": "pretrained",
                }
            ],
        }
    ]
    assert isinstance(payload["processing_ms"], float)
    assert payload["timing_ms"]["normal_ocr_ms"] is not None
    assert payload["timing_ms"]["detector_ms"] is None
    assert "detector_ms is null" in payload["timing_notes"][0]
    assert payload["error_code"] is None


def test_detections_are_reading_order_and_grouped_into_lines():
    predictions = [
        ("DATE", np.array([[30, 20], [50, 20], [50, 30], [30, 30]])),
        ("EXP", np.array([[2, 20], [20, 20], [20, 30], [2, 30]])),
        ("MFD", np.array([[2, 2], [22, 2], [22, 12], [2, 12]])),
    ]

    detections = _serialize_detections(predictions)
    assert [item["text"] for item in detections] == ["MFD", "EXP", "DATE"]
    assert [line["text"] for line in _group_detection_lines(detections)] == [
        "MFD",
        "EXP DATE",
    ]


def test_ocr_endpoint_rejects_missing_image():
    client = create_app(FakeOcrEngine()).test_client()

    response = client.post("/ocr", data={}, content_type="multipart/form-data")

    assert response.status_code == 400
    assert response.get_json() == {
        "error": "Provide an image file in the 'image' form field."
    }


def test_date_mode_returns_targeted_ocr_text():
    client = create_app(DateOcrEngine()).test_client()

    response = client.post(
        "/ocr",
        data={**image_upload(), "mode": "date"},
        content_type="multipart/form-data",
    )

    assert response.status_code == 200
    assert "MFD 16.08.26" in response.get_json()["text"]


def test_date_mode_merges_all_preprocessing_variants(monkeypatch):
    monkeypatch.setenv("OCR_RECOGNIZER_MODE", "date_custom")

    class VariantDateEngine:
        calls = 0

        def recognize(self, image: np.ndarray):
            return [("BACK LABEL", np.zeros((4, 2), dtype=np.float32))]

        def recognize_date(self, image: np.ndarray):
            self.calls += 1
            return [
                (
                    f"EXP 31/08/2027 variant {self.calls}",
                    np.zeros((4, 2), dtype=np.float32),
                )
            ]

    engine = VariantDateEngine()
    response = create_app(engine).test_client().post(
        "/ocr",
        data={**image_upload(), "mode": "date"},
        content_type="multipart/form-data",
    )

    assert response.status_code == 200
    assert engine.calls == 4
    text = response.get_json()["text"]
    assert "EXP 31/08/2027 variant 1" in text
    assert "EXP 31/08/2027 variant 4" in text


def test_empty_ocr_response_is_explicit():
    client = create_app(type("EmptyEngine", (), {"recognize": lambda self, image: []})()).test_client()

    response = client.post("/ocr", data=image_upload(), content_type="multipart/form-data")

    assert response.status_code == 200
    payload = response.get_json()
    assert payload["engine"] == "keras_ocr"
    assert payload["status"] == "empty"
    assert payload["text"] == ""
    assert payload["detections"] == []
    assert payload["lines"] == []
    assert payload["error_code"] == "EMPTY_OCR"


def test_malformed_detections_become_explicit_empty_response():
    class MalformedEngine:
        def recognize(self, image: np.ndarray):
            return [("missing box",)]

    response = create_app(MalformedEngine()).test_client().post(
        "/ocr",
        data=image_upload(),
        content_type="multipart/form-data",
    )
    assert response.status_code == 200
    assert response.get_json()["status"] == "empty"
    assert response.get_json()["detections"] == []


def test_inference_exception_returns_502():
    response = create_app(FailingOcrEngine()).test_client().post(
        "/ocr",
        data=image_upload(),
        content_type="multipart/form-data",
    )
    assert response.status_code == 502
    assert response.get_json()["error"] == "OCR inference failed."


def test_non_image_content_type_is_rejected():
    response = create_app(FakeOcrEngine()).test_client().post(
        "/ocr",
        data={"image": (io.BytesIO(b"not an image"), "sample.txt")},
        content_type="multipart/form-data",
    )
    assert response.status_code == 415


def test_pretrained_mode_is_default_and_preserves_health_contract(monkeypatch):
    monkeypatch.delenv("OCR_RECOGNIZER_MODE", raising=False)
    response = create_app(FakeOcrEngine()).test_client().get("/health")
    assert response.get_json() == {
        "status": "ok",
        "engine": "keras_ocr",
        "recognizer_mode": "pretrained",
        "date_retry_mode": "custom_lightweight",
    }


def test_invalid_recognizer_mode_is_rejected(monkeypatch):
    monkeypatch.setenv("OCR_RECOGNIZER_MODE", "invalid")
    with pytest.raises(ValueError, match="OCR_RECOGNIZER_MODE"):
        create_app(FakeOcrEngine())


def test_date_custom_mode_uses_date_recognizer(monkeypatch):
    monkeypatch.setenv("OCR_RECOGNIZER_MODE", "date_custom")
    engine = CustomDateOcrEngine()
    response = create_app(engine).test_client().post(
        "/ocr",
        data={**image_upload(), "mode": "date"},
        content_type="multipart/form-data",
    )
    assert response.status_code == 200
    assert "EXP 03/2027" in response.get_json()["text"]
    assert engine.date_calls == 4


def test_lightweight_date_retry_reuses_normal_boxes_and_marks_custom_source(monkeypatch):
    monkeypatch.setenv("OCR_DATE_RETRY_MODE", "custom_lightweight")

    class LightweightEngine:
        candidate_calls = 0

        def recognize(self, image: np.ndarray):
            return [
                (
                    "USE BY",
                    np.array([[1, 2], [30, 2], [30, 12], [1, 12]]),
                ),
                (
                    "31082027",
                    np.array([[40, 2], [100, 2], [100, 12], [40, 12]]),
                ),
            ]

        def recognize_date_candidates(self, image, detections):
            self.candidate_calls += 1
            assert len(detections) == 2
            return [
                (
                    "31/08/2027",
                    np.array([[40, 2], [100, 2], [100, 12], [40, 12]]),
                    "custom_date",
                )
            ]

    engine = LightweightEngine()
    response = create_app(engine).test_client().post(
        "/ocr",
        data={**image_upload(), "mode": "date"},
        content_type="multipart/form-data",
    )

    assert response.status_code == 200
    assert engine.candidate_calls == 1
    payload = response.get_json()
    assert "31/08/2027" in payload["text"]
    assert any(
        item["recognizer"] == "custom_date"
        for item in payload["detections"]
    )


def test_custom_loader_rejects_missing_weights(tmp_path):
    from ocr_backend.custom_recognizer import build_custom_recognizer

    with pytest.raises(FileNotFoundError, match="weights"):
        build_custom_recognizer(
            tmp_path / "missing.weights.h5",
            tmp_path / "metadata.json",
        )


def test_custom_loader_rejects_corrupt_metadata(tmp_path):
    from ocr_backend.custom_recognizer import build_custom_recognizer

    weights = tmp_path / "recognizer.weights.h5"
    weights.write_bytes(b"not-a-model")
    metadata = tmp_path / "metadata.json"
    metadata.write_text("{}", encoding="utf-8")
    with pytest.raises(RuntimeError, match="alphabet"):
        build_custom_recognizer(weights, metadata)


def test_custom_loader_rejects_corrupt_weights(tmp_path, monkeypatch):
    from ocr_backend.custom_recognizer import build_custom_recognizer

    weights = tmp_path / "recognizer.weights.h5"
    weights.write_bytes(b"not-a-model")
    metadata = tmp_path / "metadata.json"
    metadata.write_text(
        json.dumps(
            {
                "alphabet": CUSTOM_ALPHABET,
                "output_width": EXPECTED_OUTPUT_WIDTH,
                "output_timesteps": EXPECTED_OUTPUT_TIMESTEPS,
            }
        ),
        encoding="utf-8",
    )

    class BrokenModel:
        output_shape = (None, EXPECTED_OUTPUT_TIMESTEPS, EXPECTED_OUTPUT_WIDTH)

        def load_weights(self, path):
            raise OSError("invalid weights")

    fake_keras_ocr = types.SimpleNamespace(
        recognition=types.SimpleNamespace(
            Recognizer=lambda **kwargs: types.SimpleNamespace(model=BrokenModel())
        )
    )
    monkeypatch.setitem(sys.modules, "keras_ocr", fake_keras_ocr)

    with pytest.raises(RuntimeError, match="Could not load custom recognizer weights"):
        build_custom_recognizer(weights, metadata)


def test_custom_model_shape_contract():
    assert len(CUSTOM_ALPHABET) + 1 == EXPECTED_OUTPUT_WIDTH
    assert EXPECTED_OUTPUT_TIMESTEPS == 48