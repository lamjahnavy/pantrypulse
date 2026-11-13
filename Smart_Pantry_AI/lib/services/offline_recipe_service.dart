import 'recipe_models.dart';

class OfflineRecipeService {
  static const List<OfflineRecipe> recipes = [
    OfflineRecipe(
      name: 'Maggi',
      ingredients: [
        RecipeIngredient(
          name: 'Maggi noodles',
          quantity: '1 packet',
          aliases: ['maggi noodle', 'instant noodles'],
        ),
        RecipeIngredient(name: 'water', quantity: '1.5 cups'),
        RecipeIngredient(name: 'tastemaker', quantity: '1 sachet'),
        RecipeIngredient(
          name: 'onion',
          quantity: '1/2',
          optional: true,
          aliases: ['onions'],
        ),
        RecipeIngredient(name: 'oil', quantity: '1 tsp', optional: true),
      ],
      preparation: ['Chop the onion if using it.'],
      cookingMethod: [
        'Boil water in a pan.',
        'Add noodles and tastemaker.',
        'Add onion and oil if using them.',
        'Cook for 2–3 minutes and serve hot.',
      ],
      preparationTime: '5 minutes',
      cookingTime: '5 minutes',
      servings: '1',
      tips: ['Add vegetables only when they are available and suitable.'],
    ),
    OfflineRecipe(
      name: 'Chicken Curry',
      ingredients: [
        RecipeIngredient(name: 'chicken', quantity: '250 g'),
        RecipeIngredient(name: 'onion', quantity: '1', aliases: ['onions']),
        RecipeIngredient(name: 'tomato', quantity: '2', aliases: ['tomatoes']),
        RecipeIngredient(name: 'oil', quantity: '2 tbsp'),
        RecipeIngredient(
          name: 'ginger garlic paste',
          quantity: '1 tsp',
          aliases: ['ginger garlic'],
        ),
        RecipeIngredient(
            name: 'turmeric', quantity: '1/2 tsp', aliases: ['haldi']),
        RecipeIngredient(name: 'salt', quantity: 'to taste'),
      ],
      preparation: ['Cut the chicken and chop the onion and tomatoes.'],
      cookingMethod: [
        'Heat oil and saute the onion.',
        'Add ginger garlic paste, turmeric, and tomatoes.',
        'Add chicken and salt.',
        'Add water, cover, and simmer until tender.',
      ],
      preparationTime: '15 minutes',
      cookingTime: '30 minutes',
      servings: '2–3',
    ),
    OfflineRecipe(
      name: 'Veg Pulao',
      ingredients: [
        RecipeIngredient(name: 'rice', quantity: '1 cup'),
        RecipeIngredient(name: 'water', quantity: '2 cups'),
        RecipeIngredient(name: 'salt', quantity: 'to taste'),
        RecipeIngredient(
          name: 'mixed vegetables',
          quantity: '1 cup',
          optional: true,
          aliases: ['vegetables'],
        ),
        RecipeIngredient(
          name: 'onion',
          quantity: '1',
          optional: true,
          aliases: ['onions'],
        ),
        RecipeIngredient(name: 'oil', quantity: '1 tbsp', optional: true),
      ],
      preparation: ['Wash the rice and chop the vegetables if using them.'],
      cookingMethod: [
        'Saute the onion and vegetables if available. Add rice and water.',
        'Cover and cook until the rice is tender.',
      ],
      preparationTime: '10 minutes',
      cookingTime: '25 minutes',
      servings: '2',
      tips: ['Use only pantry products that are available and not expired.'],
    ),
    OfflineRecipe(
      name: 'Veg Briyani',
      ingredients: [
        RecipeIngredient(name: 'rice', quantity: '1 cup'),
        RecipeIngredient(name: 'water', quantity: '2 cups'),
        RecipeIngredient(name: 'salt', quantity: 'to taste'),
        RecipeIngredient(
          name: 'mixed vegetables',
          quantity: '1 cup',
          optional: true,
          aliases: ['vegetables'],
        ),
        RecipeIngredient(
          name: 'onion',
          quantity: '1',
          optional: true,
          aliases: ['onions'],
        ),
        RecipeIngredient(
          name: 'oil',
          quantity: '2 tbsp',
          optional: true,
        ),
        RecipeIngredient(
          name: 'biryani masala',
          quantity: '1 tbsp',
          optional: true,
        ),
      ],
      preparation: ['Wash the rice and chop the vegetables and onion.'],
      cookingMethod: [
        'Saute onion and vegetables with the masala.',
        'Add rice and water, cover, and cook until tender.',
        'Rest for five minutes, fluff gently, and serve.',
      ],
      preparationTime: '15 minutes',
      cookingTime: '30 minutes',
      servings: '2',
      tips: ['Use only available, non-expired pantry products.'],
    ),
    OfflineRecipe(
      name: 'Rice',
      ingredients: [
        RecipeIngredient(name: 'rice', quantity: '1 cup'),
        RecipeIngredient(name: 'water', quantity: '2 cups'),
        RecipeIngredient(name: 'salt', quantity: 'to taste', optional: true),
      ],
      preparation: ['Wash the rice until the water runs mostly clear.'],
      cookingMethod: [
        'Add rice and water to a pot.',
        'Cover and cook until tender, then let it rest for five minutes.',
      ],
      preparationTime: '5 minutes',
      cookingTime: '20 minutes',
      servings: '2',
    ),
    OfflineRecipe(
      name: 'Chicken Biryani',
      ingredients: [
        RecipeIngredient(name: 'chicken', quantity: '250 g'),
        RecipeIngredient(name: 'rice', quantity: '1 cup'),
        RecipeIngredient(name: 'onion', quantity: '1', aliases: ['onions']),
        RecipeIngredient(name: 'tomato', quantity: '1', aliases: ['tomatoes']),
        RecipeIngredient(name: 'oil', quantity: '2 tbsp'),
        RecipeIngredient(name: 'biryani masala', quantity: '1 tbsp'),
        RecipeIngredient(name: 'salt', quantity: 'to taste'),
      ],
      preparation: ['Wash the rice and cut the chicken into pieces.'],
      cookingMethod: [
        'Cook onion and tomato in oil.',
        'Add chicken, masala, and salt.',
        'Add rice and water.',
        'Cover and cook until the rice and chicken are done.',
      ],
      preparationTime: '20 minutes',
      cookingTime: '40 minutes',
      servings: '3',
    ),
    OfflineRecipe(
      name: 'Fried Rice',
      ingredients: [
        RecipeIngredient(name: 'rice', quantity: '2 cups cooked'),
        RecipeIngredient(name: 'onion', quantity: '1', aliases: ['onions']),
        RecipeIngredient(name: 'oil', quantity: '1 tbsp'),
        RecipeIngredient(name: 'salt', quantity: 'to taste'),
        RecipeIngredient(name: 'vegetables', quantity: '1 cup', optional: true),
      ],
      preparation: [
        'Prepare cooked rice and chop the vegetables if using them.'
      ],
      cookingMethod: [
        'Heat oil and saute onion.',
        'Add vegetables if available.',
        'Toss in rice and salt over high heat.',
        'Serve immediately.',
      ],
      preparationTime: '10 minutes',
      cookingTime: '10 minutes',
      servings: '2',
    ),
    OfflineRecipe(
      name: 'Dal',
      ingredients: [
        RecipeIngredient(name: 'lentil', quantity: '1 cup', aliases: ['dal']),
        RecipeIngredient(name: 'onion', quantity: '1', aliases: ['onions']),
        RecipeIngredient(name: 'tomato', quantity: '1', aliases: ['tomatoes']),
        RecipeIngredient(
            name: 'turmeric', quantity: '1/2 tsp', aliases: ['haldi']),
        RecipeIngredient(name: 'salt', quantity: 'to taste'),
      ],
      preparation: ['Wash the lentils and chop the onion and tomato.'],
      cookingMethod: [
        'Cook lentils with turmeric until soft.',
        'Prepare a sauteed onion and tomato tempering.',
        'Mix the tempering into the dal and add salt.',
      ],
      preparationTime: '10 minutes',
      cookingTime: '25 minutes',
      servings: '3',
    ),
    OfflineRecipe(
      name: 'Paneer Curry',
      ingredients: [
        RecipeIngredient(name: 'paneer', quantity: '250 g'),
        RecipeIngredient(name: 'onion', quantity: '1', aliases: ['onions']),
        RecipeIngredient(name: 'tomato', quantity: '2', aliases: ['tomatoes']),
        RecipeIngredient(name: 'oil', quantity: '2 tbsp'),
        RecipeIngredient(name: 'salt', quantity: 'to taste'),
      ],
      preparation: ['Cut paneer and chop the onion and tomatoes.'],
      cookingMethod: [
        'Saute onion and tomatoes in oil.',
        'Blend or mash into a sauce.',
        'Add paneer and salt, then simmer briefly.',
      ],
      preparationTime: '15 minutes',
      cookingTime: '20 minutes',
      servings: '2–3',
    ),
    OfflineRecipe(
      name: 'Pasta',
      ingredients: [
        RecipeIngredient(name: 'pasta', quantity: '200 g'),
        RecipeIngredient(name: 'tomato', quantity: '2', aliases: ['tomatoes']),
        RecipeIngredient(name: 'onion', quantity: '1', aliases: ['onions']),
        RecipeIngredient(name: 'oil', quantity: '1 tbsp'),
        RecipeIngredient(name: 'salt', quantity: 'to taste'),
      ],
      preparation: ['Chop the onion and tomatoes.'],
      cookingMethod: [
        'Boil pasta until tender.',
        'Cook onion and tomatoes in oil.',
        'Toss pasta with the sauce and salt.',
      ],
      preparationTime: '10 minutes',
      cookingTime: '20 minutes',
      servings: '2',
    ),
    OfflineRecipe(
      name: 'Omelette',
      ingredients: [
        RecipeIngredient(name: 'egg', quantity: '2', aliases: ['eggs']),
        RecipeIngredient(name: 'onion', quantity: '1/2', optional: true),
        RecipeIngredient(name: 'salt', quantity: 'to taste'),
        RecipeIngredient(name: 'oil', quantity: '1 tsp'),
      ],
      preparation: ['Beat the eggs with salt and chop onion if using.'],
      cookingMethod: [
        'Heat oil in a pan.',
        'Pour in the eggs and add onion.',
        'Cook both sides until set.',
      ],
      preparationTime: '5 minutes',
      cookingTime: '5 minutes',
      servings: '1',
    ),
    OfflineRecipe(
      name: 'Sandwich',
      ingredients: [
        RecipeIngredient(name: 'bread', quantity: '4 slices'),
        RecipeIngredient(name: 'onion', quantity: '1/2', optional: true),
        RecipeIngredient(name: 'tomato', quantity: '1', optional: true),
        RecipeIngredient(name: 'butter', quantity: '1 tbsp'),
        RecipeIngredient(name: 'salt', quantity: 'to taste'),
      ],
      preparation: ['Slice the vegetables if using them.'],
      cookingMethod: [
        'Butter the bread.',
        'Layer the vegetables and salt.',
        'Toast or serve fresh.',
      ],
      preparationTime: '5 minutes',
      cookingTime: '5 minutes',
      servings: '2',
    ),
  ];

  static OfflineRecipe? find(String request) {
    final normalized = request.toLowerCase();
    for (final recipe in recipes) {
      if (normalized.contains(recipe.name.toLowerCase())) {
        return recipe;
      }
    }
    return null;
  }
}
