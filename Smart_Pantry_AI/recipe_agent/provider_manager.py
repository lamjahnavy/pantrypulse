from __future__ import annotations

import logging
import os
import time
from typing import Any, Callable

import requests

from .matcher import expiry_status, match_recipe_ingredients
from .models import PantryItem
from .providers import ProviderAdapter, ProviderFailure, configured_adapters

LOGGER = logging.getLogger(__name__)


class ProviderManager:
    def __init__(
        self,
        adapters: list[ProviderAdapter] | None = None,
        requester: Callable[..., requests.Response] | None = None,
        sleeper: Callable[[float], None] | None = None,
    ) -> None:
        self.adapters = configured_adapters(requester) if adapters is None else adapters
        self.sleeper = sleeper or time.sleep
        self.deadline_seconds = max(10, int(os.environ.get("RECIPE_BACKEND_DEADLINE_SECONDS", "75")))
        self.max_attempts = max(1, int(os.environ.get("RECIPE_PROVIDER_ATTEMPTS", "2")))
        self.cooldowns: dict[str, float] = {}

    @property
    def configured(self) -> bool:
        return bool(self.adapters)

    @property
    def model(self) -> str:
        return self.adapters[0].config.model if self.adapters else ""

    @property
    def provider_models(self) -> list[dict[str, str]]:
        return [
            {"name": adapter.config.name, "model": adapter.config.model}
            for adapter in self.adapters
        ]

    def generate(
        self,
        message: str,
        pantry: list[PantryItem],
        context: list[dict[str, str]],
        *,
        pantry_cooking: bool,
        request_id: str | None,
    ) -> dict[str, Any]:
        if not self.adapters:
            raise ProviderFailure("not_configured", "provider_manager")
        deadline = time.monotonic() + self.deadline_seconds
        prompt = self._prompt(message, pantry, context, pantry_cooking)
        failures = []
        for adapter in self.adapters:
            if self.cooldowns.get(adapter.config.name, 0) > time.monotonic():
                continue
            attempts = self.max_attempts
            for attempt in range(attempts):
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                timeout = (
                    min(adapter.config.connect_timeout, max(1.0, remaining)),
                    min(adapter.config.read_timeout, max(1.0, remaining)),
                )
                try:
                    recipe = adapter.generate(prompt, timeout=timeout, request_id=request_id)
                    return self._finalize(recipe, pantry)
                except ProviderFailure as error:
                    failures.append(error)
                    self._cooldown(error)
                    if error.category in {
                        "daily_quota_exhausted",
                        "authentication_failed",
                        "invalid_model",
                        "invalid_request",
                        "malformed_response",
                        "invalid_recipe",
                        "extraction_failed",
                        "malformed_json",
                        "missing_required_fields",
                        "invalid_field_type",
                        "missing_ingredient_name",
                        "missing_ingredient_quantity",
                        "invalid_instruction_list",
                        "not_configured",
                    }:
                        break
                    if attempt + 1 >= attempts:
                        break
                    if error.category not in {"rate_limited", "provider_server_error", "connection_failed"}:
                        break
                    self.sleeper(min(0.5, max(0.0, deadline - time.monotonic())))
        category = failures[-1].category if failures else "not_configured"
        raise ProviderFailure(category, "provider_manager")

    def _cooldown(self, error: ProviderFailure) -> None:
        durations = {
            "daily_quota_exhausted": 24 * 60 * 60,
            "rate_limited": 60,
            "authentication_failed": 15 * 60,
            "invalid_model": 15 * 60,
        }
        duration = durations.get(error.category)
        if duration:
            if error.category == "rate_limited" and error.retry_after is not None:
                duration = max(duration, error.retry_after)
            self.cooldowns[error.provider] = time.monotonic() + duration

    @staticmethod
    def _prompt(message: str, pantry: list[PantryItem], context: list[dict[str, str]], pantry_cooking: bool) -> str:
        pantry_text = ", ".join(item.name for item in pantry) or "No pantry items"
        context_text = " ".join(item["content"] for item in context)
        mode = "Pantry Cooking" if pantry_cooking else "Normal Chat"
        return (
            f"You are PantryPulse Chef AI in {mode} mode. User request: {message}. "
            f"Pantry ingredients: {pantry_text}. Context: {context_text}. "
            "Return exactly one complete JSON object and no Markdown, prose, or code fences. "
            "All 13 top-level keys are mandatory and must always be present; never omit a key, "
            "even when its array value is empty. Use exactly these top-level fields: dish_name, "
            "cuisine, description, servings, preparation_time, cooking_time, "
            "required_ingredients, optional_ingredients, preparation, cooking, "
            "serving_suggestions, substitutions, and tips. "
            "The following fields must always be arrays: required_ingredients, optional_ingredients, "
            "preparation, cooking, serving_suggestions, substitutions, and tips. Use [] when an "
            "array section has no entries. Every ingredient object must contain a non-empty name "
            "and quantity. All required text fields must contain non-empty strings. "
            "Never return a partial recipe. Before responding, verify that all 13 keys are present. "
            'Use this complete shape: {"dish_name":"","cuisine":"","description":"","servings":"",'
            '"preparation_time":"","cooking_time":"","required_ingredients":[],"optional_ingredients":[],'
            '"preparation":[],"cooking":[],"serving_suggestions":[],"substitutions":[],"tips":[]}. '
            "Do not claim pantry availability; the backend matches it locally. "
            "Do not invent pantry products, expiry values, or missing quantities."
        )

    @staticmethod
    def _finalize(recipe: dict[str, Any], pantry: list[PantryItem]) -> dict[str, Any]:
        availability = match_recipe_ingredients(
            recipe["required_ingredients"]
            + [{**item, "optional": True} for item in recipe["optional_ingredients"]],
            pantry,
        )
        return {
            "status": "ok",
            **recipe,
            "available_pantry_ingredients": availability["available"],
            "missing_ingredients": availability["missing"],
            "missing_optional_ingredients": availability["optional_missing"],
            "expiry_warnings": expiry_status(pantry),
        }
