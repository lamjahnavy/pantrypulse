from __future__ import annotations

from datetime import date

import requests

from recipe_agent.app import create_app
from recipe_agent.models import PantryItem
from recipe_agent.provider_manager import ProviderManager
from recipe_agent.providers import (
    GeminiAdapter,
    OpenAICompatibleAdapter,
    ProviderConfig,
    ProviderFailure,
    configured_adapters,
)


def pantry(name: str, quantity: str = "1", exp: str = "Not detected", status: str = "Not Used"):
    return PantryItem(name, name, quantity, exp, status)


def recipe():
    return {
        "dish_name": "Tomato Rice",
        "cuisine": "Indian",
        "description": "A simple tomato rice.",
        "servings": "2",
        "preparation_time": "10 minutes",
        "cooking_time": "25 minutes",
        "required_ingredients": [{"name": "tomato", "quantity": "2"}],
        "optional_ingredients": [],
        "preparation": ["Chop tomatoes."],
        "cooking": ["Cook the rice with tomatoes."],
        "serving_suggestions": ["Serve hot."],
        "substitutions": [],
        "tips": ["Adjust seasoning."],
    }


class Response:
    def __init__(self, status_code, body):
        self.status_code = status_code
        self._body = body
        self.headers = {}

    def json(self):
        return self._body


def config(name, model="test-model"):
    return ProviderConfig(name, model, "test-key", "https://example.test", "TEST_KEY", 0, 7, 30)


def adapter(name, statuses=(200,), bodies=None, model="test-model"):
    calls = []
    import json

    bodies = bodies or [
        (
            {"candidates": [{"content": {"parts": [{"text": json.dumps(recipe())}]}}]}
            if name == "gemini"
            else {"choices": [{"message": {"content": json.dumps(recipe())}}]}
        )
    ]

    def requester(*args, **kwargs):
        index = len(calls)
        calls.append((args, kwargs))
        status = statuses[min(index, len(statuses) - 1)]
        body = bodies[min(index, len(bodies) - 1)]
        return Response(status, body)

    cls = GeminiAdapter if name == "gemini" else OpenAICompatibleAdapter
    return cls(config(name, model=model), requester=requester), calls


def test_prompt_requires_complete_recipe_schema():
    prompt = ProviderManager._prompt(
        "make tomato rice",
        [pantry("tomato")],
        [],
        pantry_cooking=False,
    )
    required_keys = [
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
    ]
    for key in required_keys:
        assert key in prompt
    assert "All 13 top-level keys are mandatory" in prompt
    assert "never omit a key" in prompt
    assert "must always be arrays" in prompt
    assert "Use []" in prompt
    assert "non-empty name and quantity" in prompt
    assert "All required text fields must contain non-empty strings" in prompt
    assert "Never return a partial recipe" in prompt
    assert "Before responding, verify that all 13 keys are present" in prompt
    assert "Return exactly one complete JSON object" in prompt


def test_configured_adapters_selects_gemini_only(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "gemini-test-key")
    monkeypatch.setenv("RECIPE_GEMINI_MODEL", "gemini-test-model")
    monkeypatch.setenv("GROQ_API_KEY", "groq-test-key")
    monkeypatch.setenv("GROQ_MODEL", "groq-test-model")
    monkeypatch.setenv("OPENROUTER_API_KEY", "openrouter-test-key")
    monkeypatch.setenv("OPENROUTER_MODEL", "openrouter-test-model")
    monkeypatch.setenv("RECIPE_PROVIDER_ORDER", "groq,openrouter,gemini")

    adapters = configured_adapters()

    assert [item.config.name for item in adapters] == ["gemini"]
    assert all(item.config.name not in {"groq", "openrouter"} for item in adapters)


def test_adapters_use_provider_specific_request_shapes():
    gemini, gemini_calls = adapter("gemini")
    gemini.generate("make tea", timeout=(5, 30), request_id="one")
    assert gemini_calls[0][1]["json"]["generationConfig"]["maxOutputTokens"] == 1500

    groq, groq_calls = adapter("groq")
    groq.generate("make tea", timeout=(5, 30), request_id="two")
    assert groq_calls[0][1]["json"]["max_tokens"] == 1500
    assert groq_calls[0][1]["headers"]["Authorization"].startswith("Bearer ")


