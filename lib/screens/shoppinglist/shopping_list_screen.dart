import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/manual_item_history_entry.dart';
import '../../models/shopping_list_item.dart';
import '../../providers/auth_providers.dart';
import '../../providers/recipe_providers.dart';
import '../../providers/shopping_list_providers.dart';
import '../../providers/service_providers.dart';
import '../../utils/quantity_formatter.dart';

class ShoppingListScreen extends ConsumerWidget {
  const ShoppingListScreen({super.key});

  Future<void> _confirmClear(BuildContext context, WidgetRef ref, String householdId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tøm handlelisten?'),
        content: const Text('Alle varer, inkludert manuelt tillagte, blir fjernet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tøm')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(shoppingListServiceProvider).clearAll(householdId);
    }
  }

  Future<void> _addManualItem(BuildContext context, WidgetRef ref, String householdId) async {
    await showDialog(
      context: context,
      builder: (_) => _AddManualItemDialog(householdId: householdId),
    );
  }

  Future<void> _confirmRemoveChecked(BuildContext context, WidgetRef ref, String householdId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fjerne avkryssede varer?'),
        content: const Text('Varer du har krysset av som kjøpt blir fjernet fra handlelisten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Fjern')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(shoppingListServiceProvider).removeChecked(householdId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final householdId = ref.watch(userProfileProvider).value?.householdId;
    final itemsState = ref.watch(shoppingListProvider);
    final hasCheckedItems = itemsState.value?.any((item) => item.checked) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Handleliste'),
        actions: [
          if (householdId != null && hasCheckedItems)
            IconButton(
              icon: const Icon(Icons.remove_done),
              tooltip: 'Fjern avkryssede varer',
              onPressed: () => _confirmRemoveChecked(context, ref, householdId),
            ),
          if (householdId != null)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Tøm handleliste',
              onPressed: () => _confirmClear(context, ref, householdId),
            ),
        ],
      ),
      body: itemsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Noe gikk galt: $e')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Handlelisten er tom. Generer en fra middagsplanen, eller legg til varer manuelt.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _GroupedList(items: items, householdId: householdId!);
        },
      ),
      floatingActionButton: householdId == null
          ? null
          : FloatingActionButton.extended(
              heroTag: 'shopping-list-fab',
              onPressed: () => _addManualItem(context, ref, householdId),
              icon: const Icon(Icons.add),
              label: const Text('Legg til vare'),
            ),
    );
  }
}

class _GroupedList extends ConsumerWidget {
  const _GroupedList({required this.items, required this.householdId});

  final List<ShoppingListItem> items;
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byCategory = <IngredientCategory, List<ShoppingListItem>>{};
    for (final item in items) {
      byCategory.putIfAbsent(item.category, () => []).add(item);
    }
    final categories = IngredientCategory.values.where((c) => byCategory.containsKey(c)).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (final category in categories) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              category.displayName,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          for (final item in byCategory[category]!)
            _ShoppingListTile(item: item, householdId: householdId),
        ],
      ],
    );
  }
}

class _ShoppingListTile extends ConsumerWidget {
  const _ShoppingListTile({required this.item, required this.householdId});

  final ShoppingListItem item;
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quantityText = item.quantity != null && item.unit != null
        ? '${formatQuantity(item.quantity!)} ${item.unit!.displayNameFor(item.quantity!)}'
        : null;

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => ref.read(shoppingListServiceProvider).removeItem(householdId, item.id),
      child: CheckboxListTile(
        value: item.checked,
        onChanged: (checked) => ref.read(shoppingListServiceProvider).setChecked(householdId, item.id, checked ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          item.name,
          style: item.checked ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey) : null,
        ),
        subtitle: quantityText != null ? Text(quantityText) : null,
      ),
    );
  }
}

class _AddManualItemDialog extends ConsumerStatefulWidget {
  const _AddManualItemDialog({required this.householdId});

  final String householdId;

  @override
  ConsumerState<_AddManualItemDialog> createState() => _AddManualItemDialogState();
}

class _AddManualItemDialogState extends ConsumerState<_AddManualItemDialog> {
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();

  /// Autocomplete krever at focusNode og textEditingController følges ad når
  /// begge settes eksplisitt (ellers kaster widgeten en assertion).
  final _nameFocusNode = FocusNode();
  IngredientCategory _category = IngredientCategory.annet;
  Unit? _unit;

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final quantity = double.tryParse(_quantityController.text.replaceAll(',', '.'));
    await ref.read(shoppingListServiceProvider).addManualItem(
          widget.householdId,
          name: name,
          category: _category,
          quantity: quantity,
          unit: quantity != null ? (_unit ?? Unit.stk) : null,
        );
    if (mounted) Navigator.of(context).pop();
  }

  void _applySuggestion(ManualItemHistoryEntry entry) {
    _nameController.text = entry.name;
    _quantityController.text = entry.quantity == null
        ? ''
        : (entry.quantity == entry.quantity!.roundToDouble()
            ? entry.quantity!.toStringAsFixed(0)
            : entry.quantity.toString());
    setState(() {
      _category = entry.category;
      _unit = entry.unit;
    });
  }

  /// Forslag hentes fra to kilder: husholdningens egen historikk over
  /// tidligere lagt-til varer (med husket mengde/enhet), og den sentrale,
  /// delte ingredienslisten (uten mengde/enhet, siden ingredienser der er
  /// per person i oppskrifter, ikke per innkjøp). Historikken vinner ved
  /// navnekollisjon, siden den har mer å foreslå.
  List<ManualItemHistoryEntry> _suggestions() {
    final ingredients = ref.watch(ingredientListProvider).value ?? const [];
    final history = ref.watch(manualItemHistoryProvider).value ?? const [];

    final byName = <String, ManualItemHistoryEntry>{
      for (final ing in ingredients)
        ing.name.toLowerCase(): ManualItemHistoryEntry(
          name: ing.name,
          category: ing.category,
          quantity: null,
          unit: null,
        ),
      for (final entry in history) entry.name.toLowerCase(): entry,
    };
    return byName.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions();

    return AlertDialog(
      title: const Text('Legg til vare'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Autocomplete<ManualItemHistoryEntry>(
            textEditingController: _nameController,
            focusNode: _nameFocusNode,
            optionsBuilder: (textEditingValue) {
              final query = textEditingValue.text.trim().toLowerCase();
              if (query.isEmpty) return const Iterable.empty();
              return suggestions.where((entry) => entry.name.toLowerCase().contains(query));
            },
            displayStringForOption: (entry) => entry.name,
            fieldViewBuilder: (context, controller, focusNode, onSubmit) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Vare', border: OutlineInputBorder()),
              );
            },
            onSelected: _applySuggestion,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<IngredientCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Kategori', border: OutlineInputBorder()),
            items: IngredientCategory.values
                .map((c) => DropdownMenuItem(value: c, child: Text(c.displayName)))
                .toList(),
            onChanged: (c) => setState(() => _category = c ?? _category),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantityController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Mengde (valgfritt)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<Unit>(
                  initialValue: _unit,
                  decoration: const InputDecoration(labelText: 'Enhet', border: OutlineInputBorder()),
                  items: Unit.values.map((u) => DropdownMenuItem(value: u, child: Text(u.displayName))).toList(),
                  onChanged: (u) => setState(() => _unit = u),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Avbryt')),
        FilledButton(onPressed: _save, child: const Text('Legg til')),
      ],
    );
  }
}
