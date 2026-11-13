from __future__ import annotations

import argparse
import time
from pathlib import Path
from typing import Any

from dotenv import load_dotenv

from .providers import ProviderFailure, configured_adapters


class _CaptureResponse:
    def __init__(self, response: Any, capture: dict[str, Any]) -> None:
        self._response = response
        self.status_code = response.status_code
        self.headers = response.headers
        self.content = response.content
        capture["status"] = response.status_code
        capture["size"] = len(response.content)

    def json(self):
        return self._response.json()


def main() -> None:
    project_env = Path(__file__).parent.parent / ".env"
    load_dotenv(project_env)
    load_dotenv(Path(__file__).parent / ".env", override=True)
    parser = argparse.ArgumentParser(description="Manual provider smoke test; never run automatically.")
    parser.add_argument(
        "--include-gemini",
        action="store_true",
        help="Include Gemini; it is skipped by default.",
    )
    args = parser.parse_args()
    adapters = configured_adapters()
    if not args.include_gemini:
        adapters = [adapter for adapter in adapters if adapter.config.name != "gemini"]
    prompts = (
        ("minimal", "Return a tiny tea recipe as the required JSON recipe object."),
        ("tomato-rice", "Return a realistic tomato-rice recipe for two servings as the required JSON recipe object."),
    )
    for adapter in adapters:
        for label, prompt in prompts:
            capture: dict[str, Any] = {"status": None, "size": 0}
            original = adapter.requester

            def requester(*request_args, **request_kwargs):
                return _CaptureResponse(original(*request_args, **request_kwargs), capture)

            adapter.requester = requester
            started = time.perf_counter()
            try:
                adapter.generate(prompt, timeout=(
                    adapter.config.connect_timeout,
                    adapter.config.read_timeout,
                ), request_id=f"smoke-{adapter.config.name}-{label}")
                category = "success"
            except ProviderFailure as error:
                category = error.category
            finally:
                adapter.requester = original
            latency_ms = round((time.perf_counter() - started) * 1000)
            print(
                f"provider={adapter.config.name} model={adapter.config.model} "
                f"http_status={capture['status']} latency_ms={latency_ms} "
                f"response_size_bytes={capture['size']} failure_category={category}"
            )
            if category == "daily_quota_exhausted":
                break


if __name__ == "__main__":
    main()