def test_openai_json_mode_falls_back_when_unsupported():
    import json
    calls = []

    def requester(*args, **kwargs):
        calls.append(kwargs["json"])
        if len(calls) == 1:
            return Response(400, {"error": {"message": "response_format json_object is unsupported"}})
        return Response(200, {"choices": [{"message": {"content": json.dumps(recipe())}}]})

    groq = OpenAICompatibleAdapter(config("groq"), requester=requester)
    result = groq.generate("tea", timeout=(5, 30), request_id="json-fallback")
    assert result["dish_name"] == "Tomato Rice"
    assert "response_format" in calls[0]
    assert "response_format" not in calls[1]


def test_openai_unrelated_http_400_is_invalid_request_without_retry():
    groq, calls = adapter("groq")
    groq.requester = lambda *args, **kwargs: (
        calls.append((args, kwargs))
        or Response(400, {"error": {"message": "invalid request payload"}})
    )
    try:
        groq.generate("tea", timeout=(5, 30), request_id="invalid-request")
    except ProviderFailure as error:
        assert error.category == "invalid_request"
        assert error.status == 400
    else:
        raise AssertionError("unrelated HTTP 400 must be invalid_request")
    assert len(calls) == 1


def test_invalid_request_falls_back_without_retrying_primary():
    primary, primary_calls = adapter("gemini")
    primary.requester = lambda *args, **kwargs: (
        primary_calls.append((args, kwargs))
        or Response(400, {"error": {"message": "invalid request payload"}})
    )
    fallback, _ = adapter("groq")
    manager = ProviderManager([primary, fallback], sleeper=lambda _: None)
    assert manager.generate("tea", [], [], pantry_cooking=False, request_id="invalid-fallback")["status"] == "ok"
    assert len(primary_calls) == 1


def test_openai_json_mode_malformed_json_is_rejected():
    groq, _ = adapter("groq")
    groq.requester = lambda *args, **kwargs: Response(
        200, {"choices": [{"message": {"content": "{bad"}}]}
    )
    try:
        groq.generate("tea", timeout=(5, 30), request_id="bad-json")
    except ProviderFailure as error:
        assert error.category == "malformed_json"
    else:
        raise AssertionError("malformed JSON must be rejected")


def test_extraction_failure_has_sanitized_category():
    groq, _ = adapter("groq")
    groq.requester = lambda *args, **kwargs: Response(200, {"choices": []})
    try:
        groq.generate("tea", timeout=(5, 30), request_id="missing-content")
    except ProviderFailure as error:
        assert error.category == "extraction_failed"
    else:
        raise AssertionError("missing provider content must be classified")


def test_missing_required_fields_have_sanitized_category():
    groq, _ = adapter("groq")
    incomplete = recipe()
    incomplete.pop("tips")
    import json

    groq.requester = lambda *args, **kwargs: Response(
        200, {"choices": [{"message": {"content": json.dumps(incomplete)}}]}
    )
    try:
        groq.generate("tea", timeout=(5, 30), request_id="missing-fields")
    except ProviderFailure as error:
        assert error.category == "missing_required_fields"
    else:
        raise AssertionError("missing fields must be classified")


def test_invalid_field_type_has_sanitized_category():
    groq, _ = adapter("groq")
    invalid = recipe()
    invalid["servings"] = 2
    import json

    groq.requester = lambda *args, **kwargs: Response(
        200, {"choices": [{"message": {"content": json.dumps(invalid)}}]}
    )
    try:
        groq.generate("tea", timeout=(5, 30), request_id="invalid-type")
    except ProviderFailure as error:
        assert error.category == "invalid_field_type"
    else:
        raise AssertionError("invalid field types must be classified")


