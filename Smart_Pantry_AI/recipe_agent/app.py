from __future__ import annotations

import hmac
import os
import logging
import threading
from pathlib import Path

from flask import Flask, jsonify, request
from dotenv import load_dotenv

from .agent import AgentError, RecipeAgent
from .models import validate_request_body
from .vision import MAX_IMAGE_BYTES, ProductIdentifier, VisionError

_recipe_agent_dir = Path(__file__).parent
_project_env = _recipe_agent_dir.parent / ".env"
_agent_env = _recipe_agent_dir / ".env"
load_dotenv(_project_env)
load_dotenv(_agent_env, override=True)
logging.basicConfig(
    level=os.environ.get("RECIPE_AGENT_LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)


def create_app(
    agent: object | None = None,
    identifier: ProductIdentifier | None = None,
) -> Flask:
    app = Flask(__name__)
    recipe_manager = agent or RecipeAgent()
    product_identifier = identifier or ProductIdentifier()
    active_request_ids: set[str] = set()
    request_ids_lock = threading.Lock()

    def request_id() -> str:
        value = request.headers.get("X-Request-ID", "").strip()
        if not value or len(value) > 120:
            raise ValueError("X-Request-ID is required and must be at most 120 characters")
        return value

    def run_agent(pantry_cooking: bool):
        body = validate_request_body(request.get_json(silent=True))
        current_request_id = request_id()
        with request_ids_lock:
            if current_request_id in active_request_ids:
                return jsonify({
                    "status": "duplicate",
                    "message": "A request with this ID is already in progress.",
                }), 409
            active_request_ids.add(current_request_id)
        try:
            if hasattr(recipe_manager, "generate"):
                result = recipe_manager.generate(
                    body["message"],
                    body["pantry"],
                    body["context"],
                    pantry_cooking=pantry_cooking,
                    request_id=current_request_id,
                )
            else:
                result = recipe_manager.chat(
                    body["message"],
                    body["pantry"],
                    body["context"],
                    pantry_cooking=pantry_cooking,
                    request_id=current_request_id,
                )
            return jsonify(result)
        finally:
            with request_ids_lock:
                active_request_ids.discard(current_request_id)

    @app.before_request
    def require_app_token():
        # Hosted deployments set RECIPE_AGENT_TOKEN so strangers cannot spend the
        # free-tier API quota. Unset (local dev) leaves the API open.
        expected = os.environ.get("RECIPE_AGENT_TOKEN", "").strip()
        if not expected or request.path == "/health":
            return None
        supplied = request.headers.get("X-App-Token", "")
        if not hmac.compare_digest(supplied.encode(), expected.encode()):
            return jsonify({"status": "error", "message": "Unauthorized."}), 401
        return None

    @app.get("/health")
    def health():
        provider_models = getattr(recipe_manager, "provider_models", [])
        return jsonify(
            {
                "status": "ok",
                "service": "recipe_agent",
                "providers_configured": bool(provider_models),
                "providers": provider_models,
                "gemini_configured": any(
                    provider["name"] == "gemini"
                    for provider in provider_models
                ),
                "model": getattr(recipe_manager, "model", ""),
                "port": int(os.environ.get("RECIPE_AGENT_PORT", "8001")),
            }
        )

    @app.post("/chat")
    def chat():
        try:
            return run_agent(False)
        except AgentError as error:
            return jsonify(
                {
                    "status": "error",
                    "message": "Recipe providers are temporarily unavailable.",
                    "category": getattr(error, "category", "provider_error"),
                }
            ), 503
        except ValueError as error:
            return jsonify({"status": "error", "message": str(error)}), 400

    @app.post("/identify-product")
    def identify_product():
        upload = request.files.get("image")
        if upload is None:
            return jsonify({"status": "error", "message": "Provide an 'image' file."}), 400
        image = upload.read(MAX_IMAGE_BYTES + 1)
        if not image:
            return jsonify({"status": "error", "message": "The image is empty."}), 400
        if len(image) > MAX_IMAGE_BYTES:
            return jsonify({"status": "error", "message": "The image must be 5 MB or smaller."}), 413
        mime_type = upload.mimetype if (upload.mimetype or "").startswith("image/") else "image/jpeg"
        try:
            result = product_identifier.identify(image, mime_type)
        except VisionError as error:
            logging.getLogger(__name__).warning("%s", error)
            return jsonify({
                "status": "error",
                "message": "Product identification is temporarily unavailable.",
            }), 503
        return jsonify({"status": "ok", **result})

    @app.post("/pantry-cook")
    def pantry_cook():
        try:
            return run_agent(True)
        except AgentError as error:
            return jsonify(
                {
                    "status": "error",
                    "message": "Recipe providers are temporarily unavailable.",
                    "category": getattr(error, "category", "provider_error"),
                }
            ), 503
        except ValueError as error:
            return jsonify({"status": "error", "message": str(error)}), 400

    return app


app = create_app()

if __name__ == "__main__":
    app.run(
        host=os.environ.get("RECIPE_AGENT_HOST", "127.0.0.1"),
        port=int(os.environ.get("RECIPE_AGENT_PORT", "8001")),
        debug=False,
    )
