"""Tests for the Phase 1 HTTP boundary."""

import io

import numpy as np
from PIL import Image

from ocr_backend.app import create_app


class FakeOcrEngine:
    def recognize(self, image: np.ndarray):
        assert image.shape == (8, 12, 3)
        return [("AMUL", np.array([[1, 2], [3, 2], [3, 4], [1, 4]]))]


class DateOcrEngine:
    def recognize(self, image: np.ndarray):
        return [
            (
                "MFD 16.08.26",
                np.array([[1, 2], [3, 2], [3, 4], [1, 4]]),
            )
        ]


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
    assert response.get_json() == {
        "engine": "keras_ocr",
        "text": "AMUL",
        "detections": [
            {
                "text": "AMUL",
                "box": [[1, 2], [3, 2], [3, 4], [1, 4]],
            }
        ],
    }


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