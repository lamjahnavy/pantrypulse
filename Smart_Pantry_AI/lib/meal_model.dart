import 'dart:convert';

class Meal {
  final String id;
  final String day;
  final String type;
  final String name;
  final List<String> ingredients;
  final String quantity;
  final String notes;

  const Meal({
    required this.id,
    required this.day,
    required this.type,
    required this.name,
    this.ingredients = const [],
    this.quantity = '',
    this.notes = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'day': day,
        'type': type,
        'name': name,
        'ingredients': ingredients,
        'quantity': quantity,
        'notes': notes,
      };

  factory Meal.fromMap(Map<String, dynamic> map) {
    final rawIngredients = map['ingredients'];
    return Meal(
      id: map['id']?.toString() ?? '',
      day: map['day']?.toString() ?? '',
      type: map['type']?.toString() ?? 'Lunch',
      name: map['name']?.toString() ?? '',
      ingredients: rawIngredients is List
          ? rawIngredients
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList()
          : const [],
      quantity: map['quantity']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
    );
  }

  String toJson() => jsonEncode(toMap());

  factory Meal.fromJson(String source) => Meal.fromMap(jsonDecode(source));
}