import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pantry_ai/product_model.dart';
import 'package:smart_pantry_ai/recipe_agent_client.dart';
import 'package:smart_pantry_ai/recipe_service.dart';
import 'package:smart_pantry_ai/screens.dart';
import 'package:smart_pantry_ai/services/ingredient_matcher.dart';
import 'package:smart_pantry_ai/services/offline_recipe_service.dart';
import 'package:smart_pantry_ai/services/recipe_models.dart';

Product product(
  String name, {
  String quantity = '1',
  String exp = 'Not detected',
  String status = 'Not Used',
}) {
  return Product(
    id: name,
    name: name,
    quantity: quantity,
    exp: exp,
    addedDate: DateTime(2026, 1, 1),
    status: status,
  );
}

void main() {
  group('OfflineRecipeService', () {
    test('finds dish-specific offline recipes', () {
      expect(OfflineRecipeService.find('How do I make Maggi?')?.name, 'Maggi');
      expect(
        OfflineRecipeService.find('Please give me fried rice'),
        isNotNull,
      );
      expect(
        OfflineRecipeService.find('something unsupported'),
        isNull,
      );
    });

    test('recipes have independent ingredients and instructions', () {
      final maggi = OfflineRecipeService.find('maggi')!;
      final curry = OfflineRecipeService.find('chicken curry')!;
      final briyani = OfflineRecipeService.find('veg briyani')!;

      expect(maggi.ingredients.any((item) => item.name == 'Maggi noodles'),
          isTrue);
      expect(curry.ingredients.any((item) => item.name == 'chicken'), isTrue);
      expect(briyani.name, 'Veg Briyani');
      expect(maggi.cookingMethod, isNot(curry.cookingMethod));
    });
  });

  group('IngredientMatcher', () {
    test('matches only recipe ingredients and preserves products', () {
      final recipe = OfflineRecipeService.find('maggi')!;
      final result = IngredientMatcher.match(recipe, [
        product('Maggi noodles', quantity: '2 packets'),
        product('Oil', quantity: '500 ml'),
        product('Rice', quantity: '1 kg'),
        product('Sugar', quantity: '500 g'),
      ]);

      final names = result.available
          .expand((match) => match.products)
          .map((item) => item.name)
          .toList();
      expect(names, containsAll(<String>['Maggi noodles', 'Oil']));
      expect(names, isNot(contains('Rice')));
      expect(names, isNot(contains('Sugar')));
      expect(
        result.missing.map((item) => item.name),
        contains('tastemaker'),
      );
      expect(result.missing.map((item) => item.name), isNot(contains('water')));
    });

    test('does not match rice flour, milk powder, or buttermilk incorrectly',
        () {
      final recipe = const OfflineRecipe(
        name: 'Test',
        ingredients: [
          RecipeIngredient(name: 'rice', quantity: '1 cup'),
          RecipeIngredient(name: 'milk', quantity: '1 cup'),
          RecipeIngredient(name: 'butter', quantity: '1 tbsp'),
        ],
        preparation: [],
        cookingMethod: [],
        preparationTime: '',
        cookingTime: '',
        servings: '1',
      );
      final result = IngredientMatcher.match(recipe, [
        product('Rice flour'),
        product('Milk powder'),
        product('Buttermilk'),
      ]);

      expect(result.available, isEmpty);
      expect(result.missing, hasLength(3));
    });

    test('supports aliases and excludes unusable products', () {
      final recipe = OfflineRecipeService.find('chicken curry')!;
      final result = IngredientMatcher.match(
        recipe,
        [
          product('Tomatoes'),
          product('Haldi'),
          product('Chicken', status: 'Finished'),
          product('Onion', quantity: '0'),
          product('Oil', exp: '01/01/2020'),
        ],
        now: DateTime(2026, 11, 9),
      );

      final names = result.available
          .expand((match) => match.products)
          .map((item) => item.name)
          .toList();
      expect(names, containsAll(<String>['Tomatoes', 'Haldi']));
      expect(names, isNot(contains('Chicken')));
      expect(names, isNot(contains('Onion')));
      expect(names, isNot(contains('Oil')));
      expect(
        result.missing.map((item) => item.name),
        containsAll(<String>['chicken', 'onion', 'oil']),
      );
    });

    test('does not treat unknown expiry as expired', () {
      final recipe = OfflineRecipeService.find('pasta')!;
      final result = IngredientMatcher.match(
        recipe,
        [product('Pasta', exp: 'Not detected')],
      );

      expect(
        result.available
            .expand((match) => match.products)
            .map((item) => item.name),
        contains('Pasta'),
      );
    });
  });

  group('RecipeService integration', () {
    test('reports online-agent failure instead of using offline fallback',
        () async {
      await expectLater(
        RecipeService.generateRecipeForProducts(
          'How do I make Maggi?',
          pantry: [
            product('Maggi noodles', quantity: '2 packets'),
            product('Oil', quantity: '500 ml'),
            product('Rice', quantity: '1 kg'),
          ],
        ),
        throwsA(isA<RecipeAgentException>()),
      );
    });

    test('Pantry Cooking reports online-agent failure', () async {
      await expectLater(
        RecipeService.generatePantryCooking(
          pantry: [
            product(
              'Pasta',
              quantity: '200 g',
              exp: '01/01/2020',
            ),
          ],
        ),
        throwsA(isA<RecipeAgentException>()),
      );
    });
  });

  testWidgets('Chef AI exposes separate Normal Chat and Pantry Cooking modes',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecipesScreen(
          pantryItems: [
            product('Pasta', quantity: '200 g', exp: '12/11/2026'),
          ],
        ),
      ),
    );

    expect(find.text('Normal Chat'), findsOneWidget);
    expect(find.text('Pantry Cooking'), findsOneWidget);

    await tester.tap(find.text('Pantry Cooking'));
    await tester.pump();

    expect(find.text('Suggest using products expiring soon'), findsOneWidget);
  });
}