def test_missing_ingredient_name_has_sanitized_category():
    groq, _ = adapter("groq")
    invalid = recipe()
    invalid["required_ingredients"][0].pop("name")
    import json

    groq.requester = lambda *args, **kwargs: Response(
        200, {"choices": [{"message": {"content": json.dumps(invalid)}}]}
    )
    try:
        groq.generate("tea", timeout=(5, 30), request_id="missing-name")
    except ProviderFailure as error:
        assert error.category == "missing_ingredient_name"
    else:
        raise AssertionError("missing ingredient names must be classified")


def test_missing_ingredient_quantity_has_sanitized_category():
    groq, _ = adapter("groq")
    invalid = recipe()
    invalid["required_ingredients"][0].pop("quantity")
    import json

    groq.requester = lambda *args, **kwargs: Response(
        200, {"choices": [{"message": {"content": json.dumps(invalid)}}]}
    )
    try:
        groq.generate("tea", timeout=(5, 30), request_id="missing-quantity")
    except ProviderFailure as error:
        assert error.category == "missing_ingredient_quantity"
    else:
        raise AssertionError("missing ingredient quantities must be classified")


def test_invalid_instruction_list_has_sanitized_category():
    groq, _ = adapter("groq")
    invalid = recipe()
    invalid["cooking"] = ["", "Cook the rice."]
    import json

    groq.requester = lambda *args, **kwargs: Response(
        200, {"choices": [{"message": {"content": json.dumps(invalid)}}]}
    )
    try:
        groq.generate("tea", timeout=(5, 30), request_id="invalid-instructions")
    except ProviderFailure as error:
        assert error.category == "invalid_instruction_list"
    else:
        raise AssertionError("invalid instruction lists must be classified")


def test_openai_structured_content_parts_are_parsed():
    groq, _ = adapter("groq")
    import json

    groq.requester = lambda *args, **kwargs: Response(
        200,
        {
            "choices": [
                {
                    "message": {
                        "content": [
                            {"type": "text", "text": json.dumps(recipe())},
                        ]
                    }
                }
            ]
        },
    )
    result = groq.generate("tea", timeout=(5, 30), request_id="content-parts")
    assert result["dish_name"] == "Tomato Rice"


def test_openai_tool_call_arguments_are_parsed():
    groq, _ = adapter("groq")
    import json

    groq.requester = lambda *args, **kwargs: Response(
        200,
        {
            "choices": [
                {
                    "message": {
                        "tool_calls": [
                            {
                                "function": {
                                    "name": "generate_recipe",
                                    "arguments": json.dumps(recipe()),
                                }
                            }
                        ]
                    }
                }
            ]
        },
    )
    result = groq.generate("tea", timeout=(5, 30), request_id="tool-call")
    assert result["dish_name"] == "Tomato Rice"


def test_openai_legacy_function_call_arguments_are_parsed():
    groq, _ = adapter("groq")
    import json

    groq.requester = lambda *args, **kwargs: Response(
        200,
        {
            "choices": [
                {
                    "message": {
                        "function_call": {
                            "name": "generate_recipe",
                            "arguments": json.dumps(recipe()),
                        }
                    }
                }
            ]
        },
    )
    result = groq.generate("tea", timeout=(5, 30), request_id="legacy-function-call")
    assert result["dish_name"] == "Tomato Rice"


def test_openai_fenced_json_is_parsed():
    groq, _ = adapter("groq")
    import json

    groq.requester = lambda *args, **kwargs: Response(
        200,
        {"choices": [{"message": {"content": f"```json\n{json.dumps(recipe())}\n```"}}]},
    )
    result = groq.generate("tea", timeout=(5, 30), request_id="fenced-json")
    assert result["dish_name"] == "Tomato Rice"


def test_primary_success_returns_normalized_response():
    primary, _ = adapter("gemini")
    manager = ProviderManager([primary], sleeper=lambda _: None)
    result = manager.generate("tomato rice", [pantry("tomato")], [], pantry_cooking=False, request_id="one")
    assert result["status"] == "ok"
    assert result["available_pantry_ingredients"][0]["name"] == "tomato"


