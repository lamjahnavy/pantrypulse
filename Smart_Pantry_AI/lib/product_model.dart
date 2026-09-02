import 'dart:convert';

class Product {
  final String id;
  final String name;
  final String brand;
  final String category;

  // Current remaining quantity
  final String quantity;

  // Quantity when the item was originally added
  final String originalQuantity;

  final String mfd;
  final String exp;
  final String barcode;
  final DateTime addedDate;
  final double price;

  // Pantry usage status
  // Possible values:
  // Not Used
  // Used
  // Partially Used
  // Finished
  final String status;

  Product({
    required this.id,
    required this.name,
    this.brand = 'Unknown',
    this.category = 'Others',
    this.quantity = 'Not detected',
    String? originalQuantity,
    this.mfd = 'Not detected',
    this.exp = 'Not detected',
    this.barcode = '',
    required this.addedDate,
    this.price = 0.0,
    this.status = 'Not Used',
  }) : originalQuantity = originalQuantity ?? quantity;

  /// Convert Product into Map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'brand': brand,
      'category': category,
      'quantity': quantity,
      'originalQuantity': originalQuantity,
      'mfd': mfd,
      'exp': exp,
      'barcode': barcode,
      'addedDate': addedDate.toIso8601String(),
      'price': price,
      'status': status,
    };
  }

  /// Create Product from stored Map
  factory Product.fromMap(Map<String, dynamic> map) {
    final currentQuantity =
        map['quantity']?.toString() ?? 'Not detected';

    return Product(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      brand: map['brand']?.toString() ?? 'Unknown',
      category: map['category']?.toString() ?? 'Others',
      quantity: currentQuantity,

      // Old products may not have originalQuantity.
      // In that case, use the existing quantity.
      originalQuantity:
          map['originalQuantity']?.toString() ?? currentQuantity,

      mfd: map['mfd']?.toString() ?? 'Not detected',
      exp: map['exp']?.toString() ?? 'Not detected',
      barcode: map['barcode']?.toString() ?? '',

      addedDate: map['addedDate'] != null
          ? DateTime.tryParse(map['addedDate'].toString()) ??
              DateTime.now()
          : DateTime.now(),

      price: map['price'] is num
          ? (map['price'] as num).toDouble()
          : double.tryParse(map['price']?.toString() ?? '0') ?? 0.0,

      status: map['status']?.toString() ?? 'Not Used',
    );
  }

  String toJson() => json.encode(toMap());

  factory Product.fromJson(String source) {
    return Product.fromMap(json.decode(source));
  }

  /// Create a modified copy of the product.
  /// This will make updating quantity/status easier later.
  Product copyWith({
    String? id,
    String? name,
    String? brand,
    String? category,
    String? quantity,
    String? originalQuantity,
    String? mfd,
    String? exp,
    String? barcode,
    DateTime? addedDate,
    double? price,
    String? status,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      originalQuantity: originalQuantity ?? this.originalQuantity,
      mfd: mfd ?? this.mfd,
      exp: exp ?? this.exp,
      barcode: barcode ?? this.barcode,
      addedDate: addedDate ?? this.addedDate,
      price: price ?? this.price,
      status: status ?? this.status,
    );
  }
}