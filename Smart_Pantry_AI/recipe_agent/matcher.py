from __future__ import annotations

import re
from datetime import date
from typing import Any

from .models import PantryItem

ALIASES = {
    "tomatoes": "tomato",
    "onions": "onion",
    "noodles": "noodle",
    "cilantro": "coriander",
    "jeera": "cumin",
    "haldi": "turmeric",
    "atta": "wheat",
}
KITCHEN_UTILITIES = {"water", "salt"}


def tokens(value: str) -> list[str]:
    return [
        token
        for token in re.sub(r"[^a-z0-9]+", " ", value.lower()).split()
        if token
    ]


def canonical(value: str) -> list[str]:
    return [ALIASES.get(token, token) for token in tokens(value)]


def parse_date(value: str) -> date | None:
    match = re.fullmatch(r"(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})", value.strip())
    if not match:
        return None
    day, month, year = (int(part) for part in match.groups())
    if year < 100:
        year += 2000
    try:
        return date(year, month, day)
    except ValueError:
        return None


def is_usable(item: PantryItem, today: date | None = None) -> bool:
    if item.status.strip().lower() == "finished":
        return False
    quantity = item.quantity.strip().lower()
    if re.fullmatch(r"0+(?:[.,]0+)?\s*[a-z]*", quantity):
        return False
    expiry = parse_date(item.exp)
    return expiry is None or expiry >= (today or date.today())


def match_recipe_ingredients(
    ingredients: list[dict[str, Any]],
    pantry: list[PantryItem],
    today: date | None = None,
) -> dict[str, Any]:
    available = []
    missing = []
    optional_missing = []
    for ingredient in ingredients:
        if not isinstance(ingredient, dict):
            continue
        name = str(ingredient.get("name", "")).strip()
        aliases = ingredient.get("aliases", [])
        names = [name] + [str(value) for value in aliases if str(value).strip()]
        wanted = {tuple(canonical(value)) for value in names}
        matches = [
            item
            for item in pantry
            if is_usable(item, today) and tuple(canonical(item.name)) in wanted
        ]
        result = {
            "name": name,
            "quantity": str(ingredient.get("quantity", "")),
            "optional": bool(ingredient.get("optional", False)),
            "products": [
                {
                    "id": item.id,
                    "name": item.name,
                    "quantity": item.quantity,
                    "exp": item.exp,
                }
                for item in matches
            ],
        }
        if tuple(canonical(name)) in {(utility,) for utility in KITCHEN_UTILITIES}:
            continue
        if matches:
            available.append(result)
        elif result["optional"]:
            optional_missing.append(result)
        else:
            missing.append(result)
    return {
        "available": available,
        "missing": missing,
        "optional_missing": optional_missing,
    }


def expiry_status(pantry: list[PantryItem], today: date | None = None) -> dict[str, Any]:
    reference = today or date.today()
    expired = []
    soon = []
    unknown = []
    for item in pantry:
        if item.status.strip().lower() == "finished":
            continue
        expiry = parse_date(item.exp)
        if expiry is None:
            unknown.append(item.id)
        elif expiry < reference:
            expired.append(item.id)
        elif (expiry - reference).days <= 7:
            soon.append({**item.__dict__, "days": (expiry - reference).days})
    return {"expired": expired, "soon": soon, "unknown": unknown}
