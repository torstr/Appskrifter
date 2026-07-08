import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/manual_item_history_entry.dart';
import '../../providers/auth_providers.dart';
import '../../providers/shopping_list_providers.dart';
import '../../providers/service_providers.dart';
import '../../utils/quantity_formatter.dart';

/// Full liste over husholdningens historikk over manuelt tillagte
/// handlelistevarer (brukt til autocomplete-forslag), med mulighet til å
/// redigere eller slette enkeltoppføringer.
class ManualItemHistoryScreen extends ConsumerWidget {
  const ManualItemHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final householdId = ref.watch(userProfileProvider).value?.householdId;
    final historyState = ref.watch(manualItemHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Varehistorikk')),
      body: historyState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Noe gikk galt: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ingen varer i historikken ennå. Varer du legger til manuelt i handlelisten havner her.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final entry = entries[i];
              final quantityText = entry.quantity != null && entry.unit != null
                  ? '${formatQuantity(entry.quantity!)} ${entry.unit!.displayNameFor(entry.quantity!)}'
                  : null;
              return Dismissible(
                key: ValueKey(entry.name.toLowerCase()),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete_outline),
                ),
                confirmDismiss: (_) => _confirmDelete(context, entry.name),
                onDismissed: (_) {
                  if (householdId != null) {
                    ref.read(shoppingListServiceProvider).deleteHistoryEntry(householdId, entry.name);
                  }
                },
                child: ListTile(
                  title: Text(entry.name),
                  subtitle: Text([entry.category.displayName, ?quantityText].join(' · ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: householdId == null
                            ? null
                            : () => showDialog(
                                  context: context,
                                  builder: (_) => _EditHistoryEntryDialog(householdId: householdId, entry: entry),
                                ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: householdId == null
                            ? null
                            : () async {
                                final confirmed = await _confirmDelete(context, entry.name);
                                if (confirmed) {
                                  await ref.read(shoppingListServiceProvider).deleteHistoryEntry(householdId, entry.name);
                                }
                              },
                      ),
                    ],
                  ),
                  onTap: householdId == null
                      ? null
                      : () => showDialog(
                            context: context,
                            builder: (_) => _EditHistoryEntryDialog(householdId: householdId, entry: entry),
                          ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fjerne fra historikken?'),
        content: Text('«$name» vil ikke lenger foreslås når du legger til varer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Fjern')),
        ],
      ),
    );
    return confirmed ?? false;
  }
}

class _EditHistoryEntryDialog extends ConsumerStatefulWidget {
  const _EditHistoryEntryDialog({required this.householdId, required this.entry});

  final String householdId;
  final ManualItemHistoryEntry entry;

  @override
  ConsumerState<_EditHistoryEntryDialog> createState() => _EditHistoryEntryDialogState();
}

class _EditHistoryEntryDialogState extends ConsumerState<_EditHistoryEntryDialog> {
  late final _nameController = TextEditingController(text: widget.entry.name);
  late final _quantityController = TextEditingController(
    text: widget.entry.quantity == null
        ? ''
        : (widget.entry.quantity == widget.entry.quantity!.roundToDouble()
            ? widget.entry.quantity!.toStringAsFixed(0)
            : widget.entry.quantity.toString()),
  );
  late IngredientCategory _category = widget.entry.category;
  late Unit? _unit = widget.entry.unit;

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final quantity = double.tryParse(_quantityController.text.replaceAll(',', '.'));
    final updated = ManualItemHistoryEntry(
      name: name,
      category: _category,
      quantity: quantity,
      unit: quantity != null ? (_unit ?? Unit.stk) : null,
    );
    await ref.read(shoppingListServiceProvider).updateHistoryEntry(widget.householdId, widget.entry.name, updated);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rediger vare'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Vare', border: OutlineInputBorder()),
            autofocus: true,
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
        FilledButton(onPressed: _save, child: const Text('Lagre')),
      ],
    );
  }
}
