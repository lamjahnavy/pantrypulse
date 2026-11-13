from __future__ import annotations

from typing import Any


RECIPES = {
    "maggi": {
        "dish_name": "Maggi",
        "description": "Quick masala noodles.",
        "flavor_profile": "Savory, mildly spicy masala with a comforting noodle texture.",
        "servings": "1",
        "preparation_time": "5 minutes",
        "cooking_time": "5 minutes",
        "required_ingredients": [
            {"name": "Maggi noodles", "quantity": "1 packet", "aliases": ["maggi noodle", "instant noodles"]},
            {"name": "water", "quantity": "1.5 cups"},
            {"name": "tastemaker", "quantity": "1 sachet"},
        ],
        "optional_ingredients": [
            {"name": "onion", "quantity": "1/2", "aliases": ["onions"]},
            {"name": "oil", "quantity": "1 tsp"},
        ],
        "preparation": ["Chop the onion if using it."],
        "cooking": ["Boil water, add noodles and tastemaker, then cook for 2–3 minutes."],
        "tips": ["Add only suitable vegetables that are actually available."],
    },
    "chicken curry": {
        "dish_name": "Chicken Curry",
        "description": "A practical onion and tomato chicken curry.",
        "flavor_profile": "Warm, savory, and gently spiced with a rich tomato-onion base.",
        "servings": "2–3",
        "preparation_time": "15 minutes",
        "cooking_time": "30 minutes",
        "required_ingredients": [
            {"name": "chicken", "quantity": "250 g"},
            {"name": "onion", "quantity": "1", "aliases": ["onions"]},
            {"name": "tomato", "quantity": "2", "aliases": ["tomatoes"]},
            {"name": "oil", "quantity": "2 tbsp"},
            {"name": "salt", "quantity": "to taste"},
        ],
        "optional_ingredients": [{"name": "turmeric", "quantity": "1/2 tsp", "aliases": ["haldi"]}],
        "preparation": ["Cut the chicken and chop the onion and tomatoes."],
        "cooking": ["Saute onion, add tomatoes and spices, then simmer chicken until tender."],
        "tips": ["Do not use expired products."],
    },
    "veg pulao": {
        "dish_name": "Veg Pulao",
        "description": "A simple vegetable rice pulao.",
        "flavor_profile": "Fragrant, savory rice with a light vegetable sweetness.",
        "servings": "2",
        "preparation_time": "10 minutes",
        "cooking_time": "25 minutes",
        "required_ingredients": [
            {"name": "rice", "quantity": "1 cup"},
            {"name": "water", "quantity": "2 cups"},
            {"name": "salt", "quantity": "to taste"},
        ],
        "optional_ingredients": [
            {"name": "mixed vegetables", "quantity": "1 cup", "aliases": ["vegetables"]},
            {"name": "onion", "quantity": "1", "aliases": ["onions"]},
            {"name": "oil", "quantity": "1 tbsp"},
        ],
        "preparation": ["Wash the rice and chop the vegetables if using them."],
        "cooking": ["Saute the onion and vegetables, add rice and water, then cook until tender."],
        "tips": ["Use only pantry products that are available and not expired."],
    },
    "veg briyani": {
        "dish_name": "Veg Briyani",
        "description": "A fragrant vegetable rice dish with warm spices.",
        "flavor_profile": "Aromatic, savory, and gently spiced with layered vegetable flavors.",
        "servings": "2",
        "preparation_time": "15 minutes",
        "cooking_time": "30 minutes",
        "required_ingredients": [
            {"name": "rice", "quantity": "1 cup"},
            {"name": "water", "quantity": "2 cups"},
            {"name": "salt", "quantity": "to taste"},
        ],
        "optional_ingredients": [
            {"name": "mixed vegetables", "quantity": "1 cup", "aliases": ["vegetables"]},
            {"name": "onion", "quantity": "1", "aliases": ["onions"]},
            {"name": "oil", "quantity": "2 tbsp"},
            {"name": "biryani masala", "quantity": "1 tbsp"},
        ],
        "preparation": ["Wash the rice and chop the vegetables and onion."],
        "cooking": [
            "Saute onion and vegetables with the masala.",
            "Add rice and water, cover, and cook until the rice is tender.",
            "Rest for five minutes, fluff gently, and serve.",
        ],
        "tips": ["Use only available, non-expired pantry products."],
    },
    "rice": {
        "dish_name": "Rice",
        "description": "Simple steamed rice.",
        "flavor_profile": "Mild, clean, and neutral, suited to pair with other dishes.",
        "servings": "2",
        "preparation_time": "5 minutes",
        "cooking_time": "20 minutes",
        "required_ingredients": [
            {"name": "rice", "quantity": "1 cup"},
            {"name": "water", "quantity": "2 cups"},
        ],
        "optional_ingredients": [
            {"name": "salt", "quantity": "to taste"},
        ],
        "preparation": ["Wash the rice until the water runs mostly clear."],
        "cooking": ["Add rice and water to a pot, cover, and cook until tender."],
        "tips": ["Let the rice rest for five minutes before serving."],
    },
}


def find_recipe(message: str) -> dict[str, Any] | None:
    normalized = message.lower()
    for key, recipe in RECIPES.items():
        if key in normalized:
            return recipe
    return None


def recipe_ingredients(recipe: dict[str, Any]) -> list[dict[str, Any]]:
    return recipe["required_ingredients"] + [
        {**item, "optional": True}
        for item in recipe.get("optional_ingredients", [])
    ]


def unsupported(message: str) -> dict[str, Any]:
    return {
        "status": "unsupported",
        "message": f'Gemini is unavailable and "{message}" is not in the offline recipe catalog.',
    }
