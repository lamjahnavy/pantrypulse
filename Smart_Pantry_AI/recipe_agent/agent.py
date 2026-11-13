from __future__ import annotations

import logging
import os
import random
import time
from typing import Any, Callable

import requests

from .matcher import expiry_status, match_recipe_ingredients
from .models import PantryItem, pantry_to_dict
from .offline import find_recipe, unsupported
from .recipe_schema import RecipeDiagnosticError, parse_json_payload

LOGGER = logging.getLogger(__name__)
DEFAULT_REQUEST_TIMEOUT = 25
DEFAULT_TOTAL_DEADLINE = 90
TRANSIENT_STATUS_CODES = {429, 500, 502, 503, 504}


class AgentError(RuntimeError):
    pass


class RecipeAgent:
    def __init__(
        self,
        api_key: str | None = None,
        requester: Callable[..., requests.Response] | None = None,
        sleeper: Callable[[float], None] | None = None,
        randomizer: Callable[[], float] | None = None,
    ) -> None:
        self.api_key = (
            os.environ.get("GEMINI_API_KEY", "").strip()
            if api_key is None
            else api_key.strip()
        )
        self.model = os.environ.get("RECIPE_GEMINI_MODEL", "gemini-3.5-flash")
        fallbacks = os.environ.get(
            "RECIPE_GEMINI_FALLBACK_MODELS",
            "gemini-3.5-flash,gemini-3.1-flash-lite",
        )
        self.models = list(dict.fromkeys(
            name.strip()
            for name in [self.model, *fallbacks.split(",")]
            if name.strip()
        ))
        try:
            self.request_timeout = max(
                5,
                int(os.environ.get("RECIPE_GEMINI_TIMEOUT_SECONDS", "25")),
            )
        except ValueError:
            self.request_timeout = DEFAULT_REQUEST_TIMEOUT
        try:
            self.total_deadline = max(
                10,
                int(os.environ.get("RECIPE_AGENT_DEADLINE_SECONDS", "90")),
            )
        except ValueError:
            self.total_deadline = DEFAULT_TOTAL_DEADLINE
        # Groq's free tier is the fallback when every Gemini model fails.
        self.groq_api_key = os.environ.get("GROQ_API_KEY", "").strip()
        self.groq_model = os.environ.get("GROQ_MODEL", "openai/gpt-oss-20b").strip()
        self.groq_base_url = os.environ.get("GROQ_BASE_URL", "https://api.groq.com/openai/v1")
        self.requester = requester or requests.post
        self.sleeper = sleeper or time.sleep
        self.randomizer = randomizer or random.random

    @property
    def provider_models(self) -> list[dict[str, str]]:
        if not self.api_key:
            return []
        return [{"name": "gemini", "model": self.model}]

    def chat(
        self,
        message: str,
        pantry: list[PantryItem],
        context: list[dict[str, str]],
        pantry_cooking: bool = False,
        request_id: str | None = None,
    ) -> dict[str, Any]:
        if not self.api_key:
            error = "GEMINI_API_KEY is not configured on the Recipe Agent backend."
            LOGGER.error(error)
            raise AgentError(error)
        deadline = time.monotonic() + self.total_deadline
        try:
            return self._run_gemini(
                message,
                pantry,
                context,
                pantry_cooking,
                deadline=deadline,
                request_id=request_id,
            )
        except requests.RequestException as error:
            LOGGER.error("Gemini request failed: %s", type(error).__name__)
            failure: Exception = AgentError(
                f"Gemini network request failed: {type(error).__name__}. "
                "Check backend internet access or wait for the API timeout."
            )
            failure.__cause__ = error
        except (AgentError, ValueError, KeyError, TypeError) as error:
            LOGGER.error("Gemini returned an invalid or incomplete recipe response")
            failure = error
        if not self.groq_api_key:
            raise failure
        LOGGER.warning("Gemini failed; falling back to Groq model=%s", self.groq_model)
        try:
            # Gemini may have used most of the deadline; always leave Groq a fair window.
            groq_deadline = max(deadline, time.monotonic() + 30)
            return self._run_groq(
                message, pantry, context, pantry_cooking, deadline=groq_deadline
            )
        except (requests.RequestException, AgentError, ValueError, KeyError, TypeError) as error:
            LOGGER.error("Groq fallback failed: %s", type(error).__name__)
            raise failure from error

    def _run_gemini(
        self,
        message: str,
        pantry: list[PantryItem],
        context: list[dict[str, str]],
        pantry_cooking: bool,
        deadline: float,
        request_id: str | None,
    ) -> dict[str, Any]:
        contents = [
            {"role": item["role"], "parts": [{"text": item["content"]}]}
            for item in context
        ]
        contents.append({
            "role": "user",
            "parts": [{"text": self._system_prompt(message, pantry, pantry_cooking)}],
        })
        response = self._call(contents, deadline=deadline, request_id=request_id)
        recipe = self._extract_recipe(response)
        return self._complete(recipe, pantry)

    def _run_groq(
        self,
        message: str,
        pantry: list[PantryItem],
        context: list[dict[str, str]],
        pantry_cooking: bool,
        deadline: float,
    ) -> dict[str, Any]:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise AgentError("Recipe Agent deadline exceeded")
        messages = [
            {"role": "assistant" if item["role"] == "model" else item["role"],
             "content": item["content"]}
            for item in context
        ]
        messages.append({
            "role": "user",
            "content": self._system_prompt(message, pantry, pantry_cooking),
        })
        response = self.requester(
            f"{self.groq_base_url.rstrip('/')}/chat/completions",
            headers={
                "Authorization": f"Bearer {self.groq_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": self.groq_model,
                "messages": messages,
                "temperature": 0.2,
                "max_tokens": 3000,
                "response_format": {"type": "json_object"},
            },
            timeout=(7, min(self.request_timeout, max(1, remaining))),
        )
        if response.status_code != 200:
            LOGGER.warning("Groq model=%s returned HTTP %s", self.groq_model, response.status_code)
            raise AgentError(f"Groq API request failed with HTTP {response.status_code}.")
        try:
            text = response.json()["choices"][0]["message"]["content"]
            recipe = parse_json_payload(text)
        except (RecipeDiagnosticError, KeyError, IndexError, TypeError, ValueError) as error:
            raise AgentError("Groq returned an invalid structured recipe JSON response") from error
        return self._complete(recipe, pantry)

    def _complete(self, recipe: dict[str, Any], pantry: list[PantryItem]) -> dict[str, Any]:
        # Models sometimes emit servings/times as numbers (e.g. "servings": 1).
        for field in ("servings", "preparation_time", "cooking_time"):
            value = recipe.get(field)
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                recipe[field] = str(value)
        for field in ("preparation", "cooking", "serving_suggestions", "substitutions", "tips"):
            values = recipe.get(field)
            if isinstance(values, str):
                values = [values]
            if isinstance(values, list):
                recipe[field] = [
                    text
                    for text in (self._step_text(value) for value in values)
                    if text
                ]
        for ingredient in [
            *(recipe.get("required_ingredients") or []),
            *(recipe.get("optional_ingredients") or []),
        ]:
            quantity = ingredient.get("quantity") if isinstance(ingredient, dict) else None
            if isinstance(quantity, (int, float)) and not isinstance(quantity, bool):
                ingredient["quantity"] = str(quantity)
        self._validate_recipe(recipe)
        availability = match_recipe_ingredients(
            recipe["required_ingredients"]
            + [{**item, "optional": True} for item in recipe["optional_ingredients"]],
            pantry,
        )
        return self._finalize(recipe, availability, pantry)

    @staticmethod
    def _extract_recipe(response: dict[str, Any]) -> dict[str, Any]:
        candidates = response.get("candidates")
        if not isinstance(candidates, list) or not candidates:
            raise AgentError("Gemini returned no recipe candidate")
        parts = candidates[0].get("content", {}).get("parts", [])
        if not isinstance(parts, list):
            raise AgentError("Gemini returned an invalid recipe response")
        for part in parts:
            if not isinstance(part, dict):
                continue
            function_call = part.get("functionCall")
            if isinstance(function_call, dict) and function_call.get("name") == "generate_recipe":
                args = function_call.get("args")
                if isinstance(args, dict):
                    return args
            if isinstance(part.get("text"), str):
                try:
                    return parse_json_payload(part["text"])
                except RecipeDiagnosticError as error:
                    raise AgentError(
                        "Gemini returned an invalid structured recipe JSON response"
                    ) from error
        raise AgentError("Gemini did not return a structured recipe")

    @staticmethod
    def _step_text(value: Any) -> str:
        if isinstance(value, str):
            return value.strip()
        if isinstance(value, dict):
            return " ".join(
                str(item).strip() for item in value.values()
                if isinstance(item, (str, int, float)) and str(item).strip()
            )
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return str(value)
        return ""

    @staticmethod
    def _validate_recipe(recipe: dict[str, Any]) -> None:
        required_fields = (
            "dish_name", "cuisine", "description", "servings",
            "preparation_time", "cooking_time", "required_ingredients",
            "optional_ingredients", "preparation", "cooking",
            "serving_suggestions", "substitutions", "tips",
        )
        missing = [field for field in required_fields if field not in recipe]
        if missing:
            raise ValueError(f"recipe is missing required fields: {', '.join(missing)}")
        for field in ("dish_name", "cuisine", "description", "servings", "preparation_time", "cooking_time"):
            if not isinstance(recipe[field], str) or not recipe[field].strip():
                raise ValueError(f"{field} is required")
        for field in ("preparation", "cooking", "serving_suggestions", "substitutions", "tips"):
            values = recipe[field]
            if not isinstance(values, list) or any(
                not isinstance(value, str) or not value.strip() for value in values
            ):
                raise ValueError(f"{field} must contain non-empty text items")
        required = recipe["required_ingredients"]
        optional = recipe["optional_ingredients"]
        if not isinstance(required, list) or not 1 <= len(required) <= 50:
            raise ValueError("required_ingredients must contain 1-50 items")
        if not isinstance(optional, list) or len(optional) > 50:
            raise ValueError("optional_ingredients must contain at most 50 items")
        for ingredient in [*required, *optional]:
            if not isinstance(ingredient, dict):
                raise ValueError("each ingredient must be an object")
            if not str(ingredient.get("name", "")).strip():
                raise ValueError("each ingredient needs a name")
            if not str(ingredient.get("quantity", "")).strip():
                raise ValueError("each ingredient needs a quantity")
            aliases = ingredient.get("aliases", [])
            if not isinstance(aliases, list) or any(not isinstance(alias, str) for alias in aliases):
                raise ValueError("ingredient aliases must be strings")

    def _execute_tool(
        self,
        name: str,
        args: dict[str, Any],
        pantry: list[PantryItem],
        recipe: dict[str, Any] | None,
        availability: dict[str, Any] | None,
    ) -> dict[str, Any]:
        if name == "get_pantry_inventory":
            return {"items": [pantry_to_dict(item) for item in pantry]}
        if name == "check_expiry_status":
            return expiry_status(pantry)
        if name == "generate_recipe":
            self._validate_recipe(args)
            return args
        if name == "match_recipe_ingredients":
            ingredients = args.get("ingredients")
            if not isinstance(ingredients, list) or len(ingredients) > 80:
                raise ValueError("ingredients must contain at most 80 items")
            return match_recipe_ingredients(ingredients, pantry)
        if name == "validate_recipe":
            candidate = args.get("recipe")
            if not isinstance(candidate, dict):
                raise ValueError("recipe is required")
            required = candidate.get("required_ingredients")
            if not candidate.get("dish_name") or not isinstance(required, list):
                return {"valid": False, "reason": "recipe is incomplete"}
            normalized = match_recipe_ingredients(
                required
                + [
                    {**item, "optional": True}
                    for item in candidate.get("optional_ingredients", [])
                    if isinstance(item, dict)
                ],
                pantry,
            )
            return {"valid": True, "availability": normalized}
        raise ValueError(f"unknown tool: {name}")

    def _call(
        self,
        contents: list[dict[str, Any]],
        *,
        deadline: float,
        request_id: str | None,
    ) -> dict[str, Any]:
        # Walk the model chain: an overloaded or timed-out model hands over to the
        # next one instead of retrying the same stalled model.
        attempts = len(self.models) * 2
        last_network_error: requests.RequestException | None = None
        last_response: requests.Response | None = None
        for attempt in range(attempts):
            model = self.models[attempt % len(self.models)]
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AgentError("Recipe Agent deadline exceeded")
            try:
                response = self.requester(
                    url,
                    params={"key": self.api_key},
                    json={
                        "systemInstruction": {
                            "parts": [{
                                "text": (
                                    "You are an expert recipe assistant. Return only "
                                    "one complete JSON object matching the requested "
                                    "recipe schema."
                                ),
                            }],
                        },
                        "contents": contents,
                        "generationConfig": {
                            "temperature": 0.2,
                            "responseMimeType": "application/json",
                            # Hidden thinking tokens count against maxOutputTokens
                            # and truncated the recipe JSON, so keep thinking low.
                            "thinkingConfig": {"thinkingLevel": "low"},
                            "maxOutputTokens": 4096,
                        },
                    },
                    headers={"X-Request-ID": request_id} if request_id else None,
                    timeout=min(self.request_timeout, max(1, remaining)),
                )
            except requests.RequestException as error:
                LOGGER.warning("Gemini model=%s failed: %s", model, type(error).__name__)
                last_network_error = error
                last_response = None
                if deadline - time.monotonic() <= 0:
                    break
                continue
            if response.status_code == 200:
                data = response.json()
                if not isinstance(data, dict) or not data.get("candidates"):
                    raise AgentError("Gemini returned no candidate")
                return data
            LOGGER.warning("Gemini model=%s returned HTTP %s", model, response.status_code)
            # 404 means this model was retired; the next one in the chain may work.
            if response.status_code not in TRANSIENT_STATUS_CODES | {404}:
                self._raise_provider_error(response)
            last_response = response
            last_network_error = None
            if attempt >= len(self.models) - 1:
                self._backoff(attempt // len(self.models), deadline)
        if last_network_error is not None:
            raise last_network_error
        if last_response is not None:
            self._raise_provider_error(last_response)
        raise AgentError("Gemini request could not be completed")

    def _backoff(self, attempt: int, deadline: float) -> None:
        delay = min(4.0, 0.5 * (2**attempt)) + self.randomizer() * 0.25
        self.sleeper(min(delay, max(0.0, deadline - time.monotonic())))

    @staticmethod
    def _raise_provider_error(response: requests.Response) -> None:
        LOGGER.error("Gemini API rejected request: HTTP %s", response.status_code)
        raise AgentError(
            f"Gemini API request failed with HTTP {response.status_code}. "
            "Check the backend log for the redacted API response."
        )

    def _finalize(
        self,
        recipe: dict[str, Any],
        availability: dict[str, Any] | None,
        pantry: list[PantryItem],
    ) -> dict[str, Any]:
        availability = match_recipe_ingredients(
            recipe.get("required_ingredients", [])
            + [
                {**item, "optional": True}
                for item in recipe.get("optional_ingredients", [])
                if isinstance(item, dict)
            ],
            pantry,
        )
        return {
            "status": "ok",
            "dish_name": recipe.get("dish_name", ""),
            "cuisine": recipe.get("cuisine", ""),
            "description": recipe.get("description", ""),
            "flavor_profile": recipe.get("flavor_profile", ""),
            "prioritization_reason": recipe.get("prioritization_reason", ""),
            "servings": recipe.get("servings", ""),
            "preparation_time": recipe.get("preparation_time", ""),
            "cooking_time": recipe.get("cooking_time", ""),
            "required_ingredients": recipe.get("required_ingredients", []),
            "optional_ingredients": recipe.get("optional_ingredients", []),
            "available_pantry_ingredients": availability.get("available", []),
            "missing_ingredients": availability.get("missing", []),
            "missing_optional_ingredients": availability.get("optional_missing", []),
            "preparation": recipe.get("preparation", []),
            "cooking": recipe.get("cooking", []),
            "serving_suggestions": recipe.get("serving_suggestions", []),
            "substitutions": recipe.get("substitutions", []),
            "expiry_warnings": expiry_status(pantry),
            "tips": recipe.get("tips", []),
        }

    def _offline(self, message: str, pantry: list[PantryItem], pantry_cooking: bool) -> dict[str, Any]:
        recipe = find_recipe(message)
        if recipe is None:
            return unsupported(message)
        if pantry_cooking:
            soon_ids = {
                item["id"]
                for item in expiry_status(pantry)["soon"]
                if isinstance(item, dict)
            }
            if not soon_ids:
                return {
                    "status": "unsupported",
                    "message": "No safe recipe recommendation is available from "
                    "products nearing expiry.",
                }
        availability = match_recipe_ingredients(
            recipe["required_ingredients"]
            + [
                {**item, "optional": True}
                for item in recipe.get("optional_ingredients", [])
            ],
            pantry,
        )
        return self._finalize(recipe, availability, pantry)

    @staticmethod
    def _system_prompt(
        message: str,
        pantry: list[PantryItem],
        pantry_cooking: bool,
    ) -> str:
        mode = "Pantry Cooking" if pantry_cooking else "Normal Chat"
        pantry_text = ", ".join(
            f"{item.name} ({item.quantity}; expiry: {item.exp})"
            for item in pantry
        ) or "No pantry items"
        return (
            f"You are the single PantryPulse Recipe Agent in {mode} mode. "
            f"Answer the exact user request: {message!r}. "
            f"Actual pantry inventory: {pantry_text}. Use these names and quantities "
            "only as context; the backend performs the authoritative local matching. "
            "Return only one valid JSON object with exactly these top-level fields: "
            "dish_name, cuisine, description, servings, preparation_time, "
            "cooking_time, required_ingredients, optional_ingredients, preparation, "
            "cooking, serving_suggestions, substitutions, and tips. "
            "Every ingredient must have a non-empty name and quantity. "
            "Never omit a field, invent pantry quantities, or invent expiry dates. "
            "Never return Markdown or explanatory text. "
            "Give complete ingredient quantities, preparation steps, cooking steps, "
            "serving suggestions, substitutions, and practical tips. "
            "Expired products must never be available. Unknown expiry is unknown. "
            "In Pantry Cooking prioritize suitable soon-to-expire items and "
            "explicitly explain why those items were prioritized. "
            "Explore the full range of global cuisines, including authentic "
            "Indian, Mediterranean, Middle Eastern, French, Italian, "
            "Pan-European, East Asian, Latin American, and other regional "
            "cuisines. Do not restrict suggestions to a small repetitive "
            "catalog; match the requested dish and available ingredients. "
            "Water and ordinary table salt are basic kitchen utilities and "
            "must always be treated as available in unlimited quantity. "
            "Never report them as missing, never recommend buying them, and "
            "never call addToShoppingList for water or salt. "
            "Only genuinely missing non-utility ingredients may be reported. "
            "The backend will perform ingredient matching and validation locally."
        )