def test_429_falls_back_without_retrying_daily_quota():
    primary, primary_calls = adapter("gemini", statuses=(429,))
    fallback, fallback_calls = adapter("groq")
    def daily_quota(*args, **kwargs):
        primary_calls.append((args, kwargs))
        return Response(
            429,
            {"error": {"message": "Generate content requests per day limit exceeded"}},
        )
    primary.requester = daily_quota
    manager = ProviderManager([primary, fallback], sleeper=lambda _: None)
    result = manager.generate("tea", [], [], pantry_cooking=False, request_id="two")
    assert result["status"] == "ok"
    assert len(primary_calls) == 1
    assert len(fallback_calls) == 1


def test_timeout_falls_back():
    primary, _ = adapter("gemini")

    def timeout(*args, **kwargs):
        raise requests.exceptions.ReadTimeout()

    primary.requester = timeout
    fallback, _ = adapter("groq")
    manager = ProviderManager([primary, fallback], sleeper=lambda _: None)
    assert manager.generate("tea", [], [], pantry_cooking=False, request_id="three")["status"] == "ok"


def test_read_timeout_is_not_retried_on_same_provider():
    primary, calls = adapter("gemini")

    def timeout(*args, **kwargs):
        calls.append((args, kwargs))
        raise requests.exceptions.ReadTimeout()

    primary.requester = timeout
    fallback, _ = adapter("groq")
    manager = ProviderManager([primary, fallback], sleeper=lambda _: None)
    assert manager.generate("tea", [], [], pantry_cooking=False, request_id="no-timeout-retry")["status"] == "ok"
    assert len(calls) == 1


def test_fast_5xx_retries_once_on_same_provider():
    primary, calls = adapter("gemini", statuses=(503, 200))
    fallback, _ = adapter("groq")
    manager = ProviderManager([primary, fallback], sleeper=lambda _: None)
    result = manager.generate("tea", [], [], pantry_cooking=False, request_id="fast-5xx")
    assert result["status"] == "ok"
    assert len(calls) == 2


def test_connection_failure_and_permanent_provider_errors_fall_back():
    primary, _ = adapter("gemini")
    primary.requester = lambda *args, **kwargs: (_ for _ in ()).throw(
        requests.exceptions.ConnectionError()
    )
    fallback, _ = adapter("groq")
    manager = ProviderManager([primary, fallback], sleeper=lambda _: None)
    assert manager.generate("tea", [], [], pantry_cooking=False, request_id="connect")["status"] == "ok"

    for status, expected in ((401, "authentication_failed"), (404, "invalid_model")):
        first, _ = adapter("gemini")
        first.requester = lambda *args, status=status, **kwargs: Response(
            status, {"error": {"message": "provider configuration failure"}}
        )
        second, _ = adapter("groq")
        manager = ProviderManager([first, second], sleeper=lambda _: None)
        assert manager.generate("tea", [], [], pantry_cooking=False, request_id=str(status))["status"] == "ok"
        assert manager.cooldowns["gemini"] > 0


def test_empty_provider_configuration_is_explicit():
    manager = ProviderManager([], sleeper=lambda _: None)
    try:
        manager.generate("tea", [], [], pantry_cooking=False, request_id="empty")
    except ProviderFailure as error:
        assert error.category == "not_configured"
    else:
        raise AssertionError("empty provider configuration must fail explicitly")


def test_all_providers_unavailable():
    primary, _ = adapter("gemini", statuses=(503, 503))
    fallback, _ = adapter("groq", statuses=(503, 503))
    manager = ProviderManager([primary, fallback], sleeper=lambda _: None)
    try:
        manager.generate("tea", [], [], pantry_cooking=False, request_id="four")
    except ProviderFailure as error:
        assert error.category == "provider_server_error"
    else:
        raise AssertionError("all provider failures must be reported")


