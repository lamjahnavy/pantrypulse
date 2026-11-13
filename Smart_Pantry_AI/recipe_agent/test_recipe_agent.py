from __future__ import annotations

import json
from datetime import date

from recipe_agent.agent import AgentError, RecipeAgent
from recipe_agent.app import create_app
from recipe_agent.matcher import expiry_status, match_recipe_ingredients
from recipe_agent.models import PantryItem


def pantry(name: str, quantity: str = "1", exp: str = "Not detected", status: str = "Not Used"):
    return PantryItem(name, name, quantity, exp, status)


def test_health_and_validation():
    client = create_app(RecipeAgent(api_key="")).test_client()
    assert client.get("/health").get_json()["service"] == "recipe_agent"
    response = client.post("/chat", json={"message": "", "pantry": []})
    assert response.status_code == 400


def test_missing_api_key_fails_online_generation_explicitly():
    agent = RecipeAgent(api_key="")
    try:
        agent.chat("How do I make tea?", [], [])
    except AgentError as error:
        assert "GEMINI_API_KEY" in str(error)
    else:
        raise AssertionError("Missing API key must not use offline fallback")


def test_default_flask_service_reports_gemini_only(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    monkeypatch.setenv("RECIPE_GEMINI_MODEL", "gemini-test-model")
    monkeypatch.setenv("GROQ_API_KEY", "groq-test-key")
    monkeypatch.setenv("GROQ_MODEL", "groq-test-model")
    monkeypatch.setenv("OPENROUTER_API_KEY", "openrouter-test-key")
    monkeypatch.setenv("OPENROUTER_MODEL", "openrouter-test-model")

    body = create_app().test_client().get("/health").get_json()

    assert body["providers"] == [{"name": "gemini", "model": "gemini-test-model"}]
    assert body["gemini_configured"] is True


def test_malformed_gemini_response_is_safe_error():
    class FakeResponse:
        status_code = 200

        def json(self):
            return {"candidates": [{"content": {"parts": [{"text": "not-json"}]}}]}

    agent = RecipeAgent(api_key="test-key", requester=lambda *_args, **_kwargs: FakeResponse())
    try:
        agent.chat("Make tea", [], [])
    except AgentError as error:
        assert "structured recipe" in str(error).lower() or "invalid" in str(error).lower()
    else:
        raise AssertionError("malformed Gemini response must be rejected")


def test_gemini_prompt_receives_actual_pantry_context():
    calls = []

    class FakeResponse:
        status_code = 200

        def json(self):
            return {
                "candidates": [{
                    "content": {
                        "parts": [{
                            "functionCall": {
                                "name": "generate_recipe",
                                "args": {
                                    "dish_name": "Tomato Rice",
                                    "cuisine": "Indian",
                                    "description": "Rice with tomatoes.",
                                    "servings": "2",
                                    "preparation_time": "10 minutes",
                                    "cooking_time": "25 minutes",
                                    "required_ingredients": [
                                        {"name": "tomato", "quantity": "4 pieces"},
                                        {"name": "rice", "quantity": "250 g"},
                                    ],
                                    "optional_ingredients": [],
                                    "preparation": ["Chop tomatoes."],
                                    "cooking": ["Cook the rice and tomatoes."],
                                    "serving_suggestions": ["Serve hot."],
                                    "substitutions": [],
                                    "tips": ["Adjust seasoning."],
                                },
                            },
                        }],
                    },
                }],
            }

    def requester(*args, **kwargs):
        calls.append(kwargs)
        return FakeResponse()

    agent = RecipeAgent(api_key="test-key", requester=requester)
    agent.chat(
        "Make tomato rice",
        [
            pantry("Tomato", "4 pieces"),
            pantry("Rice", "500 g"),
        ],
        [],
    )

    prompt = calls[0]["json"]["contents"][-1]["parts"][0]["text"]
    assert "Tomato (4 pieces; expiry: Not detected)" in prompt
    assert "Rice (500 g; expiry: Not detected)" in prompt


def test_gemini_request_uses_reference_direct_generation_shape():
    calls = []

    class FakeResponse:
        status_code = 200

        def json(self):
            return {"candidates": [{
                "content": {"parts": [{
                    "text": __import__("json").dumps({
                        "dish_name": "Tea",
                        "cuisine": "Indian",
                        "description": "Simple tea.",
                        "servings": "1",
                        "preparation_time": "1 minute",
                        "cooking_time": "5 minutes",
                        "required_ingredients": [{"name": "tea", "quantity": "1 tsp"}],
                        "optional_ingredients": [],
                        "preparation": ["Boil water."],
                        "cooking": ["Steep tea."],
                        "serving_suggestions": ["Serve hot."],
                        "substitutions": [],
                        "tips": ["Adjust sweetness."],
                    }),
                }]},
            }]}

    def requester(*_args, **kwargs):
        calls.append(kwargs["json"])
        return FakeResponse()

    result = RecipeAgent(api_key="test-key", requester=requester).chat("Make tea", [], [])

    payload = calls[0]
    assert payload["systemInstruction"]["parts"][0]["text"]
    assert "tools" not in payload
    assert payload["generationConfig"] == {
        "temperature": 0.2,
        "responseMimeType": "application/json",
        "thinkingConfig": {"thinkingLevel": "low"},
        "maxOutputTokens": 4096,
    }
    assert result["dish_name"] == "Tea"


def test_expired_finished_and_zero_items_are_excluded():
    items = [
        pantry("Tomato", exp="01/01/2020"),
        pantry("Onion", status="Finished"),
        pantry("Oil", quantity="0 ml"),
        pantry("Rice", exp="Not detected"),
    ]
    status = expiry_status(items, date(2026, 11, 10))
    assert status["expired"] == ["Tomato"]
    assert "Rice" in status["unknown"]
    matched = match_recipe_ingredients([{"name": "tomato", "quantity": "1"}], items, date(2026, 11, 10))
    assert matched["available"] == []


def test_offline_catalog_is_not_used_for_online_generation():
    agent = RecipeAgent(api_key="")
    try:
        agent.chat("How do I make Maggi?", [], [])
    except AgentError:
        pass
    else:
        raise AssertionError("Offline catalog must not be used")


def test_bounded_tool_loop_uses_local_validation():
    responses = [{
        "candidates": [{
            "content": {
                "parts": [{
                    "functionCall": {
                        "name": "generate_recipe",
                        "args": {
                            "dish_name": "Veg Pulao",
                            "cuisine": "Indian",
                            "description": "A simple rice dish.",
                            "servings": "2",
                            "preparation_time": "10 minutes",
                            "cooking_time": "25 minutes",
                            "required_ingredients": [
                                {"name": "rice", "quantity": "1 cup"}
                            ],
                            "optional_ingredients": [],
                            "preparation": ["Wash rice."],
                            "cooking": ["Cook rice."],
                            "serving_suggestions": ["Serve hot."],
                            "substitutions": ["Use quinoa instead of rice."],
                            "tips": ["Fluff before serving."],
                        },
                    }
                }]
            }
        }]
    }]

    def requester(*_args, **_kwargs):
        response = responses.pop(0)

        class FakeResponse:
            status_code = 200

            def json(self):
                return response

        return FakeResponse()

    result = RecipeAgent(api_key="test-key", requester=requester).chat(
        "How do I make Veg Pulao?",
        [pantry("Rice", "1 kg")],
        [],
    )
    assert result["status"] == "ok"
    assert result["dish_name"] == "Veg Pulao"
    assert result["cuisine"] == "Indian"
    assert result["available_pantry_ingredients"][0]["products"][0]["name"] == "Rice"
    assert result["serving_suggestions"] == ["Serve hot."]


def test_unfamiliar_open_domain_recipe_uses_one_generation_request():
    response = {
        "candidates": [{
            "content": {"parts": [{
                "functionCall": {
                    "name": "generate_recipe",
                    "args": {
                        "dish_name": "Khao Soi",
                        "cuisine": "Thai",
                        "description": "Northern Thai curry noodles.",
                        "servings": "2",
                        "preparation_time": "15 minutes",
                        "cooking_time": "25 minutes",
                        "required_ingredients": [
                            {"name": "egg noodles", "quantity": "200 g"}
                        ],
                        "optional_ingredients": [],
                        "preparation": ["Prepare the noodles."],
                        "cooking": ["Simmer the curry and add noodles."],
                        "serving_suggestions": ["Serve with lime."],
                        "substitutions": ["Use rice noodles if needed."],
                        "tips": ["Adjust chili to taste."],
                    },
                }
            }]},
        }]
    }
    calls = []

    def requester(*args, **kwargs):
        calls.append((args, kwargs))

        class FakeResponse:
            status_code = 200

            def json(self):
                return response

        return FakeResponse()

    result = RecipeAgent(api_key="test-key", requester=requester).chat(
        "How do I make Khao Soi?", [], [], request_id="open-domain"
    )
    assert result["dish_name"] == "Khao Soi"
    assert result["cuisine"] == "Thai"
    assert len(calls) == 1
    assert calls[0][1]["headers"]["X-Request-ID"] == "open-domain"


def test_transient_503_retries_then_succeeds_without_retrying_permanent_errors():
    response = {
        "candidates": [{
            "content": {"parts": [{
                "functionCall": {
                    "name": "generate_recipe",
                    "args": {
                        "dish_name": "Tea",
                        "cuisine": "Indian",
                        "description": "Spiced tea.",
                        "servings": "1",
                        "preparation_time": "1 minute",
                        "cooking_time": "5 minutes",
                        "required_ingredients": [
                            {"name": "tea", "quantity": "1 tsp"}
                        ],
                        "optional_ingredients": [],
                        "preparation": ["Boil water."],
                        "cooking": ["Steep tea."],
                        "serving_suggestions": ["Serve hot."],
                        "substitutions": [],
                        "tips": ["Adjust sweetness."],
                    },
                }
            }]},
        }]
    }
    statuses = [503, 200]

    def requester(*args, **kwargs):
        status = statuses.pop(0)

        class FakeResponse:
            status_code = status
            text = "temporary"

            def json(self):
                return response if status == 200 else {"error": {"status": "UNAVAILABLE"}}

        return FakeResponse()

    agent = RecipeAgent(
        api_key="test-key",
        requester=requester,
        sleeper=lambda _: None,
        randomizer=lambda: 0,
    )
    assert agent.chat("How do I make tea?", [], [])["status"] == "ok"
    assert statuses == []

    def permanent_requester(*args, **kwargs):
        class FakeResponse:
            status_code = 401
            text = "unauthorized"

            def json(self):
                return {"error": {"status": "UNAUTHENTICATED"}}

        return FakeResponse()

    permanent = RecipeAgent(
        api_key="test-key",
        requester=permanent_requester,
        sleeper=lambda _: None,
    )
    try:
        permanent.chat("How do I make tea?", [], [])
    except AgentError as error:
        assert "HTTP 401" in str(error)
    else:
        raise AssertionError("Permanent authentication errors must not retry")


def test_missing_quantity_is_rejected_without_inventing_a_value():
    recipe = {
        "dish_name": "Ratatouille",
        "cuisine": "French",
        "description": "A vegetable stew.",
        "servings": "2",
        "preparation_time": "15 minutes",
        "cooking_time": "30 minutes",
        "required_ingredients": [{"name": "eggplant"}],
        "optional_ingredients": [],
        "preparation": ["Chop vegetables."],
        "cooking": ["Simmer vegetables."],
        "serving_suggestions": ["Serve warm."],
        "substitutions": [],
        "tips": ["Use seasonal vegetables."],
    }
    try:
        RecipeAgent._validate_recipe(recipe)
    except ValueError as error:
        assert "quantity" in str(error)
    else:
        raise AssertionError("Missing quantities must be rejected")


def test_flask_propagates_request_ids_and_preserves_modes():
    class BlockingAgent:
        api_key = "configured"
        model = "test-model"

        def __init__(self):
            self.started = False
            self.modes = []

        def chat(self, message, pantry, context, pantry_cooking=False, request_id=None):
            self.started = True
            self.modes.append((pantry_cooking, request_id))
            return {"status": "ok", "mode": "pantry" if pantry_cooking else "normal"}

    agent = BlockingAgent()
    client = create_app(agent).test_client()
    headers = {"X-Request-ID": "same-request"}
    first = client.post("/chat", json={"message": "tea", "pantry": []}, headers=headers)
    second = client.post("/pantry-cook", json={"message": "tea", "pantry": []}, headers=headers)
    assert first.status_code == 200
    assert second.status_code == 200
    assert agent.started
    assert agent.modes == [(False, "same-request"), (True, "same-request")]


def test_groq_free_tier_is_used_when_every_gemini_model_fails(monkeypatch):
    monkeypatch.setenv("GROQ_API_KEY", "groq-test-key")
    recipe = {
        "dish_name": "Tomato Rice",
        "cuisine": "Indian",
        "description": "Rice cooked with tomatoes.",
        "servings": 2,
        "preparation_time": "10 minutes",
        "cooking_time": "20 minutes",
        "required_ingredients": [{"name": "rice", "quantity": 1}],
        "optional_ingredients": [],
        "preparation": ["Wash rice."],
        "cooking": [{"step": "Cook with tomatoes."}],
        "serving_suggestions": ["Serve hot."],
        "substitutions": [],
        "tips": ["Use ripe tomatoes."],
    }
    urls = []

    def requester(url, **kwargs):
        urls.append(url)

        class FakeResponse:
            status_code = 503 if "googleapis" in url else 200
            text = ""

            def json(self):
                if "googleapis" in url:
                    return {"error": {"status": "UNAVAILABLE"}}
                return {"choices": [{"message": {"content": json.dumps(recipe)}}]}

        return FakeResponse()

    agent = RecipeAgent(
        api_key="test-key",
        requester=requester,
        sleeper=lambda _: None,
        randomizer=lambda: 0,
    )
    result = agent.chat("tomato rice", [], [])
    assert result["status"] == "ok"
    assert result["servings"] == "2"
    assert result["cooking"] == ["Cook with tomatoes."]
    assert "groq.com" in urls[-1]


def test_app_token_protects_chat_but_not_health(monkeypatch):
    monkeypatch.setenv("RECIPE_AGENT_TOKEN", "secret")

    class StubAgent:
        provider_models = []

        def chat(self, *args, **kwargs):
            return {"status": "ok"}

    client = create_app(StubAgent()).test_client()
    body = {"message": "tea", "pantry": [], "context": []}
    assert client.get("/health").status_code == 200
    assert client.post("/chat", json=body, headers={"X-Request-ID": "a"}).status_code == 401
    assert client.post(
        "/chat", json=body, headers={"X-Request-ID": "b", "X-App-Token": "wrong"}
    ).status_code == 401
    assert client.post(
        "/chat", json=body, headers={"X-Request-ID": "c", "X-App-Token": "secret"}
    ).status_code == 200


def test_identify_product_reads_brand_and_name_from_gemini_vision():
    from io import BytesIO

    from recipe_agent.vision import ProductIdentifier

    calls = []

    def requester(url, **kwargs):
        calls.append(url)

        class FakeResponse:
            status_code = 503 if len(calls) == 1 else 200

            def json(self):
                return {"candidates": [{"content": {"parts": [{"text": json.dumps({
                    "brand": "Britannia",
                    "product_name": "Marie Gold",
                    "category": "snacks",
                })}]}}]}

        return FakeResponse()

    class StubAgent:
        provider_models = []

    identifier = ProductIdentifier(api_key="test-key", requester=requester)
    client = create_app(StubAgent(), identifier).test_client()
    response = client.post(
        "/identify-product",
        data={"image": (BytesIO(b"\xff\xd8fake-jpeg"), "front.jpg", "image/jpeg")},
        content_type="multipart/form-data",
    )
    assert response.status_code == 200
    assert response.get_json() == {
        "status": "ok",
        "brand": "Britannia",
        "product_name": "Marie Gold",
        "category": "Snacks",
    }
    # The overloaded first model hands over to the next one.
    assert len(calls) == 2
    assert client.post("/identify-product").status_code == 400
