from __future__ import annotations

import logging
import os
import time
from dataclasses import dataclass
from typing import Any, Callable

import requests

from .recipe_schema import (
    RECIPE_SCHEMA,
    RecipeDiagnosticError,
    extract_recipe,
    validate_recipe,
)

LOGGER = logging.getLogger(__name__)
TRANSIENT_STATUS_CODES = {429, 500, 502, 503, 504}


@dataclass(frozen=True)
class ProviderConfig:
    name: str
    model: str
    api_key: str
    base_url: str
    key_env: str
    priority: int
    connect_timeout: float
    read_timeout: float


class ProviderFailure(RuntimeError):
    def __init__(
        self,
        category: str,
        provider: str,
        status: int | None = None,
        retry_after: float | None = None,
    ):
        super().__init__(category)
        self.category = category
        self.provider = provider
        self.status = status
        self.retry_after = retry_after


def _failure_category(status: int, body: dict[str, Any]) -> str:
    error = body.get("error", {}) if isinstance(body, dict) else {}
    text = str(error).lower()
    if status == 429:
        if "per day" in text or "daily" in text or "quotaexceeded" in text:
            return "daily_quota_exhausted"
        return "rate_limited"
    if status in {401, 403}:
        return "authentication_failed"
    if status == 404:
        return "invalid_model"
    if status == 400:
        return "invalid_request"
    if status in {500, 502, 503, 504}:
        return "provider_server_error"
    return "provider_server_error"


class ProviderAdapter:
    def __init__(
        self,
        config: ProviderConfig,
        requester: Callable[..., requests.Response] | None = None,
    ) -> None:
        self.config = config
        self.requester = requester or requests.post

    def generate(
        self,
        prompt: str,
        *,
        timeout: tuple[float, float],
        request_id: str | None,
    ) -> dict[str, Any]:
        force_fail = os.environ.get("RECIPE_PROVIDER_FORCE_FAIL", "").strip()
        environment = os.environ.get("RECIPE_ENV", "").strip().lower()
        if force_fail and environment != "production" and (
            force_fail == "all" or self.config.name == force_fail
        ):
            raise ProviderFailure("provider_server_error", self.config.name)
        if not self.config.api_key:
            raise ProviderFailure("not_configured", self.config.name)
        started = time.perf_counter()
        try:
            response = self._request(prompt, timeout=timeout, request_id=request_id, json_mode=True)
        except requests.exceptions.ConnectTimeout as error:
            LOGGER.info("provider=%s status=timeout latency_ms=%s", self.config.name, round((time.perf_counter() - started) * 1000))
            raise ProviderFailure("timeout", self.config.name) from error
        except requests.exceptions.ReadTimeout as error:
            LOGGER.info("provider=%s status=timeout latency_ms=%s", self.config.name, round((time.perf_counter() - started) * 1000))
            raise ProviderFailure("timeout", self.config.name) from error
        except requests.exceptions.ConnectionError as error:
            LOGGER.info("provider=%s status=connection_failed latency_ms=%s", self.config.name, round((time.perf_counter() - started) * 1000))
            raise ProviderFailure("connection_failed", self.config.name) from error
        except requests.RequestException as error:
            LOGGER.info("provider=%s status=connection_failed latency_ms=%s", self.config.name, round((time.perf_counter() - started) * 1000))
            raise ProviderFailure("connection_failed", self.config.name) from error
        latency_ms = round((time.perf_counter() - started) * 1000)
        LOGGER.info("provider=%s status=%s latency_ms=%s", self.config.name, response.status_code, latency_ms)
        if response.status_code != 200:
            if (
                self.config.name != "gemini"
                and response.status_code == 400
                and _json_mode_unsupported(response)
            ):
                response = self._request(
                    prompt,
                    timeout=timeout,
                    request_id=request_id,
                    json_mode=False,
                )
                LOGGER.info(
                    "provider=%s status=%s latency_ms=%s",
                    self.config.name,
                    response.status_code,
                    round((time.perf_counter() - started) * 1000),
                )
            if response.status_code == 200:
                try:
                    body = response.json()
                    recipe = extract_recipe(body, self.config.name)
                    validate_recipe(recipe)
                    return recipe
                except RecipeDiagnosticError as error:
                    raise ProviderFailure(error.category, self.config.name) from error
                except (ValueError, KeyError, TypeError) as error:
                    raise ProviderFailure("invalid_recipe", self.config.name) from error
            try:
                body = response.json()
            except ValueError:
                body = {}
            raise ProviderFailure(
                _failure_category(response.status_code, body),
                self.config.name,
                response.status_code,
                _retry_after(response),
            )
        try:
            body = response.json()
            recipe = extract_recipe(body, self.config.name)
        except RecipeDiagnosticError as error:
            raise ProviderFailure(error.category, self.config.name) from error
        except (ValueError, KeyError, TypeError) as error:
            raise ProviderFailure("malformed_response", self.config.name) from error
        try:
            validate_recipe(recipe)
            return recipe
        except RecipeDiagnosticError as error:
            raise ProviderFailure(error.category, self.config.name) from error
        except (ValueError, KeyError, TypeError) as error:
            raise ProviderFailure("invalid_recipe", self.config.name) from error


