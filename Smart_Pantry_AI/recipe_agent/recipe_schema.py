from __future__ import annotations

import json
import re
from typing import Any


RECIPE_FIELDS = (
    "dish_name",
    "cuisine",
    "description",
    "servings",
    "preparation_time",
    "cooking_time",
    "required_ingredients",
    "optional_ingredients",
    "preparation",
    "cooking",
    "serving_suggestions",
    "substitutions",
    "tips",
)

INGREDIENT_SCHEMA = {
    "type": "object",
    "properties": {
        "name": {"type": "string"},
        "quantity": {"type": "string"},
        "aliases": {"type": "array", "items": {"type": "string"}},
        "optional": {"type": "boolean"},
    },
    "required": ["name", "quantity"],
}

RECIPE_SCHEMA = {
    "type": "object",
    "properties": {
        "dish_name": {"type": "string"},
        "cuisine": {"type": "string"},
        "description": {"type": "string"},
        "servings": {"type": "string"},
        "preparation_time": {"type": "string"},
        "cooking_time": {"type": "string"},
        "required_ingredients": {"type": "array", "items": INGREDIENT_SCHEMA},
        "optional_ingredients": {"type": "array", "items": INGREDIENT_SCHEMA},
        "preparation": {"type": "array", "items": {"type": "string"}},
        "cooking": {"type": "array", "items": {"type": "string"}},
        "serving_suggestions": {"type": "array", "items": {"type": "string"}},
        "substitutions": {"type": "array", "items": {"type": "string"}},
        "tips": {"type": "array", "items": {"type": "string"}},
    },
    "required": list(RECIPE_FIELDS),
}


class RecipeDiagnosticError(ValueError):
    def __init__(self, category: str, message: str) -> None:
        super().__init__(message)
        self.category = category


def parse_json_payload(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if isinstance(value, list):
        text_parts = [
            item.get("text", "")
            for item in value
            if isinstance(item, dict) and isinstance(item.get("text"), str)
        ]
        if text_parts:
            value = "".join(text_parts)
    if not isinstance(value, str):
        raise RecipeDiagnosticError("malformed_json", "provider content is not JSON text")
    text = value.strip()
    fenced = re.fullmatch(r"```(?:json)?\s*(.*?)\s*```", text, re.IGNORECASE | re.DOTALL)
    if fenced:
        text = fenced.group(1).strip()
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as error:
        raise RecipeDiagnosticError("malformed_json", "provider content is malformed JSON") from error
    if not isinstance(parsed, dict):
        raise RecipeDiagnosticError("malformed_json", "provider content is not a JSON object")
    return parsed


def _extract_tool_arguments(value: Any) -> dict[str, Any] | None:
    if isinstance(value, dict):
        arguments = value.get("arguments")
        if arguments is not None:
            return parse_json_payload(arguments)
        args = value.get("args")
        if isinstance(args, dict):
            return args
    return None


def _extract_message_recipe(message: dict[str, Any]) -> dict[str, Any]:
    tool_calls = message.get("tool_calls")
    if isinstance(tool_calls, list):
        for tool_call in tool_calls:
            if not isinstance(tool_call, dict):
                continue
            recipe = _extract_tool_arguments(tool_call.get("function"))
            if recipe is not None:
                return recipe

    function_call = _extract_tool_arguments(message.get("function_call"))
    if function_call is not None:
        return function_call

    return parse_json_payload(message.get("content"))


def extract_recipe(provider_body: dict[str, Any], provider: str) -> dict[str, Any]:
    if provider == "gemini":
        candidates = provider_body.get("candidates")
        if not isinstance(candidates, list) or not candidates:
            raise RecipeDiagnosticError("extraction_failed", "provider returned no candidates")
        parts = candidates[0].get("content", {}).get("parts", [])
        for part in parts:
            if isinstance(part, dict) and isinstance(part.get("text"), str):
                return parse_json_payload(part["text"])
            function_call = part.get("functionCall") if isinstance(part, dict) else None
            if isinstance(function_call, dict) and isinstance(function_call.get("args"), dict):
                return function_call["args"]
        raise RecipeDiagnosticError("extraction_failed", "provider returned no recipe content")
    choices = provider_body.get("choices")
    if not isinstance(choices, list) or not choices:
        raise RecipeDiagnosticError("extraction_failed", "provider returned no choices")
    message = choices[0].get("message", {})
    if not isinstance(message, dict):
        raise RecipeDiagnosticError("extraction_failed", "provider returned an invalid message")
    return _extract_message_recipe(message)


def validate_recipe(recipe: dict[str, Any]) -> None:
    missing = [field for field in RECIPE_FIELDS if field not in recipe]
    if missing:
            raise RecipeDiagnosticError("missing_required_fields", "recipe is missing required fields")
    for field in RECIPE_FIELDS[:6]:
        if not isinstance(recipe[field], str) or not recipe[field].strip():
                raise RecipeDiagnosticError("invalid_field_type", "recipe contains an invalid text field")
    for field in RECIPE_FIELDS[6:]:
        values = recipe[field]
        if not isinstance(values, list) or any(
            not isinstance(value, str) or not value.strip()
            for value in values
        ):
            if field in {"required_ingredients", "optional_ingredients"}:
                if not isinstance(values, list):
                        raise RecipeDiagnosticError("invalid_field_type", "recipe contains invalid ingredients")
            else:
                    raise RecipeDiagnosticError("invalid_instruction_list", "recipe contains invalid instruction lists")
    required = recipe["required_ingredients"]
    optional = recipe["optional_ingredients"]
    if not isinstance(required, list) or not 1 <= len(required) <= 50:
            raise RecipeDiagnosticError("invalid_field_type", "required ingredients are invalid")
    if not isinstance(optional, list) or len(optional) > 50:
            raise RecipeDiagnosticError("invalid_field_type", "optional ingredients are invalid")
    for ingredient in [*required, *optional]:
        if not isinstance(ingredient, dict):
                raise RecipeDiagnosticError("invalid_field_type", "ingredient is invalid")
        if not str(ingredient.get("name", "")).strip():
                raise RecipeDiagnosticError("missing_ingredient_name", "ingredient name is missing")
        if not str(ingredient.get("quantity", "")).strip():
                raise RecipeDiagnosticError("missing_ingredient_quantity", "ingredient quantity is missing")
        aliases = ingredient.get("aliases", [])
        if not isinstance(aliases, list) or any(not isinstance(alias, str) for alias in aliases):
                raise RecipeDiagnosticError("invalid_field_type", "ingredient aliases are invalid")