def test_malformed_json_is_classified_and_falls_back():
    primary, _ = adapter("gemini")
    primary.requester = lambda *args, **kwargs: Response(
        200, {"candidates": [{"content": {"parts": [{"text": "{bad"}]}}]}
    )
    fallback, _ = adapter("groq")
    manager = ProviderManager([primary, fallback], sleeper=lambda _: None)
    assert manager.generate("tea", [], [], pantry_cooking=False, request_id="five")["status"] == "ok"


def test_missing_quantity_is_invalid_recipe():
    primary, _ = adapter("gemini")
    invalid = recipe()
    invalid["required_ingredients"] = [{"name": "tomato"}]
    primary.requester = lambda *args, **kwargs: Response(
        200, {"candidates": [{"content": {"parts": [{"text": __import__("json").dumps(invalid)}]}}]}
    )
    manager = ProviderManager([primary], sleeper=lambda _: None)
    try:
        manager.generate("tea", [], [], pantry_cooking=False, request_id="six")
    except ProviderFailure as error:
        assert error.category == "missing_ingredient_quantity"
    else:
        raise AssertionError("missing quantities must fail validation")


def test_force_fail_switch_is_off_by_default_and_testable(monkeypatch):
    primary, _ = adapter("gemini")
    monkeypatch.setenv("RECIPE_PROVIDER_FORCE_FAIL", "gemini")
    monkeypatch.delenv("RECIPE_ENV", raising=False)
    try:
        primary.generate("tea", timeout=(5, 30), request_id="force")
    except ProviderFailure as error:
        assert error.category == "provider_server_error"
    else:
        raise AssertionError("force-fail switch must fail the selected provider")
    monkeypatch.setenv("RECIPE_ENV", "production")
    primary.generate("tea", timeout=(5, 30), request_id="production")


def test_flask_modes_and_response_shape():
    primary, _ = adapter("gemini")
    manager = ProviderManager([primary], sleeper=lambda _: None)
    client = create_app(manager).test_client()
    headers = {"X-Request-ID": "mode-test"}
    normal = client.post("/chat", json={"message": "tea", "pantry": []}, headers=headers)
    pantry_mode = client.post("/pantry-cook", json={"message": "tea", "pantry": []}, headers=headers)
    assert normal.status_code == 200
    assert pantry_mode.status_code == 200


def test_health_reports_all_configured_provider_models_without_secrets():
    gemini, _ = adapter("gemini", model="gemini-test")
    groq, _ = adapter("groq", model="groq-test")
    openrouter, _ = adapter("openrouter", model="openrouter-test")
    manager = ProviderManager([gemini, groq, openrouter], sleeper=lambda _: None)
    client = create_app(manager).test_client()

    response = client.get("/health")

    assert response.status_code == 200
    body = response.get_json()
    assert body["providers_configured"] is True
    assert body["gemini_configured"] is True
    assert body["providers"] == [
        {"name": "gemini", "model": "gemini-test"},
        {"name": "groq", "model": "groq-test"},
        {"name": "openrouter", "model": "openrouter-test"},
    ]
    assert "test-key" not in response.get_data(as_text=True)
    assert "api_key" not in response.get_data(as_text=True).lower()


def test_health_reports_gemini_false_when_gemini_adapter_is_absent():
    groq, _ = adapter("groq", model="groq-test")
    client = create_app(ProviderManager([groq], sleeper=lambda _: None)).test_client()

    body = client.get("/health").get_json()

    assert body["providers_configured"] is True
    assert body["gemini_configured"] is False
    assert body["providers"] == [{"name": "groq", "model": "groq-test"}]


def test_matcher_preserves_expiry_finished_zero_and_unknown_rules():
    primary, _ = adapter("gemini")
    manager = ProviderManager([primary], sleeper=lambda _: None)
    items = [
        pantry("tomato", exp="01/01/2020"),
        pantry("onion", status="Finished"),
        pantry("oil", quantity="0 ml"),
        pantry("rice"),
    ]
    result = manager._finalize(
        {**recipe(), "required_ingredients": [{"name": "tomato", "quantity": "1"}]},
        items,
    )
    assert result["available_pantry_ingredients"] == []
    assert "rice" in result["expiry_warnings"]["unknown"]
