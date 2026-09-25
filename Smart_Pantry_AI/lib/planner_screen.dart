import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'meal_model.dart';
import 'product_model.dart';
import 'shopping_model.dart';
import 'storage_service.dart';

class PlannerScreen extends StatefulWidget {
  final List<Product> pantryItems;
  final bool shoppingOnly;

  const PlannerScreen({
    super.key,
    required this.pantryItems,
    this.shoppingOnly = false,
  });

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  static const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  static const slots = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];
  static const categories = [
    'Fruits',
    'Vegetables',
    'Dairy',
    'Grains',
    'Snacks',
    'Beverages',
    'Meat',
    'Household',
    'Other'
  ];

  late int selectedDay;
  Map<String, List<Meal>> meals = {};
  List<ShoppingItem> shopping = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    selectedDay = DateTime.now().weekday - 1;
    meals = {for (final day in days) day: <Meal>[]};
    _load();
  }

  @override
  void didUpdateWidget(covariant PlannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_samePantry(oldWidget.pantryItems, widget.pantryItems))
      _syncPantryItems();
  }

  bool _samePantry(List<Product> oldItems, List<Product> newItems) {
    if (oldItems.length != newItems.length) return false;
    for (var index = 0; index < oldItems.length; index++) {
      final old = oldItems[index];
      final current = newItems[index];
      if (old.id != current.id ||
          old.quantity != current.quantity ||
          old.exp != current.exp ||
          old.status != current.status) return false;
    }
    return true;
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        StorageService.loadMeals(),
        StorageService.loadShoppingList(),
      ]);
      final savedMeals = results[0] as Map<String, List<Meal>>;
      final loadedMeals = {for (final day in days) day: <Meal>[]};
      for (final day in days)
        loadedMeals[day] = List<Meal>.from(savedMeals[day] ?? const []);
      if (savedMeals.isEmpty) {
        final oldPlan = await StorageService.loadMealPlan();
        for (final day in days) {
          final value = oldPlan[day] ?? oldPlan[day.substring(0, 3)];
          if (value != null && value != 'No meal planned') {
            loadedMeals[day]!
                .add(Meal(id: _id(), day: day, type: 'Lunch', name: value));
          }
        }
      }
      if (!mounted) return;
      setState(() {
        meals = loadedMeals;
        shopping = results[1] as List<ShoppingItem>;
        loading = false;
      });
      await _syncPantryItems();
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _id() => DateTime.now().microsecondsSinceEpoch.toString();
  Future<void> _saveMeals() => StorageService.saveMeals(meals);
  Future<void> _saveShopping() => StorageService.saveShoppingList(shopping);

  Future<void> _editMeal(String day, String slot, [Meal? old]) async {
    final controller = TextEditingController(text: old?.name ?? '');
    final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(old == null ? 'Add $slot' : 'Edit $slot'),
              content: TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Meal name', hintText: 'For example, Dosa'),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty)
                    Navigator.pop(dialogContext, value.trim());
                },
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('CANCEL')),
                FilledButton(
                    onPressed: () {
                      final value = controller.text.trim();
                      if (value.isNotEmpty) Navigator.pop(dialogContext, value);
                    },
                    child: const Text('SAVE')),
              ],
            ));
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (result == null || !mounted) return;
    final meal = Meal(id: old?.id ?? _id(), day: day, type: slot, name: result);
    setState(() {
      final list = meals.putIfAbsent(day, () => <Meal>[]);
      final index = list.indexWhere((item) => item.id == meal.id);
      if (index == -1)
        list.add(meal);
      else
        list[index] = meal;
    });
    await _saveMeals();
  }

  Future<void> _deleteMeal(Meal meal) async {
    if (!await _confirm('Delete meal?', 'Remove ${meal.name} from the plan?'))
      return;
    if (!mounted) return;
    setState(() => meals[meal.day]?.removeWhere((item) => item.id == meal.id));
    await _saveMeals();
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: Text(title),
                content: Text(message),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('CANCEL')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('DELETE')),
                ],
              )) ??
      false;

  bool _isAutomatic(ShoppingItem item) => item.source == 'pantry';

  Future<void> _syncPantryItems() async {
    if (!mounted) return;
    final generated = <ShoppingItem>[];
    final activeIds = <String>{};
    for (final product in widget.pantryItems) {
      final reason = _restockReason(product);
      if (reason == null) continue;
      activeIds.add(product.id);
      final existingIndex = shopping.indexWhere((item) =>
          _isAutomatic(item) &&
          (item.productId == product.id ||
              (item.productId == null && _sameName(item.name, product.name))));
      final automatic = ShoppingItem(
        id: existingIndex == -1 ? _id() : shopping[existingIndex].id,
        name: product.name,
        quantity: product.quantity,
        category: product.category,
        source: 'pantry',
        productId: product.id,
        reason: reason,
        isBought:
            existingIndex == -1 ? false : shopping[existingIndex].isBought,
      );
      if (existingIndex == -1)
        generated.add(automatic);
      else
        shopping[existingIndex] = automatic;
    }
    shopping.removeWhere((item) =>
        _isAutomatic(item) &&
        item.productId != null &&
        !activeIds.contains(item.productId));
    if (mounted) setState(() => shopping.addAll(generated));
    if (generated.isNotEmpty || shopping.any(_isAutomatic))
      await _saveShopping();
  }

  String? _restockReason(Product product) {
    final quantity =
        double.tryParse(product.quantity.replaceAll(RegExp(r'[^0-9.\-]'), ''));
    if (quantity != null && quantity <= 0) return 'Out of stock';
    if (product.status.toLowerCase().contains('unavailable'))
      return 'Unavailable';
    final expiry = _parseDate(product.exp);
    if (expiry != null && expiry.isBefore(DateTime.now())) return 'Expired';
    return null;
  }

  DateTime? _parseDate(String value) {
    final match = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})$')
        .firstMatch(value.trim());
    if (match == null) return null;
    var year = int.parse(match.group(3)!);
    if (year < 100) year += 2000;
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  bool _sameName(String first, String second) =>
      first.trim().toLowerCase() == second.trim().toLowerCase();

  Future<ShoppingItem?> _itemDialog([ShoppingItem? old]) async {
    final name = TextEditingController(text: old?.name ?? '');
    final quantity = TextEditingController(text: old?.quantity ?? '');
    final unit = TextEditingController(text: old?.unit ?? '');
    var category = old?.category ?? 'Other';
    final result = await showDialog<ShoppingItem>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                  title: Text(old == null ? 'Add Item' : 'Edit Item'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: name,
                        autofocus: true,
                        decoration:
                            const InputDecoration(labelText: 'Item name')),
                    TextField(
                        controller: quantity,
                        decoration: const InputDecoration(
                            labelText: 'Quantity (optional)')),
                    TextField(
                        controller: unit,
                        decoration: const InputDecoration(
                            labelText: 'Unit (optional)')),
                    DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration:
                            const InputDecoration(labelText: 'Category'),
                        items: categories
                            .map((item) => DropdownMenuItem(
                                value: item, child: Text(item)))
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => category = value ?? 'Other')),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('CANCEL')),
                    FilledButton(
                        onPressed: () {
                          if (name.text.trim().isEmpty) return;
                          Navigator.pop(
                              dialogContext,
                              ShoppingItem(
                                  id: old?.id ?? _id(),
                                  name: name.text.trim(),
                                  quantity: quantity.text.trim(),
                                  unit: unit.text.trim(),
                                  category: category,
                                  isBought: old?.isBought ?? false));
                        },
                        child: const Text('SAVE')),
                  ],
                )));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      quantity.dispose();
      unit.dispose();
    });
    return result;
  }

  Future<void> _editItem([ShoppingItem? old]) async {
    final result = await _itemDialog(old);
    if (result == null || !mounted) return;
    if (old == null && _sameManualName(result.name)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That item is already on your list.')));
      return;
    }
    setState(() {
      final index = shopping.indexWhere((item) => item.id == result.id);
      if (index == -1)
        shopping.add(result);
      else
        shopping[index] = result;
    });
    await _saveShopping();
  }

  Future<void> _copyShoppingList() async {
    final names = <String>[];
    for (final item in shopping) {
      final name = item.name.trim();
      if (name.isNotEmpty &&
          !names.any((existing) => _sameName(existing, name))) {
        names.add(name);
      }
    }

    if (names.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shopping list is empty.')),
        );
      }
      return;
    }

    final text =
        ['Shopping List:', ...names.map((name) => '- $name')].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Shopping list copied! You can paste it into your grocery app.',
          ),
        ),
      );
    }
  }

  bool _sameManualName(String name) => shopping.any(
        (item) => !_isAutomatic(item) && _sameName(item.name, name),
      );

  Future<void> _toggleItem(ShoppingItem item, bool value) async {
    setState(() => item.isBought = value);
    await _saveShopping();
  }

  Future<void> _deleteItem(ShoppingItem item) async {
    if (!await _confirm(
        'Delete item?', 'Remove ${item.name} from the shopping list?')) return;
    if (!mounted) return;
    setState(() => shopping.removeWhere((current) => current.id == item.id));
    await _saveShopping();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (widget.shoppingOnly) return _shoppingList();
    return Column(children: [
      Expanded(child: _planner()),
    ]);
  }

  Widget _planner() {
    final day = days[selectedDay];
    final planned = meals[day] ?? const <Meal>[];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Today is ${days[DateTime.now().weekday - 1]}'),
      const SizedBox(height: 8),
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var index = 0; index < days.length; index++)
              Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: Text(days[index].substring(0, 3)),
                      selected: selectedDay == index,
                      onSelected: (_) => setState(() => selectedDay = index)))
          ])),
      const SizedBox(height: 12),
      Text(day,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold)),
      for (final slot in slots)
        _mealSlot(
            day, slot, planned.where((meal) => meal.type == slot).toList()),
    ]);
  }

  Widget _mealSlot(String day, String slot, List<Meal> values) => Card(
      child: Padding(
          padding: const EdgeInsets.all(10),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(slot,
                      style: const TextStyle(fontWeight: FontWeight.bold))),
              IconButton(
                  onPressed: () => _editMeal(day, slot),
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Add $slot')
            ]),
            if (values.isEmpty)
              const Text('Not planned yet',
                  style: TextStyle(color: Colors.grey)),
            for (final meal in values)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(meal.name),
                  trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _editMeal(day, slot, meal);
                        if (value == 'delete') _deleteMeal(meal);
                      },
                      itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Delete'))
                          ])),
          ])));

  Widget _shoppingList() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
            onPressed: () => _editItem(),
            icon: const Icon(Icons.add),
            label: const Text('Add Item')),
        OutlinedButton.icon(
            onPressed: _copyShoppingList,
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy List'))
      ]),
      const SizedBox(height: 18),
      _shoppingSection('Shopping List', shopping),
    ]);
  }

  Widget _shoppingSection(String title, List<ShoppingItem> items) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const Divider(),
        if (items.isEmpty)
          const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Nothing here yet.',
                  style: TextStyle(color: Colors.grey))),
        for (final item in items)
          Card(
              child: CheckboxListTile(
                  value: item.isBought,
                  onChanged: (value) => _toggleItem(item, value ?? false),
                  title: Text(item.name,
                      style: TextStyle(
                          decoration: item.isBought
                              ? TextDecoration.lineThrough
                              : null)),
                  subtitle: Text(_itemSubtitle(item)),
                  secondary: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit' && !_isAutomatic(item))
                          _editItem(item);
                        if (value == 'delete') _deleteItem(item);
                      },
                      itemBuilder: (_) => [
                            if (!_isAutomatic(item))
                              const PopupMenuItem(
                                  value: 'edit', child: Text('Edit')),
                            const PopupMenuItem(
                                value: 'delete', child: Text('Delete'))
                          ]))),
      ]);

  String _itemSubtitle(ShoppingItem item) {
    final details = <String>[];
    if (item.quantity.isNotEmpty)
      details
          .add('${item.quantity}${item.unit.isEmpty ? '' : ' ${item.unit}'}');
    if (item.reason.isNotEmpty) details.add('Reason: ${item.reason}');
    if (details.isEmpty && item.category.isNotEmpty) details.add(item.category);
    return details.join(' • ');
  }
}
