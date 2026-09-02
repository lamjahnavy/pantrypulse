import 'dart:convert';

class ShoppingItem {
  final String id;
  final String name;
  bool isBought;

  ShoppingItem({
    required this.id,
    required this.name,
    this.isBought = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'isBought': isBought,
    };
  }

  factory ShoppingItem.fromMap(Map<String, dynamic> map) {
    return ShoppingItem(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      isBought: map['isBought'] ?? false,
    );
  }

  String toJson() => json.encode(toMap());

  factory ShoppingItem.fromJson(String source) => ShoppingItem.fromMap(json.decode(source));
}