def _retry_after(response: requests.Response) -> float | None:
    value = response.headers.get("Retry-After") if response.headers else None
    try:
        return max(0.0, float(value)) if value is not None else None
    except (TypeError, ValueError):
        return None

    def _request(
        self,
        prompt: str,
        *,
        timeout: tuple[float, float],
        request_id: str | None,
        json_mode: bool,
    ) -> requests.Response:
        raise NotImplementedError


class GeminiAdapter(ProviderAdapter):
    def _request(self, prompt: str, *, timeout: tuple[float, float], request_id: str | None, json_mode: bool):
        url = f"{self.config.base_url.rstrip('/')}/v1beta/models/{self.config.model}:generateContent"
        return self.requester(
            url,
            params={"key": self.config.api_key},
            headers={"Content-Type": "application/json"},
            json={
                "contents": [{"role": "user", "parts": [{"text": prompt}]}],
                "generationConfig": {
                    "responseMimeType": "application/json",
                    "responseSchema": RECIPE_SCHEMA,
                    "maxOutputTokens": 1500,
                },
            },
            timeout=timeout,
        )


class OpenAICompatibleAdapter(ProviderAdapter):
    def _request(self, prompt: str, *, timeout: tuple[float, float], request_id: str | None, json_mode: bool):
        headers = {
            "Authorization": f"Bearer {self.config.api_key}",
            "Content-Type": "application/json",
        }
        if request_id:
            headers["X-Request-ID"] = request_id
        payload = {
            "model": self.config.model,
            "messages": [{
                "role": "user",
                "content": prompt + (
                    "\nReturn only a JSON object matching the required recipe schema."
                    if not json_mode else ""
                ),
            }],
            "max_tokens": 1500,
        }
        if json_mode:
            payload["response_format"] = {"type": "json_object"}
        return self.requester(
            f"{self.config.base_url.rstrip('/')}/chat/completions",
            headers=headers,
            json=payload,
            timeout=timeout,
        )


def _json_mode_unsupported(response: requests.Response) -> bool:
    try:
        body = response.json()
    except ValueError:
        return False
    error = body.get("error", {}) if isinstance(body, dict) else {}
    text = str(error).lower()
    return "response_format" in text or "json mode" in text or "json_object" in text


def configured_adapters(
    requester: Callable[..., requests.Response] | None = None,
) -> list[ProviderAdapter]:
    # Gemini is the only active recipe provider. Other adapters remain available
    # for isolated tests and future reactivation without being selected here.
    order = ["gemini"]
    defaults = {
        "gemini": ("GEMINI_API_KEY", "RECIPE_GEMINI_MODEL", "https://generativelanguage.googleapis.com"),
        "groq": ("GROQ_API_KEY", "GROQ_MODEL", "https://api.groq.com/openai/v1"),
        "openrouter": ("OPENROUTER_API_KEY", "OPENROUTER_MODEL", "https://openrouter.ai/api/v1"),
    }
    adapters = []
    for priority, name in enumerate(order):
        if name not in defaults:
            continue
        key_env, model_env, base_url = defaults[name]
        key = os.environ.get(key_env, "").strip()
        model = os.environ.get(model_env, "").strip()
        if not key or not model:
            continue
        config = ProviderConfig(
            name=name,
            model=model,
            api_key=key,
            base_url=os.environ.get(f"{name.upper()}_BASE_URL", base_url),
            key_env=key_env,
            priority=priority,
            connect_timeout=float(os.environ.get("RECIPE_PROVIDER_CONNECT_TIMEOUT", "7")),
            read_timeout=float(os.environ.get("RECIPE_PROVIDER_READ_TIMEOUT", "30")),
        )
        adapter_type = GeminiAdapter if name == "gemini" else OpenAICompatibleAdapter
        adapters.append(adapter_type(config, requester=requester))
    return adapters
