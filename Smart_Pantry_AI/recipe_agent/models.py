from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class PantryItem:
    id: str
    name: str
    quantity: str
    exp: str
    status: str
    brand: str = ""
    category: str = ""

    @classmethod
    def from_dict(cls, value: Any) -> "PantryItem":
        if not isinstance(value, dict):
            raise ValueError("pantry item must be an object")
        name = str(value.get("name", "")).strip()
        if not name or len(name) > 160:
            raise ValueError("pantry item name is required and must be short")
        return cls(
            id=str(value.get("id", name))[:120],
            name=name,
            quantity=str(value.get("quantity", "Not detected"))[:80],
            exp=str(value.get("exp", "Not detected"))[:40],
            status=str(value.get("status", "Not Used"))[:40],
            brand=str(value.get("brand", ""))[:100],
            category=str(value.get("category", ""))[:100],
        )


def validate_request_body(body: Any) -> dict[str, Any]:
    if not isinstance(body, dict):
        raise ValueError("request body must be an object")
    message = str(body.get("message", "")).strip()
    if not message or len(message) > 4000:
        raise ValueError("message is required and must be at most 4000 characters")
    pantry_raw = body.get("pantry", [])
    if not isinstance(pantry_raw, list) or len(pantry_raw) > 500:
        raise ValueError("pantry must be a list of at most 500 items")
    pantry = [PantryItem.from_dict(item) for item in pantry_raw]
    context = body.get("context", [])
    if not isinstance(context, list) or len(context) > 20:
        raise ValueError("context must be a list of at most 20 messages")
    safe_context = []
    for item in context:
        if not isinstance(item, dict):
            raise ValueError("context messages must be objects")
        role = str(item.get("role", "user"))
        content = str(item.get("content", ""))
        if role not in {"user", "assistant"} or len(content) > 4000:
            raise ValueError("invalid context message")
        safe_context.append({"role": role, "content": content})
    return {
        "message": message,
        "pantry": pantry,
        "context": safe_context,
    }


def pantry_to_dict(item: PantryItem) -> dict[str, str]:
    return {
        "id": item.id,
        "name": item.name,
        "quantity": item.quantity,
        "exp": item.exp,
        "status": item.status,
        "brand": item.brand,
        "category": item.category,
    }
