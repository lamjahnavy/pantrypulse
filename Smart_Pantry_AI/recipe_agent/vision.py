"""Gemini vision fallback that reads brand and product name from a front photo.

The app only calls this when its own OCR is unsure of the brand or name;
dates, quantity and price always come from the local OCR pipeline.
"""
from __future__ import annotations

import base64
import logging
import os
import time
from typing import Any, Callable

import requests

from .recipe_schema import RecipeDiagnosticError, parse_json_payload

LOGGER = logging.getLogger(__name__)
CATEGORIES = (
    "Dairy",
    "Grains",
    "Snacks",
    "Beverages",
    "Household",
    "Groceries",
    "Others",
)
MAX_IMAGE_BYTES = 5 * 1024 * 1024
# 404 means the model was retired; the next model in the chain may work.
RETRYABLE_STATUS_CODES = {404, 429, 500, 502, 503, 504}
PROMPT = (
    "This is a photo of the front of a packaged grocery product. Read the "
    "printed packaging and return one JSON object with exactly these keys: "
    '"brand" (the brand or company name as printed, e.g. "Britannia"), '
    '"product_name" (the product name without the brand, e.g. "Marie Gold"), '
    f'"category" (one of: {", ".join(CATEGORIES)}). '
    'Use "" for any value you cannot read on the pack. Do not guess from '
    "colours or shapes alone."
)


class VisionError(RuntimeError):
    pass


class ProductIdentifier:
    def __init__(
        self,
        api_key: str | None = None,
        requester: Callable[..., requests.Response] | None = None,
    ) -> None:
        self.api_key = (
            os.environ.get("GEMINI_API_KEY", "") if api_key is None else api_key
        ).strip()
        primary = os.environ.get("RECIPE_GEMINI_MODEL", "gemini-3.5-flash")
        fallbacks = os.environ.get(
            "RECIPE_GEMINI_FALLBACK_MODELS",
            "gemini-3.5-flash,gemini-3.1-flash-lite",
        )
        self.models = list(dict.fromkeys(
            name.strip()
            for name in [primary, *fallbacks.split(",")]
            if name.strip()
        ))
        self.requester = requester or requests.post
        self.deadline_seconds = 40

    def identify(self, image: bytes, mime_type: str) -> dict[str, str]:
        if not self.api_key:
            raise VisionError("GEMINI_API_KEY is not configured")
        payload = {
            "contents": [{
                "role": "user",
                "parts": [
                    {"inlineData": {
                        "mimeType": mime_type,
                        "data": base64.b64encode(image).decode("ascii"),
                    }},
                    {"text": PROMPT},
                ],
            }],
            "generationConfig": {
                "temperature": 0,
                "responseMimeType": "application/json",
                "thinkingConfig": {"thinkingLevel": "low"},
                "maxOutputTokens": 512,
            },
        }
        deadline = time.monotonic() + self.deadline_seconds
        last_error = "no model attempted"
        for model in self.models:
            remaining = deadline - time.monotonic()
            if remaining <= 1:
                break
            url = (
                "https://generativelanguage.googleapis.com/v1beta/models/"
                f"{model}:generateContent"
            )
            try:
                response = self.requester(
                    url,
                    params={"key": self.api_key},
                    json=payload,
                    timeout=(7, min(20, remaining)),
                )
            except requests.RequestException as error:
                LOGGER.warning("Vision model=%s failed: %s", model, type(error).__name__)
                last_error = type(error).__name__
                continue
            if response.status_code != 200:
                LOGGER.warning("Vision model=%s returned HTTP %s", model, response.status_code)
                last_error = f"HTTP {response.status_code}"
                if response.status_code in RETRYABLE_STATUS_CODES:
                    continue
                break
            try:
                return self._parse(response.json())
            except (RecipeDiagnosticError, KeyError, IndexError, TypeError, ValueError) as error:
                LOGGER.warning("Vision model=%s returned unusable JSON", model)
                last_error = type(error).__name__
        raise VisionError(f"Product identification failed: {last_error}")

    @staticmethod
    def _parse(body: dict[str, Any]) -> dict[str, str]:
        parts = body["candidates"][0]["content"]["parts"]
        data = parse_json_payload(parts)

        def text(key: str) -> str:
            value = data.get(key, "")
            return value.strip()[:60] if isinstance(value, str) else ""

        category = text("category").title()
        return {
            "brand": text("brand"),
            "product_name": text("product_name"),
            "category": category if category in CATEGORIES else "Others",
        }
