import 'dart:convert';

class ShoppingItem {
  final String id;
  final String name;
  final String quantity;
  final String unit;
  final String category;
  final String source;
  final String? productId;
  final String reason;
  bool isBought;

  ShoppingItem({
    required this.id,
    required this.name,
    this.quantity = '',
    this.unit = '',
    this.category = 'Other',
    this.source = 'manual',
    this.productId,
    this.reason = '',
    this.isBought = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'category': category,
      'source': source,
      'productId': productId,
      'reason': reason,
      'isBought': isBought,
    };
  }

  factory ShoppingItem.fromMap(Map<String, dynamic> map) {
    return ShoppingItem(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      quantity: map['quantity']?.toString() ?? '',
      unit: map['unit']?.toString() ?? '',
      category: map['category']?.toString() ?? 'Other',
      source: map['source']?.toString() ?? 'manual',
      productId: map['productId']?.toString(),
      reason: map['reason']?.toString() ?? '',
      isBought: map['isBought'] == true,
    );
  }

  ShoppingItem copyWith({
    String? name,
    String? quantity,
    String? unit,
    String? category,
    String? source,
    String? productId,
    String? reason,
    bool? isBought,
  }) {
    return ShoppingItem(
      id: id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      source: source ?? this.source,
      productId: productId ?? this.productId,
      reason: reason ?? this.reason,
      isBought: isBought ?? this.isBought,
    );
  }

  String toJson() => json.encode(toMap());

  factory ShoppingItem.fromJson(String source) =>
      ShoppingItem.fromMap(json.decode(source));
}
